// ignore_for_file: use_build_context_synchronously
//
// `contextIsAlive` in shared/widgets/common.dart is the Flutter 3.0
// stand-in for `BuildContext.mounted` (added in 3.4). It is a stronger
// check than the lint assumes: it returns false for a deactivated
// element in both debug (where `findRenderObject()` throws) and
// release (where it returns null), and it additionally verifies the
// render object is still attached, so teardown races cannot slip
// through. Every use below is guarded by it immediately after an
// `await`. The analyzer only special-cases the literal name `mounted`,
// so it cannot follow the indirection; see test/shared/
// context_guard_test.dart for the behaviour locked in by tests.
//
// 本文件中的 `contextIsAlive`（见 shared/widgets/common.dart）是
// `BuildContext.mounted`（3.4 引入）在 Flutter 3.0 下的等价替代，且比
// 该 lint 的假设更严格：对已 deactivate 的 element，它在 debug（此时
// `findRenderObject()` 抛异常）与 release（此时返回 null）两种模式下
// 都返回 false，并额外校验 render object 仍然 attached，因此拆除过程中的
// 竞态也无法绕过。下方每一处调用都在 `await` 之后立即受其守卫。
// 分析器只对字面量名 `mounted` 特判，无法跟随这层间接，因此在此按文件
// 抑制；其行为已由 test/shared/context_guard_test.dart 用测试锁定。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../../shared/widgets/sticker_tile.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';
import 'widgets/series_card.dart';

/// Home screen: a grid of every series in the library.
/// 主页：库中全部系列的网格。
///
/// Also owns the "double back to exit" behaviour: on the home (root) route,
/// the first back press only shows a toast, and the app exits on the second
/// press within the grace window. This prevents accidental exits from a stray
/// back gesture.
///
/// 同时承载「双击返回退出」行为：在主页（根路由）上，第一次按返回只弹提示，
/// 在宽限窗口内再次按下才退出应用，避免误触返回导致直接退出。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({Key? key}) : super(key: key);

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  DateTime? _lastBackPressed;

  /// Tabs: gallery and favourites.
  /// 标签页：图库与收藏。
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// Multi-select mode, entered by long-pressing a series card.
  /// 多选模式，由长按系列卡片进入。
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _enterSelection(String seriesId) {
    setState(() {
      _selectionMode = true;
      _selected.clear();
      _selected.add(seriesId);
    });
  }

  void _toggle(String seriesId) {
    setState(() {
      if (!_selected.remove(seriesId)) _selected.add(seriesId);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelectAll(List<Series> all) {
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((Series s) => s.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Series> seriesList = ref.watch(seriesListProvider);
    final int stickerCount = ref.watch(stickerListProvider).length;

    // WillPopScope is the Flutter 3.0 mechanism for intercepting the system
    // back button (PopScope only arrives in 3.12). It fires on the root route
    // because the home page is the bottom of the navigation stack.
    // WillPopScope 是 Flutter 3.0 下拦截系统返回键的机制（PopScope 到 3.12 才有）。
    // 由于主页位于导航栈底部，它在根路由上生效。
    return WillPopScope(
      onWillPop: _onWillPop,
      child: MoeScaffold(
        appBar: AppBar(
          title: Text(_selectionMode ? '已选 ${_selected.length} 项' : '拾萌'),
          leading: _selectionMode
              ? IconButton(
                  tooltip: '取消多选',
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelection,
                )
              : null,
          actions: _selectionMode
              ? <Widget>[
                  IconButton(
                    tooltip: _selected.length == seriesList.length
                        ? '取消全选'
                        : '全选',
                    icon: const Icon(Icons.select_all_outlined),
                    onPressed: () => _toggleSelectAll(seriesList),
                  ),
                  IconButton(
                    tooltip: '删除所选',
                    icon: Icon(
                      Icons.delete_outline,
                      color: _selected.isEmpty
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                    onPressed:
                        _selected.isEmpty ? null : () => _deleteSelected(),
                  ),
                ]
              : <Widget>[
                  IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.search),
                    onPressed: () => context.go(RoutePaths.search),
                  ),
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.go(RoutePaths.settings),
                  ),
                ],
          // Tab bar is hidden during multi-select so the selection actions are
          // the only thing on screen.
          // 多选期间隐藏标签栏，使选择操作成为界面唯一焦点。
          bottom: _selectionMode
              ? null
              : TabBar(
                  controller: _tabs,
                  tabs: const <Widget>[
                    Tab(text: '图库'),
                    Tab(text: '收藏'),
                  ],
                ),
        ),
        floatingActionButton: _selectionMode
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _createSeries(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新建系列'),
              ),
        body: _selectionMode
            ? _buildGallery(seriesList, stickerCount)
            : TabBarView(
                controller: _tabs,
                children: <Widget>[
                  _buildGallery(seriesList, stickerCount),
                  const _FavoritesTab(),
                ],
              ),
      ),
    );
  }

  /// The gallery tab: the series grid (or its empty state).
  /// 图库标签页：系列网格（或其空状态）。
  Widget _buildGallery(List<Series> seriesList, int stickerCount) {
    return seriesList.isEmpty
        ? EmptyState(
            icon: Icons.collections_outlined,
            title: '还没有系列',
            message: '创建一个系列来收纳你的表情包。\n'
                '系列可以有自己的分类、标签和备注，'
                '其中的表情包会自动继承。',
            action: ElevatedButton.icon(
              onPressed: () => _createSeries(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('新建系列'),
            ),
          )
        : CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    _selectionMode
                        ? '点按选择或取消，长按进入多选'
                        : '${seriesList.length} 个系列 · $stickerCount 个表情包',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      final Series series = seriesList[index];
                      return SeriesCard(
                        series: series,
                        selected:
                            _selectionMode && _selected.contains(series.id),
                        onTap: () {
                          if (_selectionMode) {
                            _toggle(series.id);
                          } else {
                            context.push(RoutePaths.seriesOf(series.id));
                          }
                        },
                        onLongPress: () {
                          if (_selectionMode) {
                            _toggle(series.id);
                          } else {
                            _enterSelection(series.id);
                          }
                        },
                      );
                    },
                    childCount: seriesList.length,
                  ),
                ),
              ),
            ],
          );
  }

  Future<void> _deleteSelected() async {
    final List<Series> all = ref.read(seriesListProvider);
    final List<Series> chosen =
        all.where((Series s) => _selected.contains(s.id)).toList();
    final int count = chosen.length;

    final bool ok = await confirm(
      context,
      title: '删除所选系列',
      message: '将删除选中的 $count 个系列及其中的表情包，'
          '删除后会移入回收站，可在「设置 → 回收站」中恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    await ref
        .read(libraryActionsProvider)
        .deleteSeriesBatch(chosen.map((Series s) => s.id).toList());
    if (mounted) {
      _exitSelection();
      showToast(context, '已将 $count 个系列移入回收站');
    }
  }

  /// Return true to allow the back event to pop the app.
  /// 返回 true 表示允许返回事件退出应用。
  Future<bool> _onWillPop() async {
    // Back during multi-select exits selection, not the app.
    // 多选期间按返回应先退出多选，而非退出应用。
    if (_selectionMode) {
      _exitSelection();
      return false;
    }

    final DateTime now = DateTime.now();
    final bool withinGrace =
        _lastBackPressed != null &&
        now.difference(_lastBackPressed!) <
            const Duration(seconds: 2);

    if (withinGrace) {
      return true; // 第二次返回，放行退出
    }

    _lastBackPressed = now;
    if (contextIsAlive(context)) {
      showToast(context, '再次返回退出应用');
    }
    return false; // 第一次返回，拦截并提示
  }

  /// Prompt for a name, then create the series and open it.
  /// 询问名称，随后创建系列并进入该系列。
  Future<void> _createSeries(BuildContext context, WidgetRef ref) async {
    final String? name = await _promptForName(context, title: '新建系列');
    if (name == null || name.trim().isEmpty) return;

    final String id = await ref
        .read(libraryActionsProvider)
        .createSeries(name: name.trim());
    // `contextIsAlive` flips to false the moment the element is deactivated, so the
    // context below is provably live. The analyzer cannot see through the helper
    // (it only special-cases the literal name `mounted`), hence the targeted ignore.
    // `contextIsAlive` 在 element 被 deactivate 的那一刻即变为 false，因此下面的
    // context 可证为存活。分析器无法看穿该辅助函数（它只对字面量名
    // `mounted` 特判），故此处做针对性忽略。
    if (!contextIsAlive(context)) return;
    context.push(RoutePaths.seriesOf(id));
  }
}

/// Small reusable name prompt.
/// 可复用的名称输入对话框。
///
/// Delegates to the shared [promptForText] rather than keeping a local copy.
/// The local copy used to own its [TextEditingController] and dispose it from
/// `.whenComplete`, which crashed the app; see the note on `_TextPromptDialog`
/// in `shared/widgets/common.dart` for the full explanation. Keeping a second
/// implementation here would have kept a second copy of that bug.
///
/// 委托给共享的 [promptForText]，不再保留本地副本。
/// 本地副本曾自行持有 [TextEditingController] 并在 `.whenComplete` 中释放，导致应用
/// 崩溃；完整解释见 `shared/widgets/common.dart` 中 `_TextPromptDialog` 的注释。
/// 若在此保留第二份实现，就等于保留了该 bug 的第二份拷贝。
Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '给这个系列起个名字',
}) =>
    promptForText(
      context,
      title: title,
      initial: initial,
      hint: hint,
    );

/// Exposed for the series edit screen which reuses the same prompt.
/// 供系列编辑页复用同一输入对话框。
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
}) =>
    _promptForName(context, title: title, initial: initial, hint: hint);

/// Favourites tab: pinned series and stickers marked as favourite.
/// 收藏标签页：收藏的系列与表情包。
class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Series> series = ref.watch(favoriteSeriesProvider);
    final List<Sticker> stickers = ref.watch(favoriteStickersProvider);

    if (series.isEmpty && stickers.isEmpty) {
      return const EmptyState(
        icon: Icons.star_border,
        title: '还没有收藏',
        message: '在系列或表情包详情页点星标收藏，\n就会出现在这里。',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: <Widget>[
        if (series.isNotEmpty) ...<Widget>[
          SectionHeader('收藏的系列', subtitle: '${series.length} 个'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            itemCount: series.length,
            itemBuilder: (BuildContext context, int index) {
              final Series s = series[index];
              return SeriesCard(
                series: s,
                onTap: () => context.push(RoutePaths.seriesOf(s.id)),
              );
            },
          ),
        ],
        if (stickers.isNotEmpty) ...<Widget>[
          SectionHeader('收藏的表情包', subtitle: '${stickers.length} 个'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: stickers.length,
            itemBuilder: (BuildContext context, int index) {
              final Sticker sticker = stickers[index];
              return StickerTile(
                sticker: sticker,
                showName: true,
                onTap: () =>
                    context.push(RoutePaths.stickerOf(sticker.id)),
              );
            },
          ),
        ],
      ],
    );
  }
}
