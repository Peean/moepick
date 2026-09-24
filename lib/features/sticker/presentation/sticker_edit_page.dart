import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../../shared/widgets/taxonomy_selectors.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';

/// Edit one sticker's name, categories, tags and note.
/// 编辑单个表情包的名称、分类、标签与备注。
///
/// The inheritance rules are spelled out inline, next to the fields they apply
/// to. A sticker-level category replaces the series'; a sticker-level tag is
/// added to the series'. Without that reminder the two controls look identical
/// but behave differently.
///
/// 继承规则在其作用的字段旁就地说明。表情包级分类会替换系列的；标签则是叠加。
/// 缺少这一提示时，两个控件外观相同但行为不同，用户无从分辨。
class StickerEditPage extends ConsumerStatefulWidget {
  const StickerEditPage({Key? key, required this.stickerId}) : super(key: key);

  final String stickerId;

  @override
  ConsumerState<StickerEditPage> createState() => _StickerEditPageState();
}

class _StickerEditPageState extends ConsumerState<StickerEditPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  List<String> _categoryIds = <String>[];
  List<String> _tagIds = <String>[];
  bool _initialised = false;
  bool _saving = false;

  /// Original values, used to detect whether anything actually changed so the
  /// save path can skip a pointless write (and therefore a pointless sync).
  /// 原始值，用于判断是否真的有改动，使保存路径可以跳过无意义的写入
  /// （以及随之而来的无意义同步）。
  String _originalName = '';
  String _originalNote = '';
  List<String> _originalCategoryIds = <String>[];
  List<String> _originalTagIds = <String>[];

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Sticker? sticker =
        ref.watch(stickerByIdLookupProvider(widget.stickerId));
    final Series? series = sticker == null
        ? null
        : ref.watch(seriesByIdLookupProvider(sticker.seriesId));

    if (sticker == null) {
      return MoeScaffold(
        appBar: AppBar(title: const Text('编辑表情包')),
        body: EmptyState(
          icon: Icons.error_outline,
          title: '找不到这张表情包',
          message: '它可能已被删除。',
          action: ElevatedButton(
            onPressed: () => context.go(RoutePaths.library),
            child: const Text('返回首页'),
          ),
        ),
      );
    }

    if (!_initialised) _seed(sticker);

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('编辑表情包'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(RoutePaths.stickerOf(sticker.id)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : () => _save(sticker),
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          const SectionHeader('名称'),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: series?.name.isNotEmpty == true
                  ? '留空则显示系列名「${series!.name}」'
                  : '给这张表情包起个名字',
            ),
            textInputAction: TextInputAction.next,
          ),

          const SectionHeader(
            '分类',
            subtitle: '留空则继承系列分类；一旦选择，就只使用你在这里选的分类',
          ),
          if (series != null && series.categoryIds.isNotEmpty)
            _InheritedHint(
              text: '当前继承系列分类（共 ${series.categoryIds.length} 个）',
            ),
          CategorySelector(
            selectedIds: _categoryIds,
            onChanged: (List<String> ids) =>
                setState(() => _categoryIds = ids),
          ),

          const SectionHeader(
            '标签',
            subtitle: '这里的标签会叠加到系列标签之上，而不是替换',
          ),
          if (series != null && series.tagIds.isNotEmpty)
            _InheritedHint(
              text: '会自动带上系列的 ${series.tagIds.length} 个标签',
            ),
          TagSelector(
            selectedIds: _tagIds,
            onChanged: (List<String> ids) => setState(() => _tagIds = ids),
          ),

          const SectionHeader(
            '备注',
            subtitle: '与系列备注拼接后一起显示',
          ),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              hintText: '记录这张表情包的用途或出处',
            ),
            maxLines: 4,
            minLines: 3,
          ),

          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _delete(sticker),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除这张表情包'),
            style: OutlinedButton.styleFrom(
              primary: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  void _seed(Sticker sticker) {
    _initialised = true;
    _nameController.text = sticker.name;
    _noteController.text = sticker.note;
    _categoryIds = List<String>.from(sticker.categoryIds);
    _tagIds = List<String>.from(sticker.tagIds);
    _originalName = sticker.name;
    _originalNote = sticker.note;
    _originalCategoryIds = List<String>.from(sticker.categoryIds);
    _originalTagIds = List<String>.from(sticker.tagIds);
  }

  /// Whether the form differs from what was loaded.
  /// 表单内容是否与载入时不同。
  bool get _isDirty {
    if (_nameController.text != _originalName) return true;
    if (_noteController.text != _originalNote) return true;
    if (!_sameList(_categoryIds, _originalCategoryIds)) return true;
    if (!_sameList(_tagIds, _originalTagIds)) return true;
    return false;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _save(Sticker sticker) async {
    if (!_isDirty) {
      if (mounted) context.go(RoutePaths.stickerOf(sticker.id));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(libraryActionsProvider).updateSticker(
            sticker,
            name: _nameController.text.trim(),
            categoryIds: _categoryIds,
            tagIds: _tagIds,
            note: _noteController.text.trim(),
          );
      if (!mounted) return;
      showToast(context, '已保存');
      context.go(RoutePaths.stickerOf(sticker.id));
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Sticker sticker) async {
    final bool ok = await confirm(
      context,
      title: '删除表情包',
      message: '这张表情包将被移入回收站。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(libraryActionsProvider).deleteSticker(sticker);
    if (mounted) {
      showToast(context, '已移入回收站');
      context.go(RoutePaths.seriesOf(sticker.seriesId));
    }
  }
}

/// One-line explanation of what will be inherited if the field is left empty.
/// 说明字段留空时将继承什么的一行提示。
class _InheritedHint extends StatelessWidget {
  const _InheritedHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.subdirectory_arrow_right,
            size: 15,
            color: theme.colorScheme.primary.withOpacity(0.7),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
