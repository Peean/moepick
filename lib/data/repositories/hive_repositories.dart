import 'package:hive/hive.dart';

import '../../core/constants/hive_boxes.dart';
import '../../core/storage/hive_store.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id_utils.dart';
import '../models/category.dart';
import '../models/series.dart';
import '../models/sticker.dart';
import '../models/tag.dart';
import 'repository_contracts.dart';

/// Hive-backed [SeriesRepository].
/// 基于 Hive 的 [SeriesRepository] 实现。
class HiveSeriesRepository implements SeriesRepository {
  HiveSeriesRepository(this._store);

  final HiveStore _store;
  Box<Series> get _box => _store.boxByName(HiveBoxes.series) as Box<Series>;

  @override
  List<Series> getAll() {
    final List<Series> list =
        _box.values.where((Series s) => !s.isDeleted).toList();
    list.sort((Series a, Series b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  List<Series> getAllIncludingDeleted() => _box.values.toList();

  @override
  Series? getById(String id) {
    final Series? found = _box.get(id);
    if (found == null || found.isDeleted) return null;
    return found;
  }

  @override
  Future<void> save(Series series) async {
    // Stamp updatedAt centrally so callers cannot forget: sync conflict
    // resolution depends entirely on this field being trustworthy.
    // 在此统一打 updatedAt 时间戳，避免调用方遗漏：
    // 同步冲突解决完全依赖该字段的可信度。
    final Series stamped = series.copyWith(updatedAt: DateUtils.nowUtc());
    await _box.put(stamped.id, stamped);
  }

  @override
  Future<void> softDelete(String id) async {
    final Series? existing = _box.get(id);
    if (existing == null) return;
    await _box.put(
      id,
      existing.copyWith(isDeleted: true, updatedAt: DateUtils.nowUtc()),
    );
  }

  /// Update the denormalised sticker count so the gallery grid need not load
  /// every sticker to render a badge.
  /// 更新冗余的表情包计数，使图库网格无需加载全部表情包即可渲染角标。
  Future<void> updateStickerCount(String seriesId, int count) async {
    final Series? existing = _box.get(seriesId);
    if (existing == null || existing.stickerCount == count) return;
    await _box.put(
      seriesId,
      existing.copyWith(
        stickerCount: count,
        updatedAt: DateUtils.nowUtc(),
      ),
    );
  }
}

/// Hive-backed [StickerRepository].
/// 基于 Hive 的 [StickerRepository] 实现。
class HiveStickerRepository implements StickerRepository {
  HiveStickerRepository(this._store);

  final HiveStore _store;
  Box<Sticker> get _box =>
      _store.boxByName(HiveBoxes.stickers) as Box<Sticker>;

  @override
  List<Sticker> getAll() =>
      _box.values.where((Sticker s) => !s.isDeleted).toList();

  @override
  List<Sticker> getAllIncludingDeleted() => _box.values.toList();

  @override
  Sticker? getById(String id) {
    final Sticker? found = _box.get(id);
    if (found == null || found.isDeleted) return null;
    return found;
  }

  @override
  List<Sticker> getBySeries(String seriesId) {
    final List<Sticker> list = _box.values
        .where((Sticker s) => !s.isDeleted && s.seriesId == seriesId)
        .toList();
    list.sort((Sticker a, Sticker b) {
      final int byIndex = a.sortIndex.compareTo(b.sortIndex);
      // Fall back to creation time so equal sortIndex values stay stable.
      // 回退到创建时间，使 sortIndex 相同时排序稳定。
      return byIndex != 0 ? byIndex : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  @override
  int countBySeries(String seriesId) => _box.values
      .where((Sticker s) => !s.isDeleted && s.seriesId == seriesId)
      .length;

  @override
  Map<String, String> hashIndex() {
    final Map<String, String> index = <String, String>{};
    for (final Sticker s in _box.values) {
      if (s.isDeleted || s.sha256.isEmpty) continue;
      index[s.sha256] = s.id;
    }
    return index;
  }

  @override
  Future<void> save(Sticker sticker) async {
    final Sticker stamped = sticker.copyWith(updatedAt: DateUtils.nowUtc());
    await _box.put(stamped.id, stamped);
  }

  @override
  Future<void> saveAll(List<Sticker> stickers) async {
    final Map<String, Sticker> entries = <String, Sticker>{};
    for (final Sticker s in stickers) {
      entries[s.id] = s;
    }
    await _box.putAll(entries);
  }

  @override
  Future<void> softDelete(String id) async {
    final Sticker? existing = _box.get(id);
    if (existing == null) return;
    await _box.put(
      id,
      existing.copyWith(isDeleted: true, updatedAt: DateUtils.nowUtc()),
    );
  }

  @override
  Future<void> deleteBySeries(String seriesId) async {
    final List<String> ids = _box.values
        .where((Sticker s) => s.seriesId == seriesId)
        .map((Sticker s) => s.id)
        .toList();
    await _box.deleteAll(ids);
  }
}

/// Hive-backed [TaxonomyRepository].
/// 基于 Hive 的 [TaxonomyRepository] 实现。
class HiveTaxonomyRepository implements TaxonomyRepository {
  HiveTaxonomyRepository(this._store);

  final HiveStore _store;

  Box<Category> get _categories =>
      _store.boxByName(HiveBoxes.categories) as Box<Category>;
  Box<Tag> get _tags => _store.boxByName(HiveBoxes.tags) as Box<Tag>;

  @override
  List<Category> getCategories() {
    final List<Category> list =
        _categories.values.where((Category c) => !c.isDeleted).toList();
    list.sort((Category a, Category b) {
      final int byIndex = a.sortIndex.compareTo(b.sortIndex);
      return byIndex != 0 ? byIndex : a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  List<Category> getCategoriesIncludingDeleted() => _categories.values.toList();

  @override
  Category? getCategoryById(String id) {
    final Category? found = _categories.get(id);
    if (found == null || found.isDeleted) return null;
    return found;
  }

  @override
  Future<void> saveCategory(Category category) async {
    await _categories.put(
      category.id,
      category.copyWith(updatedAt: DateUtils.nowUtc()),
    );
  }

  @override
  Future<void> deleteCategory(String id) async {
    final Category? existing = _categories.get(id);
    if (existing == null) return;
    await _categories.put(
      id,
      existing.copyWith(isDeleted: true, updatedAt: DateUtils.nowUtc()),
    );
  }

  @override
  List<Tag> getTags() {
    final List<Tag> list =
        _tags.values.where((Tag t) => !t.isDeleted).toList();
    // Most-used first, then alphabetical: keeps frequently used tags within
    // reach without the user having to search.
    // 先按使用次数降序，再按名称：让常用标签无需搜索即可触达。
    list.sort((Tag a, Tag b) {
      final int byUsage = b.usageCount.compareTo(a.usageCount);
      return byUsage != 0 ? byUsage : a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  List<Tag> getAllTagsIncludingDeleted() => _tags.values.toList();

  @override
  Tag? getTagById(String id) {
    final Tag? found = _tags.get(id);
    if (found == null || found.isDeleted) return null;
    return found;
  }

  @override
  Future<String> ensureTag(String name) async {
    final String cleaned = name.trim();
    if (cleaned.isEmpty) return '';

    // Case-insensitive match so "Cat" and "cat" do not become two tags.
    // 大小写不敏感匹配，避免 "Cat" 与 "cat" 变成两个标签。
    final String lower = cleaned.toLowerCase();
    for (final Tag t in _tags.values) {
      if (t.isDeleted) continue;
      if (t.name.toLowerCase() == lower) return t.id;
    }

    final Tag created = Tag(
      id: IdUtils.newId(),
      name: cleaned,
      updatedAt: DateUtils.nowUtc(),
    );
    await _tags.put(created.id, created);
    return created.id;
  }

  @override
  Future<void> saveTag(Tag tag) async {
    await _tags.put(tag.id, tag.copyWith(updatedAt: DateUtils.nowUtc()));
  }

  @override
  Future<void> deleteTag(String id) async {
    final Tag? existing = _tags.get(id);
    if (existing == null) return;
    await _tags.put(
      id,
      existing.copyWith(isDeleted: true, updatedAt: DateUtils.nowUtc()),
    );
  }

  @override
  Future<void> refreshTagUsage() async {
    final Box<Sticker> stickersBox =
        _store.boxByName(HiveBoxes.stickers) as Box<Sticker>;
    final Box<Series> seriesBox =
        _store.boxByName(HiveBoxes.series) as Box<Series>;

    final Map<String, int> counts = <String, int>{};
    void tally(Iterable<String> ids) {
      for (final String id in ids) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    for (final Sticker s in stickersBox.values) {
      if (s.isDeleted) continue;
      tally(s.tagIds);
    }
    for (final Series s in seriesBox.values) {
      if (s.isDeleted) continue;
      tally(s.tagIds);
    }

    final Map<String, Tag> updates = <String, Tag>{};
    for (final Tag t in _tags.values) {
      final int count = counts[t.id] ?? 0;
      if (t.usageCount != count) {
        updates[t.id] = t.copyWith(usageCount: count);
      }
    }
    if (updates.isNotEmpty) {
      await _tags.putAll(updates);
    }
  }
}
