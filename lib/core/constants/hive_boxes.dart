/// Hive box names.
/// Hive box 名称。
///
/// Boxes are split by concern so that a "settings-only" backup can export just
/// [settings] + [background] without filtering full data.
/// box 按职责拆分，使「仅设置备份」能直接导出 settings + background，无需过滤全量数据。
class HiveBoxes {
  HiveBoxes._();

  static const String series = 'series_v1';
  static const String stickers = 'stickers_v1';
  static const String categories = 'categories_v1';
  static const String tags = 'tags_v1';
  static const String settings = 'settings_v1';
  static const String background = 'background_v1';
  static const String sync = 'sync_v1';

  /// Boxes holding user content (included in a full backup).
  /// 承载用户内容的 box（全量备份包含）。
  static const List<String> contentBoxes = <String>[
    series,
    stickers,
    categories,
    tags,
  ];

  /// Boxes holding preferences only (included in a settings-only backup).
  /// 仅承载偏好设置的 box（仅设置备份包含）。
  static const List<String> settingsBoxes = <String>[settings, background];

  static const List<String> all = <String>[
    series,
    stickers,
    categories,
    tags,
    settings,
    background,
    sync,
  ];
}
