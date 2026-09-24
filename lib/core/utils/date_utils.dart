/// ISO-8601 date helpers.
/// ISO-8601 日期工具。
///
/// All timestamps are persisted as ISO-8601 UTC strings rather than epoch
/// integers: they are human-readable in backup archives and unambiguous about
/// time zone, which matters when merging records across devices.
///
/// 所有时间戳以 ISO-8601 UTC 字符串持久化，而非 epoch 整数：在备份包中可读，
/// 且时区明确——这在跨设备合并记录时很重要。
class DateUtils {
  DateUtils._();

  /// Current time in UTC. Never call `DateTime.now()` directly in models —
  /// routing it through here keeps timestamps timezone-consistent.
  /// 当前 UTC 时间。模型里不要直接调用 `DateTime.now()`，
  /// 统一走这里可保证时间戳的时区一致性。
  static DateTime nowUtc() => DateTime.now().toUtc();

  /// Serialize to an ISO-8601 UTC string.
  /// 序列化为 ISO-8601 UTC 字符串。
  static String toIso(DateTime value) => value.toUtc().toIso8601String();

  /// Parse an ISO-8601 string, returning null when malformed.
  /// 解析 ISO-8601 字符串，格式非法时返回 null。
  static DateTime? tryParse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// Parse with a fallback, so a corrupt field never loses the whole record.
  /// 带兜底的解析，避免单个字段损坏导致整条记录丢失。
  static DateTime parseOr(Object? raw, DateTime fallback) =>
      tryParse(raw) ?? fallback;

  /// Epoch milliseconds since 1970, used by Hive adapters (compact + sortable).
  /// 1970 年以来的毫秒数，供 Hive 适配器使用（紧凑且可排序）。
  static int toEpochMs(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  /// Rebuild a UTC DateTime from epoch milliseconds.
  /// 从毫秒数还原 UTC DateTime。
  static DateTime fromEpochMs(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  /// Compact timestamp safe for filenames, e.g. `20260924-091530`.
  /// 可用于文件名的紧凑时间戳，例如 `20260924-091530`。
  static String fileStamp(DateTime value) {
    final DateTime u = value.toUtc();
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(u.year, 4)}${p(u.month)}${p(u.day)}'
        '-${p(u.hour)}${p(u.minute)}${p(u.second)}';
  }
}
