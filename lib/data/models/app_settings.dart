import 'package:hive/hive.dart';

import '../../core/constants/hive_type_ids.dart';
import '../../core/utils/date_utils.dart';

/// How the background image is applied across the UI.
/// 背景图在界面中的应用方式。
enum BackgroundMode {
  /// Background shows through the page shell and card backdrops; content areas
  /// stay opaque for readability. This is the default.
  /// 背景透出在页面外壳与卡片背板上；内容区保持不透明以确保可读性。默认值。
  card,

  /// Background fills the whole screen with content floating above it.
  /// 背景铺满整屏，内容浮于其上。
  fullscreen,
}

/// Background rendering configuration.
/// 背景渲染配置。
class BackgroundConfig {
  BackgroundConfig({
    this.imageRelativePath,
    this.opacity = 0.35,
    this.scrimColorValue = 0xFF000000,
    this.scrimOpacity = 0.18,
    this.blurSigma = 0.0,
    this.mode = BackgroundMode.card,
    this.useBlur = false,
    this.cachedBlurRelativePath,
    this.cachedBlurSourceHash,
  });

  /// Stored relative path to the background image, or null for a solid colour.
  /// 背景图的**相对**存储路径；为 null 时使用纯色。
  final String? imageRelativePath;

  /// Overall image opacity, 0..1.
  /// 图片整体不透明度，0..1。
  final double opacity;

  /// Scrim (overlay) colour as 0xAARRGGBB.
  /// 遮罩颜色，格式 0xAARRGGBB。
  final int scrimColorValue;

  /// Scrim opacity, 0..1.
  /// 遮罩不透明度，0..1。
  final double scrimOpacity;

  /// Blur radius requested by the user (0 = no blur).
  /// 用户设定的模糊半径（0 表示不模糊）。
  final double blurSigma;

  final BackgroundMode mode;

  /// Whether blur is enabled. Kept separate from [blurSigma] so toggling blur
  /// off and on again restores the previous radius.
  /// 是否启用模糊。与 [blurSigma] 分开保存，使关闭再开启时能恢复原半径。
  final bool useBlur;

  /// Relative path to the cached pre-blurred bitmap, if generated.
  /// 已生成的预模糊位图缓存的相对路径。
  final String? cachedBlurRelativePath;

  /// Hash of the source + parameters that produced [cachedBlurRelativePath],
  /// used to decide when the cache is stale.
  /// 生成 [cachedBlurRelativePath] 的源图与参数哈希，用于判断缓存是否失效。
  final String? cachedBlurSourceHash;

  /// Sensible defaults: no image, no blur, card mode.
  /// 合理默认值：无图片、无模糊、卡片模式。
  static BackgroundConfig defaults() => BackgroundConfig();

  /// True when there is an image to render.
  /// 是否存在可渲染的图片。
  bool get hasImage =>
      imageRelativePath != null && imageRelativePath!.isNotEmpty;

  /// Effective blur applied to the rendered bitmap. Pre-blurring means this is
  /// normally 0 at paint time (the blur is already baked into the cached file),
  /// so the live filter is only used for slider previews.
  /// 实际作用于绘制时的模糊。由于已预模糊，绘制时通常为 0
  /// （模糊已烘焙进缓存文件），实时滤镜仅用于滑杆预览。
  bool get needsLiveBlur => useBlur && blurSigma > 0 && cachedBlurRelativePath == null;

  BackgroundConfig copyWith({
    Object? imageRelativePath = _unset,
    double? opacity,
    int? scrimColorValue,
    double? scrimOpacity,
    double? blurSigma,
    BackgroundMode? mode,
    bool? useBlur,
    Object? cachedBlurRelativePath = _unset,
    Object? cachedBlurSourceHash = _unset,
  }) {
    return BackgroundConfig(
      imageRelativePath: identical(imageRelativePath, _unset)
          ? this.imageRelativePath
          : imageRelativePath as String?,
      opacity: opacity ?? this.opacity,
      scrimColorValue: scrimColorValue ?? this.scrimColorValue,
      scrimOpacity: scrimOpacity ?? this.scrimOpacity,
      blurSigma: blurSigma ?? this.blurSigma,
      mode: mode ?? this.mode,
      useBlur: useBlur ?? this.useBlur,
      cachedBlurRelativePath: identical(cachedBlurRelativePath, _unset)
          ? this.cachedBlurRelativePath
          : cachedBlurRelativePath as String?,
      cachedBlurSourceHash: identical(cachedBlurSourceHash, _unset)
          ? this.cachedBlurSourceHash
          : cachedBlurSourceHash as String?,
    );
  }

  /// Clear the image and every cache deriving from it.
  /// 清除图片及其派生的全部缓存。
  BackgroundConfig cleared() => BackgroundConfig(
        opacity: opacity,
        scrimColorValue: scrimColorValue,
        scrimOpacity: scrimOpacity,
        mode: mode,
        useBlur: useBlur,
      );

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'imageRelativePath': imageRelativePath,
        // Enums persist as names, never indices: reordering the enum would
        // otherwise silently remap stored values.
        // 枚举以名称持久化，绝不用序号：否则重排枚举会静默改变已存值的含义。
        'mode': mode.name,
        'opacity': opacity,
        'scrimColorValue': scrimColorValue,
        'scrimOpacity': scrimOpacity,
        'blurSigma': blurSigma,
        'useBlur': useBlur,
        'cachedBlurRelativePath': cachedBlurRelativePath,
        'cachedBlurSourceHash': cachedBlurSourceHash,
      };

  static BackgroundConfig fromJson(Map<String, dynamic> json) {
    return BackgroundConfig(
      imageRelativePath: json['imageRelativePath'] as String?,
      mode: _modeFromName(json['mode']),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.35,
      scrimColorValue: (json['scrimColorValue'] as num?)?.toInt() ?? 0xFF000000,
      scrimOpacity: (json['scrimOpacity'] as num?)?.toDouble() ?? 0.18,
      blurSigma: (json['blurSigma'] as num?)?.toDouble() ?? 0.0,
      useBlur: (json['useBlur'] as bool?) ?? false,
      cachedBlurRelativePath: json['cachedBlurRelativePath'] as String?,
      cachedBlurSourceHash: json['cachedBlurSourceHash'] as String?,
    );
  }

  /// Unknown names fall back to the default mode rather than throwing, so a
  /// future format never bricks an older build.
  /// 未知名称回退到默认模式而非抛异常，使未来格式不会导致旧版本不可用。
  static BackgroundMode _modeFromName(Object? raw) {
    for (final BackgroundMode m in BackgroundMode.values) {
      if (m.name == raw) return m;
    }
    return BackgroundMode.card;
  }
}

/// Hand-written Hive adapter.
/// 手写 Hive 适配器。
class BackgroundConfigAdapter extends TypeAdapter<BackgroundConfig> {
  @override
  final int typeId = HiveTypeIds.backgroundConfig;

  @override
  BackgroundConfig read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return BackgroundConfig(
      imageRelativePath: fields[0] as String?,
      opacity: (fields[1] as num?)?.toDouble() ?? 0.35,
      scrimColorValue: (fields[2] as int?) ?? 0xFF000000,
      scrimOpacity: (fields[3] as num?)?.toDouble() ?? 0.18,
      blurSigma: (fields[4] as num?)?.toDouble() ?? 0.0,
      mode: BackgroundConfig._modeFromName(fields[5]),
      useBlur: (fields[6] as bool?) ?? false,
      cachedBlurRelativePath: fields[7] as String?,
      cachedBlurSourceHash: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, BackgroundConfig obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.imageRelativePath)
      ..writeByte(1)
      ..write(obj.opacity)
      ..writeByte(2)
      ..write(obj.scrimColorValue)
      ..writeByte(3)
      ..write(obj.scrimOpacity)
      ..writeByte(4)
      ..write(obj.blurSigma)
      ..writeByte(5)
      ..write(obj.mode.name)
      ..writeByte(6)
      ..write(obj.useBlur)
      ..writeByte(7)
      ..write(obj.cachedBlurRelativePath)
      ..writeByte(8)
      ..write(obj.cachedBlurSourceHash);
  }
}

/// Application preferences (excluding background, which has its own box).
/// 应用偏好设置（不含背景，背景有独立 box）。
class AppSettings {
  AppSettings({
    this.seedColorValue = 0xFFE38FB1,
    this.useDarkMode = false,
    this.followSystemTheme = true,
    this.gridColumns = 3,
    this.compactCards = false,
  });

  /// Seed colour driving the generated `ColorScheme`, 0xAARRGGBB.
  /// 生成 `ColorScheme` 的种子色，格式 0xAARRGGBB。
  final int seedColorValue;

  final bool useDarkMode;

  /// When true, [useDarkMode] is ignored and the system setting wins.
  /// 为 true 时忽略 [useDarkMode]，以系统设置为准。
  final bool followSystemTheme;

  /// Number of columns in the sticker grid.
  /// 表情包网格的列数。
  final int gridColumns;

  /// Whether to use tighter card padding.
  /// 是否使用更紧凑的卡片内边距。
  final bool compactCards;

  static AppSettings defaults() => AppSettings();

  AppSettings copyWith({
    int? seedColorValue,
    bool? useDarkMode,
    bool? followSystemTheme,
    int? gridColumns,
    bool? compactCards,
  }) {
    return AppSettings(
      seedColorValue: seedColorValue ?? this.seedColorValue,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      followSystemTheme: followSystemTheme ?? this.followSystemTheme,
      gridColumns: gridColumns ?? this.gridColumns,
      compactCards: compactCards ?? this.compactCards,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seedColorValue': seedColorValue,
        'useDarkMode': useDarkMode,
        'followSystemTheme': followSystemTheme,
        'gridColumns': gridColumns,
        'compactCards': compactCards,
      };

  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      seedColorValue: (json['seedColorValue'] as num?)?.toInt() ?? 0xFFE38FB1,
      useDarkMode: (json['useDarkMode'] as bool?) ?? false,
      followSystemTheme: (json['followSystemTheme'] as bool?) ?? true,
      gridColumns: (json['gridColumns'] as num?)?.toInt() ?? 3,
      compactCards: (json['compactCards'] as bool?) ?? false,
    );
  }
}

/// Hand-written Hive adapter.
/// 手写 Hive 适配器。
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = HiveTypeIds.appSettings;

  @override
  AppSettings read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return AppSettings(
      seedColorValue: (fields[0] as int?) ?? 0xFFE38FB1,
      useDarkMode: (fields[1] as bool?) ?? false,
      followSystemTheme: (fields[2] as bool?) ?? true,
      gridColumns: (fields[3] as int?) ?? 3,
      compactCards: (fields[4] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.seedColorValue)
      ..writeByte(1)
      ..write(obj.useDarkMode)
      ..writeByte(2)
      ..write(obj.followSystemTheme)
      ..writeByte(3)
      ..write(obj.gridColumns)
      ..writeByte(4)
      ..write(obj.compactCards);
  }
}

/// A timestamp triple used by the sync engine to detect divergence.
/// 同步引擎用于检测分叉的时间戳三元组。
///
/// Plain class rather than a record, because Dart 2.17 has no records.
/// 使用普通类而非 record，因为 Dart 2.17 没有 records。
class SyncMeta {
  SyncMeta({
    this.deviceId = '',
    this.lastSyncAt,
    this.lastUploadedManifestHash = '',
    this.lastKnownRemoteHash = '',
    this.remoteEtag = '',
    this.autoSyncEnabled = false,
    this.conflictIds = const <String>[],
  });

  /// Stable identifier of this installation, used for idempotency so a device
  /// never downloads the snapshot it just uploaded.
  /// 本安装的稳定标识，用于幂等判断，避免设备下载自己刚上传的快照。
  final String deviceId;

  final DateTime? lastSyncAt;

  /// Manifest hash of the last snapshot this device uploaded.
  /// 本设备上次上传快照的 manifest 哈希。
  final String lastUploadedManifestHash;

  /// Manifest hash last seen on the remote.
  /// 最近一次在远端看到的 manifest 哈希。
  final String lastKnownRemoteHash;

  final String remoteEtag;

  final bool autoSyncEnabled;

  /// Ids of records that ended up in conflict, surfaced in the UI.
  /// 发生冲突的记录 id，在 UI 中展示。
  final List<String> conflictIds;

  static SyncMeta defaults() => SyncMeta();

  SyncMeta copyWith({
    String? deviceId,
    Object? lastSyncAt = _unset,
    String? lastUploadedManifestHash,
    String? lastKnownRemoteHash,
    String? remoteEtag,
    bool? autoSyncEnabled,
    List<String>? conflictIds,
  }) {
    return SyncMeta(
      deviceId: deviceId ?? this.deviceId,
      lastSyncAt: identical(lastSyncAt, _unset)
          ? this.lastSyncAt
          : lastSyncAt as DateTime?,
      lastUploadedManifestHash:
          lastUploadedManifestHash ?? this.lastUploadedManifestHash,
      lastKnownRemoteHash: lastKnownRemoteHash ?? this.lastKnownRemoteHash,
      remoteEtag: remoteEtag ?? this.remoteEtag,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      conflictIds: conflictIds ?? List<String>.from(this.conflictIds),
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'lastSyncAt': lastSyncAt == null ? null : DateUtils.toIso(lastSyncAt!),
        'lastUploadedManifestHash': lastUploadedManifestHash,
        'lastKnownRemoteHash': lastKnownRemoteHash,
        'remoteEtag': remoteEtag,
        'autoSyncEnabled': autoSyncEnabled,
        'conflictIds': conflictIds,
      };

  static SyncMeta fromJson(Map<String, dynamic> json) {
    return SyncMeta(
      deviceId: (json['deviceId'] as String?) ?? '',
      lastSyncAt: DateUtils.tryParse(json['lastSyncAt']),
      lastUploadedManifestHash:
          (json['lastUploadedManifestHash'] as String?) ?? '',
      lastKnownRemoteHash: (json['lastKnownRemoteHash'] as String?) ?? '',
      remoteEtag: (json['remoteEtag'] as String?) ?? '',
      autoSyncEnabled: (json['autoSyncEnabled'] as bool?) ?? false,
      conflictIds: () {
        final Object? raw = json['conflictIds'];
        if (raw is! List) return <String>[];
        return raw.whereType<String>().toList();
      }(),
    );
  }
}

/// Hand-written Hive adapter.
/// 手写 Hive 适配器。
class SyncMetaAdapter extends TypeAdapter<SyncMeta> {
  @override
  final int typeId = HiveTypeIds.syncMeta;

  @override
  SyncMeta read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return SyncMeta(
      deviceId: (fields[0] as String?) ?? '',
      lastSyncAt:
          fields[1] is int ? DateUtils.fromEpochMs(fields[1] as int) : null,
      lastUploadedManifestHash: (fields[2] as String?) ?? '',
      lastKnownRemoteHash: (fields[3] as String?) ?? '',
      remoteEtag: (fields[4] as String?) ?? '',
      autoSyncEnabled: (fields[5] as bool?) ?? false,
      conflictIds: () {
        final Object? raw = fields[6];
        if (raw is! List) return <String>[];
        return raw.whereType<String>().toList();
      }(),
    );
  }

  @override
  void write(BinaryWriter writer, SyncMeta obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.deviceId)
      ..writeByte(1)
      ..write(obj.lastSyncAt == null ? null : DateUtils.toEpochMs(obj.lastSyncAt!))
      ..writeByte(2)
      ..write(obj.lastUploadedManifestHash)
      ..writeByte(3)
      ..write(obj.lastKnownRemoteHash)
      ..writeByte(4)
      ..write(obj.remoteEtag)
      ..writeByte(5)
      ..write(obj.autoSyncEnabled)
      ..writeByte(6)
      ..write(obj.conflictIds);
  }
}
