import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Shows the about sheet.
/// 展示关于面板。
///
/// A bottom sheet rather than a route: the content is a handful of lines with
/// nothing to navigate to, and keeping it off the route table means
/// `RoutePaths.settingsAbout` is not needed.
///
/// 用底部面板而非路由：内容只有几行且无下级页面，
/// 不放进路由表也就不需要 `RoutePaths.settingsAbout`。
Future<void> showAboutSheet(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.emoji_emotions_outlined,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        AppConstants.appName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '版本 ${AppConstants.appVersion}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '一个本地优先的表情包管理工具。\n'
                '表情包按系列收纳，系列与单张都可以有自己的分类、标签和备注，'
                '搜索时任意一项都能找到它们。',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
              const SizedBox(height: 18),
              const _InfoRow(
                icon: Icons.storage_outlined,
                label: '数据位置',
                value: '应用数据目录 / ${AppConstants.dataRootDir}',
              ),
              const _InfoRow(
                icon: Icons.cloud_off_outlined,
                label: '本地优先',
                value: '不联网也能完整使用',
              ),
              const _InfoRow(
                icon: Icons.backup_outlined,
                label: '备份格式',
                value: 'schema v${AppConstants.backupSchemaVersion}',
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 17,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
