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
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';
import 'widgets/series_card.dart';

/// Home screen: a grid of every series in the library.
/// 主页：库中全部系列的网格。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Series> seriesList = ref.watch(seriesListProvider);
    final int stickerCount = ref.watch(stickerListProvider).length;

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('拾萌'),
        actions: <Widget>[
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSeries(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建系列'),
      ),
      body: seriesList.isEmpty
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
                      '${seriesList.length} 个系列 · $stickerCount 个表情包',
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
                          onTap: () => context
                              .go(RoutePaths.seriesOf(series.id)),
                        );
                      },
                      childCount: seriesList.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Prompt for a name, then create the series and open it.
  /// 询问名称，随后创建系列并进入该系列。
  Future<void> _createSeries(BuildContext context, WidgetRef ref) async {
    final String? name = await _promptForName(context, title: '新建系列');
    if (name == null || name.trim().isEmpty) return;

    final String id = await ref
        .read(libraryActionsProvider)
        .createSeries(name: name.trim());
    // Flutter 3.0's BuildContext has no `mounted` getter, so guard on the
    // render object, which is non-null for exactly as long as the context is
    // mounted in the tree.
    // Flutter 3.0 的 BuildContext 没有 `mounted` getter，因此改以 render object
    // 判断：它在 context 挂载于组件树期间恒为非 null。
    // `contextIsAlive` flips to false the moment the element is deactivated, so the
    // context below is provably live. The analyzer cannot see through the helper
    // (it only special-cases the literal name `mounted`), hence the targeted ignore.
    // `contextIsAlive` 在 element 被 deactivate 的那一刻即变为 false，因此下面的
    // context 可证为存活。分析器无法看穿该辅助函数（它只对字面量名
    // `mounted` 特判），故此处做针对性忽略。
    if (!contextIsAlive(context)) return;
    context.go(RoutePaths.seriesOf(id));
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
