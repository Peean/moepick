import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/category.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/models/tag.dart';
import '../../../data/repositories/search_repository.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../../../shared/widgets/sticker_tile.dart';
import '../../library/application/library_providers.dart';

/// Search across names, series names, categories, tags and notes.
/// 跨名称、系列名、分类、标签与备注的搜索。
///
/// Structured filters and free text are kept in one query object, so the two
/// compose without the page having to reconcile them. The chips double as both
/// filters and a way to *discover* what is in the library.
///
/// 结构化过滤与自由文本保存在同一个查询对象中，二者自然组合，
/// 页面无需自行协调。芯片既可作过滤条件，也是**发现**库中内容的入口。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Seed from the provider so re-entering the page keeps the last query.
    // 从 provider 初始化，使再次进入本页时保留上次的查询。
    _controller.text = ref.read(searchQueryProvider).text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SearchQuery query = ref.watch(searchQueryProvider);
    final SearchQueryNotifier notifier = ref.read(searchQueryProvider.notifier);
    final AsyncValue<List<SearchHit>> results =
        ref.watch(searchResultsProvider);

    final String resultLabel = query.isEmpty
        ? ''
        : '找到 ${results.value?.length ?? 0} 个结果';

    return MoeScaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: false,
          decoration: InputDecoration(
            hintText: '搜索名称、分类、标签、备注',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    tooltip: '清空',
                    onPressed: () {
                      _controller.clear();
                      notifier.setText('');
                    },
                  ),
          ),
          textInputAction: TextInputAction.search,
          onChanged: notifier.setText,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          // Filters are collapsed behind a bar so the result grid gets the
          // space when the user is only typing text.
          // 过滤条件收在一条横栏后，使用户只输入文本时把空间留给结果网格。
          _FilterBar(
            query: query,
            onExpand: () => _openFilterSheet(context, notifier),
            onClear: () {
              notifier.clearFilters();
            },
          ),

          if (resultLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  resultLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                ),
              ),
            ),

          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stack) => EmptyState(
                icon: Icons.error_outline,
                title: '搜索出错了',
                message: '$error',
              ),
              data: (List<SearchHit> hits) =>
                  _ResultView(query: query, hits: hits),
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context, SearchQueryNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => _FilterSheet(notifier: notifier),
    );
  }
}

/// Condensed summary of the active filters, with a tap target to edit them.
/// 当前过滤条件的浓缩摘要，可点击进行编辑。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.onExpand,
    required this.onClear,
  });

  final SearchQuery query;
  final VoidCallback onExpand;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasFilters = query.categoryIds.isNotEmpty ||
        query.tagIds.isNotEmpty ||
        (query.seriesId != null && query.seriesId!.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: onExpand,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.tune,
                      size: 17,
                      color: hasFilters
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        hasFilters
                            ? _summary()
                            : '按分类或标签筛选',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasFilters
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasFilters)
                      GestureDetector(
                        onTap: onClear,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _summary() {
    final List<String> parts = <String>[];
    if (query.categoryIds.isNotEmpty) {
      parts.add('${query.categoryIds.length} 个分类');
    }
    if (query.tagIds.isNotEmpty) {
      parts.add('${query.tagIds.length} 个标签');
    }
    if (query.seriesId != null && query.seriesId!.isNotEmpty) {
      parts.add('限定系列');
    }
    return '已筛选：${parts.join(' · ')}';
  }
}

/// Scrollable bottom sheet holding the category / tag / series filters.
/// 承载分类 / 标签 / 系列过滤条件的可滚动底部面板。
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.notifier});

  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SearchQuery query = ref.watch(searchQueryProvider);
    final List<Category> categories = ref.watch(categoryListProvider);
    final List<Tag> tags = ref.watch(tagListProvider);
    final List<Series> seriesList = ref.watch(seriesListProvider);
    final ThemeData theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (BuildContext ctx, ScrollController controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '筛选',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: notifier.clearFilters,
                  child: const Text('清除筛选'),
                ),
              ],
            ),

            if (categories.isEmpty && tags.isEmpty && seriesList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  '还没有分类、标签或系列可以筛选。\n'
                  '在设置里的「分类与标签」中创建它们。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    height: 1.6,
                  ),
                ),
              ),

            if (seriesList.isNotEmpty) ...<Widget>[
              const SectionHeader('限定系列'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: seriesList.map((Series s) {
                  final bool selected = query.seriesId == s.id;
                  return FilterChip(
                    selected: selected,
                    label: Text(s.name),
                    onSelected: (bool value) =>
                        notifier.setSeries(value ? s.id : null),
                  );
                }).toList(),
              ),
            ],

            if (categories.isNotEmpty) ...<Widget>[
              const SectionHeader(
                '分类',
                subtitle: '同时选择多个时，只保留全部命中的表情包',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((Category c) {
                  final bool selected = query.categoryIds.contains(c.id);
                  return FilterChip(
                    selected: selected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CategoryDot(color: Color(c.colorValue)),
                        const SizedBox(width: 6),
                        Text(c.name),
                      ],
                    ),
                    onSelected: (_) => notifier.toggleCategory(c.id),
                  );
                }).toList(),
              ),
            ],

            if (tags.isNotEmpty) ...<Widget>[
              const SectionHeader(
                '标签',
                subtitle: '同时选择多个时，只保留全部命中的表情包',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags.map((Tag t) {
                  final bool selected = query.tagIds.contains(t.id);
                  return FilterChip(
                    selected: selected,
                    label: Text(t.name),
                    onSelected: (_) => notifier.toggleTag(t.id),
                  );
                }).toList(),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The search results: an empty prompt, a no-hits state, or the grid.
/// 搜索结果：初始提示、无结果状态或结果网格。
class _ResultView extends StatelessWidget {
  const _ResultView({required this.query, required this.hits});

  final SearchQuery query;
  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: '搜索你的表情包',
        message: '输入关键词即可检索名称、分类、标签和备注。\n'
            '系列上的分类、标签和备注同样能被搜到。',
      );
    }

    if (hits.isEmpty) {
      return const EmptyState(
        icon: Icons.sentiment_dissatisfied_outlined,
        title: '没有找到匹配的表情包',
        message: '试试更短的关键词，或减少筛选条件。',
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final SearchHit hit = hits[index];
                return _ResultTile(hit: hit);
              },
              childCount: hits.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// A result tile with a match-reason strip underneath.
/// 带命中原因条的结果瓦片。
class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final Sticker sticker = hit.sticker;
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: StickerTile(
            sticker: sticker,
            cacheWidth: 240,
            borderRadius: 10,
            onTap: () => context.push(RoutePaths.stickerOf(sticker.id)),
          ),
        ),
        const SizedBox(height: 4),
        // Showing *why* something matched makes a weak hit understandable
        // instead of looking like a bug.
        // 展示**为何**命中，使弱相关的命中可被理解，而不像是一个 bug。
        Text(
          _reason(hit),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            color: theme.colorScheme.onSurface.withOpacity(0.55),
          ),
        ),
      ],
    );
  }

  /// Human-readable description of the strongest matching field.
  /// 最强命中字段的可读描述。
  static String _reason(SearchHit hit) {
    if (hit.matchedName) return '名称命中';
    if (hit.matchedSeriesName) {
      return '系列「${hit.series?.name ?? ''}」命中';
    }
    if (hit.matchedTag) return '标签命中';
    if (hit.matchedCategory) return '分类命中';
    if (hit.matchedNote) return '备注命中';
    return '筛选命中';
  }
}
