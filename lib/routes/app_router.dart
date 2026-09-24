import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/library/presentation/library_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/series/presentation/series_detail_page.dart';
import '../features/series/presentation/series_edit_page.dart';
import '../features/settings/presentation/background_settings_page.dart';
import '../features/settings/presentation/backup_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/taxonomy_page.dart';
import '../features/settings/presentation/theme_settings_page.dart';
import '../features/settings/presentation/webdav_settings_page.dart';
import '../features/sticker/presentation/sticker_detail_page.dart';
import '../features/sticker/presentation/sticker_edit_page.dart';
import '../shared/widgets/common.dart';
import 'route_paths.dart';

/// The application router.
/// 应用路由器。
///
/// Built on go_router 4.5.1, which is the newest release compatible with
/// Flutter 3.0 (5.x requires Flutter >= 3.3). Note the 4.x API differences from
/// modern go_router: parameters come from `state.params`, there is no
/// `StatefulShellRoute`, and `routerConfig:` is used on `MaterialApp`.
///
/// 基于 go_router 4.5.1，这是与 Flutter 3.0 兼容的最新版本（5.x 要求 Flutter ≥3.3）。
/// 注意与新版 API 的差异：参数取自 `state.params`，没有 `StatefulShellRoute`，
/// `MaterialApp` 上使用 `routerConfig:`。
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: RoutePaths.library,
    debugLogDiagnostics: false,
    routes: <GoRoute>[
      GoRoute(
        path: RoutePaths.library,
        builder: (BuildContext context, GoRouterState state) =>
            const LibraryPage(),
        routes: <GoRoute>[
          GoRoute(
            path: 'search',
            builder: (BuildContext context, GoRouterState state) =>
                const SearchPage(),
          ),
          GoRoute(
            path: 'settings',
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsPage(),
            routes: <GoRoute>[
              GoRoute(
                path: 'theme',
                builder: (BuildContext context, GoRouterState state) =>
                    const ThemeSettingsPage(),
              ),
              GoRoute(
                path: 'background',
                builder: (BuildContext context, GoRouterState state) =>
                    const BackgroundSettingsPage(),
              ),
              GoRoute(
                path: 'taxonomy',
                builder: (BuildContext context, GoRouterState state) =>
                    const TaxonomyPage(),
              ),
              GoRoute(
                path: 'backup',
                builder: (BuildContext context, GoRouterState state) =>
                    const BackupPage(),
              ),
              GoRoute(
                path: 'webdav',
                builder: (BuildContext context, GoRouterState state) =>
                    const WebDavSettingsPage(),
              ),
            ],
          ),

          // Series routes live UNDER the library route so the home screen stays
          // on the navigation stack. `create` is declared before `:id` so that a
          // literal segment is never captured as an id.
          //
          // 系列路由挂在 library 之下，使主页始终保留在导航栈中。
          // `create` 声明在 `:id` 之前，避免字面量段被当作 id 捕获。
          GoRoute(
            path: 'series/create',
            builder: (BuildContext context, GoRouterState state) =>
                const SeriesEditPage(),
          ),
          GoRoute(
            path: 'series/:id',
            builder: (BuildContext context, GoRouterState state) =>
                SeriesDetailPage(
              seriesId: state.params['id'] ?? '',
            ),
            routes: <GoRoute>[
              GoRoute(
                path: 'edit',
                builder: (BuildContext context, GoRouterState state) =>
                    SeriesEditPage(
                  seriesId: state.params['id'] ?? '',
                ),
              ),
            ],
          ),

          // Sticker routes, likewise nested so the back gesture returns to the
          // series instead of exiting the app.
          // 表情包路由，同样嵌套，使返回手势回到系列而非退出应用。
          GoRoute(
            path: 'sticker/:id',
            builder: (BuildContext context, GoRouterState state) =>
                StickerDetailPage(
              stickerId: state.params['id'] ?? '',
            ),
            routes: <GoRoute>[
              GoRoute(
                path: 'edit',
                builder: (BuildContext context, GoRouterState state) =>
                    StickerEditPage(
                  stickerId: state.params['id'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: '找不到这个页面',
        message: state.location,
        action: ElevatedButton(
          onPressed: () => context.go(RoutePaths.library),
          child: const Text('回到首页'),
        ),
      ),
    ),
  );
});
