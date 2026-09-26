import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/path_utils.dart';

/// A picked image together with its original file name.
/// 所选图片与其原始文件名。
///
/// `image_picker`'s `XFile.path` on Android is a cache path whose file name is
/// a media-store id (e.g. `1000016848.gif`), NOT the user-visible name. The
/// real name lives in `XFile.name`; we carry it so imports can default to a
/// meaningful display name.
/// Android 上 `image_picker` 的 `XFile.path` 是缓存路径，其文件名是媒体库 id
/// （如 `1000016848.gif`），并非用户可见的名字。真实名字在 `XFile.name` 里；
/// 这里把它一并带上，使导入能以有意义的名字作为默认显示名。
class PickedImage {
  const PickedImage({required this.path, required this.name});

  /// Filesystem path to the (copied/cached) image.
  /// 图片（复制/缓存后）的文件系统路径。
  final String path;

  /// Original file name without extension; empty when the platform could not
  /// provide one (callers then fall back to deriving from [path]).
  /// 不含扩展名的原始文件名；平台无法提供时为空（调用方随后回退到 [path]）。
  final String name;
}

/// Platform-aware "pick one image from the device" helper.
/// 平台自适应的「从设备选择一张图片」工具。
///
/// WHY TWO PLUGINS: `image_picker` covers Android (including the photo picker
/// and camera roll) but has **no Windows implementation** at the time of
/// writing; `file_selector` has a first-class Windows implementation but its
/// Android support only routes through the system file browser, which is a poor
/// experience for photos. So the plugin is chosen by platform rather than
/// forcing one to do a job it does not do well.
///
/// 为何用两个插件：`image_picker` 覆盖 Android（含相册与系统照片选择器），
/// 但**没有 Windows 实现**；`file_selector` 有完善的 Windows 实现，
/// 但 Android 侧只能走系统文件浏览器，选照片体验很差。
/// 因此按平台选择插件，而非勉强用一个去干它不擅长的事。
///
/// Returns the picked file's absolute path, or null when the user cancelled.
/// 返回所选文件的绝对路径；用户取消时返回 null。
class ImagePickerService {
  ImagePickerService._();

  /// Image extensions offered to the desktop file browser.
  /// 桌面文件浏览器中可选的图片扩展名。
  static const List<String> imageExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  ];

  /// Pick a single image.
  /// 选择单张图片。
  ///
  /// [fromCamera] is Android-only: Windows has no camera-roll concept here and
  /// the file browser is always the right affordance.
  /// [fromCamera] 仅对 Android 有效：Windows 上没有这里的相册概念，
  /// 文件浏览器始终是正确选择。
  static Future<String?> pickSingle({bool fromCamera = false}) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      final XFile? picked = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // No resizing here: the storage layer decides the final dimensions, and
        // double-compressing would lose quality for no benefit.
        // 此处不压缩：最终尺寸由存储层决定，二次压缩只会损失画质而无收益。
      );
      return picked?.path;
    }

    // Windows / Linux / macOS.
    // Windows / Linux / macOS。
    const XTypeGroup group = XTypeGroup(
      label: '图片',
      extensions: imageExtensions,
    );
    final XFile? picked = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    return picked?.path;
  }

  /// Pick several images at once, returning each image's path and original name.
  /// 一次选择多张图片，返回每张图片的路径与原始文件名。
  static Future<List<PickedImage>> pickMultiple() async {
    if (kIsWeb) return <PickedImage>[];

    if (Platform.isAndroid || Platform.isIOS) {
      final List<XFile> picked = await ImagePicker().pickMultiImage();
      return picked.map(_toPickedImage).toList();
    }

    const XTypeGroup group = XTypeGroup(
      label: '图片',
      extensions: imageExtensions,
    );
    final List<XFile> picked =
        await openFiles(acceptedTypeGroups: <XTypeGroup>[group]);
    return picked.map(_toPickedImage).toList();
  }

  /// Convert a platform [XFile] into a [PickedImage], deriving the default
  /// display name from the original file name when available.
  /// 将平台 [XFile] 转为 [PickedImage]；可用时从原始文件名推导默认显示名。
  static PickedImage _toPickedImage(XFile f) {
    final String originalName = f.name.trim();
    return PickedImage(
      path: f.path,
      name: originalName.isEmpty
          ? ''
          : PathUtils.baseNameWithoutExt(originalName),
    );
  }
}
