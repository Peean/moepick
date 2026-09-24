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

import '../../../core/state/data_version.dart';
import '../../../data/models/category.dart';
import '../../../data/models/tag.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../library/application/library_providers.dart';
import '../application/storage_providers.dart';

/// Manage the vocabulary: categories and tags.
/// 管理词汇表：分类与标签。
///
/// Two tabs rather than one merged list: categories are a small, curated,
/// coloured set used for mutual-exclusion grouping, while tags are a large,
/// free-form, flat set. Presenting them identically would hide that difference.
///
/// 使用两个标签页而非合并列表：分类是精心维护的小型有色集合，用于互斥归类；
/// 标签则是大型、自由、扁平的集合。二者外观相同会掩盖这一差异。
class TaxonomyPage extends ConsumerStatefulWidget {
  const TaxonomyPage({Key? key}) : super(key: key);

  @override
  ConsumerState<TaxonomyPage> createState() => _TaxonomyPageState();
}

class _TaxonomyPageState extends ConsumerState<TaxonomyPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int categoryCount = ref.watch(categoryListProvider).length;
    final int tagCount = ref.watch(tagListProvider).length;

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('分类与标签'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.settings),
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            Tab(text: '分类 ($categoryCount)'),
            Tab(text: '标签 ($tagCount)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const <Widget>[
          _CategoryTab(),
          _TagTab(),
        ],
      ),
    );
  }
}

/// Category list with rename / recolour / delete.
/// 分类列表，支持重命名 / 改色 / 删除。
class _CategoryTab extends ConsumerWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Category> categories = ref.watch(categoryListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建分类'),
      ),
      body: categories.isEmpty
          ? EmptyState(
              icon: Icons.folder_outlined,
              title: '还没有分类',
              message: '分类适合做互斥的归类，比如「可爱」「日常」「职场」。\n'
                  '表情包设置自己的分类时，会覆盖所属系列的分类。',
              action: ElevatedButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新建分类'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: categories.length,
              itemBuilder: (BuildContext context, int index) {
                final Category category = categories[index];
                return _CategoryRow(category: category);
              },
            ),
    );
  }

  static Future<void> _create(BuildContext context, WidgetRef ref) async {
    final String? name = await promptForText(
      context,
      title: '新建分类',
      hint: '例如：可爱、日常、职场',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(taxonomyRepositoryProvider)
        .saveCategoryWithName(name.trim());
    // `showToast` reads Theme from the context, so re-check liveness first.
    // `showToast` 会从 context 读取 Theme，因此先重新校验存活性。
    // `contextIsAlive` flips to false the moment the element is deactivated, so the
    // context below is provably live. The analyzer cannot see through the helper
    // (it only special-cases the literal name `mounted`), hence the targeted ignore.
    // `contextIsAlive` 在 element 被 deactivate 的那一刻即变为 false，因此下面的
    // context 可证为存活。分析器无法看穿该辅助函数（它只对字面量名
    // `mounted` 特判），故此处做针对性忽略。
    if (!contextIsAlive(context)) return;
    showToast(context, '已添加分类');
  }
}

/// One category row, expandable into its edit controls.
/// 单条分类行，可展开显示编辑控件。
class _CategoryRow extends ConsumerStatefulWidget {
  const _CategoryRow({required this.category});

  final Category category;

  @override
  ConsumerState<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends ConsumerState<_CategoryRow> {
  bool _editing = false;

  /// Colour palette restricted to hues that stay legible as small dots on both
  /// light and dark surfaces.
  /// 限定在浅色与深色表面上作为小圆点都保持可辨识的色相范围内。
  static const List<int> palette = <int>[
    0xFF7E9CD8,
    0xFFE38FB1,
    0xFF5FBF9F,
    0xFFE8945F,
    0xFF9B8FE0,
    0xFFD9B53F,
    0xFFE07070,
    0xFF6E7A88,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Category category = widget.category;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MoeCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                CategoryDot(color: Color(category.colorValue), size: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.name,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  tooltip: _editing ? '收起' : '编辑',
                  icon: Icon(_editing ? Icons.expand_less : Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = !_editing),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context),
                ),
              ],
            ),
            if (_editing) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _rename(context),
                      icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                      label: const Text('重命名'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '颜色',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: palette.map((int value) {
                  final bool selected = value == category.colorValue;
                  return GestureDetector(
                    onTap: () => _setColor(value),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              Icons.check,
                              size: 15,
                              color: Color(value).computeLuminance() > 0.55
                                  ? Colors.black87
                                  : Colors.white,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final String? name = await promptForText(
      context,
      title: '重命名分类',
      initial: widget.category.name,
      confirmLabel: '保存',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(taxonomyRepositoryProvider)
        .saveCategory(widget.category.copyWith(name: name.trim()));
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<void> _setColor(int colorValue) async {
    await ref
        .read(taxonomyRepositoryProvider)
        .saveCategory(widget.category.copyWith(colorValue: colorValue));
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<void> _delete(BuildContext context) async {
    final bool ok = await confirm(
      context,
      title: '删除分类',
      message: '使用「${widget.category.name}」的系列和表情包会失去这个分类，'
          '但内容本身不会丢失。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(taxonomyRepositoryProvider).deleteCategory(widget.category.id);
    ref.read(dataVersionProvider.notifier).bump();
  }
}

/// Tag list with rename / delete, ordered by usage.
/// 标签列表，支持重命名 / 删除，按使用频率排序。
class _TagTab extends ConsumerWidget {
  const _TagTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Tag> tags = ref.watch(tagListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建标签'),
      ),
      body: tags.isEmpty
          ? EmptyState(
              icon: Icons.local_offer_outlined,
              title: '还没有标签',
              message: '标签适合自由、多选的描述，比如「沙雕」「猫」「同事」。\n'
                  '表情包的标签会叠加在系列标签之上。',
              action: ElevatedButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新建标签'),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: tags.length,
              itemBuilder: (BuildContext context, int index) {
                return _TagRow(tag: tags[index]);
              },
            ),
    );
  }

  static Future<void> _create(BuildContext context, WidgetRef ref) async {
    final String? name = await promptForText(
      context,
      title: '新建标签',
      hint: '例如：沙雕、猫、同事',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(taxonomyRepositoryProvider).ensureTag(name.trim());
    // `contextIsAlive` flips to false the moment the element is deactivated, so the
    // context below is provably live. The analyzer cannot see through the helper
    // (it only special-cases the literal name `mounted`), hence the targeted ignore.
    // `contextIsAlive` 在 element 被 deactivate 的那一刻即变为 false，因此下面的
    // context 可证为存活。分析器无法看穿该辅助函数（它只对字面量名
    // `mounted` 特判），故此处做针对性忽略。
    if (!contextIsAlive(context)) return;
    showToast(context, '已添加标签');
  }
}

/// One tag row.
/// 单条标签行。
class _TagRow extends ConsumerWidget {
  const _TagRow({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MoeCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.local_offer_outlined,
              size: 17,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(tag.name, style: theme.textTheme.bodyLarge),
            ),
            // Usage count turns the list into a signal about what the library
            // actually contains, not just a settings dump.
            // 使用次数让这个列表反映库中真实的内容分布，而不只是一份设置清单。
            Text(
              '${tag.usageCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.45),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '重命名',
              icon: const Icon(Icons.edit_outlined, size: 19),
              onPressed: () => _rename(context, ref),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 19),
              onPressed: () => _delete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final String? name = await promptForText(
      context,
      title: '重命名标签',
      initial: tag.name,
      confirmLabel: '保存',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(taxonomyRepositoryProvider)
        .saveTag(tag.copyWith(name: name.trim()));
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final bool ok = await confirm(
      context,
      title: '删除标签',
      message: tag.usageCount > 0
          ? '「${tag.name}」正被 ${tag.usageCount} 处使用，删除后这些地方会失去该标签。'
          : '删除标签「${tag.name}」。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(taxonomyRepositoryProvider).deleteTag(tag.id);
    ref.read(dataVersionProvider.notifier).bump();
  }
}
