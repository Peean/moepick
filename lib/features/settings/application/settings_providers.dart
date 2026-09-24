import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/state/data_version.dart';
import '../../../core/storage/file_store.dart';
import '../../../core/storage/hive_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/hash_utils.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../settings/application/background_service.dart';
import 'storage_providers.dart';

/// Current application settings, backed by the `settings_v1` box.
/// 当前应用设置，由 `settings_v1` box 支撑。
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final HiveStore store = ref.watch(hiveStoreProvider);
    return store.readSettings();
  }

  Future<void> setSeedColor(int colorValue) =>
      _update(state.copyWith(seedColorValue: colorValue));

  Future<void> setFollowSystemTheme(bool value) =>
      _update(state.copyWith(followSystemTheme: value));

  Future<void> setDarkMode(bool value) =>
      _update(state.copyWith(useDarkMode: value, followSystemTheme: false));

  Future<void> setGridColumns(int columns) =>
      _update(state.copyWith(gridColumns: columns.clamp(2, 6)));

  Future<void> setCompactCards(bool value) =>
      _update(state.copyWith(compactCards: value));

  Future<void> _update(AppSettings next) async {
    state = next;
    await ref.read(hiveStoreProvider).writeSettings(next);
    // Settings are part of the synced payload, so a change is a data change.
    // 设置属于同步内容的一部分，因此设置变更也是数据变更。
    ref.read(dataVersionProvider.notifier).bump();
  }
}

final NotifierProvider<AppSettingsNotifier, AppSettings> appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);

/// Current background configuration.
/// 当前背景配置。
class BackgroundConfigNotifier extends Notifier<BackgroundConfig> {
  @override
  BackgroundConfig build() {
    final HiveStore store = ref.watch(hiveStoreProvider);
    return store.readBackground();
  }

  /// Update and persist, reusing any blur cache that is still valid.
  /// 更新并持久化，复用在仍然有效的模糊缓存。
  Future<void> _update(BackgroundConfig next) async {
    final BackgroundConfig reconciled = await _reconcileCache(next);
    state = reconciled;
    await ref.read(hiveStoreProvider).writeBackground(reconciled);
    ref.read(dataVersionProvider.notifier).bump();
  }

  /// Invalidate the blur cache when its inputs changed, and generate it when
  /// the new configuration needs one.
  /// 输入变化时使模糊缓存失效，并在新配置需要时生成缓存。
  ///
  /// Doing this on write (not on paint) keeps the frame loop free of file I/O.
  /// 在写入时（而非绘制时）完成，使帧循环不含文件 I/O。
  Future<BackgroundConfig> _reconcileCache(BackgroundConfig next) async {
    final String? source = next.imageRelativePath;
    if (source == null || source.isEmpty) {
      return next.copyWith(
        cachedBlurRelativePath: null,
        cachedBlurSourceHash: null,
      );
    }

    final String wantedKey = ref.read(backgroundImageServiceProvider).cacheKey(
          sourceRelativePath: source,
          blurSigma: next.blurSigma,
          useBlur: next.useBlur,
          maxSize: AppConstants.backgroundBlurMaxSize,
        );

    // Cache still describes the current inputs: keep it.
    // 缓存仍对应当前输入：保留。
    if (next.cachedBlurSourceHash == wantedKey &&
        next.cachedBlurRelativePath != null) {
      return next;
    }

    if (!next.useBlur || next.blurSigma <= 0) {
      return next.copyWith(
        cachedBlurRelativePath: null,
        cachedBlurSourceHash: wantedKey,
      );
    }

    final String? cached =
        await ref.read(backgroundImageServiceProvider).ensureBlurred(
              sourceRelativePath: source,
              blurSigma: next.blurSigma,
              useBlur: next.useBlur,
            );

    if (cached == null) {
      // Generation failed; clear the pointer so the renderer falls back to the
      // unblurred source instead of referencing a missing file.
      // 生成失败；清空指针，使渲染层退化为未模糊原图，而非引用不存在的文件。
      return next.copyWith(
        cachedBlurRelativePath: null,
        cachedBlurSourceHash: wantedKey,
      );
    }

    return next.copyWith(
      cachedBlurRelativePath: cached,
      cachedBlurSourceHash: wantedKey,
    );
  }

  Future<void> setMode(BackgroundMode mode) =>
      _update(state.copyWith(mode: mode));

  Future<void> setOpacity(double value) =>
      _update(state.copyWith(opacity: value.clamp(0.0, 1.0)));

  Future<void> setScrimColor(int colorValue) =>
      _update(state.copyWith(scrimColorValue: colorValue));

  Future<void> setScrimOpacity(double value) =>
      _update(state.copyWith(scrimOpacity: value.clamp(0.0, 1.0)));

  Future<void> setBlurEnabled(bool enabled) =>
      _update(state.copyWith(useBlur: enabled));

  Future<void> setBlurSigma(double value) =>
      _update(state.copyWith(blurSigma: value.clamp(0.0, 40.0)));

  /// Replace the background image: store the source, then rebuild the cache.
  /// 替换背景图：先存原图，再重建缓存。
  Future<void> setImageFromPath(String absoluteSourcePath) async {
    final FileStore files = ref.read(fileStoreProvider);
    final Uint8List bytes = await File(absoluteSourcePath).readAsBytes();

    // Downscale the stored source too: background art rarely benefits from
    // full resolution, and this keeps the backup small.
    // 存储的源图也一并降采样：背景图极少受益于原分辨率，且能使备份更小。
    final Uint8List stored = ImageUtils.downscaleSync(
      bytes,
      1920,
    );
    final String hash = HashUtils.ofBytes(stored);
    final String relative = PathUtils.backgroundSourceRelativePath(
      hash,
      PathUtils.extensionOf(absoluteSourcePath),
    );

    await files.writeRelative(relative, stored);

    // Remove the previous source image so repeated changes do not accumulate.
    // 删除上一张源图，避免反复更换导致文件堆积。
    final String? previous = state.imageRelativePath;
    if (previous != null && previous.isNotEmpty && previous != relative) {
      await files.delete(previous);
    }

    await _update(
      state.copyWith(
        imageRelativePath: relative,
        cachedBlurRelativePath: null,
        cachedBlurSourceHash: null,
      ),
    );
  }

  /// Remove the background image and its caches.
  /// 移除背景图及其缓存。
  Future<void> clearImage() async {
    final String? source = state.imageRelativePath;
    if (source != null && source.isNotEmpty) {
      await ref.read(fileStoreProvider).delete(source);
    }
    await _update(state.cleared());
  }
}

final NotifierProvider<BackgroundConfigNotifier, BackgroundConfig>
    backgroundConfigProvider =
    NotifierProvider<BackgroundConfigNotifier, BackgroundConfig>(
        BackgroundConfigNotifier.new);

/// Whether the UI should use dark mode right now.
/// 当前 UI 是否应使用深色模式。
final Provider<bool> isDarkModeProvider = Provider<bool>((Ref ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  if (settings.followSystemTheme) {
    final Brightness platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return platform == Brightness.dark;
  }
  return settings.useDarkMode;
});

/// Resolved light theme.
/// 解析后的浅色主题。
final Provider<ThemeData> lightThemeProvider = Provider<ThemeData>((Ref ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  return AppTheme.build(
    seedColor: Color(settings.seedColorValue),
    brightness: Brightness.light,
  );
});

/// Resolved dark theme.
/// 解析后的深色主题。
final Provider<ThemeData> darkThemeProvider = Provider<ThemeData>((Ref ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  return AppTheme.build(
    seedColor: Color(settings.seedColorValue),
    brightness: Brightness.dark,
  );
});

/// Result of a cheap CSV-style data export, used by the settings screen.
/// 供设置页使用的轻量数据统计结果。
class LibraryStats {
  const LibraryStats({
    required this.seriesCount,
    required this.stickerCount,
    required this.categoryCount,
    required this.tagCount,
  });

  final int seriesCount;
  final int stickerCount;
  final int categoryCount;
  final int tagCount;
}
