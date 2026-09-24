import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

/// Filesystem path helpers.
/// 文件系统路径工具。
///
/// THE RULE: the database stores only *relative* paths, never absolute ones.
/// Why:
///   - Android app sandbox paths change across reinstalls / app migrations.
///   - The Windows user profile directory can be relocated.
///   - Absolute paths are meaningless after restoring a backup on another device.
///
/// 核心规则：数据库只存**相对**路径，绝不存绝对路径。原因：
///   - Android 应用沙盒路径在重装 / 迁移后会变化。
///   - Windows 用户目录可能被重定位。
///   - 绝对路径在跨设备恢复备份后必然失效。
///
/// Every join goes through `package:path` so Windows `\` and Android `/` are
/// handled without hand-rolled string concatenation.
/// 所有拼接都走 `package:path`，以正确处理 Windows `\` 与 Android `/`，禁止手工拼接。
class PathUtils {
  PathUtils._();

  static String? _cachedRoot;

  /// Relative sub-directories inside the app data folder.
  /// 应用数据文件夹内的相对子目录。
  static const String imagesDir = 'images';
  static const String thumbsDir = 'thumbs';
  static const String coversDir = 'covers';
  static const String backgroundDir = 'background';
  static const String tempDir = 'temp';
  static const String trashDir = 'trash';

  /// Absolute path of the app data root, creating it on first use.
  /// 应用数据根的绝对路径，首次使用时创建。
  static Future<String> rootPath() async {
    final String cached = _cachedRoot ?? '';
    if (cached.isNotEmpty && await Directory(cached).exists()) {
      return cached;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final String root = p.join(docs.path, AppConstants.dataRootDir);
    await Directory(root).create(recursive: true);
    _cachedRoot = root;
    return root;
  }

  /// Override the cached root. Test-only seam so unit tests can point the app
  /// at a temporary directory without touching path_provider.
  /// 覆盖缓存的根路径。仅供测试使用，使单元测试无需依赖 path_provider
  /// 即可将应用指向临时目录。
  static void debugOverrideRoot(String? path) => _cachedRoot = path;

  /// Absolute path for a relative sub-directory, creating it.
  /// 相对子目录的绝对路径，并创建该目录。
  static Future<String> subDir(String name, {bool create = true}) async {
    final String abs = p.join(await rootPath(), name);
    if (create) {
      await Directory(abs).create(recursive: true);
    }
    return abs;
  }

  static Future<String> imagesPath({bool create = true}) =>
      subDir(imagesDir, create: create);
  static Future<String> thumbsPath({bool create = true}) =>
      subDir(thumbsDir, create: create);
  static Future<String> coversPath({bool create = true}) =>
      subDir(coversDir, create: create);
  static Future<String> backgroundPath({bool create = true}) =>
      subDir(backgroundDir, create: create);
  static Future<String> tempPath({bool create = true}) =>
      subDir(tempDir, create: create);
  static Future<String> trashPath({bool create = true}) =>
      subDir(p.join(tempDir, trashDir), create: create);

  /// Turn a stored relative path into an absolute one.
  /// 将存储的相对路径转为绝对路径。
  ///
  /// Accepts already-absolute paths and returns them unchanged, so legacy or
  /// externally supplied values do not break.
  /// 若传入的已是绝对路径则原样返回，避免历史数据或外部传值出错。
  static Future<String> absolute(String relative) async {
    if (p.isAbsolute(relative)) return relative;
    return p.join(await rootPath(), relative);
  }

  /// Turn an absolute path into the form stored in the database.
  /// 将绝对路径转为数据库中存储的形式。
  static Future<String> relative(String absolute) async {
    if (!p.isAbsolute(absolute)) return absolute;
    final String root = await rootPath();
    if (p.isWithin(root, absolute)) {
      return p.relative(absolute, from: root);
    }
    return absolute;
  }

  /// Absolute File for a stored relative path.
  /// 存储的相对路径对应的绝对 File。
  static Future<File> resolve(String relative) async =>
      File(await absolute(relative));

  /// Synchronous variant of [absolute], usable only once the root is cached
  /// (i.e. after app start-up has resolved it).
  /// [absolute] 的同步版本，仅在根路径已缓存后可用（即应用启动完成解析后）。
  ///
  /// Exists so hot paths such as grid item builders do not have to await the
  /// root inside a `FutureBuilder`, which would add a frame of blank content
  /// per tile during scrolling.
  ///
  /// 存在的目的是让网格 item builder 等热路径不必在 `FutureBuilder` 中等待根路径，
  /// 否则滚动时每个瓦片都会多出一帧空白。
  static String absoluteSync(String relative) {
    if (p.isAbsolute(relative)) return relative;
    final String root = _cachedRoot ?? '';
    if (root.isEmpty) return relative;
    return p.join(root, relative);
  }

  /// Whether the root has already been resolved and cached.
  /// 根路径是否已解析并缓存。
  static bool get hasCachedRoot => (_cachedRoot ?? '').isNotEmpty;

  /// Relative path for an image belonging to [id].
  /// 属于 [id] 的图片的相对路径。
  static String imageRelativePath(String id, String extension) =>
      p.join(imagesDir, '$id${_normalizeExt(extension)}');

  /// Relative path for a thumbnail belonging to [id].
  /// 属于 [id] 的缩略图的相对路径。
  static String thumbRelativePath(String id, String extension) =>
      p.join(thumbsDir, '${id}_t${_normalizeExt(extension)}');

  /// Relative path for a series cover.
  /// 系列封面的相对路径。
  static String coverRelativePath(String seriesId, String extension) =>
      p.join(coversDir, '$seriesId${_normalizeExt(extension)}');

  /// Relative path for a cached pre-blurred background.
  /// 预模糊背景缓存的相对路径。
  static String backgroundBlurRelativePath(String hash) =>
      p.join(backgroundDir, 'bg_blur_$hash.png');

  /// Relative path for the stored (unprocessed) background source image.
  /// 存储的（未处理）背景原图的相对路径。
  static String backgroundSourceRelativePath(String hash, String extension) =>
      p.join(backgroundDir, 'bg_src_$hash${_normalizeExt(extension)}');

  /// Ensure an extension starts with a dot and is lowercase.
  /// 确保扩展名以小写点号开头。
  static String _normalizeExt(String extension) {
    final String e = extension.trim().toLowerCase();
    if (e.isEmpty) return '.png';
    return e.startsWith('.') ? e : '.$e';
  }

  /// Extension of a path, lowercased and including the dot.
  /// 路径的扩展名，小写并含点号。
  static String extensionOf(String path) =>
      p.extension(path).toLowerCase().isEmpty
          ? '.png'
          : p.extension(path).toLowerCase();

  /// File name without directory.
  /// 去除目录后的文件名。
  static String baseName(String path) => p.basename(path);

  /// File name without extension.
  /// 去除扩展名的文件名。
  static String baseNameWithoutExt(String path) =>
      p.basenameWithoutExtension(path);
}
