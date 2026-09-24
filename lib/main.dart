import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/error/app_exception.dart';
import 'core/storage/hive_store.dart';
import 'core/storage/secure_store.dart';
import 'core/utils/path_utils.dart';
import 'features/settings/application/storage_providers.dart';
import 'moepick_app.dart';

/// Entry point.
/// 应用入口。
///
/// Heavy initialisation happens *before* `runApp`, and the results are injected
/// through provider overrides rather than having each provider do its own async
/// open. Reasons:
///
///   1. A single, explicit startup sequence is far easier to reason about than
///      N lazily-opening providers.
///   2. Hive boxes must be open before the first frame reads them; otherwise the
///      first paint shows defaults and then flickers to real values.
///
/// 重量级初始化在 `runApp` **之前**完成，结果通过 provider override 注入，
/// 而不是让每个 provider 各自异步打开。原因：
///
///   1. 单一、显式的启动流程远比 N 个惰性打开的 provider 易于理解。
///   2. Hive box 必须在首帧读取之前打开；否则首帧显示默认值，随后闪烁为真实值。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route every framework error into a log file as well as the console, so a
  // crash on a machine without a terminal still leaves a full stack trace.
  // 把所有框架错误同时写入日志文件，使无终端环境下的崩溃也留有完整堆栈。
  final File errorLog = File(
    '${await PathUtils.rootPath()}${Platform.pathSeparator}error.log',
  );
  Future<void> log(Object detail, StackTrace? stack) async {
    try {
      await errorLog.writeAsString(
        '$detail\n$stack\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
    debugPrint('$detail\n$stack');
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    log(
      'FLUTTER ERROR: ${details.exception}',
      details.stack ?? StackTrace.current,
    );
    FlutterError.presentError(details);
  };

  final HiveStore hiveStore;
  try {
    hiveStore = await HiveStore.open();
  } catch (e) {
    // The app cannot function without its database. Show a real message instead
    // of a white screen or a red error box.
    // 没有数据库应用无法工作。展示真实提示，而不是白屏或红色报错框。
    runApp(_StartupFailureApp(error: e));
    return;
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        hiveStoreProvider.overrideWithValue(hiveStore),
        // Constructed eagerly so the degraded-storage flag is known before the
        // settings screen asks for it.
        // 提前构造，使降级存储标记在设置页请求之前就已确定。
        secureStoreProvider.overrideWithValue(SecureStore()),
      ],
      child: const MoePickApp(),
    ),
  );
}

/// Minimal app shown when start-up fails.
/// 启动失败时展示的最小应用。
///
/// Deliberately does not use the full app shell: the shell depends on the very
/// providers that just failed to initialise.
/// 有意不使用完整应用外壳：外壳依赖的正是刚刚初始化失败的 provider。
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final String detail =
        error is AppException ? (error as AppException).message : '$error';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      theme: ThemeData(useMaterial3: false),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '${AppConstants.appName} 启动失败',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请尝试重启应用；若问题持续，可能是本地数据目录不可写。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
