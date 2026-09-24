/// Route path constants.
/// 路由路径常量。
///
/// Centralised so a typo becomes a compile error at the call site instead of a
/// runtime navigation failure.
/// 集中定义，使拼写错误在调用处即为编译错误，而非运行时导航失败。
class RoutePaths {
  RoutePaths._();

  static const String library = '/';
  static const String seriesDetail = '/series';
  static const String seriesCreate = '/series/create';
  static const String seriesEdit = '/series/edit';
  static const String stickerDetail = '/sticker';
  static const String stickerEdit = '/sticker/edit';
  static const String import = '/import';
  static const String search = '/search';
  static const String settings = '/settings';
  static const String settingsTheme = '/settings/theme';
  static const String settingsBackground = '/settings/background';
  static const String settingsTaxonomy = '/settings/taxonomy';
  static const String settingsTrash = '/settings/trash';
  static const String settingsBackup = '/settings/backup';
  static const String settingsWebdav = '/settings/webdav';
  static const String settingsAbout = '/settings/about';

  /// Build a series detail location.
  /// 构建系列详情路径。
  static String seriesOf(String id) => '$seriesDetail/$id';

  /// Build a series edit location.
  /// 构建系列编辑路径。
  static String seriesEditOf(String id) => '$seriesDetail/$id/edit';

  /// Build a sticker detail location.
  /// 构建表情包详情路径。
  static String stickerOf(String id) => '$stickerDetail/$id';

  /// Build a sticker edit location.
  /// 构建表情包编辑路径。
  static String stickerEditOf(String id) => '$stickerDetail/$id/edit';

  /// Import into a specific series.
  /// 导入到指定系列。
  static String importInto(String seriesId) =>
      '$import?seriesId=$seriesId';
}
