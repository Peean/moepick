import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Platform-aware "save a file" and "open a file" helper.
/// 平台自适应的「保存文件」与「打开文件」工具。
///
/// Android has no native save dialog, and `file_selector`'s `getSaveLocation`
/// is desktop-only. So on Android a backup is written into the app's external
/// files directory and then handed to the system share sheet, which is the
/// platform-idiomatic way to get a file out of a sandboxed app.
///
/// Android 没有原生保存对话框，且 `file_selector` 的 `getSaveLocation` 仅桌面可用。
/// 因此在 Android 上，备份先写入应用的外部文件目录，再交给系统分享面板——
/// 这是在沙箱应用中将文件导出到外部的平台惯用方式。
class FileSaveService {
  FileSaveService._();

  /// Where Android backups land, as an absolute path.
  /// Android 备份的落盘目录（绝对路径）。
  static Future<String?> androidExportDir() async {
    if (!Platform.isAndroid) return null;
    try {
      // `getExternalStorageDirectory` is the app-scoped external dir on modern
      // Android (no permission needed); falling back to the app documents dir
      // keeps things working if it is unavailable.
      // 在现代 Android 上 `getExternalStorageDirectory` 是应用专属外部目录
      // （无需权限）；若不可用则回退到应用文档目录以保证仍能工作。
      final Directory? dir = await getExternalStorageDirectory();
      if (dir != null) return dir.path;
    } catch (_) {
      // Ignore and fall through to the documents directory.
      // 忽略并继续尝试文档目录。
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// Ask the user where to save [suggestedName].
  /// 询问用户把 [suggestedName] 保存到哪里。
  ///
  /// Returns the chosen absolute path, or null when the user cancelled. On
  /// Android (which cannot show a picker) this returns a path inside the export
  /// directory.
  ///
  /// 返回所选绝对路径；用户取消时返回 null。在无法展示选择器的 Android 上，
  /// 返回导出目录内的路径。
  static Future<String?> chooseSavePath({
    required String suggestedName,
    String extensionLabel = 'zip',
  }) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      final String? dir = await androidExportDir();
      if (dir == null) return null;
      return p.join(dir, suggestedName);
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

    final XFile? picked = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: label, extensions: extensions),
      ],
    );
    return picked?.path;
  }
}
