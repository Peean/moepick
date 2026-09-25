import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_version.dart';
import '../../../data/models/category.dart';
import '../../../data/models/series.dart';
import '../../../data/models/sticker.dart';
import '../../../data/models/tag.dart';
import '../../../data/repositories/search_repository.dart';
import '../../settings/application/storage_providers.dart';

/// All live series, newest first.
/// 全部未删除的系列，按创建时间倒序。
///
/// Every provider below watches [dataVersionProvider], so any write anywhere in
/// the app refreshes them consistently. This is the single invalidation path.
///
/// 以下每个 provider 都监听 [dataVersionProvider]，
/// 因此应用中任何位置写入都会一致地刷新它们。这是唯一的失效路径。
final Provider<List<Series>> seriesListProvider = Provider<List<Series>>(
  (Ref ref) {
    ref.watch(dataVersionProvider);
    return ref.watch(seriesRepositoryProvider).getAll();
  },
);

/// All live stickers.
/// 全部未删除的表情包。
final Provider<List<Sticker>> stickerListProvider = Provider<List<Sticker>>(
  (Ref ref) {
    ref.watch(dataVersionProvider);
    return ref.watch(stickerRepositoryProvider).getAll();
  },
);

/// All live categories, ordered for display.
/// 全部未删除的分类，按展示顺序排列。
final Provider<List<Category>> categoryListProvider = Provider<List<Category>>(
  (Ref ref) {
    ref.watch(dataVersionProvider);
    return ref.watch(taxonomyRepositoryProvider).getCategories();
  },
);

/// All live tags, most used first.
/// 全部未删除的标签，使用次数多的在前。
final Provider<List<Tag>> tagListProvider = Provider<List<Tag>>((Ref ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(taxonomyRepositoryProvider).getTags();
});

/// Series indexed by id, for O(1) lookups when resolving a sticker's parent.
/// 按 id 索引的系列，用于解析表情包父级时的 O(1) 查找。
final Provider<Map<String, Series>> seriesByIdProvider =
    Provider<Map<String, Series>>((Ref ref) {
  final List<Series> list = ref.watch(seriesListProvider);
  return <String, Series>{
    for (final Series s in list) s.id: s,
  };
});

/// Categories indexed by id.
/// 按 id 索引的分类。
final Provider<Map<String, Category>> categoryByIdProvider =
    Provider<Map<String, Category>>((Ref ref) {
  final List<Category> list = ref.watch(categoryListProvider);
  return <String, Category>{
    for (final Category c in list) c.id: c,
  };
});

/// Tags indexed by id.
/// 按 id 索引的标签。
final Provider<Map<String, Tag>> tagByIdProvider = Provider<Map<String, Tag>>(
  (Ref ref) {
    final List<Tag> list = ref.watch(tagListProvider);
    return <String, Tag>{
      for (final Tag t in list) t.id: t,
    };
  },
);

/// Live stickers belonging to one series, in display order.
/// 某系列下未删除的表情包，按展示顺序排列。
final ProviderFamily<List<Sticker>, String> stickersBySeriesProvider =
    Provider.family<List<Sticker>, String>((Ref ref, String seriesId) {
  ref.watch(dataVersionProvider);
  return ref.watch(stickerRepositoryProvider).getBySeries(seriesId);
});

/// A single series by id.
/// 按 id 取单个系列。
final ProviderFamily<Series?, String> seriesByIdLookupProvider =
    Provider.family<Series?, String>((Ref ref, String id) {
  ref.watch(dataVersionProvider);
  return ref.watch(seriesRepositoryProvider).getById(id);
});

/// A single sticker by id.
/// 按 id 取单个表情包。
final ProviderFamily<Sticker?, String> stickerByIdLookupProvider =
    Provider.family<Sticker?, String>((Ref ref, String id) {
  ref.watch(dataVersionProvider);
  return ref.watch(stickerRepositoryProvider).getById(id);
});

/// The active search query.
/// 当前生效的搜索查询。
class SearchQueryNotifier extends Notifier<SearchQuery> {
  @override
  SearchQuery build() => SearchQuery.empty;

  void setText(String text) => state = state.copyWith(text: text);

  void toggleCategory(String id) {
    final Set<String> next = Set<String>.from(state.categoryIds);
    if (!next.add(id)) next.remove(id);
    state = state.copyWith(categoryIds: next);
  }

  void toggleTag(String id) {
    final Set<String> next = Set<String>.from(state.tagIds);
    if (!next.add(id)) next.remove(id);
    state = state.copyWith(tagIds: next);
  }

  void setSeries(String? id) => state = state.copyWith(seriesId: id);

  void clear() => state = SearchQuery.empty;

  /// Clear filters but keep the typed text.
  /// 清除过滤条件但保留已输入文本。
  void clearFilters() => state = SearchQuery(
        text: state.text,
        seriesId: state.seriesId,
      );
}

final NotifierProvider<SearchQueryNotifier, SearchQuery> searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, SearchQuery>(SearchQueryNotifier.new);

/// Results for the current query.
/// 当前查询的结果。
///
/// Depends on the query plus every data source, so editing a sticker's note
/// immediately refreshes an open search view.
/// 依赖查询条件与全部数据源，因此修改表情包备注会立即刷新正在展示的搜索结果。
final Provider<AsyncValue<List<SearchHit>>> searchResultsProvider =
    Provider<AsyncValue<List<SearchHit>>>((Ref ref) {
  final SearchQuery query = ref.watch(searchQueryProvider);
  if (query.isEmpty) {
    return const AsyncValue<List<SearchHit>>.data(<SearchHit>[]);
  }

  final List<Sticker> stickers = ref.watch(stickerListProvider);
  final Map<String, Series> seriesById = ref.watch(seriesByIdProvider);
  final Map<String, Category> categoryById = ref.watch(categoryByIdProvider);
  final Map<String, Tag> tagById = ref.watch(tagByIdProvider);

  final List<SearchHit> hits = ref.watch(searchRepositoryProvider).search(
        query: query,
        stickers: stickers,
        seriesById: seriesById,
        categoryById: categoryById,
        tagById: tagById,
      );

  return AsyncValue<List<SearchHit>>.data(hits);
});

/// Aggregate counts shown on the settings / stats screen.
/// 设置与统计页展示的汇总计数。
final Provider<Map<String, int>> libraryStatsProvider =
    Provider<Map<String, int>>((Ref ref) {
  return <String, int>{
    'series': ref.watch(seriesListProvider).length,
    'stickers': ref.watch(stickerListProvider).length,
    'categories': ref.watch(categoryListProvider).length,
    'tags': ref.watch(tagListProvider).length,
  };
});

// --------------------------------------------------------------------- 回收站

/// Soft-deleted series, oldest deletion first.
/// 已软删除的系列，按删除时间倒序（最旧在前）。
final Provider<List<Series>> trashSeriesProvider = Provider<List<Series>>(
  (Ref ref) {
    ref.watch(dataVersionProvider);
    final List<Series> list = ref
        .watch(seriesRepositoryProvider)
        .getAllIncludingDeleted()
        .where((Series s) => s.isDeleted)
        .toList();
    list.sort((Series a, Series b) => a.updatedAt.compareTo(b.updatedAt));
    return list;
  },
);

/// Soft-deleted stickers, oldest deletion first.
/// 已软删除的表情包，按删除时间倒序（最旧在前）。
final Provider<List<Sticker>> trashStickersProvider =
    Provider<List<Sticker>>((Ref ref) {
  ref.watch(dataVersionProvider);
  final List<Sticker> list = ref
      .watch(stickerRepositoryProvider)
      .getAllIncludingDeleted()
      .where((Sticker s) => s.isDeleted)
      .toList();
  list.sort((Sticker a, Sticker b) => a.updatedAt.compareTo(b.updatedAt));
  return list;
});

/// How many items the trash holds, for the settings-page badge.
/// 回收站条目数，供设置页角标使用。
final Provider<int> trashCountProvider = Provider<int>((Ref ref) {
  return ref.watch(trashSeriesProvider).length +
      ref.watch(trashStickersProvider).length;
});

// --------------------------------------------------------------------- 收藏

/// Series marked as favourite, pinned first then newest.
/// 已收藏的系列，置顶在前，其次按创建时间倒序。
final Provider<List<Series>> favoriteSeriesProvider =
    Provider<List<Series>>((Ref ref) {
  ref.watch(dataVersionProvider);
  final List<Series> list = ref
      .watch(seriesRepositoryProvider)
      .getAll()
      .where((Series s) => s.favorite)
      .toList();
  return list;
});

/// Stickers marked as favourite, grouped visually by the caller.
/// 已收藏的表情包。
final Provider<List<Sticker>> favoriteStickersProvider =
    Provider<List<Sticker>>((Ref ref) {
  ref.watch(dataVersionProvider);
  return ref
      .watch(stickerRepositoryProvider)
      .getAll()
      .where((Sticker s) => s.favorite)
      .toList();
});
