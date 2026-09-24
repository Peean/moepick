import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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

  /// Pick several images at once (desktop only; Android falls back to repeats).
  /// 一次选择多张图片（仅桌面端；Android 退化为多次单选）。
  static Future<List<String>> pickMultiple() async {
    if (kIsWeb) return <String>[];

    if (Platform.isAndroid || Platform.isIOS) {
      final List<XFile> picked =
          await ImagePicker().pickMultiImage();
      return picked.map((XFile f) => f.path).toList();
    }

    const XTypeGroup group = XTypeGroup(
      label: '图片',
      extensions: imageExtensions,
    );
    final List<XFile> picked =
        await openFiles(acceptedTypeGroups: <XTypeGroup>[group]);
    return picked.map((XFile f) => f.path).toList();
  }
}
