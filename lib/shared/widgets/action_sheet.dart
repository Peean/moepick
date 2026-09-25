import 'package:flutter/material.dart';

/// A single labelled action shown in [showActionSheet].
/// [showActionSheet] 中展示的单条带标签操作。
class ActionSheetItem {
  const ActionSheetItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Highlight the item as currently engaged (e.g. already pinned / favourited).
  /// 将该操作高亮为「当前已启用」状态（如已置顶 / 已收藏）。
  final bool active;

  /// Render the item in the error colour (delete-style actions).
  /// 以错误色渲染该操作（删除类动作）。
  final bool destructive;
}

/// Show a bottom action sheet: a title plus a vertical list of labelled
/// actions. Each item closes the sheet before invoking its callback, so the
/// callback can safely use the caller's own context afterwards.
/// 弹出底部操作面板：一个标题加上一组垂直排列的带标签操作。
/// 每项在触发回调前先关闭面板，因此回调之后可安全使用调用方自己的 context。
Future<void> showActionSheet(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<ActionSheetItem> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (BuildContext ctx) => _ActionSheet(
      title: title,
      subtitle: subtitle,
      items: items,
    ),
  );
}

/// The panel behind [showActionSheet].
/// [showActionSheet] 背后的面板。
class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    this.title,
    this.subtitle,
    required this.items,
  });

  final String? title;
  final String? subtitle;
  final List<ActionSheetItem> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            for (final ActionSheetItem item in items) _ActionTile(item: item),
          ],
        ),
      ),
    );
  }
}

/// One row of the action sheet.
/// 操作面板中的单行。
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.item});

  final ActionSheetItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = item.destructive
        ? theme.colorScheme.error
        : (item.active
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface);

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        item.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(item.icon, size: 22, color: color),
            const SizedBox(width: 16),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                color: color,
                fontWeight: item.active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
