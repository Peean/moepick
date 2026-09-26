import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/image_picker_service.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/category.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/models/tag.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/action_sheet.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../../shared/widgets/sticker_tile.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';
import '../../settings/application/settings_providers.dart';
import 'widgets/inheritance_summary.dart';

/// One series: its inherited metadata and the stickers inside it.
/// 单个系列：其继承元数据与内部的表情包。
class SeriesDetailPage extends ConsumerStatefulWidget {
  const SeriesDetailPage({Key? key, required this.seriesId}) : super(key: key);

  final String seriesId;

  @override
  ConsumerState<SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends ConsumerState<SeriesDetailPage> {
  /// Grid density is user-configurable, so the delegate is built per frame
  /// rather than cached.
  /// 网格密度可由用户配置，因此每次构建展现代理而非缓存。
  bool _busy = false;

  /// Multi-select mode, entered by long-pressing a tile.
  /// 多选模式，由长按某个瓦片进入。
  ///
  /// Long-press used to quick-delete, which destroyed work with a single
  /// clumsy gesture; deletion now lives behind an explicit confirm in the
  /// selection bar.
  ///
  /// 长按过去是快速删除，一次误触就毁掉成果；
  /// 现在删除收进多选栏中并需显式确认。
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  void _enterSelection(String stickerId) {
    setState(() {
      _selectionMode = true;
      _selected.clear();
      _selected.add(stickerId);
    });
  }

  void _toggleSelection(String stickerId) {
    setState(() {
      if (!_selected.remove(stickerId)) _selected.add(stickerId);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Series? series =
        ref.watch(seriesByIdLookupProvider(widget.seriesId));

    // A series can vanish while this page is open (deleted from another device
    // via sync), so handle the missing case instead of asserting.
    // 系列可能在本页打开期间消失（例如被另一台设备通过同步删除），
    // 因此要处理缺失情况而非直接断言。
    if (series == null) {
      return MoeScaffold(
        appBar: AppBar(
          title: const Text('系列'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: EmptyState(
          icon: Icons.search_off_outlined,
          title: '这个系列已不存在',
          message: '它可能已被删除。',
          action: ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('返回首页'),
          ),
        ),
      );
    }

    final List<Sticker> stickers =
        ref.watch(stickersBySeriesProvider(widget.seriesId));
    final Map<String, Category> categoryById =
        ref.watch(categoryByIdProvider);
    final Map<String, Tag> tagById = ref.watch(tagByIdProvider);

    return MoeScaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选择 ${_selected.length} 项' : series.name),
        leading: IconButton(
          icon: Icon(_selectionMode ? Icons.close : Icons.arrow_back),
          onPressed: () {
            if (_selectionMode) {
              _exitSelection();
            } else {
              context.pop();
            }
          },
        ),
        actions: _selectionMode
            ? <Widget>[
                IconButton(
                  tooltip: _selected.length == stickers.length
                      ? '取消全选'
                      : '全选',
                  icon: const Icon(Icons.select_all_outlined),
                  onPressed: () {
                    setState(() {
                      if (_selected.length == stickers.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(stickers.map((Sticker s) => s.id));
                      }
                    });
                  },
                ),
                IconButton(
                  tooltip: '编辑所选名称',
                  icon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _editSelectedNames(stickers),
                ),
                IconButton(
                  tooltip: '删除所选',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _deleteSelected(stickers),
                ),
              ]
            : <Widget>[
                IconButton(
                  tooltip: series.pinned ? '取消置顶' : '置顶',
                  icon: Icon(
                    series.pinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    color: series.pinned
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: () => _togglePin(series),
                ),
                IconButton(
                  tooltip: series.favorite ? '取消收藏' : '收藏',
                  icon: Icon(
                    series.favorite ? Icons.star : Icons.star_border,
                    color: series.favorite
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: () => _toggleFavorite(series),
                ),
                IconButton(
                  tooltip: '编辑系列信息',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.push(RoutePaths.seriesEditOf(series.id)),
                ),
                PopupMenuButton<String>(
                  onSelected: (String value) {
                    if (value == 'delete') _deleteSeries(series);
                  },
                  itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: DestructiveMenuItem(
                        icon: Icons.delete_outline,
                        label: '删除系列',
                      ),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _importStickers(series),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_busy ? '导入中' : '导入表情包'),
            ),
      body: CustomScrollView(
        slivers: <Widget>[
          if (!_selectionMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InheritanceSummary(
                  series: series,
                  categoryById: categoryById,
                  tagById: tagById,
                ),
              ),
            ),

          if (stickers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.image_outlined,
                title: '这个系列还没有表情包',
                message: '导入本地图片作为表情包。\n'
                    '系列的分类、标签和备注会被它们自动继承。',
                action: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _importStickers(series),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('导入表情包'),
                ),
              ),
            )
          else ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      '${stickers.length} 个表情包',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      _selectionMode ? '点按选择或取消，右上角可改名或删除' : '点按查看详情，长按快捷操作',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: _StickerGrid(
                stickers: stickers,
                selectedIds: _selectionMode ? _selected : null,
                onOpen: (Sticker s) {
                  if (_selectionMode) {
                    _toggleSelection(s.id);
                  } else {
                    context.push(RoutePaths.stickerOf(s.id));
                  }
                },
                onLongPress: (Sticker s) {
                  if (_selectionMode) {
                    _toggleSelection(s.id);
                  } else {
                    _showStickerActions(s);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _importStickers(Series series) async {
    setState(() => _busy = true);
    try {
      final List<String> paths = await ImagePickerService.pickMultiple();
      if (paths.isEmpty) return;

      final result = await ref
          .read(libraryActionsProvider)
          .importStickers(
            seriesId: series.id,
            sourcePaths: paths,
          );

      if (!mounted) return;

      if (result.failed > 0) {
        // Show exactly which files failed, so the user does not have to hunt
        // through the batch one by one.
        // 精确展示哪些文件失败，使用户不必在整批里逐一查找。
        await _showImportFailures(result);
        return;
      }

      final String message = _importMessage(result);
      showToast(context, message);
    } catch (e) {
      if (mounted) showToast(context, '导入失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Dialog listing the files that failed to import, alongside the summary of
  /// what did import.
  /// 列出导入失败文件的对话框，并附带成功导入的汇总。
  Future<void> _showImportFailures(ImportBatchResult result) async {
    final List<String> failedFiles = result.failedFiles;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final ThemeData theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('部分文件导入失败'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '成功导入 ${result.imported} 张，失败 ${result.failed} 张'
                  '${result.duplicates > 0 ? '，跳过 ${result.duplicates} 张重复' : ''}。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '失败的文件：',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final String name in failedFiles)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Icons.broken_image_outlined,
                                  size: 16,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  /// Summarise an import run, distinguishing new from duplicate files.
  /// 汇总一次导入结果，区分新增与重复文件。
  String _importMessage(ImportBatchResult result) {
    if (result.imported == 0 && result.duplicates > 0) {
      return '这 ${result.duplicates} 张都已经在库里了';
    }
    final List<String> parts = <String>['导入 ${result.imported} 张'];
    if (result.duplicates > 0) {
      parts.add('跳过 ${result.duplicates} 张重复');
    }
    return parts.join('，');
  }

  Future<void> _deleteSelected(List<Sticker> stickers) async {
    final int count = _selected.length;
    final bool ok = await confirm(
      context,
      title: '删除所选表情包',
      message: '选中的 $count 个表情包将被移入回收站，'
          '可在「设置 → 回收站」中恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    final List<Sticker> chosen = stickers
        .where((Sticker s) => _selected.contains(s.id))
        .toList();
    await ref.read(libraryActionsProvider).deleteStickers(chosen);
    if (mounted) {
      _exitSelection();
      showToast(context, '已将 $count 个表情包移入回收站');
    }
  }

  /// Long-press a sticker tile: offer pin / favourite / share / multi-select /
  /// delete directly, so the user need not open the sticker to act on it.
  /// 长按表情包瓦片：直接提供置顶 / 收藏 / 分享 / 多选 / 删除，
  /// 无需点进表情包即可操作。
  Future<void> _showStickerActions(Sticker sticker) async {
    await showActionSheet(
      context,
      title: sticker.name.isEmpty ? '表情包' : sticker.name,
      items: <ActionSheetItem>[
        ActionSheetItem(
          label: sticker.pinned ? '取消置顶' : '置顶',
          icon: sticker.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          active: sticker.pinned,
          onTap: () => _toggleStickerPin(sticker),
        ),
        ActionSheetItem(
          label: sticker.favorite ? '取消收藏' : '收藏',
          icon: sticker.favorite ? Icons.star : Icons.star_border,
          active: sticker.favorite,
          onTap: () => _toggleStickerFavorite(sticker),
        ),
        ActionSheetItem(
          label: '分享',
          icon: Icons.share_outlined,
          onTap: () => _shareSticker(sticker),
        ),
        ActionSheetItem(
          label: '多选',
          icon: Icons.checklist,
          onTap: () => _enterSelection(sticker.id),
        ),
        ActionSheetItem(
          label: '删除',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => _deleteSingleSticker(sticker),
        ),
      ],
    );
  }

  Future<void> _toggleStickerPin(Sticker sticker) async {
    final bool? result = await ref
        .read(libraryActionsProvider)
        .toggleStickerPin(sticker.id);
    if (!mounted) return;
    if (result == null) {
      showToast(context, '已达置顶上限，请先取消其他置顶', isError: true);
    } else {
      showToast(context, result ? '已置顶' : '已取消置顶');
    }
  }

  Future<void> _toggleStickerFavorite(Sticker sticker) async {
    final bool result = await ref
        .read(libraryActionsProvider)
        .toggleStickerFavorite(sticker.id);
    if (!mounted) return;
    showToast(context, result ? '已收藏' : '已取消收藏');
  }

  /// Share the sticker's image through the platform share sheet.
  /// 通过系统分享面板分享表情包图片。
  Future<void> _shareSticker(Sticker sticker) async {
    final String absolute = PathUtils.absoluteSync(sticker.relativePath);
    final File file = File(absolute);
    if (!await file.exists()) {
      if (mounted) {
        showToast(context, '图片文件已丢失，无法分享', isError: true);
      }
      return;
    }
    try {
      await Share.shareXFiles(
        <XFile>[XFile(absolute)],
        text: sticker.name.isNotEmpty ? sticker.name : null,
      );
    } catch (e) {
      if (mounted) showToast(context, '分享失败：$e', isError: true);
    }
  }

  Future<void> _deleteSingleSticker(Sticker sticker) async {
    final bool ok = await confirm(
      context,
      title: '删除表情包',
      message: '「${sticker.name.isEmpty ? "这张表情包" : sticker.name}」'
          '将被移入回收站。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(libraryActionsProvider).deleteSticker(sticker);
    if (mounted) showToast(context, '已移入回收站');
  }

  /// Edit the names of the selected stickers in one bottom sheet: each gets its
  /// own field, pre-filled with the current name, and a single save applies all
  /// the changes.
  /// 在一个底部面板中逐个编辑所选表情包的名称：每个表情包一个输入框，
  /// 预填当前名称，点一次保存统一应用所有改动。
  Future<void> _editSelectedNames(List<Sticker> stickers) async {
    final List<Sticker> chosen = stickers
        .where((Sticker s) => _selected.contains(s.id))
        .toList();

    final Map<String, String>? result =
        await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _BatchRenameSheet(stickers: chosen),
    );

    if (result == null || result.isEmpty || !mounted) return;

    await ref.read(libraryActionsProvider).renameStickers(result);
    if (mounted) {
      _exitSelection();
      showToast(context, '已更新 ${result.length} 个名称');
    }
  }

  Future<void> _togglePin(Series series) async {
    final bool? result =
        await ref.read(libraryActionsProvider).toggleSeriesPin(series.id);
    if (!mounted) return;
    if (result == null) {
      showToast(context, '已达置顶上限，请先取消其他置顶', isError: true);
    } else {
      showToast(context, result ? '已置顶' : '已取消置顶');
    }
  }

  Future<void> _toggleFavorite(Series series) async {
    final bool result = await ref
        .read(libraryActionsProvider)
        .toggleSeriesFavorite(series.id);
    if (!mounted) return;
    showToast(context, result ? '已收藏' : '已取消收藏');
  }

  Future<void> _deleteSeries(Series series) async {
    final bool ok = await confirm(
      context,
      title: '删除系列',
      message: '将删除「${series.name}」以及其中的 '
          '${series.stickerCount} 个表情包。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(libraryActionsProvider).deleteSeries(series.id);
    if (mounted) {
      showToast(context, '已删除「${series.name}」');
      context.pop();
    }
  }
}

/// Responsive sticker grid driven by the user's preferred column count.
/// 由用户偏好列数驱动的响应式表情包网格。
///
/// Uses a max-extent delegate rather than a fixed column count: a `gridColumns`
/// of 3 is right on a phone but absurd on a 27" desktop window, and max-extent
/// honours the intent ("about this many per row") across both.
///
/// 使用最大宽度代理而非固定列数：3 列在手机上合适，在 27 寸桌面窗口上则荒谬；
/// 最大宽度代理能在两种场景下都尊重「大约每行这么多个」的意图。
class _StickerGrid extends ConsumerWidget {
  const _StickerGrid({
    required this.stickers,
    required this.onOpen,
    required this.onLongPress,
    this.selectedIds,
  });

  final List<Sticker> stickers;
  final ValueChanged<Sticker> onOpen;
  final ValueChanged<Sticker> onLongPress;

  /// Non-null while multi-select mode is active; ids in the set render
  /// with the selection overlay.
  /// 多选模式激活时非 null；集合内的 id 会渲染选中覆盖层。
  final Set<String>? selectedIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int columns =
        ref.watch(appSettingsProvider.select((AppSettings s) => s.gridColumns));

    // Convert the desired column count into a max extent using the actual
    // viewport width, so the requested density is respected on any screen.
    // 用真实视口宽度把期望列数换算为最大宽度，使请求的密度在任何屏幕上都被尊重。
    final double width = MediaQuery.of(context).size.width - 32;
    final double maxExtent =
        ((width - (columns - 1) * 10) / columns).clamp(72.0, 260.0);

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Height = width + a caption line, so the name under each tile has room
        // without being clipped.
        // 高度 = 宽度 + 一行名称，使每个瓦片下方的名称有空间而不被裁剪。
        childAspectRatio: 0.82,
      ),
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          final Sticker sticker = stickers[index];
          return StickerTile(
            sticker: sticker,
            showName: true,
            selected: selectedIds?.contains(sticker.id) ?? false,
            onTap: () => onOpen(sticker),
            onLongPress: () => onLongPress(sticker),
          );
        },
        childCount: stickers.length,
      ),
    );
  }
}

/// Bottom sheet that lets the user edit the name of every selected sticker at
/// once — one field per sticker, pre-filled, saved in a single tap.
/// 底部面板：一次编辑所有选中表情包的名称——每个表情包一个输入框，
/// 预填当前名称，点一次保存统一应用。
class _BatchRenameSheet extends StatefulWidget {
  const _BatchRenameSheet({required this.stickers});

  final List<Sticker> stickers;

  @override
  State<_BatchRenameSheet> createState() => _BatchRenameSheetState();
}

class _BatchRenameSheetState extends State<_BatchRenameSheet> {
  late final List<TextEditingController> _controllers =
      widget.stickers
          .map((Sticker s) => TextEditingController(text: s.name))
          .toList();

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final Map<String, String> result = <String, String>{};
    for (int i = 0; i < widget.stickers.length; i++) {
      final String name = _controllers[i].text.trim();
      if (name != widget.stickers[i].name) {
        result[widget.stickers[i].id] = name;
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      // Lift the sheet above the keyboard so fields near the bottom stay
      // visible while typing.
      // 把面板抬到键盘上方，使底部输入框在输入时仍可见。
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '编辑名称（${widget.stickers.length} 个）',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.stickers.length,
                itemBuilder: (BuildContext context, int index) {
                  final Sticker sticker = widget.stickers[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 5,
                    ),
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Image.file(
                              File(
                                PathUtils.absoluteSync(
                                  sticker.thumbPath ?? sticker.relativePath,
                                ),
                              ),
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                              errorBuilder: (_, __, ___) => Container(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.06),
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 20,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.3),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _controllers[index],
                            decoration: const InputDecoration(
                              hintText: '留空则跟随系列名',
                              isDense: true,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
