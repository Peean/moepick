import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../features/settings/application/settings_providers.dart';
import 'background_layer.dart';

/// Scaffold that adapts to the active background mode.
/// 随当前背景模式自适应的 scaffold。
///
/// Every page uses this instead of a raw [Scaffold]: in fullscreen mode the
/// background must remain visible, so the scaffull goes transparent and content
/// surfaces become translucent; in card mode the ordinary opaque theme surface
/// is used. Centralising the decision means pages never branch on the mode.
///
/// 所有页面使用它而非原生 [Scaffold]：全屏模式下背景必须保持可见，
/// 因此 scaffold 转为透明、内容表面转为半透明；卡片模式下使用普通不透明主题表面。
/// 集中做此决策，使各页面无需自行判断模式。
class MoeScaffold extends ConsumerWidget {
  const MoeScaffold({
    Key? key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.drawer,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  }) : super(key: key);

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? drawer;

  /// Explicit override; when null the mode decides.
  /// 显式覆盖；为 null 时由模式决定。
  final Color? backgroundColor;

  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackgroundConfig config = ref.watch(backgroundConfigProvider);
    final bool hasImage = config.hasImage;
    final bool fullscreen = config.mode == BackgroundMode.fullscreen;

    // Only go transparent when there is actually an image to reveal; otherwise
    // a transparent scaffold would show a bare window background.
    // 仅当确实有图片可透出时才转透明；否则透明 scaffold 会露出空洞的窗口底色。
    final Color resolvedBackground = backgroundColor ??
        (fullscreen && hasImage ? Colors.transparent : Theme.of(context).scaffoldBackgroundColor);

    PreferredSizeWidget? resolvedAppBar = appBar;
    if (resolvedAppBar != null && fullscreen && hasImage) {
      // Make the app bar translucent so the artwork is not cut off at the top.
      // The wrapper preserves the original height contract.
      // 使 app bar 半透明，避免图案在顶部被硬切断。
      // 包装类保留原有的高度契约。
      resolvedAppBar = _TranslucentAppBar(
        preferredSize: resolvedAppBar.preferredSize,
        child: resolvedAppBar,
      );
    }

    return Scaffold(
      backgroundColor: resolvedBackground,
      appBar: resolvedAppBar,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: body,
    );
  }
}

/// Wraps an app bar so it draws on a translucent surface while keeping the
/// original height contract.
/// 包裹 app bar，使其绘制在半透明表面上，同时保留原有高度契约。
class _TranslucentAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TranslucentAppBar({
    required this.preferredSize,
    required this.child,
  });

  @override
  final Size preferredSize;

  final PreferredSizeWidget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: Theme.of(context).appBarTheme.copyWith(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      ),
      child: child,
    );
  }
}

/// A card whose surface adapts to the background mode.
/// 表面随背景模式自适应的卡片。
///
/// In fullscreen mode, cards become translucent so the background remains
/// visible between them; in card mode they stay opaque.
/// 全屏模式下卡片转为半透明，使背景在卡片之间保持可见；卡片模式下保持不透明。
class MoeCard extends ConsumerWidget {
  const MoeCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.margin = EdgeInsets.zero,
  }) : super(key: key);

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackgroundConfig config = ref.watch(backgroundConfigProvider);
    final ThemeData theme = Theme.of(context);

    final bool fullscreen =
        config.mode == BackgroundMode.fullscreen && config.hasImage;

    Color surface = theme.colorScheme.surface;
    if (fullscreen) {
      // Blend toward the scaffold colour rather than pure transparency, so the
      // card still reads as a distinct layer instead of dissolving entirely.
      // 向 scaffold 颜色混合而非纯透明，使卡片仍能读出层次，而不是完全消解。
      surface = surface.withOpacity(
        BackgroundSurfaceStyle.of(BackgroundMode.fullscreen).surfaceOpacity,
      );
    }

    return Padding(
      padding: margin,
      child: Material(
        color: surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A section header used across settings screens.
/// 设置页通用的分区标题。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {Key? key, this.subtitle}) : super(key: key);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
              letterSpacing: 0.4,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
