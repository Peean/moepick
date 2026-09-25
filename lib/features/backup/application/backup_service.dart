import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/hive_boxes.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/platform/file_save_service.dart';
import '../../../core/storage/hive_store.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/hash_utils.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/category.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/models/tag.dart';

/// What a backup contains.
/// 备份包含的范围。
enum BackupScope {
  /// Records only: series, stickers, categories, tags, the settings singleton
  /// and the background *configuration*. Image files are excluded.
  /// 仅记录：系列、表情包、分类、标签、设置单例与背景**配置**。不含图片文件。
  settingsOnly,

  /// Records plus every referenced image, thumbnail and background source.
  /// 记录加上全部被引用的图片、缩略图与背景原图。
  full;

  String get label => this == BackupScope.full ? '完整备份' : '仅设置';
}

/// Result of writing a backup file.
/// 写出备份文件的结果。
class BackupResult {
  const BackupResult({
    required this.path,
    required this.bytes,
    required this.entryCount,
    required this.imageCount,
    required this.scope,
    this.usedFallback = false,
  });

  /// Absolute path the archive was actually written to.
  /// 归档实际写入的绝对路径。
  final String path;
  final int bytes;
  final int entryCount;
  final int imageCount;
  final BackupScope scope;

  /// True when the user's chosen folder could not be written and the archive
  /// was placed in an app-owned directory instead.
  /// 为真时表示用户所选文件夹无法写入，归档改放在了应用自有目录。
  final bool usedFallback;
}

/// Result of restoring a backup.
/// 恢复备份的结果。
class RestoreResult {
  const RestoreResult({
    required this.seriesCount,
    required this.stickerCount,
    required this.assetCount,
    required this.skippedAssets,
    required this.isFullRestore,
  });

  final int seriesCount;
  final int stickerCount;
  final int assetCount;

  /// Assets referenced by the manifest but absent from the archive.
  /// manifest 中引用但压缩包内缺失的资源数。
  final int skippedAssets;

  final bool isFullRestore;

  String get summary {
    final String base = '恢复 $seriesCount 个系列、$stickerCount 个表情包';
    if (assetCount > 0) {
      return '$base，$assetCount 个图片文件';
    }
    return base;
  }
}

/// Creates and restores backup archives.
/// 创建与恢复备份归档。
///
/// FORMAT: a single zip containing
///   - `manifest.json` — schema version, counts, and the full record set
///   - `assets/...` — relative image paths, preserved verbatim
///
/// 格式：单个 zip，包含
///   - `manifest.json` — schema 版本、计数与全部记录
///   - `assets/...` — 相对图片路径，原样保留
///
/// DESIGN NOTES
///
/// 1. Records are serialised as **JSON**, not as raw Hive boxes. Hive's binary
///    format is tied to adapter field numbering; JSON survives a future field
///    reorder and is diffable when debugging.
///
/// 2. Asset paths inside the archive mirror the *relative* paths used at rest,
///    so a restore is a straight copy rather than a path-rewriting exercise.
///
/// 3. A `settingsOnly` backup deliberately omits images but still records the
///    sticker rows: restoring it yields a library whose entries point at files
///    that may not exist, which is visible and recoverable, rather than a
///    silently empty library.
///
/// 设计说明
///
/// 1. 记录序列化为 **JSON** 而非原始 Hive box。Hive 的二进制格式与适配器字段编号绑定；
///    JSON 能挺过未来的字段重排，且调试时可读可 diff。
///
/// 2. 归档内的资源路径与静止状态下的**相对**路径一一对应，
///    因此恢复是直接拷贝，而不需要重写路径。
///
/// 3. `settingsOnly` 备份有意省略图片但仍记录表情包行：恢复后得到的库中，
///    条目会指向可能不存在的文件——这是可见且可恢复的状态，
///    而不是一个静默变空的库。
class BackupService {
  BackupService(this._store);

  final HiveStore _store;

  /// Archive entry names.
  /// 归档内的条目名。
  static const String manifestEntry = 'manifest.json';
  static const String assetsPrefix = 'assets/';

  /// Build an archive and return its bytes.
  /// 构建归档并返回其字节。
  ///
  /// The expensive part — reading every image and ZIP-encoding the archive —
  /// runs in an isolate, so neither a backup export nor a WebDAV sync blocks
  /// the UI thread. Images are stored uncompressed (they are already JPEG/PNG),
  /// which is the single biggest win: re-compressing them was pure CPU waste
  /// that made a 20 MB sync take half a minute.
  ///
  /// 昂贵的部分——读取每张图片并做 ZIP 编码——在 isolate 中执行，因此备份导出与
  /// WebDAV 同步都不会阻塞 UI 线程。图片以无压缩方式存储（它们本就是 JPEG/PNG），
  /// 这是最大的提速点：对它们再压缩纯属浪费 CPU，是 20MB 同步耗时半分钟的元凶。
  Future<Uint8List> buildArchive({required BackupScope scope}) async {
    final Map<String, dynamic> manifest = _buildManifest();
    manifest['scope'] = scope.name;

    final List<ArchiveAsset> assets = <ArchiveAsset>[];
    if (scope == BackupScope.full) {
      for (final String relative in _collectAssetPaths()) {
        assets.add(
          ArchiveAsset(
            name: '$assetsPrefix${_toArchivePath(relative)}',
            path: await PathUtils.absolute(relative),
          ),
        );
      }
      manifest['assetCount'] = assets.length;
    }

    final String manifestJson = jsonEncode(manifest);
    return compute(
      _encodeBackupArchive,
      _ArchiveBuildRequest(manifestJson: manifestJson, assets: assets),
    );
  }

  /// Assemble the manifest map, minus the asset count which is filled in by the
  /// caller once the asset list is known.
  /// 组装 manifest 映射（不含资源数，由调用方在确定资源列表后补齐）。
  Map<String, dynamic> _buildManifest() {
    return <String, dynamic>{
      'schemaVersion': AppConstants.backupSchemaVersion,
      'appId': AppConstants.appId,
      'createdAt': DateUtils.toIso(DateUtils.nowUtc()),
      'boxes': <String, dynamic>{
        HiveBoxes.series: _seriesJson(),
        HiveBoxes.stickers: _stickersJson(),
        HiveBoxes.categories: _categoriesJson(),
        HiveBoxes.tags: _tagsJson(),
      },
      'settings': _store.readSettings().toJson(),
      'background': _store.readBackground().toJson(),
      'counts': <String, int>{
        'series': _store.series.length,
        'stickers': _store.stickers.length,
        'categories': _store.categories.length,
        'tags': _store.tags.length,
      },
    };
  }

  /// Write a backup file to a destination the user approved.
  /// 将备份文件写入用户已批准的目标。
  ///
  /// The bytes are produced by [buildArchive] and handed to
  /// [FileSaveService.writeBytes], which knows where the app is actually
  /// allowed to write. Accepts a bare path too, so the desktop flow and the
  /// older call sites keep working.
  ///
  /// 字节由 [buildArchive] 生成后交给 [FileSaveService.writeBytes]，
  /// 由后者决定应用真正有权写入的位置。同时接受裸路径，
  /// 以便桌面流程与既有调用点继续可用。
  Future<BackupResult> writeTo(
    SaveDestination destination, {
    required BackupScope scope,
  }) async {
    final Uint8List bytes = await buildArchive(scope: scope);
    final SaveOutcome outcome =
        await FileSaveService.writeBytes(destination, bytes);

    final int imageCount =
        scope == BackupScope.full ? _collectAssetPaths().length : 0;

    return BackupResult(
      path: outcome.path,
      bytes: bytes.length,
      entryCount: _totalRecordCount(),
      imageCount: imageCount,
      scope: scope,
      usedFallback: outcome.usedFallback,
    );
  }

  /// Suggest a file name for a new backup.
  /// 为新备份建议一个文件名。
  static String suggestedFileName(BackupScope scope) {
    final String stamp = DateUtils.fileStamp(DateUtils.nowUtc());
    final String kind = scope == BackupScope.full ? 'full' : 'settings';
    return '${AppConstants.appId}_${kind}_$stamp.zip';
  }

  /// Restore from an archive file, replacing the current library.
  /// 从归档文件恢复，替换当前库。
  ///
  /// This is a **replace**, not a merge. Merging two libraries raises questions
  /// (whose tags win? whose deletions win?) that cannot be answered
  /// automatically, and a wrong guess silently corrupts data. Replace is
  /// predictable and the previous state is recoverable by backing up first.
  ///
  /// 这是**替换**而非合并。合并两个库会引出无法自动回答的问题
  /// （标签以谁为准？删除以谁为准？），猜错会静默损坏数据。
  /// 替换是可预期的，且只要先备份即可回溯。
  Future<RestoreResult> restoreFrom(String archivePath) async {
    final File file = File(archivePath);
    if (!await file.exists()) {
      throw BackupException('备份文件不存在: $archivePath');
    }

    final Archive archive;
    try {
      final List<int> raw = await file.readAsBytes();
      archive = ZipDecoder().decodeBytes(raw);
    } catch (e) {
      throw BackupException('无法读取备份文件，可能已损坏', cause: e);
    }

    final ArchiveFile? manifestFile = archive.findFile(manifestEntry);
    if (manifestFile == null) {
      throw BackupException('备份文件缺少 manifest，可能不是拾萌的备份');
    }

    final Map<String, dynamic> manifest = _decodeManifest(manifestFile);
    _checkSchema(manifest);

    final Map<String, dynamic> boxes =
        (manifest['boxes'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    // Clear before writing: a replace that appends would leave records from the
    // old library behind, producing a chimera that is worse than either input.
    // 先清空再写入：只追加的「替换」会残留旧库记录，产生比任一输入都更糟的混合体。
    await _store.series.clear();
    await _store.stickers.clear();
    await _store.categories.clear();
    await _store.tags.clear();

    final List<Series> series = _decodeList<Series>(
      boxes[HiveBoxes.series],
      Series.fromJson,
    );
    final List<Sticker> stickers = _decodeList<Sticker>(
      boxes[HiveBoxes.stickers],
      Sticker.fromJson,
    );
    final List<Category> categories = _decodeList<Category>(
      boxes[HiveBoxes.categories],
      Category.fromJson,
    );
    final List<Tag> tags = _decodeList<Tag>(
      boxes[HiveBoxes.tags],
      Tag.fromJson,
    );

    await _store.series.putAll(<String, Series>{
      for (final Series s in series) s.id: s,
    });
    await _store.stickers.putAll(<String, Sticker>{
      for (final Sticker s in stickers) s.id: s,
    });
    await _store.categories.putAll(<String, Category>{
      for (final Category c in categories) c.id: c,
    });
    await _store.tags.putAll(<String, Tag>{
      for (final Tag t in tags) t.id: t,
    });

    if (manifest['settings'] is Map) {
      await _store.writeSettings(
        AppSettings.fromJson(
          Map<String, dynamic>.from(manifest['settings'] as Map),
        ),
      );
    }
    if (manifest['background'] is Map) {
      await _store.writeBackground(
        BackgroundConfig.fromJson(
          Map<String, dynamic>.from(manifest['background'] as Map),
        ),
      );
    }

    // Extract assets, then reconcile: a record whose file is missing after
    // restore would render as a broken tile forever, so count and report it.
    // 解包资源后做核对：恢复后文件缺失的记录会永远显示为破损瓦片，
    // 因此统计并上报。
    int assetCount = 0;
    for (final ArchiveFile f in archive.files) {
      if (!f.name.startsWith(assetsPrefix)) continue;
      final String relative =
          _fromArchivePath(f.name.substring(assetsPrefix.length));
      if (relative.isEmpty) continue;

      final File target = File(await PathUtils.absolute(relative));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(f.content as List<int>, flush: true);
      assetCount++;
    }

    final Set<String> onDisk = _collectRestoredAssets();
    int missing = 0;
    for (final Sticker s in stickers) {
      if (s.isDeleted) continue;
      if (!onDisk.contains(_normalize(s.relativePath))) missing++;
    }

    return RestoreResult(
      seriesCount: series.where((Series s) => !s.isDeleted).length,
      stickerCount: stickers.where((Sticker s) => !s.isDeleted).length,
      assetCount: assetCount,
      skippedAssets: missing,
      isFullRestore: assetCount > 0,
    );
  }

  // ---------------------------------------------------------------- encoding

  List<Map<String, dynamic>> _seriesJson() => _store.series.values
      .map((Series s) => s.toJson())
      .toList();

  List<Map<String, dynamic>> _stickersJson() => _store.stickers.values
      .map((Sticker s) => s.toJson())
      .toList();

  List<Map<String, dynamic>> _categoriesJson() => _store.categories.values
      .map((Category c) => c.toJson())
      .toList();

  List<Map<String, dynamic>> _tagsJson() =>
      _store.tags.values.map((Tag t) => t.toJson()).toList();

  int _totalRecordCount() =>
      _store.series.length +
      _store.stickers.length +
      _store.categories.length +
      _store.tags.length;

  /// Every relative asset path that should travel with a full backup.
  /// 完整备份应携带的全部相对资源路径。
  List<String> _collectAssetPaths() {
    final Set<String> paths = <String>{};

    for (final Sticker s in _store.stickers.values) {
      if (s.isDeleted) continue;
      if (s.relativePath.isNotEmpty) paths.add(_normalize(s.relativePath));
      final String? thumb = s.thumbPath;
      if (thumb != null && thumb.isNotEmpty) paths.add(_normalize(thumb));
    }

    for (final Series s in _store.series.values) {
      if (s.isDeleted) continue;
      final String? cover = s.coverImagePath;
      if (cover != null && cover.isNotEmpty) paths.add(_normalize(cover));
    }

    // Background source and its blur cache, both of which live outside the
    // per-record paths.
    // 背景原图及其模糊缓存，二者都不在各记录的路径里。
    final BackgroundConfig bg = _store.readBackground();
    final String? bgSource = bg.imageRelativePath;
    if (bgSource != null && bgSource.isNotEmpty) paths.add(_normalize(bgSource));
    final String? bgCache = bg.cachedBlurRelativePath;
    if (bgCache != null && bgCache.isNotEmpty) paths.add(_normalize(bgCache));

    return paths.toList();
  }

  /// Paths actually present after extraction, for the missing-asset check.
  /// 解包后实际存在的路径，用于缺失资源核对。
  Set<String> _collectRestoredAssets() {
    final Set<String> found = <String>{};
    for (final Sticker s in _store.stickers.values) {
      if (s.relativePath.isNotEmpty) found.add(_normalize(s.relativePath));
    }
    return found;
  }

  /// Normalise a stored path into the archive's forward-slash form.
  /// 将存储路径规范化为归档使用的正斜杠形式。
  ///
  /// Windows produces `images\a.png`; the archive must use `/` so the same zip
  /// restores correctly on Android.
  /// Windows 会产出 `images\a.png`；归档必须用 `/`，
  /// 使同一个 zip 能在 Android 上正确恢复。
  static String _toArchivePath(String relative) =>
      relative.replaceAll(r'\', '/');

  static String _fromArchivePath(String archivePath) =>
      p.joinAll(archivePath.split('/'));

  static String _normalize(String relative) =>
      relative.replaceAll(r'\', '/');

  Map<String, dynamic> _decodeManifest(ArchiveFile file) {
    try {
      final Object? raw = jsonDecode(utf8.decode(file.content as List<int>));
      if (raw is! Map) throw const FormatException('manifest 不是对象');
      return Map<String, dynamic>.from(raw);
    } catch (e) {
      throw BackupException('manifest 解析失败', cause: e);
    }
  }

  /// Reject archives from a newer schema than this build understands.
  /// 拒绝本版本无法理解的更高 schema 归档。
  ///
  /// Older schemas are accepted: every model's `fromJson` fills defaults for
  /// missing keys, which is precisely why JSON was chosen over raw Hive data.
  /// 接受更低的 schema：各模型的 `fromJson` 会为缺失键填充默认值，
  /// 这正是选择 JSON 而非原始 Hive 数据的原因。
  void _checkSchema(Map<String, dynamic> manifest) {
    final int version =
        (manifest['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > AppConstants.backupSchemaVersion) {
      throw BackupException(
        '这个备份来自更新的版本（schema v$version），'
        '当前版本只支持到 v${AppConstants.backupSchemaVersion}',
      );
    }
  }

  static List<T> _decodeList<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return <T>[];
    final List<T> result = <T>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      try {
        result.add(fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip an unparseable record rather than failing the whole restore:
        // losing one entry beats losing the entire library.
        // 跳过无法解析的单条记录，而不是让整个恢复失败：
        // 丢掉一条总好过丢掉整个库。
      }
    }
    return result;
  }

  /// Cheap fingerprint of the current library, used by the sync engine to skip
  /// no-op uploads.
  /// 当前库的轻量指纹，供同步引擎跳过无意义的上传。
  String contentFingerprint() {
    final List<String> parts = <String>[];
    for (final Series s in _store.series.values) {
      parts.add('s:${s.id}:${DateUtils.toEpochMs(s.updatedAt)}:${s.isDeleted}');
    }
    for (final Sticker s in _store.stickers.values) {
      parts.add('k:${s.id}:${DateUtils.toEpochMs(s.updatedAt)}:${s.isDeleted}');
    }
    for (final Category c in _store.categories.values) {
      parts.add('c:${c.id}:${DateUtils.toEpochMs(c.updatedAt)}:${c.isDeleted}');
    }
    for (final Tag t in _store.tags.values) {
      parts.add('t:${t.id}:${DateUtils.toEpochMs(t.updatedAt)}:${t.isDeleted}');
    }
    parts.add('cfg:${jsonEncode(_store.readSettings().toJson())}');
    parts.sort();
    return HashUtils.ofString(parts.join('|'));
  }
}

/// One asset file to embed in the archive.
/// 归档中要嵌入的单个资源文件。
///
/// Carries the archive entry name and the absolute path so the isolate worker
/// needs no knowledge of the app's path layout.
/// 携带归档条目名与绝对路径，使 isolate 工作函数无需了解应用的路径布局。
class ArchiveAsset {
  const ArchiveAsset({required this.name, required this.path});

  final String name;
  final String path;
}

/// Arguments for [_encodeBackupArchive], sent across the isolate boundary.
/// [_encodeBackupArchive] 的参数，需跨 isolate 传递。
class _ArchiveBuildRequest {
  const _ArchiveBuildRequest({
    required this.manifestJson,
    required this.assets,
  });

  final String manifestJson;
  final List<ArchiveAsset> assets;
}

/// Top-level isolate worker: read the asset files, assemble and ZIP-encode the
/// archive. Images are stored uncompressed (already JPEG/PNG), the manifest is
/// deflated.
/// 顶层 isolate 工作函数：读取资源文件、组装并 ZIP 编码归档。
/// 图片无压缩存储（本就是 JPEG/PNG），manifest 采用 deflate。
Uint8List _encodeBackupArchive(_ArchiveBuildRequest request) {
  final Archive archive = Archive();

  for (final ArchiveAsset asset in request.assets) {
    final File file = File(asset.path);
    if (!file.existsSync()) continue;
    final Uint8List bytes = file.readAsBytesSync();
    final ArchiveFile entry = ArchiveFile(asset.name, bytes.length, bytes);
    // Re-compressing already-compressed image data is pure CPU waste.
    // 对已压缩的图片数据再压缩纯属浪费 CPU。
    entry.compress = false;
    archive.addFile(entry);
  }

  final Uint8List manifestBytes =
      Uint8List.fromList(utf8.encode(request.manifestJson));
  archive.addFile(
    ArchiveFile(BackupService.manifestEntry, manifestBytes.length, manifestBytes),
  );

  final List<int>? encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw BackupException('打包失败');
  }
  return Uint8List.fromList(encoded);
}
