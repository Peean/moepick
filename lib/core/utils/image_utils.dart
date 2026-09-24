import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../error/app_exception.dart';
import '../utils/path_utils.dart';

/// Result of decoding an image: dimensions plus the decoded bytes.
/// 图片解码结果：尺寸信息与解码后的字节。
///
/// Dart 2.17 has no records, so a small class carries the pair.
/// Dart 2.17 没有 records，因此用小类承载这对返回值。
class DecodedImageInfo {
  DecodedImageInfo({
    required this.width,
    required this.height,
    required this.bytes,
    required this.extension,
  });

  final int width;
  final int height;
  final Uint8List bytes;
  final String extension;

  int get byteSize => bytes.length;
}

/// Arguments for [preBlurBackground], passed across an isolate boundary so it
/// must stay a plain, serializable class (no closures, no `ref`).
/// [preBlurBackground] 的参数。需跨 isolate 传递，因此必须是可序列化的普通类
/// （不能含闭包、不能捕获 `ref`）。
class PreBlurRequest {
  const PreBlurRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.maxSize,
    required this.blurSigma,
    this.scaleHint = 3.0,
  });

  final String sourcePath;
  final String outputPath;
  final int maxSize;
  final double blurSigma;

  /// `sigma` of `package:image`'s gaussianBlur is roughly 1/3 of the visual
  /// radius, so the UI-facing value is scaled up for a comparable look.
  /// `package:image` 的 gaussianBlur 的 sigma 约为视觉半径的 1/3，
  /// 因此将面向 UI 的取值放大以取得相近效果。
  final double scaleHint;

  PreBlurRequest copyWith({double? blurSigma, String? outputPath}) {
    return PreBlurRequest(
      sourcePath: sourcePath,
      outputPath: outputPath ?? this.outputPath,
      maxSize: maxSize,
      blurSigma: blurSigma ?? this.blurSigma,
      scaleHint: scaleHint,
    );
  }
}

/// Standalone image helpers.
/// 独立的图片工具。
class ImageUtils {
  ImageUtils._();

  /// Decode enough of an image to learn its dimensions.
  /// 解码图片以获取尺寸信息。
  static Future<DecodedImageInfo> decode(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ImageException('无法识别的图片格式: ${file.path}');
    }
    return DecodedImageInfo(
      width: decoded.width,
      height: decoded.height,
      bytes: bytes,
      extension: PathUtils.extensionOf(file.path),
    );
  }

  /// Downscale bytes so the longest edge is at most [maxSize].
  /// 缩放字节数据，使最长边不超过 [maxSize]。
  ///
  /// Returns the original bytes untouched when already small enough, avoiding a
  /// pointless re-encode that would only lose quality.
  /// 若尺寸已足够小则原样返回，避免无意义的重编码导致画质损失。
  static Uint8List downscaleSync(Uint8List bytes, int maxSize) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final int longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (longest <= maxSize) return bytes;

    final img.Image resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? maxSize : null,
      height: decoded.height > decoded.width ? maxSize : null,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
  }

  /// Generate a JPEG thumbnail (longest edge ≤ [maxSize]).
  /// 生成 JPEG 缩略图（最长边 ≤ [maxSize]）。
  static Uint8List createThumbnailSync(Uint8List source, int maxSize) {
    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null) {
      throw ImageException('无法解码图片以生成缩略图');
    }
    final int longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final img.Image resized = longest <= maxSize
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSize : null,
            height: decoded.height > decoded.width ? maxSize : null,
            interpolation: img.Interpolation.average,
          );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  /// Scale a blur radius into the sigma expected by `package:image`.
  /// 将模糊半径换算为 `package:image` 期望的 sigma。
  static double sigmaFor(double radius) => radius / 3.0;

  /// Build the Gaussian blur used for background images.
  /// 生成用于背景图的高斯模糊。
  ///
  /// `package:image` exposes `gaussianBlur(radius:)`, and its own docs note the
  /// radius behaves like a sigma. Keeping the conversion in one place means the
  /// UI slider, the cached file and the live preview all agree.
  ///
  /// `package:image` 提供 `gaussianBlur(radius:)`，其 radius 实际等同 sigma。
  /// 将换算集中在此处，可保证 UI 滑杆、缓存文件与实时预览三者一致。
  static img.Image applyBlur(img.Image source, double sigma) {
    if (sigma <= 0) return source;
    return img.gaussianBlur(source, radius: sigma.round().clamp(1, 500));
  }
}

/// Top-level worker for background pre-blurring.
/// 背景预模糊的顶层工作函数。
///
/// MUST be a top-level (or static) function with serializable arguments: Dart
/// 2.17 forbids `compute` closures from capturing `ref`, `BuildContext` or any
/// non-sendable object.
/// 必须是顶层（或静态）函数且参数可序列化：Dart 2.17 下 `compute` 的闭包
/// 不能捕获 `ref`、`BuildContext` 或任何不可发送的对象。
///
/// Returns the output file path on success.
/// 成功时返回输出文件路径。
Future<String> preBlurBackground(PreBlurRequest request) async {
  final File source = File(request.sourcePath);
  if (!await source.exists()) {
    throw ImageException('背景原图不存在: ${request.sourcePath}');
  }

  final Uint8List bytes = await source.readAsBytes();
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw ImageException('无法解码背景图');
  }

  // 1. Downscale first: blurring a small image is dramatically cheaper and the
  //    background is never viewed at full resolution anyway.
  // 1. 先降采样：小图模糊代价低得多，且背景本就不会以原分辨率显示。
  final int longest =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longest > request.maxSize) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? request.maxSize : null,
      height: decoded.height > decoded.width ? request.maxSize : null,
      interpolation: img.Interpolation.average,
    );
  }

  // 2. Blur the downscaled bitmap once. The result is written to disk and
  //    reused across app restarts, so this cost is paid rarely.
  // 2. 对小图模糊一次。结果写入磁盘并跨重启复用，因此该代价很少付出。
  final img.Image blurred = ImageUtils.applyBlur(
    decoded,
    ImageUtils.sigmaFor(request.blurSigma * request.scaleHint),
  );

  final File output = File(request.outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsBytes(img.encodePng(blurred), flush: true);

  return output.path;
}

/// Decode a file into a `ui.Image` for direct painting via `RawImage`.
/// 将文件解码为 `ui.Image`，用于通过 `RawImage` 直接绘制。
///
/// Returns null when the file is missing or corrupt, letting callers fall back
/// to a solid colour instead of crashing the whole background.
/// 文件缺失或损坏时返回 null，使调用方可退化为纯色而非整个背景崩掉。
Future<ui.Image?> loadUiImage(File file, {int? cacheWidth}) async {
  try {
    if (!await file.exists()) return null;
    final Uint8List bytes = await file.readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: cacheWidth,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[ImageUtils] loadUiImage failed for ${file.path}: $e');
    }
    return null;
  }
}
