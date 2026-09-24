import '../models/category.dart';
import '../models/series.dart';
import '../models/sticker.dart';
import '../models/tag.dart';

/// Read/write contract for series.
/// 系列读写的抽象契约。
///
/// Declared as an interface so tests can supply an in-memory implementation
/// instead of booting Hive. This is more reliable on Dart 2.17 than code
/// generation based mocking.
///
/// 以接口形式声明，使测试可注入内存实现而不必启动 Hive。
/// 在 Dart 2.17 上这比基于代码生成的 mock 更可靠。
abstract class SeriesRepository {
  /// All non-deleted series, newest first.
  /// 全部未删除的系列，按创建时间倒序。
  List<Series> getAll();

  /// Single series by id, or null when absent/deleted.
  /// 按 id 取单个系列，不存在或已删除时返回 null。
  Series? getById(String id);

  /// Insert or replace.
  /// 插入或替换。
  Future<void> save(Series series);

  /// Soft-delete a series and its stickers.
  /// 软删除系列及其下的表情包。
  Future<void> softDelete(String id);

  /// Undo a soft-delete (回收站还原).
  /// 撤销软删除（回收站还原）。
  Future<void> restore(String id);

  /// Physically remove the record (回收站彻底删除).
  /// 物理移除记录（回收站彻底删除）。
  Future<void> purge(String id);

  /// Direct access to raw records including deleted ones (used by backup/sync).
  /// 直接访问含已删除记录的原始数据（备份与同步使用）。
  List<Series> getAllIncludingDeleted();
}

/// Read/write contract for stickers.
/// 表情包读写的抽象契约。
abstract class StickerRepository {
  List<Sticker> getAll();
  Sticker? getById(String id);

  /// Stickers belonging to a series, ordered by [Sticker.sortIndex].
  /// 某系列下的表情包，按 [Sticker.sortIndex] 排序。
  List<Sticker> getBySeries(String seriesId);

  /// Count of live stickers in a series.
  /// 某系列下存活表情包的数量。
  int countBySeries(String seriesId);

  /// Map of sha256 -> stickerId, for import de-duplication.
  /// sha256 -> stickerId 的映射，用于导入去重。
  Map<String, String> hashIndex();

  Future<void> save(Sticker sticker);

  /// Bulk insert, used by restore.
  /// 批量插入，供恢复使用。
  Future<void> saveAll(List<Sticker> stickers);

  Future<void> softDelete(String id);

  /// Undo a soft-delete for the given ids (回收站批量还原).
  /// 对给定 id 批量撤销软删除（回收站批量还原）。
  Future<void> restoreAll(List<String> ids);

  /// Physically remove the given records (回收站彻底删除).
  /// 物理移除给定记录（回收站彻底删除）。
  Future<void> purgeAll(List<String> ids);

  /// Physically remove every sticker in a series (used with series deletion).
  /// 物理移除某系列下的全部表情包（配合系列删除使用）。
  Future<void> deleteBySeries(String seriesId);

  List<Sticker> getAllIncludingDeleted();
}

/// Read/write contract for categories and tags.
/// 分类与标签的读写抽象契约。
abstract class TaxonomyRepository {
  List<Category> getCategories();
  Category? getCategoryById(String id);
  Future<void> saveCategory(Category category);
  Future<void> deleteCategory(String id);

  List<Tag> getTags();
  Tag? getTagById(String id);

  /// Create a tag if a same-named one does not already exist, returning its id.
  /// 若同名标签不存在则创建，并返回其 id。
  ///
  /// Prevents the tag list from filling with near-duplicates as users type.
  /// 避免用户反复输入导致标签列表充斥近似重复项。
  Future<String> ensureTag(String name);

  Future<void> saveTag(Tag tag);
  Future<void> deleteTag(String id);

  /// Create a category with a default colour and return its id.
  /// 以默认颜色创建分类并返回其 id。
  ///
  /// Convenience for the inline "new category" affordance, which only ever
  /// asks for a name. Colour and ordering are adjusted later on the taxonomy
  /// screen.
  /// 供内联「新建分类」入口使用的便捷方法，该入口只询问名称。
  /// 颜色与排序可在分类体系页稍后调整。
  Future<String> saveCategoryWithName(String name);

  List<Category> getCategoriesIncludingDeleted();
  List<Tag> getAllTagsIncludingDeleted();

  /// Recompute [Tag.usageCount] from the current sticker/series data.
  /// 根据当前表情包/系列数据重算 [Tag.usageCount]。
  Future<void> refreshTagUsage();
}
