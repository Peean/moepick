import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Increments whenever stored data changes.
/// 存储数据每次变化时自增。
///
/// Acts as the app's single invalidation signal. Providers that derive from
/// stored data watch this, and the sync engine debounces off it. One user action
/// that writes to several boxes therefore bumps it once, not once per box.
///
/// 作为应用统一的失效信号。所有派生自存储数据的 provider 监听它，
/// 同步引擎也基于它做防抖。一次操作即使写了多个 box，也只自增一次。
class DataVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Signal that stored data changed.
  /// 通知存储数据已变化。
  void bump() => state = state + 1;
}

/// The current data version.
/// 当前数据版本号。
final NotifierProvider<DataVersionNotifier, int> dataVersionProvider =
    NotifierProvider<DataVersionNotifier, int>(DataVersionNotifier.new);
