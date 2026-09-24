import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/image_picker_service.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/category.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/models/tag.dart';
import '../../../routes/route_paths.dart';
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
                  tooltip: '删除所选',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _deleteSelected(stickers),
                ),
              ]
            : <Widget>[
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
                      _selectionMode ? '点按选择或取消，选完点右上角删除' : '点按查看详情，长按进入多选',
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
                    _enterSelection(s.id);
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
      final String message = _importMessage(result);
      showToast(context, message, isError: result.imported == 0);
    } catch (e) {
      if (mounted) showToast(context, '导入失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (result.failed > 0) {
      parts.add('${result.failed} 张失败');
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
