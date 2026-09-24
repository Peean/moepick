/// Registry of Hive type adapters.
/// Hive 类型适配器登记表。
///
/// Keeping every typeId in one place prevents accidental collisions, which Hive
/// does not detect at compile time and which would corrupt stored data.
/// 集中登记可避免 typeId 冲突——Hive 不会在编译期检测冲突，一旦重复会损坏已存数据。
///
/// NEVER renumber an existing entry: the number is written into every stored
/// record. Add new types at the end.
/// 绝不要修改已存在条目的编号：该编号会写入每条记录。新类型一律追加。
class HiveTypeIds {
  HiveTypeIds._();

  static const int series = 1;
  static const int sticker = 2;
  static const int category = 3;
  static const int tag = 4;
  static const int appSettings = 5;
  static const int backgroundConfig = 6;
  static const int syncMeta = 7;

  // 8..19 reserved for future models.
  // 8..19 预留给后续模型。

  /// Highest id currently in use, useful for sanity checks in tests.
  /// 当前使用的最大 id，便于测试做完整性校验。
  static const int maxUsed = syncMeta;
}
