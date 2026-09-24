import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/path_utils.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';

/// The recycle bin: soft-deleted series and stickers, restorable until
/// purged (either manually or after the retention window).
/// 回收站：已软删除的系列与表情包，在被彻底删除前（手动或超过保留期）
/// 均可还原。
///
/// Supports single-item actions and, via long-press, multi-select with batch
/// restore / purge.
///
/// 既支持单条操作，也支持长按进入多选后批量还原 / 彻底删除。
class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({Key? key}) : super(key: key);

  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  bool _purging = false;

  /// Multi-select state. Keys are `k:<stickerId>` / `s:<seriesId>`.
  /// 多选状态。键为 `k:<表情包id>` / `s:<系列id>`。
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  static String _stickerKey(String id) => 'k:$id';
  static String _seriesKey(String id) => 's:$id';

  @override
  void initState() {
    super.initState();
    // Retention enforcement happens on open: a periodic timer would keep the
    // app alive for no other purpose, and a slightly-late purge is harmless.
    // 保留期在打开时执行：为它开定时器会让应用无缘无故常驻，
    // 而稍晚一点的清除并无大碍。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryActionsProvider).purgeExpired();
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Sticker> stickers = ref.watch(trashStickersProvider);
    final List<Series> series = ref.watch(trashSeriesProvider);

    // A deleted sticker's parent may itself be deleted, so merge live and
    // trashed series into one lookup.
    // 已删除表情包的父系列可能也已被删除，因此将存活与回收站系列合并查找。
    final Map<String, Series> seriesById = <String, Series>{
      for (final Series s in ref.watch(seriesByIdProvider).values) s.id: s,
      for (final Series s in series) s.id: s,
    };

    final bool empty = stickers.isEmpty && series.isEmpty;
    final int total = stickers.length + series.length;

    return MoeScaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selected.length} 项' : '回收站'),
        leading: IconButton(
          icon: Icon(_selectionMode ? Icons.close : Icons.arrow_back),
          onPressed: () {
            if (_selectionMode) {
              _exitSelection();
            } else {
              context.go(RoutePaths.settings);
            }
          },
        ),
        actions: _selectionMode
            ? <Widget>[
                IconButton(
                  tooltip: _selected.length == total ? '取消全选' : '全选',
                  icon: const Icon(Icons.select_all_outlined),
                  onPressed: _toggleSelectAll,
                ),
                IconButton(
                  tooltip: '批量还原',
                  icon: const Icon(Icons.restore_from_trash_outlined),
                  onPressed: _selected.isEmpty ? null : _restoreSelected,
                ),
                IconButton(
                  tooltip: '彻底删除所选',
                  icon: Icon(
                    Icons.delete_forever_outlined,
                    color: _selected.isEmpty
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _selected.isEmpty ? null : _purgeSelected,
                ),
              ]
            : <Widget>[
                if (!empty)
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String value) {
                      if (value == 'empty') _emptyTrash();
                    },
                    itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'empty',
                        child: DestructiveMenuItem(
                          icon: Icons.delete_forever_outlined,
                          label: '清空回收站',
                        ),
                      ),
                    ],
                  ),
              ],
      ),
      body: Stack(
        children: <Widget>[
          if (empty)
            const EmptyState(
              icon: Icons.delete_outline,
              title: '回收站是空的',
              message: '删除的系列和表情包会先到这里，\n保留 7 天后自动清除。',
            )
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: <Widget>[
                if (series.isNotEmpty) ...<Widget>[
                  const SectionHeader('已删除的系列'),
                  ...series.map(
                    (Series s) => _SeriesRow(
                      series: s,
                      busy: _purging,
                      selectionMode: _selectionMode,
                      selected: _selected.contains(_seriesKey(s.id)),
                      onTap: () => _onRowTap(_seriesKey(s.id)),
                      onLongPress: () => _onRowLongPress(_seriesKey(s.id)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (stickers.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    '已删除的表情包',
                    subtitle: '${stickers.length} 个',
                  ),
                  ...stickers.map(
                    (Sticker s) => _StickerRow(
                      sticker: s,
                      series: seriesById[s.seriesId],
                      busy: _purging,
                      selectionMode: _selectionMode,
                      selected: _selected.contains(_stickerKey(s.id)),
                      onTap: () => _onRowTap(_stickerKey(s.id)),
                      onLongPress: () => _onRowLongPress(_stickerKey(s.id)),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const _TrashNote(),
              ],
            ),
          if (_purging)
            ColoredBox(
              color: Colors.black.withOpacity(0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void _enterSelection(String key) {
    setState(() {
      _selectionMode = true;
      _selected.clear();
      _selected.add(key);
    });
  }

  void _onRowTap(String key) {
    if (!_selectionMode) return;
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _onRowLongPress(String key) {
    if (_selectionMode) {
      _onRowTap(key);
    } else {
      _enterSelection(key);
    }
  }

  void _toggleSelectAll() {
    final List<Sticker> stickers = ref.read(trashStickersProvider);
    final List<Series> series = ref.read(trashSeriesProvider);
    final int total = stickers.length + series.length;
    setState(() {
      if (_selected.length == total) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(stickers.map((Sticker s) => _stickerKey(s.id)))
          ..addAll(series.map((Series s) => _seriesKey(s.id)));
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  Future<void> _restoreSelected() async {
    final List<Sticker> stickers = ref.read(trashStickersProvider);
    final List<Series> series = ref.read(trashSeriesProvider);
    final List<String> stickerIds = stickers
        .where((Sticker s) => _selected.contains(_stickerKey(s.id)))
        .map((Sticker s) => s.id)
        .toList();
    final List<Series> chosenSeries = series
        .where((Series s) => _selected.contains(_seriesKey(s.id)))
        .toList();
    final int count = stickerIds.length + chosenSeries.length;

    setState(() => _purging = true);
    try {
      final LibraryActions actions = ref.read(libraryActionsProvider);
      await actions.restoreStickers(stickerIds);
      for (final Series s in chosenSeries) {
        await actions.restoreSeries(s.id);
      }
      if (mounted) {
        _exitSelection();
        showToast(context, '已还原 $count 项');
      }
    } catch (e) {
      if (mounted) showToast(context, '还原失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  Future<void> _purgeSelected() async {
    final List<Sticker> stickers = ref.read(trashStickersProvider);
    final List<Series> series = ref.read(trashSeriesProvider);
    final List<String> stickerIds = stickers
        .where((Sticker s) => _selected.contains(_stickerKey(s.id)))
        .map((Sticker s) => s.id)
        .toList();
    final List<Series> chosenSeries = series
        .where((Series s) => _selected.contains(_seriesKey(s.id)))
        .toList();
    final int count = stickerIds.length + chosenSeries.length;

    final bool ok = await confirm(
      context,
      title: '彻底删除所选',
      message: '将**彻底删除**选中的 $count 项及其图片文件，此操作无法撤销。',
      confirmLabel: '彻底删除',
      destructive: true,
    );
    if (!ok) return;

    setState(() => _purging = true);
    try {
      final LibraryActions actions = ref.read(libraryActionsProvider);
      await actions.purgeStickers(stickerIds);
      for (final Series s in chosenSeries) {
        await actions.purgeSeries(s.id);
      }
      if (mounted) {
        _exitSelection();
        showToast(context, '已彻底删除 $count 项');
      }
    } catch (e) {
      if (mounted) showToast(context, '删除失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  Future<void> _emptyTrash() async {
    final List<Sticker> stickers = ref.read(trashStickersProvider);
    final List<Series> series = ref.read(trashSeriesProvider);
    final int total = stickers.length + series.length;

    final bool ok = await confirm(
      context,
      title: '清空回收站',
      message: '将**彻底删除** $total 个条目及其图片文件，此操作无法撤销。',
      confirmLabel: '彻底删除',
      destructive: true,
    );
    if (!ok) return;

    setState(() => _purging = true);
    try {
      final LibraryActions actions = ref.read(libraryActionsProvider);
      await actions.purgeStickers(stickers.map((Sticker s) => s.id).toList());
      for (final Series s in series) {
        await actions.purgeSeries(s.id);
      }
      if (mounted) showToast(context, '回收站已清空');
    } catch (e) {
      if (mounted) showToast(context, '清空失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }
}

/// One deleted sticker with restore / purge actions.
/// 单个已删除表情包，附还原与彻底删除操作。
class _StickerRow extends ConsumerWidget {
  const _StickerRow({
    required this.sticker,
    required this.series,
    required this.busy,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Sticker sticker;
  final Series? series;
  final bool busy;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title = sticker.name.isNotEmpty
        ? sticker.name
        : (series?.name ?? '未命名');

    return _TrashRow(
      leading: _Thumb(path: sticker.thumbPath ?? sticker.relativePath),
      title: title,
      subtitle: series == null ? '所属系列已被删除' : '来自「${series!.name}」',
      enabled: !busy,
      selectionMode: selectionMode,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      onRestore: () => _restore(ref, context),
      onPurge: () => _purge(ref, context),
    );
  }

  Future<void> _restore(WidgetRef ref, BuildContext context) async {
    await ref.read(libraryActionsProvider).restoreStickers(<String>[sticker.id]);
    // ignore: use_build_context_synchronously
    if (contextIsAlive(context)) showToast(context, '已还原');
  }

  Future<void> _purge(WidgetRef ref, BuildContext context) async {
    final bool ok = await confirm(
      context,
      title: '彻底删除',
      message: '将**彻底删除**这个表情包及其图片文件，此操作无法撤销。',
      confirmLabel: '彻底删除',
      destructive: true,
    );
    if (!ok) return;
    await ref
        .read(libraryActionsProvider)
        .purgeStickers(<String>[sticker.id]);
    // ignore: use_build_context_synchronously
    if (contextIsAlive(context)) showToast(context, '已彻底删除');
  }
}

/// One deleted series with restore / purge actions.
/// 单个已删除系列，附还原与彻底删除操作。
class _SeriesRow extends ConsumerWidget {
  const _SeriesRow({
    required this.series,
    required this.busy,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Series series;
  final bool busy;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TrashRow(
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.folder_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: series.name,
      subtitle: '系列（含 ${series.stickerCount} 个表情包）',
      enabled: !busy,
      selectionMode: selectionMode,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      onRestore: () => _restore(ref, context),
      onPurge: () => _purge(ref, context),
    );
  }

  Future<void> _restore(WidgetRef ref, BuildContext context) async {
    await ref.read(libraryActionsProvider).restoreSeries(series.id);
    // ignore: use_build_context_synchronously
    if (contextIsAlive(context)) showToast(context, '已还原系列及其表情包');
  }

  Future<void> _purge(WidgetRef ref, BuildContext context) async {
    final bool ok = await confirm(
      context,
      title: '彻底删除',
      message: '将**彻底删除**「${series.name}」及其全部表情包与图片文件，'
          '此操作无法撤销。',
      confirmLabel: '彻底删除',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(libraryActionsProvider).purgeSeries(series.id);
    // ignore: use_build_context_synchronously
    if (contextIsAlive(context)) showToast(context, '已彻底删除');
  }
}

/// Shared row layout for a trashed item.
/// 回收站条目的通用行布局。
class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onRestore,
    required this.onPurge,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: selectionMode ? onTap : null,
        onLongPress: onLongPress,
        child: MoeCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              if (selectionMode) ...<Widget>[
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 24,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(width: 12),
              ],
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (!selectionMode) ...<Widget>[
                IconButton(
                  tooltip: '还原',
                  icon: const Icon(Icons.restore_from_trash_outlined),
                  onPressed: enabled ? onRestore : null,
                ),
                IconButton(
                  tooltip: '彻底删除',
                  icon: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: enabled ? onPurge : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small thumbnail for a trashed sticker.
/// 已删除表情包的小缩略图。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final String absolute = PathUtils.absoluteSync(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Image.file(
          File(absolute),
          fit: BoxFit.cover,
          cacheWidth: 120,
          errorBuilder: (_, __, ___) => Container(
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retention footnote.
/// 保留期脚注。
class _TrashNote extends StatelessWidget {
  const _TrashNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.info_outline,
          size: 15,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '回收站中的条目保留 7 天，之后会在打开本页时自动彻底删除。'
            '长按可进入多选，批量还原或彻底删除；'
            '还原系列时会一并还原其中的表情包。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
