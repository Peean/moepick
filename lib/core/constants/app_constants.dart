/// Application-wide constants.
/// 应用级常量。
class AppConstants {
  AppConstants._();

  /// Display name shown in the UI.
  /// 界面显示名。
  static const String appName = '拾萌';

  /// Package / application id. Must NOT use pinyin.
  /// 包名 / 应用 ID。要求不使用拼音。
  static const String appId = 'moepick';

  /// Root folder name inside the documents directory.
  /// 文档目录下的根文件夹名。
  static const String dataRootDir = 'moepick';

  /// Version string shown on the about screen. Kept in sync with pubspec by
  /// hand: pulling it from the platform channel would be overkill for a label.
  /// 关于页展示的版本号。与 pubspec 手工同步：
  /// 为了一个标签去走平台通道得不偿失。
  static const String appVersion = '1.0.0';

  /// Backup schema version understood by this build.
  /// 本版本可识别的备份 schema 版本。
  static const int backupSchemaVersion = 1;

  /// Sentinel key used for single-record boxes (settings / background / sync).
  /// 单记录 box 使用的固定 key（设置 / 背景 / 同步）。
  static const String singletonKey = 'root';

  /// Thumbnail longest-edge size in pixels.
  /// 缩略图最长边像素。
  static const int thumbnailMaxSize = 300;

  /// Background pre-blur working size (longest edge).
  /// 背景预模糊的工作尺寸（最长边）。
  static const int backgroundBlurMaxSize = 720;

  /// Live-preview background size while dragging the blur slider.
  /// 拖动模糊滑杆时实时预览的尺寸。
  static const int backgroundPreviewMaxSize = 256;

  /// Debounce applied before auto-sync runs after a data change.
  /// 数据变更后触发自动同步的防抖时长。
  static const Duration syncDebounce = Duration(seconds: 20);

  /// Debounce applied while adjusting background sliders before persisting.
  /// 调整背景滑杆时落盘的防抖时长。
  static const Duration backgroundDebounce = Duration(milliseconds: 500);

  /// Fallback interval for the periodic sync safety net.
  /// 定时兜底同步间隔。
  static const Duration syncFallbackInterval = Duration(minutes: 15);

  /// How long soft-deleted items stay in trash before physical purge.
  /// 软删除条目在回收站保留多久后物理清除。
  static const Duration trashRetention = Duration(days: 7);
}
