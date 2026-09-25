import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/series.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../../shared/widgets/taxonomy_selectors.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';

/// Create or edit a series.
/// 新建或编辑系列。
///
/// One screen covers both: the field set is identical and the only difference is
/// whether the record already exists, so splitting them would duplicate the form
/// and let validation drift apart.
///
/// 两种用途共用一个页面：字段完全相同，唯一区别是记录是否已存在；
/// 拆分会导致表单重复并使校验规则逐渐分叉。
///
/// Edits are held in local state and committed on save. This differs from the
/// theme screen deliberately: a half-typed note should not be written to disk
/// (and therefore synced to every device) on each keystroke.
///
/// 编辑内容保存在本地状态，保存时统一提交。这与主题页的做法有意不同：
/// 半途输入的备注不应在每次按键时就落盘（进而同步到每台设备）。
class SeriesEditPage extends ConsumerStatefulWidget {
  const SeriesEditPage({Key? key, this.seriesId}) : super(key: key);

  /// Null means "create a new series".
  /// 为 null 表示「新建系列」。
  final String? seriesId;

  bool get isCreating => seriesId == null || seriesId!.isEmpty;

  @override
  ConsumerState<SeriesEditPage> createState() => _SeriesEditPageState();
}

class _SeriesEditPageState extends ConsumerState<SeriesEditPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  List<String> _categoryIds = <String>[];
  List<String> _tagIds = <String>[];
  bool _initialised = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _sourceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Series? existing = widget.isCreating
        ? null
        : ref.watch(seriesByIdLookupProvider(widget.seriesId!));

    // Seed the form once, from whatever was on disk when the page opened.
    // Re-seeding on every rebuild would fight the user's typing.
    // 仅在首次进入时用磁盘上的值填充表单。
    // 每次重建都重新填充会与用户的输入相冲突。
    if (!_initialised) {
      if (!widget.isCreating && existing == null) {
        // Still loading or genuinely gone; wait for a non-null series.
        // 仍在加载或确实已不存在；等待非 null 的系列。
        if (ref.watch(seriesListProvider).isNotEmpty) {
          return _missingScaffold();
        }
      } else {
        _seed(existing);
      }
    }

    return MoeScaffold(
      appBar: AppBar(
        title: Text(widget.isCreating ? '新建系列' : '编辑系列'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _cancel(context),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : () => _save(context),
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          const SectionHeader('基本信息'),
          TextField(
            controller: _nameController,
            autofocus: widget.isCreating,
            decoration: const InputDecoration(
              labelText: '系列名称',
              hintText: '例如：猫猫日常',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '简介（可选）',
              hintText: '一句话说明这个系列的内容',
            ),
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _authorController,
            decoration: const InputDecoration(
              labelText: '作者（可选）',
              hintText: '画师、创作者或出处署名',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _sourceController,
            decoration: const InputDecoration(
              labelText: '来源（可选）',
              hintText: '链接或出处，例如 https://…',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
          ),

          const SectionHeader(
            '分类',
            subtitle: '系列内的表情包会继承这些分类；'
                '表情包自己设置分类时，会改为使用自己的',
          ),
          CategorySelector(
            selectedIds: _categoryIds,
            onChanged: (List<String> ids) =>
                setState(() => _categoryIds = ids),
          ),

          const SectionHeader(
            '标签',
            subtitle: '这里的标签会与表情包自己的标签叠加',
          ),
          TagSelector(
            selectedIds: _tagIds,
            onChanged: (List<String> ids) => setState(() => _tagIds = ids),
          ),

          const SectionHeader(
            '备注',
            subtitle: '系列备注与表情包备注会拼接显示',
          ),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              hintText: '记录使用场景、注意事项等',
            ),
            maxLines: 4,
            minLines: 3,
          ),

          if (!widget.isCreating) ...<Widget>[
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _delete(existing!),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除这个系列'),
              style: OutlinedButton.styleFrom(
                primary: Theme.of(context).colorScheme.error,
                // Keep the outline in step with the destructive text colour,
                // now that the theme defines a themed side for outlined buttons.
                // 主题为 Outlined 按钮定义了边框后，需保持边框与红色文字一致。
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.45),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Populate the form from an existing series, exactly once.
  /// 用已有系列填充表单，且只执行一次。
  void _seed(Series? series) {
    _initialised = true;
    if (series == null) return;
    _nameController.text = series.name;
    _descriptionController.text = series.description;
    _authorController.text = series.author;
    _sourceController.text = series.source;
    _noteController.text = series.note;
    _categoryIds = List<String>.from(series.categoryIds);
    _tagIds = List<String>.from(series.tagIds);
  }

  Widget _missingScaffold() {
    return MoeScaffold(
      appBar: AppBar(title: const Text('系列')),
      body: EmptyState(
        icon: Icons.error_outline,
        title: '找不到这个系列',
        message: '它可能已被删除。',
        action: ElevatedButton(
          onPressed: () => context.pop(),
          child: const Text('返回首页'),
        ),
      ),
    );
  }

  void _cancel(BuildContext context) {
    context.pop();
  }

  Future<void> _save(BuildContext context) async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, '请先填写系列名称', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final LibraryActions actions = ref.read(libraryActionsProvider);

      if (widget.isCreating) {
        final String id = await actions.createSeries(name: name);
        // Apply the rest of the form in a second pass rather than widening
        // `createSeries` with four optional parameters it rarely needs.
        // 其余字段分第二步写入，而不是给 `createSeries` 加上四个它很少用到的可选参数。
        final Series? created = ref.read(seriesByIdLookupProvider(id));
        if (created != null) {
          await actions.updateSeries(
            created,
            description: _descriptionController.text.trim(),
            author: _authorController.text.trim(),
            source: _sourceController.text.trim(),
            categoryIds: _categoryIds,
            tagIds: _tagIds,
            note: _noteController.text.trim(),
          );
        }
        if (!mounted) return;
        context.pop();
      } else {
        final Series? series =
            ref.read(seriesByIdLookupProvider(widget.seriesId!));
        if (series == null) {
          if (mounted) showToast(context, '系列已不存在', isError: true);
          return;
        }
        await actions.updateSeries(
          series,
          name: name,
          description: _descriptionController.text.trim(),
          author: _authorController.text.trim(),
          source: _sourceController.text.trim(),
          categoryIds: _categoryIds,
          tagIds: _tagIds,
          note: _noteController.text.trim(),
        );
        if (!mounted) return;
        showToast(context, '已保存');
        context.pop();
      }
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Series series) async {
    final bool ok = await confirm(
      context,
      title: '删除系列',
      message: '将删除「${series.name}」以及其中的 '
          '${series.stickerCount} 个表情包，此操作会同步到其他设备。',
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
