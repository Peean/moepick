import 'package:flutter/material.dart';

import '../../../../data/models/category.dart';
import '../../../../data/models/series.dart';
import '../../../../data/models/sticker.dart';
import '../../../../data/models/tag.dart';
import '../../../../shared/widgets/moe_scaffold.dart';

/// Renders a series' own category / tag / note in an expandable card.
/// 以可展开卡片展示系列自身的分类 / 标签 / 备注。
///
/// Collapsed by default: on a series with many stickers the metadata is
/// reference information, and keeping it open would push the grid below the
/// fold on every visit.
///
/// 默认折叠：在有大量表情包的系列中，这些元数据属于「查阅型」信息，
/// 若默认展开会在每次进入时把网格推到首屏之外。
class InheritanceSummary extends StatefulWidget {
  const InheritanceSummary({
    Key? key,
    required this.series,
    required this.categoryById,
    required this.tagById,
  }) : super(key: key);

  final Series series;
  final Map<String, Category> categoryById;
  final Map<String, Tag> tagById;

  @override
  State<InheritanceSummary> createState() => _InheritanceSummaryState();
}

class _InheritanceSummaryState extends State<InheritanceSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Series series = widget.series;

    final bool hasAnyMeta = series.categoryIds.isNotEmpty ||
        series.tagIds.isNotEmpty ||
        series.note.isNotEmpty ||
        series.description.isNotEmpty;

    return MoeCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: hasAnyMeta ? () => setState(() => _expanded = !_expanded) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.folder_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  series.description.isEmpty
                      ? '系列信息'
                      : series.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: _expanded ? 4 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasAnyMeta)
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Always-visible condensed metadata, so the common case (a couple of
          // tags) needs no expansion at all.
          // 始终可见的浓缩元数据，使常见情况（少数几个标签）无需展开。
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ...series.categoryIds.take(3).map((String id) {
                final Category? c = widget.categoryById[id];
                if (c == null) return const SizedBox.shrink();
                return _MetaChip(
                  label: c.name,
                  color: Color(c.colorValue),
                  icon: Icons.folder_outlined,
                );
              }),
              ...series.tagIds.take(_expanded ? 99 : 3).map((String id) {
                final Tag? t = widget.tagById[id];
                if (t == null) return const SizedBox.shrink();
                return _MetaChip(
                  label: t.name,
                  color: theme.colorScheme.secondary,
                  icon: Icons.local_offer_outlined,
                );
              }),
              if (_expanded && series.note.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      series.note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ),
                ),
              if (!hasAnyMeta)
                Text(
                  '点右上角编辑，给这个系列加上分类、标签或备注',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
            ],
          ),

          if (_expanded && (series.categoryIds.isNotEmpty || series.tagIds.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '这些分类、标签和备注会被系列内的表情包继承；'
                '表情包自己设置分类时会覆盖系列分类，标签则是叠加。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small metadata chip.
/// 小型元数据芯片。
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: color),
          ),
        ],
      ),
    );
  }
}

/// Compact metadata chips for a single sticker, showing its *effective* values.
/// 单个表情包的紧凑元数据芯片，展示其**生效后**的值。
///
/// Distinguishes inherited values visually: a dimmed chip means "came from the
/// series", a solid one means "set on this sticker". Without that distinction
/// the override semantics are invisible and users cannot predict what clearing
/// a field will do.
///
/// 在视觉上区分继承值：淡色芯片表示「来自系列」，实色表示「在本张上设置」。
/// 缺少这一区分时覆盖语义将不可见，用户也无法预判清空某字段的后果。
class EffectiveMetaChips extends StatelessWidget {
  const EffectiveMetaChips({
    Key? key,
    required this.sticker,
    required this.series,
    required this.categoryById,
    required this.tagById,
    this.maxChips = 6,
  }) : super(key: key);

  final Sticker sticker;
  final Series? series;
  final Map<String, Category> categoryById;
  final Map<String, Tag> tagById;
  final int maxChips;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Set<String> ownCategories = sticker.categoryIds.toSet();
    final Set<String> ownTags = sticker.tagIds.toSet();

    // Category is either the sticker's own or the series' — never both.
    // 分类要么是表情包自身的，要么是系列的——不会同时存在。
    final bool categoryInherited = ownCategories.isEmpty;

    final List<Widget> chips = <Widget>[];

    for (final String id in sticker.categoryIds.take(maxChips)) {
      final Category? c = categoryById[id];
      if (c == null) continue;
      chips.add(_MetaChip(
        label: c.name,
        color: Color(c.colorValue),
        icon: Icons.folder_outlined,
      ));
    }
    if (categoryInherited && series != null) {
      for (final String id in series!.categoryIds.take(maxChips)) {
        final Category? c = categoryById[id];
        if (c == null) continue;
        chips.add(_MetaChip(
          label: c.name,
          color: Color(c.colorValue).withOpacity(0.55),
          icon: Icons.folder_outlined,
        ));
      }
    }

    for (final String id in sticker.tagIds.take(maxChips)) {
      final Tag? t = tagById[id];
      if (t == null) continue;
      chips.add(_MetaChip(
        label: t.name,
        color: theme.colorScheme.secondary,
        icon: Icons.local_offer_outlined,
      ));
    }
    if (series != null) {
      for (final String id in series!.tagIds.take(maxChips)) {
        if (ownTags.contains(id)) continue;
        final Tag? t = tagById[id];
        if (t == null) continue;
        chips.add(_MetaChip(
          label: t.name,
          color: theme.colorScheme.secondary.withOpacity(0.55),
          icon: Icons.local_offer_outlined,
        ));
      }
    }

    if (chips.isEmpty && (series?.note.isEmpty ?? true) && sticker.note.isEmpty) {
      return Text(
        '没有分类或标签',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }
}
