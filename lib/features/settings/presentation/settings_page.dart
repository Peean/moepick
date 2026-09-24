import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../library/application/library_providers.dart';
import '../application/settings_providers.dart';
import 'about_page.dart';

/// Settings hub.
/// 设置中心。
///
/// Deliberately a plain list rather than a scroll of inline controls: each
/// concern (theme, background, taxonomy, backup, sync) has enough surface area
/// to deserve its own screen, and this keeps the hub scannable.
///
/// 刻意做成纯列表而非一排内联控件：主题、背景、分类体系、备份、同步各自的内容量
/// 都足以独占一屏，集中成索引更易浏览。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final BackgroundConfig background = ref.watch(backgroundConfigProvider);
    final Map<String, int> stats = ref.watch(libraryStatsProvider);
    final int trashCount = ref.watch(trashCountProvider);

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.library),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _StatsStrip(stats: stats),

          const SectionHeader('外观'),
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: '主题色',
            subtitle: _themeSubtitle(settings),
            trailing: _ColorSwatch(color: Color(settings.seedColorValue)),
            onTap: () => context.go(RoutePaths.settingsTheme),
          ),
          _SettingsTile(
            icon: Icons.wallpaper_outlined,
            title: '背景图片',
            subtitle: _backgroundSubtitle(background),
            onTap: () => context.go(RoutePaths.settingsBackground),
          ),

          const SectionHeader('内容'),
          _SettingsTile(
            icon: Icons.local_offer_outlined,
            title: '分类与标签',
            subtitle: '${stats['categories']} 个分类 · ${stats['tags']} 个标签',
            onTap: () => context.go(RoutePaths.settingsTaxonomy),
          ),

          const SectionHeader('数据'),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: '回收站',
            subtitle: trashCount > 0
                ? '$trashCount 个条目 · 保留 7 天'
                : '已删除的系列与表情包在这里还原',
            onTap: () => context.go(RoutePaths.settingsTrash),
          ),
          _SettingsTile(
            icon: Icons.backup_outlined,
            title: '备份与恢复',
            subtitle: '导出到本地文件，或从备份还原',
            onTap: () => context.go(RoutePaths.settingsBackup),
          ),
          _SettingsTile(
            icon: Icons.cloud_sync_outlined,
            title: 'WebDAV 同步',
            subtitle: '多设备自动同步表情包与设置',
            onTap: () => context.go(RoutePaths.settingsWebdav),
          ),

          const SectionHeader('关于'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: '关于拾萌',
            subtitle: '版本 ${AppConstants.appVersion}',
            onTap: () => showAboutSheet(context),
          ),
        ],
      ),
    );
  }

  /// Summarise the theme choice in one line, avoiding a bare colour code.
  /// 用一行概括主题选择，避免只显示色值。
  static String _themeSubtitle(AppSettings settings) {
    final ThemePreset? preset = AppTheme.presetFor(settings.seedColorValue);
    final String name = preset?.label ?? '自定义';
    final String mode;
    if (settings.followSystemTheme) {
      mode = '跟随系统';
    } else {
      mode = settings.useDarkMode ? '深色' : '浅色';
    }
    return '$name · $mode · 每行 ${settings.gridColumns} 列';
  }

  static String _backgroundSubtitle(BackgroundConfig config) {
    if (!config.hasImage) return '未设置';
    final String mode =
        config.mode == BackgroundMode.fullscreen ? '全屏' : '卡片';
    final String blur = config.useBlur && config.blurSigma > 0
        ? ' · 模糊 ${config.blurSigma.toStringAsFixed(0)}'
        : '';
    return '$mode · 不透明度 ${(config.opacity * 100).round()}%$blur';
  }
}

/// Compact row of counts so the hub immediately conveys library size.
/// 紧凑的计数行，使设置页一眼可见库的规模。
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});

  final Map<String, int> stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: <Widget>[
          _StatsCell(label: '系列', value: stats['series'] ?? 0),
          _StatsCell(label: '表情包', value: stats['stickers'] ?? 0),
          _StatsCell(label: '分类', value: stats['categories'] ?? 0),
          _StatsCell(label: '标签', value: stats['tags'] ?? 0),
        ],
      ),
    );
  }
}

class _StatsCell extends StatelessWidget {
  const _StatsCell({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single navigable settings row.
/// 单条可跳转的设置行。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.08)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  trailing!,
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular colour preview used as a trailing widget on the theme row.
/// 主题行尾部的圆形颜色预览。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
        ),
      ),
    );
  }
}
