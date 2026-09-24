import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/constants/hive_boxes.dart';
import '../../core/error/app_exception.dart';
import '../../core/utils/path_utils.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/category.dart';
import '../../data/models/series.dart';
import '../../data/models/sticker.dart';
import '../../data/models/tag.dart';
import 'hive_registrar.dart';

/// Opens and owns every Hive box used by the app.
/// 打开并持有应用使用的全部 Hive box。
///
/// Held by a Riverpod provider so the rest of the app never touches
/// `Hive.openBox` directly and tests can substitute an in-memory instance.
/// 由 Riverpod provider 持有，使应用其他部分不直接调用 `Hive.openBox`，
/// 且测试可替换为内存实例。
class HiveStore {
  HiveStore._({
    required this.series,
    required this.stickers,
    required this.categories,
    required this.tags,
    required this.settings,
    required this.background,
    required this.sync,
  });

  final Box<Series> series;
  final Box<Sticker> stickers;
  final Box<Category> categories;
  final Box<Tag> tags;
  final Box<AppSettings> settings;

  /// Typed as dynamic-free `Box<BackgroundConfig>`; declared below to keep the
  /// import list tidy is not worth it, so it is spelled out fully.
  /// 使用 `Box<BackgroundConfig>` 完整类型；为保持导入整洁而不写出类型并不划算。
  final Box<BackgroundConfig> background;

  final Box<SyncMeta> sync;

  /// Open every box, registering adapters first.
  /// 打开全部 box，并先注册适配器。
  static Future<HiveStore> open({String? overrideRootPath}) async {
    registerHiveAdapters();

    // Use Hive.init with an explicit directory from path_provider rather than
    // Hive.initFlutter(): the latter adds another path_provider layer and its
    // Windows behaviour has been ambiguous in older versions.
    // 用 path_provider 拿到目录后显式 Hive.init，而不用 Hive.initFlutter()：
    // 后者多套一层 path_provider，且在旧版本的 Windows 上行为有歧义。
    final String root = overrideRootPath ?? await PathUtils.rootPath();
    final String hiveDir = p.join(root, 'hive');
    await Directory(hiveDir).create(recursive: true);
    Hive.init(hiveDir);

    try {
      return HiveStore._(
        series: await Hive.openBox<Series>(HiveBoxes.series),
        stickers: await Hive.openBox<Sticker>(HiveBoxes.stickers),
        categories: await Hive.openBox<Category>(HiveBoxes.categories),
        tags: await Hive.openBox<Tag>(HiveBoxes.tags),
        settings: await Hive.openBox<AppSettings>(HiveBoxes.settings),
        background:
            await Hive.openBox<BackgroundConfig>(HiveBoxes.background),
        sync: await Hive.openBox<SyncMeta>(HiveBoxes.sync),
      );
    } on HiveError catch (e) {
      throw StorageException('打开本地数据库失败', cause: e);
    }
  }

  /// Read the singleton settings record, falling back to defaults on a fresh
  /// install or after a schema change.
  /// 读取单例设置记录；全新安装或结构变更后回退到默认值。
  AppSettings readSettings() =>
      settings.get(AppConstants.singletonKey) ?? AppSettings.defaults();

  Future<void> writeSettings(AppSettings value) =>
      settings.put(AppConstants.singletonKey, value);

  BackgroundConfig readBackground() =>
      background.get(AppConstants.singletonKey) ?? BackgroundConfig.defaults();

  Future<void> writeBackground(BackgroundConfig value) =>
      background.put(AppConstants.singletonKey, value);

  SyncMeta readSyncMeta() =>
      sync.get(AppConstants.singletonKey) ?? SyncMeta.defaults();

  Future<void> writeSyncMeta(SyncMeta value) =>
      sync.put(AppConstants.singletonKey, value);

  /// The box behind a given name, resolved to a common supertype so the backup
  /// service can iterate boxes generically.
  /// 按名称取 box，统一为公共父类型，使备份服务能泛化遍历。
  Box<dynamic> boxByName(String name) {
    switch (name) {
      case HiveBoxes.series:
        return series;
      case HiveBoxes.stickers:
        return stickers;
      case HiveBoxes.categories:
        return categories;
      case HiveBoxes.tags:
        return tags;
      case HiveBoxes.settings:
        return settings;
      case HiveBoxes.background:
        return background;
      case HiveBoxes.sync:
        return sync;
      default:
        throw StorageException('未知的 box: $name');
    }
  }

  /// Close every box. Called on app shutdown and by tests.
  /// 关闭全部 box。应用退出与测试中调用。
  Future<void> close() async {
    await Future.wait<void>(<Future<void>>[
      series.close(),
      stickers.close(),
      categories.close(),
      tags.close(),
      settings.close(),
      background.close(),
      sync.close(),
    ]);
  }
}
