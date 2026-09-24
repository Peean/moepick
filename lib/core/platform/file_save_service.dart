import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Platform-aware "save a file" and "open a file" helper.
/// 平台自适应的「保存文件」与「打开文件」工具。
///
/// Two plugins are involved, chosen by platform:
///   - Android / iOS: `file_picker` (system Storage Access Framework dialogs).
///     On Android `saveFile` is not implemented in file_picker 5.x, so a backup
///     is exported by letting the user pick a destination *folder* via
///     `getDirectoryPath` and then writing the suggested file name into it —
///     which is exactly the "choose where to save" flow the user expects.
///   - Desktop: `file_selector`, whose `getSavePath` / `openFile` are first-class.
///
/// 两个插件按平台选择：
///   - Android / iOS：`file_picker`（系统 SAF 对话框）。Android 上 file_picker 5.x
///     未实现 `saveFile`，因此备份导出改为让用户通过 `getDirectoryPath` 选择目标
///     **文件夹**，再把建议文件名写入其中——这正是用户期望的「选择保存位置」流程。
///   - 桌面端：`file_selector`，其 `getSavePath` / `openFile` 为原生实现。
class FileSaveService {
  FileSaveService._();

  /// Ask the user where to save [suggestedName].
  /// 询问用户把 [suggestedName] 保存到哪里。
  ///
  /// Returns the chosen absolute path, or null when the user cancelled.
  /// 返回所选绝对路径；用户取消时返回 null。
  static Future<String?> chooseSavePath({
    required String suggestedName,
    String extensionLabel = 'zip',
  }) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid) {
      // Android has no save dialog in file_picker 5.x, so pick a destination
      // folder instead and combine it with the suggested name.
      // Android 上 file_picker 5.x 无保存对话框，因此改为选择目标文件夹，
      // 再与建议文件名组合。
      final String? dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择备份保存位置',
      );
      if (dir == null || dir.isEmpty) return null;
      return p.join(dir, suggestedName);
    }

    if (Platform.isIOS) {
      // iOS implements saveFile, so use it directly.
      // iOS 已实现 saveFile，直接使用。
      return FilePicker.platform.saveFile(
        dialogTitle: '保存备份',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: <String>[extensionLabel],
      );
    }

    // `getSavePath` is the 0.9.x API; `getSaveLocation` only arrives in 0.9.3+,
    // which requires a newer Flutter than this project targets.
    // `getSavePath` 是 0.9.x 的 API；`getSaveLocation` 要到 0.9.3+ 才有，
    // 而那需要比本项目目标更新的 Flutter。
    return getSavePath(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: extensionLabel, extensions: <String>[extensionLabel]),
      ],
    );
  }

  /// Ask the user to pick an existing file.
  /// 询问用户选择一个已有文件。
  static Future<String?> chooseOpenPath({
    List<String> extensions = const <String>['zip'],
    String label = '备份文件',
  }) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择备份文件',
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.single.path;
    }

    final XFile? picked = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: label, extensions: extensions),
      ],
    );
    return picked?.path;
  }
}
