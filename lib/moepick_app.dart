import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_constants.dart';
import 'data/models/app_settings.dart';
import 'features/settings/application/settings_providers.dart';
import 'routes/app_router.dart';
import 'shared/widgets/app_background.dart';

/// Root widget: theme, router and the background layer.
/// 根组件：主题、路由与背景层。
///
/// Kept separate from `main.dart` so that widget tests can mount the real app
/// without running the start-up sequence (which opens Hive and touches the
/// filesystem).
///
/// 与 `main.dart` 分离，使 widget 测试可以挂载真实应用
/// 而不必执行启动流程（那会打开 Hive 并访问文件系统）。
class MoePickApp extends ConsumerWidget {
  const MoePickApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

    // go_router 4.x predates `routerConfig`; `MaterialApp.router` must be given
    // the provider, delegate and parser as three separate arguments. 5.x merged
    // them, which is why the modern single-argument form does not appear here.
    //
    // All three are required. `GoRouteInformationParser` asserts that the
    // `RouteInformation` handed to it is a `DebugGoRouteInformation` — a type
    // only `GoRouteInformationProvider` produces. Omitting the provider
    // therefore builds a Router that throws during state restoration, which
    // only surfaces as a crash once the framework tries to restore, not at
    // construction time.
    //
    // go_router 4.x 早于 `routerConfig`；`MaterialApp.router` 必须分别接收
    // provider、delegate 与 parser 三个参数。5.x 才将它们合并，因此此处看不到
    // 现代的单一参数写法。
    //
    // 三者缺一不可。`GoRouteInformationParser` 会断言传入的 `RouteInformation`
    // 是 `DebugGoRouteInformation`，而该类型只有 `GoRouteInformationProvider`
    // 才会产出。因此漏传 provider 会构造出一个在状态恢复阶段抛错的 Router——
    // 且该问题在构造时不暴露，只在框架尝试恢复时才表现为崩溃。
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: _themeMode(ref),
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,

      // The background lives here rather than in each page so it is mounted
      // exactly once and never re-decodes across navigations.
      // 背景挂在此处而非每页，因此只挂载一次，且跨导航不会重新解码。
      builder: (BuildContext context, Widget? child) {
        return AppBackground(child: child ?? const SizedBox.shrink());
      },
    );
  }

  /// Which theme the app should use.
  /// 应用应使用的主题。
  ///
  /// `followSystemTheme` maps to `ThemeMode.system`, which lets Flutter pick
  /// between [lightThemeProvider] and [darkThemeProvider] using the platform
  /// brightness. That is preferred over reading the brightness ourselves and
  /// forcing an explicit mode: the platform value updates on change when the
  /// mode is `system`, but must be listened to manually otherwise.
  ///
  /// `followSystemTheme` 映射为 `ThemeMode.system`，由 Flutter 依据平台亮度
  /// 在 [lightThemeProvider] 与 [darkThemeProvider] 之间选择。
  /// 这优于自行读取亮度后强制指定模式：模式为 `system` 时平台值变化会自动更新，
  /// 否则必须手动监听。
  ThemeMode _themeMode(WidgetRef ref) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    if (settings.followSystemTheme) return ThemeMode.system;
    return settings.useDarkMode ? ThemeMode.dark : ThemeMode.light;
  }
}
