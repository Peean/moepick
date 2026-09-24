import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A destination the user approved for a new file.
/// 用户已批准的新文件写入目标。
///
/// WHY THIS EXISTS / 为什么需要它
///
/// On Android 11+ the Storage Access Framework hands back a *content* URI whose
/// grant is bound to that URI — it does **not** authorise a raw filesystem path.
/// `file_picker.getDirectoryPath()` nevertheless converts the tree URI into a
/// raw path (`FileUtils.getFullPathFromTreeUri`) and returns it, so the old
/// "pick a folder, then `File(path).writeAsBytes(...)`" flow failed with a
/// permission error: the app holds no `WRITE_EXTERNAL_STORAGE`, and on scoped
/// storage that permission would not help anyway.
///
/// Android 11+ 上，SAF 返回的是**内容** URI，其授权绑定在该 URI 上，
/// 并**不**授权裸文件系统路径。而 `file_picker.getDirectoryPath()` 仍会把
/// tree URI 经 `FileUtils.getFullPathFromTreeUri` 转成裸路径返回，
/// 于是旧的「选文件夹 → `File(path).writeAsBytes(...)`」流程必然报权限不足：
/// 应用既没有 `WRITE_EXTERNAL_STORAGE`，分区存储下该权限也于事无补。
///
/// The fix is to stop writing to inferred paths. A destination is now a pair of
/// (approved directory, file name) — or an explicit absolute path on desktop —
/// and every byte goes through [writeBytes], which performs the platform-correct
/// operation.
///
/// 修复方式是停止向推断出的路径写入。目标现在是
/// （已批准的目录, 文件名）组合——桌面端则是显式绝对路径——
/// 且所有字节都经 [writeBytes] 写出，由它执行平台正确的操作。
@immutable
class SaveDestination {
  const SaveDestination({
    required this.path,
    this.directory,
    this.fileName,
  });

  /// Absolute path shown to the user and used directly on desktop.
  /// 展示给用户的绝对路径，桌面端直接使用。
  final String path;

  /// On Android: the directory the user approved. Null elsewhere.
  /// Android 上：用户批准的目录。其他平台为 null。
  final String? directory;

  /// File name to create inside [directory].
  /// 要在 [directory] 内创建的文件名。
  final String? fileName;

  /// True when bytes must be written by this app rather than handed to a
  /// platform dialog.
  /// 为真时，字节由本应用写出，而非交给平台对话框。
  bool get isAppWritten => directory != null && fileName != null;

  /// Last path segment, for toasts.
  /// 路径最后一段，用于提示条。
  String get displayName =>
      fileName ?? path.split(Platform.pathSeparator).last;

  /// Build the primary candidate together with fallback directories, ordered.
  /// 构建主候选与备选目录，按优先级排列。
  List<String> get candidates {
    if (!isAppWritten) return <String>[path];
    final String dir = directory!;
    final String name = fileName!;
    return <String>[
      p.join(dir, name),
      // A picked folder that maps to a read-only volume (some OEM file managers
      // hand back the card root) falls back to app-owned storage, which is
      // always writable and still user-reachable via 「Android/data」.
      // 选中的文件夹可能映射到只读卷（部分厂商文件管理器会返回卡根目录），
      // 此时退回到应用自有存储——它始终可写，且用户仍可在
      // 「Android/data」下访问。
      p.join(dir, AppDirNames.storageSubdir, name),
      p.join(dir, AppDirNames.homeSubdir, AppDirNames.importedSubdir, name),
    ];
  }
}

/// Directory names used by the fallback ladder.
/// 回退阶梯使用的目录名。
class AppDirNames {
  AppDirNames._();

  static const String homeSubdir = 'moepick';
  static const String storageSubdir = 'MoepickExports';
  static const String importedSubdir = 'Imports';

  /// Our own share of external storage, always writable without permissions.
  /// 自有的外部存储份额，无需权限即可写入。
  static const String externalRoot = 'MoepickExport';
}

/// Platform-aware "save a file" and "open a file" helper.
/// 平台自适应的「保存文件」与「打开文件」工具。
///
/// Two plugins are involved, chosen by platform:
///   - Android / iOS: `file_picker` (system Storage Access Framework dialogs).
///   - Desktop: `file_selector`, whose `getSavePath` / `openFile` are
///     first-class.
///
/// 两个插件按平台选择：
///   - Android / iOS：`file_picker`（系统 SAF 对话框）。
///   - 桌面端：`file_selector`，其 `getSavePath` / `openFile` 为原生实现。
class FileSaveService {
  FileSaveService._();

  /// Ask the user where to save [suggestedName].
  /// 询问用户把 [suggestedName] 保存到哪里。
  ///
  /// Returns the approved destination, or null when the user cancelled.
  /// 返回已批准的目标；用户取消时返回 null。
  static Future<SaveDestination?> chooseSaveDestination({
    required String suggestedName,
    String extensionLabel = 'zip',
  }) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid) {
      // `saveFile` is unimplemented on Android in file_picker 5.x, so ask for a
      // destination *folder* and keep it as (directory, name) instead of
      // flattening to a raw path we are not allowed to write.
      // Android 上 file_picker 5.x 未实现 `saveFile`，因此改为选择目标**文件夹**，
      // 并保留为（目录, 文件名），而不是压平成我们无权写入的裸路径。
      final String? dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择备份保存位置',
      );
      if (dir == null || dir.isEmpty) return null;
      return SaveDestination(
        path: p.join(dir, suggestedName),
        directory: dir,
        fileName: suggestedName,
      );
    }

    if (Platform.isIOS) {
      // iOS implements saveFile, so use it directly.
      // iOS 已实现 saveFile，直接使用。
      final String? target = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: <String>[extensionLabel],
      );
      if (target == null) return null;
      return SaveDestination(path: target);
    }

    // `getSavePath` is the 0.9.x API; `getSaveLocation` only arrives in 0.9.3+,
    // which requires a newer Flutter than this project targets.
    // `getSavePath` 是 0.9.x 的 API；`getSaveLocation` 要到 0.9.3+ 才有，
    // 而那需要比本项目目标更新的 Flutter。
    final String? path = await getSavePath(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: extensionLabel, extensions: <String>[extensionLabel]),
      ],
    );
    if (path == null) return null;
    return SaveDestination(path: path);
  }

  /// Write [bytes] to [destination], trying each candidate until one succeeds.
  /// 将 [bytes] 写入 [destination]，依次尝试各候选直到成功。
  ///
  /// Returns the path actually written.
  /// 返回实际写入的路径。
  ///
  /// WHY A LADDER / 为什么用阶梯
  ///
  /// The user-picked folder is a *request*, not a guarantee: a folder on a
  /// read-only volume, or one whose SAF grant is stale, fails at write time.
  /// Rather than surfacing a bare "permission denied" we fall back to a
  /// directory the app is certain it can write, and report where the file
  /// actually landed. The file is never lost, only relocated — and the caller
  /// can say so.
  ///
  /// 用户选中的文件夹是一个*请求*而非保证：只读卷上的文件夹、或 SAF 授权已过期的
  /// 文件夹都会在写入时失败。与其抛出赤裸的「权限不足」，不如退回到应用确定可写的
  /// 目录，并如实告知文件最终落在哪里。文件不会丢失，只是位置变了——调用方可以说明。
  static Future<SaveOutcome> writeBytes(
    SaveDestination destination,
    Uint8List bytes,
  ) async {
    Object? lastError;
    final List<String> tried = <String>[];

    for (final String candidate in destination.candidates) {
      tried.add(candidate);
      try {
        final File file = File(candidate);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        return SaveOutcome(path: candidate, usedFallback: tried.length > 1);
      } catch (e) {
        lastError = e;
      }
    }

    // Last resort on Android: app-private external storage needs no permission
    // on any API level this app supports.
    // Android 上最后一招：应用私有的外部存储在本应用支持的任一 API 级别
    // 都无需权限。
    if (Platform.isAndroid) {
      try {
        final Directory? root = await getExternalStorageDirectory();
        if (root != null) {
          final Directory dir =
              Directory(p.join(root.path, AppDirNames.externalRoot));
          await dir.create(recursive: true);
          final String name = destination.displayName;
          final File file = File(p.join(dir.path, name));
          await file.writeAsBytes(bytes, flush: true);
          return SaveOutcome(path: file.path, usedFallback: true);
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw FileSaveException(
      '无法写入所选位置，请换一个文件夹再试',
      cause: lastError,
      triedPaths: tried,
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

/// Where a save actually landed.
/// 保存实际落到何处。
@immutable
class SaveOutcome {
  const SaveOutcome({required this.path, required this.usedFallback});

  final String path;

  /// True when the user's first choice could not be written.
  /// 为真时表示用户的首选位置无法写入。
  final bool usedFallback;
}

/// Raised when every candidate destination refused the write.
/// 所有候选目标都拒绝写入时抛出。
class FileSaveException implements Exception {
  FileSaveException(
    this.message, {
    this.cause,
    this.triedPaths = const <String>[],
  });

  final String message;
  final Object? cause;
  final List<String> triedPaths;

  @override
  String toString() => 'FileSaveException: $message';
}
