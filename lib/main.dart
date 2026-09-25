import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/error/app_exception.dart';
import 'core/logging/app_log.dart';
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
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // `runZonedGuarded` is the Flutter 3.0 way to catch uncaught async errors
  // (`PlatformDispatcher.onError` only arrives in 3.3). Any error escaping the
  // zone still lands in the log file, so a device crash leaves a trace.
  // `runZonedGuarded` 是 Flutter 3.0 捕获未捕获异步错误的机制
  // （`PlatformDispatcher.onError` 到 3.3 才有）。任何逃出 zone 的错误仍会写入
  // 日志文件，使设备崩溃留下痕迹。
  runZonedGuarded(() async {
    await _bootstrap();
  }, (Object error, StackTrace stack) {
    AppLog.error('未捕获异常', error: error, stack: stack);
  });
}

Future<void> _bootstrap() async {
  // Initialise the logger first so every subsequent step — including start-up
  // failures — is captured to disk.
  // 最先初始化日志器，使后续每一步（含启动失败）都能落盘。
  try {
    await AppLog.init(await PathUtils.rootPath());
  } catch (e) {
    // Logging is best-effort; if even the directory cannot be created the app
    // should still try to start and report through the console.
    // 日志是尽力而为；若连目录都无法创建，应用仍应尝试启动并经控制台报告。
    debugPrint('日志初始化失败：$e');
  }

  // Route framework errors into the log file as well as the console.
  // 把框架错误同时写入日志文件与控制台。
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLog.error(
      '框架错误：${details.exception}',
      error: details.exception,
      stack: details.stack ?? StackTrace.current,
    );
    FlutterError.presentError(details);
  };

  AppLog.info('应用启动，版本 ${AppConstants.appVersion}');

  final HiveStore hiveStore;
  try {
    hiveStore = await HiveStore.open();
  } catch (e) {
    AppLog.error('数据库打开失败', error: e);
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
