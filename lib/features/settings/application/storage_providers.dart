import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/hive_store.dart';
import '../../../core/storage/secure_store.dart';
import '../../../data/repositories/hive_repositories.dart';
import '../../../data/repositories/repository_contracts.dart';
import '../../../data/repositories/search_repository.dart';

/// The open Hive store.
/// 已打开的 Hive 存储。
///
/// Overridden in `main.dart` once the boxes are open, and in tests with an
/// in-memory substitute. Declared with a throwing default so a missing override
/// fails loudly at the point of use rather than returning a half-built store.
///
/// 在 `main.dart` 中 box 打开后被覆盖，测试中替换为内存实现。
/// 默认实现直接抛异常，使缺失覆盖时能在使用点立即暴露，而不是返回半成品。
final Provider<HiveStore> hiveStoreProvider = Provider<HiveStore>((Ref ref) {
  throw StateError(
    'hiveStoreProvider 必须被覆盖：请在 main.dart 的 ProviderScope.overrides '
    '中传入已打开的 HiveStore。',
  );
});

/// Secure credential storage.
/// 凭据安全存储。
final Provider<SecureStore> secureStoreProvider =
    Provider<SecureStore>((Ref ref) => SecureStore());

/// Series repository.
/// 系列仓储。
final Provider<SeriesRepository> seriesRepositoryProvider =
    Provider<SeriesRepository>((Ref ref) {
  return HiveSeriesRepository(ref.watch(hiveStoreProvider));
});

/// Sticker repository.
/// 表情包仓储。
final Provider<StickerRepository> stickerRepositoryProvider =
    Provider<StickerRepository>((Ref ref) {
  return HiveStickerRepository(ref.watch(hiveStoreProvider));
});

/// Taxonomy (category + tag) repository.
/// 分类与标签仓储。
final Provider<TaxonomyRepository> taxonomyRepositoryProvider =
    Provider<TaxonomyRepository>((Ref ref) {
  return HiveTaxonomyRepository(ref.watch(hiveStoreProvider));
});

/// Search repository.
/// 搜索仓储。
final Provider<SearchRepository> searchRepositoryProvider =
    Provider<SearchRepository>((Ref ref) => SearchRepository());
