import 'package:hive/hive.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/category.dart';
import '../../data/models/series.dart';
import '../../data/models/sticker.dart';
import '../../data/models/tag.dart';
import '../constants/hive_type_ids.dart';

/// Registers every Hive type adapter exactly once.
/// 一次性注册全部 Hive 类型适配器。
///
/// `Hive.registerAdapter` throws when a typeId is registered twice, and hot
/// restart re-runs `main`, so each registration is guarded by
/// [Hive.isAdapterRegistered].
///
/// `Hive.registerAdapter` 对同一个 typeId 重复注册会抛异常，而热重启会重跑
/// `main`，因此每次注册都用 [Hive.isAdapterRegistered] 做守卫。
void registerHiveAdapters() {
  _register(HiveTypeIds.series, () => Hive.registerAdapter(SeriesAdapter()));
  _register(HiveTypeIds.sticker, () => Hive.registerAdapter(StickerAdapter()));
  _register(HiveTypeIds.category, () => Hive.registerAdapter(CategoryAdapter()));
  _register(HiveTypeIds.tag, () => Hive.registerAdapter(TagAdapter()));
  _register(
      HiveTypeIds.appSettings, () => Hive.registerAdapter(AppSettingsAdapter()));
  _register(HiveTypeIds.backgroundConfig,
      () => Hive.registerAdapter(BackgroundConfigAdapter()));
  _register(HiveTypeIds.syncMeta, () => Hive.registerAdapter(SyncMetaAdapter()));
}

void _register(int typeId, void Function() register) {
  if (!Hive.isAdapterRegistered(typeId)) {
    register();
  }
}
