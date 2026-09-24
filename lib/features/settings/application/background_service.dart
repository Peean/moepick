import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/file_store.dart';
import '../../../core/utils/hash_utils.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/models/app_settings.dart';

/// Shared [FileStore] instance (the single file-I/O gateway).
/// 共享的 [FileStore] 实例（唯一的文件 I/O 出口）。
final Provider<FileStore> fileStoreProvider = Provider<FileStore>(
  (Ref ref) => FileStore(),
);

/// Service that keeps a pre-blurred background bitmap in sync with the config.
/// 使预模糊背景位图与配置保持同步的服务。
///
/// WHY PRE-BLUR: Flutter 3.0 renders through Skia (no Impeller), where a
/// full-screen `BackdropFilter`/`ImageFiltered` re-samples **every frame**.
/// On mid-range Android hardware that reliably drops below 60fps. Blurring the
/// bitmap once and caching it on disk moves that cost out of the frame loop
/// entirely.
///
/// 为何预模糊：Flutter 3.0 走 Skia（无 Impeller），全屏 `BackdropFilter` /
/// `ImageFiltered` **每帧**都要重新采样，在中端 Android 上会稳定掉到 60fps 以下。
/// 将位图模糊一次并缓存到磁盘，可把该开销完全移出帧循环。
class BackgroundImageService {
  BackgroundImageService(this._files);

  final FileStore _files;

  /// Compute the hash that identifies a given (source, blur) combination.
  /// 计算标识特定（源图, 模糊度）组合的哈希。
  String cacheKey({
    required String sourceRelativePath,
    required double blurSigma,
    required bool useBlur,
    required int maxSize,
  }) {
    return HashUtils.ofString(
      '$sourceRelativePath|${useBlur ? blurSigma.toStringAsFixed(2) : '0'}|$maxSize',
    );
  }

  /// Ensure a blurred cache file exists, generating it when missing or stale.
  /// 确保模糊缓存文件存在，缺失或过期时重新生成。
  ///
  /// Returns the relative path of the cached file, or null when there is no
  /// image or generation failed (callers then fall back to the unblurred
  /// source rather than showing nothing).
  ///
  /// 返回缓存文件的相对路径；无图片或生成失败时返回 null
  /// （调用方随后退化为未模糊的原图，而不是什么都不显示）。
  Future<String?> ensureBlurred({
    required String sourceRelativePath,
    required double blurSigma,
    required bool useBlur,
  }) async {
    if (sourceRelativePath.isEmpty) return null;
    if (!useBlur || blurSigma <= 0) return null;

    final String key = cacheKey(
      sourceRelativePath: sourceRelativePath,
      blurSigma: blurSigma,
      useBlur: useBlur,
      maxSize: AppConstants.backgroundBlurMaxSize,
    );
    final String relative = PathUtils.backgroundBlurRelativePath(key);

    // Reuse the cache when the file is already on disk.
    // 缓存文件已在磁盘上时直接复用。
    if (await _files.exists(relative)) return relative;

    try {
      final String sourceAbs = await PathUtils.absolute(sourceRelativePath);
      final String outputAbs = await PathUtils.absolute(relative);

      // Run in an isolate: blurring a 720px bitmap takes tens of milliseconds
      // and would visibly stall the UI thread.
      // 放在 isolate 中执行：模糊 720px 位图需数十毫秒，在主线程会造成可见卡顿。
      await compute(
        preBlurBackground,
        PreBlurRequest(
          sourcePath: sourceAbs,
          outputPath: outputAbs,
          maxSize: AppConstants.backgroundBlurMaxSize,
          blurSigma: blurSigma,
        ),
      );

      // Delete sibling caches for the same source with a different blur value:
      // sliders generate one per drag otherwise.
      // 删除同源图下模糊值不同的兄弟缓存：否则拖动滑杆会不断产生新文件。
      await _pruneSiblings(exceptRelative: relative);

      return relative;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackgroundImageService] pre-blur failed: $e');
      }
      return null;
    }
  }

  /// Remove other cached blur files, keeping the current one.
  /// 删除其他模糊缓存文件，保留当前使用的那个。
  Future<void> _pruneSiblings({required String exceptRelative}) async {
    try {
      final Directory dir =
          Directory(await PathUtils.backgroundPath(create: false));
      if (!await dir.exists()) return;
      final String keepName = PathUtils.baseName(exceptRelative);
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final String name = PathUtils.baseName(entity.path);
        if (!name.startsWith('bg_blur_')) continue;
        if (name == keepName) continue;
        await entity.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackgroundImageService] prune failed: $e');
      }
    }
  }

  /// Decode the bitmap to paint: the blurred cache when available, else the
  /// original, else null.
  /// 解码用于绘制的位图：优先模糊缓存，其次原图，都没有则返回 null。
  Future<ui.Image?> loadForPaint(BackgroundConfig config) async {
    final String? source = config.imageRelativePath;
    if (source == null || source.isEmpty) return null;

    if (config.useBlur && config.blurSigma > 0) {
      final String? cached = await ensureBlurred(
        sourceRelativePath: source,
        blurSigma: config.blurSigma,
        useBlur: config.useBlur,
      );
      if (cached != null) {
        final ui.Image? image =
            await loadUiImage(File(await PathUtils.absolute(cached)));
        if (image != null) return image;
      }
    }

    // Cap the decode size: the background is never shown at native resolution,
    // and decoding a 4000px photo to paint it at 1080px wastes memory.
    // 限制解码尺寸：背景从不以原分辨率展示，
    // 把 4000px 照片解码后按 1080px 绘制会浪费内存。
    return loadUiImage(
      File(await PathUtils.absolute(source)),
      cacheWidth: AppConstants.backgroundBlurMaxSize,
    );
  }
}

/// Shared background image service.
/// 共享的背景图服务。
final Provider<BackgroundImageService> backgroundImageServiceProvider =
    Provider<BackgroundImageService>(
  (Ref ref) => BackgroundImageService(ref.watch(fileStoreProvider)),
);
