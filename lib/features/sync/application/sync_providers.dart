import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/data_version.dart';
import '../../../core/storage/hive_store.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/utils/debouncer.dart';
import '../../../data/models/app_settings.dart';
import '../../settings/application/storage_providers.dart';
import 'webdav_sync_service.dart';

/// Current WebDAV credentials, loaded asynchronously from secure storage.
/// 当前 WebDAV 凭据，从安全存储异步读取。
///
/// A plain [FutureProvider] rather than a Notifier: the credentials are written
/// by the settings screen (which owns the form state) and only *read* here, so
/// there is no second copy of the truth to keep in step.
///
/// 使用普通 [FutureProvider] 而非 Notifier：凭据由设置页（持有表单状态）写入，
/// 此处只**读**，因此不存在需要保持同步的第二份真相。
final FutureProvider<WebDavCredentials> webDavCredentialsProvider =
    FutureProvider<WebDavCredentials>((Ref ref) async {
  return ref.watch(secureStoreProvider).read();
});

/// Current sync metadata.
/// 当前同步元数据。
class SyncMetaNotifier extends Notifier<SyncMeta> {
  @override
  SyncMeta build() => ref.watch(hiveStoreProvider).readSyncMeta();

  /// Reload from storage after the sync engine wrote to it behind our back.
  /// 同步引擎在背后写入后，从存储重新加载。
  void refresh() {
    state = ref.read(hiveStoreProvider).readSyncMeta();
  }

  Future<void> setAutoSync(bool enabled) async {
    final SyncMeta next = state.copyWith(autoSyncEnabled: enabled);
    state = next;
    await ref.read(hiveStoreProvider).writeSyncMeta(next);
  }
}

final NotifierProvider<SyncMetaNotifier, SyncMeta> syncMetaProvider =
    NotifierProvider<SyncMetaNotifier, SyncMeta>(SyncMetaNotifier.new);

/// Drives the sync engine and exposes its progress to the UI.
/// 驱动同步引擎并向界面暴露进度。
///
/// Auto-sync is wired to [dataVersionProvider] with a debounce: editing five
/// stickers in a row should produce one upload, not five. A periodic fallback
/// covers the case where the device was offline when the debounce fired.
///
/// 自动同步通过防抖挂在 [dataVersionProvider] 上：连续编辑五张表情包应只产生一次上传，
/// 而不是五次。定时兜底则覆盖防抖触发时设备恰好离线的情况。
class SyncController extends Notifier<SyncStatus> {
  Debouncer? _debounce;
  Timer? _fallbackTimer;
  int _watchingVersion = -1;
  bool _running = false;
  bool _disposed = false;

  @override
  SyncStatus build() {
    // React to data changes.
    // 响应数据变更。
    final int version = ref.watch(dataVersionProvider);
    final SyncMeta meta = ref.watch(syncMetaProvider);

    if (version != _watchingVersion) {
      _watchingVersion = version;
      if (meta.autoSyncEnabled) {
        _scheduleAutoSync();
      }
    }

    // Tear down timers when the provider is disposed. `ref.mounted` does not
    // exist on NotifierProviderRef in Riverpod 2.3, so a local flag is used
    // instead of querying the ref from inside the timer callback.
    // provider 被销毁时清理定时器。Riverpod 2.3 的 NotifierProviderRef 没有
    // `mounted`，因此用本地标志替代在定时器回调中查询 ref。
    ref.onDispose(() {
      _disposed = true;
      _debounce?.dispose();
      _fallbackTimer?.cancel();
    });

    return const SyncStatus.idle();
  }

  /// Run a sync now, regardless of the auto-sync setting.
  /// 立即执行一次同步，无论自动同步设置如何。
  Future<SyncReport> syncNow() async {
    if (_running) {
      return const SyncReport(
        outcome: SyncOutcome.skipped,
        message: '同步正在进行中',
      );
    }

    _running = true;
    state = const SyncStatus.running();

    try {
      final WebDavCredentials credentials =
          await ref.read(webDavCredentialsProvider.future);
      final HiveStore store = ref.read(hiveStoreProvider);
      final SyncReport report =
          await WebDavSyncService(store).sync(credentials);

      // The engine mutates sync metadata directly; re-read it so the UI shows
      // the new timestamp instead of the pre-sync value.
      // 引擎会直接修改同步元数据；重新读取，使界面显示新的时间戳而非同步前的值。
      ref.read(syncMetaProvider.notifier).refresh();

      state = SyncStatus.done(report);
      return report;
    } catch (e) {
      final SyncReport report = SyncReport(
        outcome: SyncOutcome.failed,
        message: '$e',
      );
      state = SyncStatus.done(report);
      return report;
    } finally {
      _running = false;
    }
  }

  /// Test the connection without touching data.
  /// 在不改动数据的前提下测试连接。
  Future<SyncReport> testConnection(WebDavCredentials credentials) {
    return WebDavSyncService(ref.read(hiveStoreProvider))
        .testConnection(credentials);
  }

  void _scheduleAutoSync() {
    _debounce ??= Debouncer(AppConstants.syncDebounce);
    _debounce!.run(() {
      if (_disposed) return;
      syncNow();
    });

    // Fallback: if the debounce fires while offline, the next data change would
    // normally be needed to retry. A periodic attempt removes that dependency.
    // 兜底：若防抖触发时恰好离线，通常需要下一次数据变更才能重试。
    // 定时尝试可解除这一依赖。
    _fallbackTimer ??= Timer.periodic(
      AppConstants.syncFallbackInterval,
      (_) {
        final SyncMeta meta = ref.read(syncMetaProvider);
        if (!meta.autoSyncEnabled || _disposed) return;
        syncNow();
      },
    );
  }
}

/// Sync progress, readable by the settings screen.
/// 可供设置页读取的同步进度。
class SyncStatus {
  const SyncStatus._({
    required this.isRunning,
    this.report,
  });

  const SyncStatus.idle() : this._(isRunning: false);

  const SyncStatus.running() : this._(isRunning: true);

  const SyncStatus.done(SyncReport report)
      : this._(isRunning: false, report: report);

  final bool isRunning;

  /// The most recent completed run, if any.
  /// 最近一次已完成的运行结果（若有）。
  final SyncReport? report;
}

final NotifierProvider<SyncController, SyncStatus> syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Convenience: whether a remote connection is configured at all.
/// 便捷方法：是否已配置远端连接。
final Provider<bool> isWebDavConfiguredProvider = Provider<bool>((Ref ref) {
  final AsyncValue<WebDavCredentials> credentials =
      ref.watch(webDavCredentialsProvider);
  return credentials.maybeWhen(
    data: (WebDavCredentials c) => c.isConfigured,
    orElse: () => false,
  );
});

/// True when secure storage had to fall back to plain preferences.
/// 安全存储被迫降级为普通偏好存储时为 true。
final Provider<bool> secureStoreDegradedProvider = Provider<bool>((Ref ref) {
  return ref.watch(secureStoreProvider).isDegraded;
});

/// Debug-only: surfaces the configured base URL without the password.
/// 仅调试用：展示已配置的服务器地址（不含密码）。
String describeCredentials(WebDavCredentials c) {
  if (!c.isConfigured) return '未配置';
  return '${c.baseUrl} · ${c.username}';
}

/// Keeps the linter honest about the debug flag import in release builds.
/// 使 linter 在 release 构建中也能正确看待 debug 标记。
bool get isDebugBuild => kDebugMode;
