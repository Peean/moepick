import '../mappers/effective_meta.dart';
import '../models/category.dart';
import '../models/series.dart';
import '../models/sticker.dart';
import '../models/tag.dart';

/// A search request.
/// 一次搜索请求。
///
/// Structured filters combine with AND; the free-text term matches with OR
/// across fields but is weighted, so the best match floats to the top.
/// 结构化过滤条件之间为 AND；自由文本在各字段间为 OR 匹配但带权重，
/// 使匹配度最高的结果排在前面。
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.categoryIds = const <String>{},
    this.tagIds = const <String>{},
    this.seriesId,
  });

  final String text;

  /// Required categories. Empty means "no category filter".
  /// 必需的分类。为空表示不按分类过滤。
  final Set<String> categoryIds;

  /// Required tags. Empty means "no tag filter".
  /// 必需的标签。为空表示不按标签过滤。
  final Set<String> tagIds;

  /// Restrict to one series.
  /// 限定到某个系列。
  final String? seriesId;

  bool get isEmpty =>
      text.trim().isEmpty &&
      categoryIds.isEmpty &&
      tagIds.isEmpty &&
      (seriesId == null || seriesId!.isEmpty);

  static const SearchQuery empty = SearchQuery();

  SearchQuery copyWith({
    String? text,
    Set<String>? categoryIds,
    Set<String>? tagIds,
    Object? seriesId = _unset,
  }) {
    return SearchQuery(
      text: text ?? this.text,
      categoryIds: categoryIds ?? this.categoryIds,
      tagIds: tagIds ?? this.tagIds,
      seriesId:
          identical(seriesId, _unset) ? this.seriesId : seriesId as String?,
    );
  }

  static const Object _unset = Object();
}

/// One search result with its relevance score and the fields that matched.
/// 单条搜索结果，含相关度评分与命中的字段。
class SearchHit {
  const SearchHit({
    required this.sticker,
    required this.series,
    required this.score,
    required this.matchedFields,
  });

  final Sticker sticker;
  final Series? series;

  /// Higher is more relevant.
  /// 数值越大越相关。
  final double score;

  /// Which fields matched, for UI highlighting.
  /// 命中的字段，供 UI 高亮显示。
  final Set<String> matchedFields;

  bool get matchedName => matchedFields.contains(SearchFields.name);
  bool get matchedTag => matchedFields.contains(SearchFields.tag);
  bool get matchedCategory => matchedFields.contains(SearchFields.category);
  bool get matchedNote => matchedFields.contains(SearchFields.note);
  bool get matchedSeriesName => matchedFields.contains(SearchFields.seriesName);
}

/// Field identifiers used in [SearchHit.matchedFields].
/// [SearchHit.matchedFields] 中使用的字段标识。
class SearchFields {
  SearchFields._();
  static const String name = 'name';
  static const String seriesName = 'seriesName';
  static const String tag = 'tag';
  static const String category = 'category';
  static const String note = 'note';
}

/// One entry of the in-memory search index.
/// 内存搜索索引的一条条目。
///
/// All text is pre-lowercased so matching does not repeat that work per query.
/// 所有文本预先转小写，避免每次查询重复处理。
class SearchIndexEntry {
  SearchIndexEntry({
    required this.stickerId,
    required this.seriesId,
    required this.nameLower,
    required this.seriesNameLower,
    required this.noteLower,
    required this.categoryNamesLower,
    required this.tagNamesLower,
    required this.rawCategoryIds,
    required this.rawTagIds,
  });

  final String stickerId;
  final String seriesId;
  final String nameLower;
  final String seriesNameLower;
  final String noteLower;
  final List<String> categoryNamesLower;
  final List<String> tagNamesLower;

  /// Effective ids retained so structured filtering works on ids rather than
  /// names (names can be edited, ids cannot).
  /// 保留解析后的 id，使结构化过滤基于 id 而非名称（名称可改，id 不可）。
  final List<String> rawCategoryIds;
  final List<String> rawTagIds;
}

/// Scores assigned to each matching field.
/// 各命中字段的权重。
///
/// A name match is the strongest signal; a note match is the weakest, since
/// notes are prose and produce more incidental substring hits.
/// 名称命中是最强信号；备注命中最弱，因为备注是散文，容易产生偶然的子串命中。
class SearchWeights {
  SearchWeights._();
  static const double name = 10.0;
  static const double seriesName = 6.0;
  static const double tag = 5.0;
  static const double category = 3.0;
  static const double note = 2.0;

  /// Extra weight when the match is a prefix of the field, so typing "开"
  /// ranks "开心" above "不开心".
  /// 命中为字段前缀时的额外权重，使输入「开」时「开心」排在「不开心」之前。
  static const double prefixBonus = 2.0;
}

/// In-memory search over stickers, resolving series metadata via
/// [EffectiveMeta] so series-level categories, tags and notes are searchable
/// without any extra bookkeeping.
///
/// 基于内存的表情包搜索。通过 [EffectiveMeta] 解析系列元数据，
/// 因此系列级分类、标签、备注天然可被搜索，无需额外维护。
///
/// Design note: an in-memory scan was chosen over a persisted inverted index.
/// At the data scale this app targets (hundreds to a few thousand stickers),
/// a full scan costs on the order of milliseconds, while a persisted index
/// would add incremental-update and consistency burden for no user-visible gain.
///
/// 设计说明：选择内存扫描而非持久化倒排索引。在本应用的目标数据规模
/// （数百至数千个表情包）下，全量扫描仅需毫秒级，而持久化索引会带来
/// 增量更新与一致性的负担，却没有用户可感知的收益。
class SearchRepository {
  SearchRepository();

  /// Build the index and run [query].
  /// 构建索引并执行 [query]。
  ///
  /// The index is rebuilt per call. Caching it would need an invalidation
  /// signal that can drift; at this data scale a rebuild is cheaper than the
  /// bug surface of a stale cache.
  ///
  /// 索引在每次调用时重建。缓存它需要一套可能失准的失效信号；
  /// 在当前数据规模下，重建的代价低于陈旧缓存带来的缺陷面。
  List<SearchHit> search({
    required SearchQuery query,
    required List<Sticker> stickers,
    required Map<String, Series> seriesById,
    required Map<String, Category> categoryById,
    required Map<String, Tag> tagById,
  }) {
    if (query.isEmpty) return const <SearchHit>[];

    final List<SearchIndexEntry> index = _buildIndex(
      stickers: stickers,
      seriesById: seriesById,
      categoryById: categoryById,
      tagById: tagById,
    );

    final String needle = query.text.trim().toLowerCase();
    final List<SearchHit> hits = <SearchHit>[];

    for (final SearchIndexEntry entry in index) {
      // --- Structured filters (AND) ---------------------------------------
      // --- 结构化过滤（AND）-----------------------------------------------
      if (query.seriesId != null &&
          query.seriesId!.isNotEmpty &&
          entry.seriesId != query.seriesId) {
        continue;
      }
      if (query.categoryIds.isNotEmpty &&
          !_covers(entry.rawCategoryIds, query.categoryIds)) {
        continue;
      }
      if (query.tagIds.isNotEmpty &&
          !_covers(entry.rawTagIds, query.tagIds)) {
        continue;
      }

      // --- Text matching (weighted OR) ------------------------------------
      // --- 文本匹配（加权 OR）---------------------------------------------
      double score = 0;
      final Set<String> matched = <String>{};

      if (needle.isNotEmpty) {
        score += _scoreField(
          needle,
          entry.nameLower,
          SearchWeights.name,
          SearchFields.name,
          matched,
        );
        score += _scoreField(
          needle,
          entry.seriesNameLower,
          SearchWeights.seriesName,
          SearchFields.seriesName,
          matched,
        );
        score += _scoreList(
          needle,
          entry.tagNamesLower,
          SearchWeights.tag,
          SearchFields.tag,
          matched,
        );
        score += _scoreList(
          needle,
          entry.categoryNamesLower,
          SearchWeights.category,
          SearchFields.category,
          matched,
        );
        score += _scoreField(
          needle,
          entry.noteLower,
          SearchWeights.note,
          SearchFields.note,
          matched,
        );

        // Require at least one text match, otherwise a text search would
        // return the entire library.
        // 必须至少命中一处文本，否则文本搜索会返回整个库。
        if (score <= 0) continue;
      }

      final Sticker? sticker = _findSticker(stickers, entry.stickerId);
      if (sticker == null) continue;

      hits.add(
        SearchHit(
          sticker: sticker,
          series: seriesById[entry.seriesId],
          score: score,
          matchedFields: matched,
        ),
      );
    }

    // Relevance first; ties broken by newest so results are deterministic.
    // 先按相关度，相同则按最新排序，保证结果确定性。
    hits.sort((SearchHit a, SearchHit b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.sticker.createdAt.compareTo(a.sticker.createdAt);
    });

    return hits;
  }

  List<SearchIndexEntry> _buildIndex({
    required List<Sticker> stickers,
    required Map<String, Series> seriesById,
    required Map<String, Category> categoryById,
    required Map<String, Tag> tagById,
  }) {
    final List<SearchIndexEntry> index = <SearchIndexEntry>[];

    for (final Sticker sticker in stickers) {
      if (sticker.isDeleted) continue;

      final Series? series = seriesById[sticker.seriesId];
      final EffectiveMeta meta = EffectiveMeta.of(sticker, series);

      index.add(
        SearchIndexEntry(
          stickerId: sticker.id,
          seriesId: sticker.seriesId,
          nameLower: meta.displayName.toLowerCase(),
          seriesNameLower: meta.seriesName.toLowerCase(),
          noteLower: meta.note.toLowerCase(),
          categoryNamesLower: _namesOf(meta.categoryIds, categoryById),
          tagNamesLower: _namesOf(meta.tagIds, tagById),
          rawCategoryIds: meta.categoryIds,
          rawTagIds: meta.tagIds,
        ),
      );
    }

    return index;
  }

  /// Map ids to lowercase names, skipping ids that no longer resolve.
  /// 将 id 映射为小写名称，跳过已无法解析的 id。
  List<String> _namesOf(
    List<String> ids,
    Map<String, Object?> byId,
  ) {
    final List<String> names = <String>[];
    for (final String id in ids) {
      final Object? entity = byId[id];
      if (entity == null) continue;
      // Both Category and Tag expose `name`; reading it dynamically avoids
      // duplicating this helper for each type.
      // Category 与 Tag 都有 `name`；动态读取可避免为每种类型重复实现。
      final String name = _nameOf(entity);
      if (name.isEmpty) continue;
      names.add(name.toLowerCase());
    }
    return names;
  }

  String _nameOf(Object entity) {
    if (entity is Category) return entity.name;
    if (entity is Tag) return entity.name;
    return '';
  }

  double _scoreField(
    String needle,
    String haystack,
    double weight,
    String field,
    Set<String> matched,
  ) {
    if (haystack.isEmpty) return 0;
    final bool hit = haystack.contains(needle);
    if (!hit) return 0;
    matched.add(field);
    // Prefix matches are stronger evidence than mid-string matches.
    // 前缀匹配比中间匹配是更强的证据。
    return haystack.startsWith(needle) ? weight + SearchWeights.prefixBonus : weight;
  }

  double _scoreList(
    String needle,
    List<String> haystacks,
    double weight,
    String field,
    Set<String> matched,
  ) {
    double best = 0;
    for (final String haystack in haystacks) {
      final double score = _scoreField(
        needle,
        haystack,
        weight,
        field,
        matched,
      );
      if (score > best) best = score;
    }
    // A field contributes once, at its best match, so that adding more tags
    // does not inflate the score.
    // 同一字段只按其最佳命中计分一次，避免标签越多分数越高。
    return best;
  }

  /// True when every required id is present in [owned].
  /// [owned] 是否包含全部必需的 id。
  bool _covers(List<String> owned, Set<String> required) {
    if (required.isEmpty) return true;
    for (final String id in required) {
      if (!owned.contains(id)) return false;
    }
    return true;
  }

  Sticker? _findSticker(List<Sticker> stickers, String id) {
    for (final Sticker s in stickers) {
      if (s.id == id) return s;
    }
    return null;
  }
}
