import '../models/series.dart';
import '../models/sticker.dart';

/// Effective (resolved) metadata for a sticker after combining its own values
/// with those inherited from its series.
/// 表情包在结合自身值与系列继承值后得到的有效（解析后）元数据。
///
/// This is the heart of the app's search semantics, so the rules are stated
/// explicitly rather than being implicit:
///
/// 这是全应用搜索语义的核心，因此规则明确写出而非隐含：
///
/// | field       | rule                          | why                                               |
/// |-------------|-------------------------------|---------------------------------------------------|
/// | categoryIds | sticker overrides series      | categories are a mutual-exclusion grouping        |
/// | tagIds      | series ∪ sticker (deduplicated) | tags are independent descriptive dimensions     |
/// | note        | concatenated with a separator | both notes should be searchable                   |
/// | displayName | falls back to series name      | keeps unnamed stickers identifiable              |
///
/// | 字段        | 规则                          | 原因                                              |
/// |-------------|-------------------------------|---------------------------------------------------|
/// | categoryIds | 表情包覆盖系列                | 分类是互斥归类，不应叠加                          |
/// | tagIds      | 系列 ∪ 表情包（去重）         | 标签是互相独立的描述维度                          |
/// | note        | 以分隔符拼接                  | 两处备注都应可被搜索                              |
/// | displayName | 回退到系列名                  | 使未命名的表情包仍可辨识                          |
///
/// Deliberately NOT denormalised into storage: a series tag edit would then
/// require rewriting every child sticker (write amplification plus a real risk
/// of inconsistent state). Computing on read is cheap at this data scale.
///
/// 有意**不**冗余写入存储：否则修改系列标签就要重写其下每个表情包
/// （写放大，且存在真实的一致性风险）。在当前数据规模下，读取时计算成本很低。
class EffectiveMeta {
  const EffectiveMeta({
    required this.categoryIds,
    required this.tagIds,
    required this.note,
    required this.displayName,
    required this.seriesName,
  });

  /// Resolved category ids (already applying override semantics).
  /// 解析后的分类 id（已应用覆盖语义）。
  final List<String> categoryIds;

  /// Resolved tag ids (already applying union semantics, deduplicated).
  /// 解析后的标签 id（已应用并集语义并去重）。
  final List<String> tagIds;

  /// Combined note text.
  /// 合并后的备注文本。
  final String note;

  /// Name to show in the UI.
  /// UI 中展示的名称。
  final String displayName;

  /// Name of the owning series, kept for search weighting.
  /// 所属系列名，用于搜索加权。
  final String seriesName;

  /// Separator used when joining the two notes.
  /// 拼接两处备注时使用的分隔符。
  static const String noteSeparator = ' · ';

  /// Resolve a sticker against its series.
  /// 将表情包与其系列进行解析。
  ///
  /// [series] may be null when the parent is missing (for example a record
  /// restored from a partially corrupt backup); the sticker's own values are
  /// then used unchanged so no metadata is silently dropped.
  ///
  /// 当父级缺失时 [series] 可为 null（例如从部分损坏的备份恢复），
  /// 此时原样使用表情包自身的值，避免元数据被静默丢弃。
  static EffectiveMeta of(Sticker sticker, Series? series) {
    if (series == null) {
      return EffectiveMeta(
        categoryIds: List<String>.unmodifiable(sticker.categoryIds),
        tagIds: List<String>.unmodifiable(sticker.tagIds),
        note: sticker.note,
        displayName: sticker.name.isNotEmpty ? sticker.name : '',
        seriesName: '',
      );
    }

    // Override: the sticker's own categories win when it has any.
    // 覆盖：表情包自身有分类时以其为准。
    final List<String> categories = sticker.categoryIds.isNotEmpty
        ? List<String>.from(sticker.categoryIds)
        : List<String>.from(series.categoryIds);

    // Union: both sides contribute tags, order-stable and deduplicated.
    // 并集：两侧标签都参与，保持顺序且去重。
    final List<String> tags = _union(series.tagIds, sticker.tagIds);

    return EffectiveMeta(
      categoryIds: List<String>.unmodifiable(categories),
      tagIds: List<String>.unmodifiable(tags),
      note: _joinNotes(series.note, sticker.note),
      displayName: sticker.name.isNotEmpty
          ? sticker.name
          : (series.name.isNotEmpty ? series.name : ''),
      seriesName: series.name,
    );
  }

  /// Order-stable union of two id lists.
  /// 两个 id 列表的顺序稳定并集。
  ///
  /// Hand-rolled rather than `{...a, ...b}` so the resulting order is
  /// predictable: series tags first, then sticker-only tags. Predictable order
  /// keeps tag chips from jumping around between rebuilds.
  ///
  /// 手写而非用 `{...a, ...b}`，使结果顺序可预测：先系列标签，再表情包独有标签。
  /// 顺序可预测能避免重建时标签芯片位置跳动。
  static List<String> _union(List<String> first, List<String> second) {
    final List<String> result = <String>[];
    final Set<String> seen = <String>{};
    for (final String id in first) {
      if (id.isEmpty) continue;
      if (seen.add(id)) result.add(id);
    }
    for (final String id in second) {
      if (id.isEmpty) continue;
      if (seen.add(id)) result.add(id);
    }
    return result;
  }

  /// Join the two notes, tolerating either side being empty.
  /// 拼接两处备注，容忍任意一侧为空。
  static String _joinNotes(String seriesNote, String stickerNote) {
    final String a = seriesNote.trim();
    final String b = stickerNote.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    if (a == b) return a;
    return '$a$noteSeparator$b';
  }

  @override
  String toString() =>
      'EffectiveMeta("$displayName", cats=${categoryIds.length}, '
      'tags=${tagIds.length})';
}
