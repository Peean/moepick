import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../data/models/sticker.dart';
import '../constants/app_constants.dart';
import '../error/app_exception.dart';
import '../utils/date_utils.dart';
import '../utils/hash_utils.dart';
import '../utils/id_utils.dart';
import '../utils/image_utils.dart';
import '../utils/path_utils.dart';

/// Outcome of importing one image file.
/// 导入单个图片文件的结果。
class ImportOutcome {
  ImportOutcome({
    required this.sticker,
    required this.wasDuplicate,
    this.duplicateOfId,
  });

  /// The created sticker, or the pre-existing one when [wasDuplicate] is true.
  /// 新建的表情包；[wasDuplicate] 为 true 时指已存在的那条记录。
  final Sticker sticker;

  /// True when an identical image (same sha256) was already in the library.
  /// 当库中已存在相同图片（sha256 相同）时为 true。
  final bool wasDuplicate;

  final String? duplicateOfId;
}

/// The single gateway for all image file I/O.
/// 所有图片文件 I/O 的唯一出口。
///
/// Centralising file work here means path handling, dedup hashing, thumbnail
/// generation and cleanup all happen in one place instead of being scattered
/// across feature code.
/// 集中处理文件操作，使路径处理、去重哈希、缩略图生成与清理只在一处实现，
/// 而不散落在各业务模块中。
class FileStore {
  FileStore();

  /// Import an image from an arbitrary source path into the library.
  /// 将任意源路径的图片导入库中。
  ///
  /// Steps: copy to temp → hash → de-duplicate → move into place → thumbnail.
  /// 步骤：复制到临时目录 → 计算哈希 → 去重 → 移入正式目录 → 生成缩略图。
  Future<ImportOutcome> importImage({
    required String sourcePath,
    required String seriesId,
    String? name,
    Map<String, String> existingHashes = const <String, String>{},
    int sortIndex = 0,
  }) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw ImageException('源文件不存在: $sourcePath');
    }

    final String extension = PathUtils.extensionOf(sourcePath);
    final Uint8List raw = await source.readAsBytes();

    // `existingHashes` maps sha256 -> stickerId, letting an import of an
    // already-present image short-circuit before touching the filesystem.
    // `existingHashes` 是 sha256 -> stickerId 的映射，使重复导入可在落盘前短路返回。
    final String hash = HashUtils.ofBytes(raw);
    final String? duplicateId = existingHashes[hash];
    if (duplicateId != null) {
      // Return rather than throw: a duplicate is an ordinary, expected outcome
      // when the user re-imports a folder, not an error condition. Throwing
      // would force every caller into a try/catch that just counts skips.
      // 返回而非抛异常：用户重复导入同一批文件时，重复是正常且可预期的结果，
      // 不是错误状态。抛异常会迫使每个调用方写只为统计跳过的 try/catch。
      return ImportOutcome(
        wasDuplicate: true,
        duplicateOfId: duplicateId,
        sticker: Sticker(
          id: duplicateId,
          seriesId: seriesId,
          relativePath: '',
          createdAt: DateUtils.nowUtc(),
          updatedAt: DateUtils.nowUtc(),
        ),
      );
    }

    final DecodedImageInfo decoded = await ImageUtils.decode(source);

    final String stickerId = IdUtils.newId();
    final String imageRel = PathUtils.imageRelativePath(stickerId, extension);

    // Write into a temp file first, then rename into place: a rename within the
    // same filesystem is atomic, so a crash mid-import never leaves a
    // half-written image referenced by the database.
    // 先写临时文件再重命名到位：同一文件系统内的重命名是原子的，
    // 因此导入中途崩溃不会留下被数据库引用的半截图片。
    final String tempDir = await PathUtils.tempPath();
    final File tempFile =
        File(p.join(tempDir, 'import_$stickerId$extension'));
    await tempFile.writeAsBytes(raw, flush: true);

    final File destination = File(await PathUtils.absolute(imageRel));
    await destination.parent.create(recursive: true);
    await tempFile.rename(destination.path);

    // Thumbnails are best-effort: a failure here must not lose the original.
    // 缩略图尽力而为：其失败不应导致原图丢失。
    String? thumbRel;
    try {
      final Uint8List thumbBytes = ImageUtils.createThumbnailSync(
        raw,
        AppConstants.thumbnailMaxSize,
      );
      final String thumbPathRel =
          PathUtils.thumbRelativePath(stickerId, '.jpg');
      final File thumbFile = File(await PathUtils.absolute(thumbPathRel));
      await thumbFile.parent.create(recursive: true);
      await thumbFile.writeAsBytes(thumbBytes, flush: true);
      thumbRel = thumbPathRel;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FileStore] thumbnail generation failed: $e');
      }
    }

    return ImportOutcome(
      wasDuplicate: false,
      sticker: Sticker(
        id: stickerId,
        seriesId: seriesId,
        name: name ?? '',
        relativePath: imageRel,
        thumbPath: thumbRel,
        width: decoded.width,
        height: decoded.height,
        byteSize: decoded.byteSize,
        sha256: hash,
        sortIndex: sortIndex,
        createdAt: DateUtils.nowUtc(),
        updatedAt: DateUtils.nowUtc(),
      ),
    );
  }

  /// Write raw bytes (e.g. a background image) to a relative path.
  /// 将原始字节（如背景图）写入指定相对路径。
  Future<String> writeRelative(String relativePath, Uint8List bytes) async {
    final File file = File(await PathUtils.absolute(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return relativePath;
  }

  /// Copy a file into a relative destination path.
  /// 复制文件到指定相对目标路径。
  Future<String> copyInto(String sourcePath, String relativePath) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw ImageException('源文件不存在: $sourcePath');
    }
    final File destination = File(await PathUtils.absolute(relativePath));
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    return relativePath;
  }

  /// Soft-delete: move a file into trash so the action can be undone.
  /// 软删除：将文件移入回收站，使操作可撤销。
  Future<void> moveToTrash(String relativePath) async {
    try {
      final File file = File(await PathUtils.absolute(relativePath));
      if (!await file.exists()) return;
      final String trashDir = await PathUtils.trashPath();
      final String target = p.join(
        trashDir,
        '${DateUtils.fileStamp(DateUtils.nowUtc())}_'
            '${PathUtils.baseName(relativePath)}',
      );
      await file.rename(target);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FileStore] moveToTrash failed for $relativePath: $e');
      }
    }
  }

  /// Permanently delete a file, ignoring absence.
  /// 永久删除文件，忽略文件不存在的情况。
  Future<void> delete(String relativePath) async {
    try {
      final File file = File(await PathUtils.absolute(relativePath));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FileStore] delete failed for $relativePath: $e');
      }
    }
  }

  /// Purge trash entries older than [AppConstants.trashRetention].
  /// 清除超过保留期的回收站条目。
  Future<int> purgeTrash() async {
    int removed = 0;
    try {
      final Directory trash = Directory(await PathUtils.trashPath());
      if (!await trash.exists()) return 0;
      final DateTime cutoff =
          DateUtils.nowUtc().subtract(AppConstants.trashRetention);
      await for (final FileSystemEntity entity in trash.list()) {
        if (entity is! File) continue;
        final FileStat stat = await entity.stat();
        if (stat.modified.toUtc().isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FileStore] purgeTrash failed: $e');
      }
    }
    return removed;
  }

  /// Absolute path for a stored relative path (convenience for UI layers).
  /// 存储的相对路径对应的绝对路径（供 UI 层便捷调用）。
  Future<String> abs(String relativePath) => PathUtils.absolute(relativePath);

  /// File existence check that never throws.
  /// 不会抛异常的文件存在性检查。
  Future<bool> exists(String relativePath) async {
    try {
      return await File(await PathUtils.absolute(relativePath)).exists();
    } catch (_) {
      return false;
    }
  }
}
