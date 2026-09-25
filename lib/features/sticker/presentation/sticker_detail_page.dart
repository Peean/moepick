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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/id_utils.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/mappers/effective_meta.dart';
import '../../../data/models/category.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/models/tag.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../library/application/library_actions.dart';
import '../../library/application/library_providers.dart';
import '../../series/presentation/widgets/inheritance_summary.dart';

/// One sticker: full-size preview plus its effective metadata.
/// 单个表情包：大图预览及其生效后的元数据。
///
/// The metadata panel shows *effective* values and labels which ones are
/// inherited, because the inheritance rules (categories override, tags union,
/// notes concatenate) are not guessable from the raw stored fields.
///
/// 元数据面板展示**生效后**的值，并标明哪些是继承来的，
/// 因为继承规则（分类覆盖、标签并集、备注拼接）无法从原始存储字段中猜出。
class StickerDetailPage extends ConsumerWidget {
  const StickerDetailPage({Key? key, required this.stickerId})
      : super(key: key);

  final String stickerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Sticker? sticker = ref.watch(stickerByIdLookupProvider(stickerId));

    if (sticker == null) {
      return MoeScaffold(
        appBar: AppBar(
          title: const Text('表情包'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: EmptyState(
          icon: Icons.image_not_supported_outlined,
          title: '这张表情包已不存在',
          message: '它可能已被删除。',
          action: ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('返回首页'),
          ),
        ),
      );
    }

    final Series? series = ref.watch(seriesByIdLookupProvider(sticker.seriesId));
    final EffectiveMeta meta = EffectiveMeta.of(sticker, series);
    final Map<String, Category> categoryById = ref.watch(categoryByIdProvider);
    final Map<String, Tag> tagById = ref.watch(tagByIdProvider);

    return MoeScaffold(
      appBar: AppBar(
        title: Text(_titleFor(sticker, series)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: sticker.pinned ? '取消置顶' : '置顶',
            icon: Icon(
              sticker.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: sticker.pinned
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => _togglePin(context, ref, sticker),
          ),
          IconButton(
            tooltip: sticker.favorite ? '取消收藏' : '收藏',
            icon: Icon(
              sticker.favorite ? Icons.star : Icons.star_border,
              color: sticker.favorite
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => _toggleFavorite(context, ref, sticker),
          ),
          IconButton(
            tooltip: '分享',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _share(context, sticker),
          ),
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(RoutePaths.stickerEditOf(sticker.id)),
          ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'delete') _delete(context, ref, sticker);
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'delete',
                child: DestructiveMenuItem(
                  icon: Icons.delete_outline,
                  label: '删除表情包',
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          _Preview(sticker: sticker),

          const SectionHeader('归属'),
          MoeCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    series?.name ?? '（系列已删除）',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                if (series != null)
                  TextButton(
                    onPressed: () =>
                        context.push(RoutePaths.seriesOf(series.id)),
                    child: const Text('查看系列'),
                  ),
              ],
            ),
          ),

          const SectionHeader(
            '生效中的分类与标签',
            subtitle: '淡色表示继承自系列，实色表示在本张上设置',
          ),
          MoeCard(
            child: EffectiveMetaChips(
              sticker: sticker,
              series: series,
              categoryById: categoryById,
              tagById: tagById,
              maxChips: 12,
            ),
          ),

          const SectionHeader('生效中的备注'),
          MoeCard(
            child: Text(
              meta.note.isEmpty ? '没有备注' : meta.note,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: meta.note.isEmpty
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5)
                        : null,
                  ),
            ),
          ),

          const SectionHeader('文件信息'),
          MoeCard(
            child: Column(
              children: <Widget>[
                _InfoRow(label: '尺寸', value: '${sticker.width} × ${sticker.height}'),
                _InfoRow(label: '大小', value: _formatBytes(sticker.byteSize)),
                _InfoRow(
                  label: '导入时间',
                  value: _formatDate(sticker.createdAt),
                ),
                if (sticker.sha256.isNotEmpty)
                  _InfoRow(
                    label: '内容哈希',
                    value: IdUtils.shortId(sticker.sha256, length: 16),
                    mono: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _titleFor(Sticker sticker, Series? series) {
    if (sticker.name.isNotEmpty) return sticker.name;
    return series?.name ?? '表情包';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '未知';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String _formatDate(DateTime utc) {
    final DateTime local = utc.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Share the sticker's image through the platform share sheet.
  /// 通过系统分享面板分享表情包图片。
  ///
  /// Shares the original image file (not the thumbnail), which is what the
  /// recipient expects to receive in a chat or social app.
  ///
  /// 分享的是原图文件（而非缩略图），这正是对方在聊天或社交应用里期望收到的东西。
  Future<void> _share(BuildContext context, Sticker sticker) async {
    final String absolute = PathUtils.absoluteSync(sticker.relativePath);
    final File file = File(absolute);
    if (!await file.exists()) {
      if (contextIsAlive(context)) {
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
      if (contextIsAlive(context)) {
        showToast(context, '分享失败：$e', isError: true);
      }
    }
  }

  Future<void> _togglePin(
    BuildContext context,
    WidgetRef ref,
    Sticker sticker,
  ) async {
    final bool? result = await ref
        .read(libraryActionsProvider)
        .toggleStickerPin(sticker.id);
    if (!contextIsAlive(context)) return;
    if (result == null) {
      showToast(context, '已达置顶上限，请先取消其他置顶', isError: true);
    } else {
      showToast(context, result ? '已置顶' : '已取消置顶');
    }
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    Sticker sticker,
  ) async {
    final bool result = await ref
        .read(libraryActionsProvider)
        .toggleStickerFavorite(sticker.id);
    if (!contextIsAlive(context)) return;
    showToast(context, result ? '已收藏' : '已取消收藏');
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Sticker sticker,
  ) async {
    final bool ok = await confirm(
      context,
      title: '删除表情包',
      message: '这张表情包将被移入回收站，并从它的系列中移除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;

    await ref.read(libraryActionsProvider).deleteSticker(sticker);
    // `contextIsAlive` flips to false the moment the element is deactivated, so the
    // context below is provably live. The analyzer cannot see through the helper
    // (it only special-cases the literal name `mounted`), hence the targeted ignore.
    // `contextIsAlive` 在 element 被 deactivate 的那一刻即变为 false，因此下面的
    // context 可证为存活。分析器无法看穿该辅助函数（它只对字面量名
    // `mounted` 特判），故此处做针对性忽略。
    if (!contextIsAlive(context)) return;
    showToast(context, '已移入回收站');
    context.pop();
  }
}

/// Full-bleed preview of the sticker at its natural aspect ratio.
/// 按原始宽高比全宽预览表情包。
///
/// Constrains the decode size to the screen width: an 8000px source would
/// otherwise allocate a texture far larger than the screen can display.
/// 将解码尺寸限制在屏幕宽度内：否则 8000px 的源图会分配远超屏幕可显示面积的纹理。
class _Preview extends StatelessWidget {
  const _Preview({required this.sticker});

  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Fall back to a square when the natural size is unknown (0×0), which
    // happens for images whose header could not be parsed.
    // 自然尺寸未知（0×0）时退化为正方形；这出现在无法解析文件头的图片上。
    final double aspect = (sticker.width > 0 && sticker.height > 0)
        ? sticker.width / sticker.height
        : 1.0;

    final int cacheWidth =
        (MediaQuery.of(context).size.width *
                MediaQuery.of(context).devicePixelRatio)
            .round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: theme.colorScheme.onSurface.withOpacity(0.05),
        constraints: const BoxConstraints(maxHeight: 420),
        child: AspectRatio(
          aspectRatio: aspect.clamp(0.4, 2.5),
          child: Image.file(
            File(PathUtils.absoluteSync(sticker.relativePath)),
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            errorBuilder: (_, __, ___) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.broken_image_outlined,
                    size: 36,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '图片文件已丢失',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One label/value line in the file info block.
/// 文件信息区块中的单条标签/值。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
