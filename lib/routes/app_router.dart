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
import '../features/settings/presentation/trash_page.dart';
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
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _fadeThroughPage(const LibraryPage(), state),
        routes: <GoRoute>[
          GoRoute(
            path: 'search',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _fadeThroughPage(const SearchPage(), state),
          ),
          GoRoute(
            path: 'settings',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _fadeThroughPage(const SettingsPage(), state),
            routes: <GoRoute>[
              GoRoute(
                path: 'theme',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(const ThemeSettingsPage(), state),
              ),
              GoRoute(
                path: 'background',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(const BackgroundSettingsPage(), state),
              ),
              GoRoute(
                path: 'taxonomy',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(const TaxonomyPage(), state),
              ),
              GoRoute(
                path: 'trash',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(const TrashPage(), state),
              ),
              GoRoute(
                path: 'backup',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(const BackupPage(), state),
              ),
              GoRoute(
                path: 'webdav',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(const WebDavSettingsPage(), state),
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
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _fadeThroughPage(const SeriesEditPage(), state),
          ),
          GoRoute(
            path: 'series/:id',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _fadeThroughPage(
              SeriesDetailPage(seriesId: state.params['id'] ?? ''),
              state,
            ),
            routes: <GoRoute>[
              GoRoute(
                path: 'edit',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(
                  SeriesEditPage(seriesId: state.params['id'] ?? ''),
                  state,
                ),
              ),
            ],
          ),

          // Sticker routes, likewise nested so the back gesture returns to the
          // series instead of exiting the app.
          // 表情包路由，同样嵌套，使返回手势回到系列而非退出应用。
          GoRoute(
            path: 'sticker/:id',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _fadeThroughPage(
              StickerDetailPage(stickerId: state.params['id'] ?? ''),
              state,
            ),
            routes: <GoRoute>[
              GoRoute(
                path: 'edit',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadeThroughPage(
                  StickerEditPage(stickerId: state.params['id'] ?? ''),
                  state,
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

/// A "fade-through" page transition shared by every route.
/// 所有路由共用的「淡入淡出」页面转场。
///
/// WHY NOT THE PLATFORM DEFAULT / 为什么不用平台默认转场
///
/// The app draws one global background image *behind* the Navigator (see
/// AppBackground), and every page's scaffold is transparent so the background
/// shows through. With the platform zoom/slide transition the covered page
/// keeps rendering at full opacity until the incoming page physically covers
/// it — with transparent scaffolds the user then sees *both* pages' content
/// stacked on the same background, and the old content vanishes only when the
/// transition ends. That is the reported "background jumps when switching
/// pages".
///
/// 应用在 Navigator **背后**绘制一张全局背景图（见 AppBackground），
/// 且每个页面的 scaffold 都是透明的，使背景透出。在平台默认的缩放/滑动转场下，
/// 被覆盖的页面会一直以完全不透明的方式渲染，直到新页面物理上盖住它——
/// 由于 scaffold 透明，用户会在同一背景上看到**两层**页面内容叠在一起，
/// 而旧内容要到转场结束才突然消失。这正是「切换页面时背景跳变」的原因。
///
/// The fix is to fade the covered page out *during* the transition instead of
/// waiting to be covered. The background itself never moves, so a cross-fade
/// reads as one continuous surface.
///
/// 修复方式是让被覆盖的页面在转场**过程中**淡出，而不是等着被盖住。
/// 背景本身不动，交叉淡入淡出看起来就是一块连续的表面。
CustomTransitionPage<void> _fadeThroughPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder:
        (BuildContext context, Animation<double> animation,
            Animation<double> secondaryAnimation, Widget child) {
      // Covered page: fade out as the new page arrives (reversed on pop, so
      // the page below fades back in).
      // 被覆盖的页面：随新页到来而淡出（返回时反向，下方页面随之淡入）。
      final Animation<double> coveredFade = Tween<double>(begin: 1.0, end: 0.0)
          .animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut));

      return FadeTransition(
        opacity: coveredFade,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );
    },
  );
}
