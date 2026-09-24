import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/data_version.dart';
import '../../data/models/category.dart';
import '../../data/models/tag.dart';
import '../../features/library/application/library_providers.dart';
import '../../features/settings/application/storage_providers.dart';
import 'common.dart';

/// Multi-select chip row for categories.
/// 分类的多选芯片行。
///
/// Shows an inline "create" affordance when the list is empty or the user wants
/// a new one, so tagging never dead-ends on an empty taxonomy.
///
/// 列表为空或用户需要新建时提供内联「创建」入口，
/// 使打标签操作不会因分类体系为空而无路可走。
class CategorySelector extends ConsumerWidget {
  const CategorySelector({
    Key? key,
    required this.selectedIds,
    required this.onChanged,
  }) : super(key: key);

  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Category> all = ref.watch(categoryListProvider);
    final Set<String> selected = selectedIds.toSet();

    return _ChipWrap(
      emptyHint: '还没有分类，点右侧「新建」添加一个',
      onAdd: () => _createCategory(context, ref),
      children: all.map((Category category) {
        return FilterChip(
          selected: selected.contains(category.id),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CategoryDot(color: Color(category.colorValue)),
              const SizedBox(width: 6),
              Text(category.name),
            ],
          ),
          onSelected: (bool value) {
            final List<String> next = List<String>.from(selectedIds);
            if (value) {
              if (!next.contains(category.id)) next.add(category.id);
            } else {
              next.remove(category.id);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }

  Future<void> _createCategory(BuildContext context, WidgetRef ref) async {
    final String? name = await promptForText(
      context,
      title: '新建分类',
      hint: '例如：可爱、日常、职场',
    );
    if (name == null || name.trim().isEmpty) return;

    final String id = await ref
        .read(taxonomyRepositoryProvider)
        .saveCategoryWithName(name.trim());

    // The category/tag list providers derive from the data-version signal, so
    // writing a new category here must bump it — otherwise the new chip does not
    // appear until some other write (e.g. saving the series) refreshes the list.
    // 分类/标签列表 provider 派生自数据版本信号，因此这里写入新分类后必须自增该信号——
    // 否则新芯片要等到其他写入（如保存系列）刷新列表时才会出现。
    ref.read(dataVersionProvider.notifier).bump();

    // Auto-select the freshly created category: creating one mid-edit almost
    // always means the user wants it applied.
    // 自动选中新建的分类：编辑过程中新建，几乎总是意味着用户想立刻用上它。
    final List<String> next = List<String>.from(selectedIds);
    if (!next.contains(id)) next.add(id);
    onChanged(next);
  }
}

/// Multi-select chip row for tags, with an inline text field to add one.
/// 标签的多选芯片行，带内联输入框用于新增。
///
/// Tags are created on the fly here rather than in a separate dialog because
/// naming tags is a rapid, stream-of-thought activity.
/// 标签在此直接新建而非弹独立对话框，因为给标签命名是快速、连贯的动作。
class TagSelector extends ConsumerStatefulWidget {
  const TagSelector({
    Key? key,
    required this.selectedIds,
    required this.onChanged,
    this.hint = '添加标签',
  }) : super(key: key);

  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;
  final String hint;

  @override
  ConsumerState<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends ConsumerState<TagSelector> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Tag> all = ref.watch(tagListProvider);
    final Set<String> selected = widget.selectedIds.toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (all.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: all.map((Tag tag) {
              return FilterChip(
                selected: selected.contains(tag.id),
                label: Text(tag.name),
                onSelected: (bool value) {
                  final List<String> next =
                      List<String>.from(widget.selectedIds);
                  if (value) {
                    if (!next.contains(tag.id)) next.add(tag.id);
                  } else {
                    next.remove(tag.id);
                  }
                  widget.onChanged(next);
                },
              );
            }).toList(),
          ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: '添加',
                    onPressed: _addTag,
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTag(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addTag() async {
    final String name = _controller.text.trim();
    if (name.isEmpty) return;

    // `ensureTag` is case-insensitively idempotent, so typing an existing tag
    // selects it rather than creating a near-duplicate.
    // `ensureTag` 对大小写不敏感且幂等，因此输入已有标签会选中它，
    // 而不是创建近似重复项。
    final String id =
        await ref.read(taxonomyRepositoryProvider).ensureTag(name);

    // Same as the category path: bump the data version so the tag chip shows up
    // immediately instead of after the next unrelated write.
    // 与分类路径同理：自增数据版本，使标签芯片立即出现，而不是等到下一次无关写入。
    ref.read(dataVersionProvider.notifier).bump();

    _controller.clear();
    _focusNode.requestFocus();

    final List<String> next = List<String>.from(widget.selectedIds);
    if (!next.contains(id)) next.add(id);
    widget.onChanged(next);
  }
}

/// Shared chip container that supplies the "add" affordance.
/// 提供「新建」入口的共享芯片容器。
class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.children,
    required this.onAdd,
    this.emptyHint = '暂无内容',
  });

  final List<Widget> children;
  final VoidCallback onAdd;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              emptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: children),
          ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建'),
        ),
      ],
    );
  }
}
