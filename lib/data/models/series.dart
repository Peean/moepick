import 'dart:convert';

import 'package:hive/hive.dart';

import '../../core/constants/hive_type_ids.dart';
import '../../core/utils/date_utils.dart';

/// A sticker series — the top-level grouping for stickers.
/// 表情包系列——表情包的最高层分组。
///
/// Series can carry its own category / tag / note, which stickers inherit
/// according to the rules in `EffectiveMeta`.
/// 系列可自带分类 / 标签 / 备注，表情包按 `EffectiveMeta` 的规则继承。
class Series {
  Series({
    required this.id,
    required this.name,
    this.description = '',
    this.author = '',
    this.source = '',
    this.coverImagePath,
    List<String>? categoryIds,
    List<String>? tagIds,
    this.note = '',
    this.stickerCount = 0,
    this.pinned = false,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  })  : categoryIds = categoryIds ?? <String>[],
        tagIds = tagIds ?? <String>[];

  /// Stable unique id (uuid v4, lowercase).
  /// 稳定的唯一 id（uuid v4，小写）。
  final String id;

  final String name;
  final String description;

  /// Creator / artist credit.
  /// 作者 / 画师署名。
  final String author;

  /// Origin of the artwork: free text or a URL.
  /// 作品来源：自由文本或 URL。
  final String source;

  /// Stored *relative* path to the cover image, or null for a generated cover.
  /// 封面图的**相对**路径；为 null 时使用生成的封面。
  final String? coverImagePath;

  /// Category ids assigned at series level.
  /// 系列级分类 id。
  final List<String> categoryIds;

  /// Tag ids assigned at series level.
  /// 系列级标签 id。
  final List<String> tagIds;

  /// Series-level note.
  /// 系列级备注。
  final String note;

  /// Denormalised count kept in sync by the repository, so the gallery grid can
  /// render without loading every sticker.
  /// 由仓储维护的冗余计数，使图库网格无需加载全部表情包即可渲染。
  final int stickerCount;

  /// Whether this series is pinned to the top of the gallery.
  /// 该系列是否置顶到图库最前。
  final bool pinned;

  /// Whether this series is marked as a favourite.
  /// 该系列是否被收藏。
  final bool favorite;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete tombstone. Deleted records are retained so that sync can
  /// propagate deletions instead of resurrecting them from another device.
  /// 软删除墓碑。保留已删除记录，使同步能传播删除操作，
  /// 而不是被其他设备重新恢复。
  final bool isDeleted;

  /// Empty series shell with generated id and timestamps.
  /// 空系列模板，自动生成 id 与时间戳。
  factory Series.empty({required String id, required String name}) {
    final DateTime now = DateUtils.nowUtc();
    return Series(id: id, name: name, createdAt: now, updatedAt: now);
  }

  Series copyWith({
    String? name,
    String? description,
    String? author,
    String? source,
    Object? coverImagePath = _unset,
    List<String>? categoryIds,
    List<String>? tagIds,
    String? note,
    int? stickerCount,
    bool? pinned,
    bool? favorite,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Series(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      source: source ?? this.source,
      coverImagePath: identical(coverImagePath, _unset)
          ? this.coverImagePath
          : coverImagePath as String?,
      categoryIds: categoryIds ?? List<String>.from(this.categoryIds),
      tagIds: tagIds ?? List<String>.from(this.tagIds),
      note: note ?? this.note,
      stickerCount: stickerCount ?? this.stickerCount,
      pinned: pinned ?? this.pinned,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  /// Sentinel letting `copyWith` distinguish "not provided" from "set to null".
  /// 哨兵值，使 `copyWith` 能区分「未传参」与「显式设为 null」。
  static const Object _unset = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'author': author,
        'source': source,
        'coverImagePath': coverImagePath,
        'categoryIds': categoryIds,
        'tagIds': tagIds,
        'note': note,
        'stickerCount': stickerCount,
        'pinned': pinned,
        'favorite': favorite,
        'createdAt': DateUtils.toIso(createdAt),
        'updatedAt': DateUtils.toIso(updatedAt),
        'isDeleted': isDeleted,
      };

  static Series fromJson(Map<String, dynamic> json) {
    final DateTime fallback = DateUtils.nowUtc();
    return Series(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      author: (json['author'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      coverImagePath: json['coverImagePath'] as String?,
      categoryIds: _stringList(json['categoryIds']),
      tagIds: _stringList(json['tagIds']),
      note: (json['note'] as String?) ?? '',
      stickerCount: (json['stickerCount'] as num?)?.toInt() ?? 0,
      pinned: (json['pinned'] as bool?) ?? false,
      favorite: (json['favorite'] as bool?) ?? false,
      createdAt: DateUtils.parseOr(json['createdAt'], fallback),
      updatedAt: DateUtils.parseOr(json['updatedAt'], fallback),
      isDeleted: (json['isDeleted'] as bool?) ?? false,
    );
  }

  /// Tolerant list decoding: a corrupt element never discards the whole record.
  /// 容错的列表解码：单个损坏元素不会导致整条记录丢失。
  static List<String> _stringList(Object? raw) {
    if (raw is! List) return <String>[];
    return raw.whereType<String>().toList();
  }

  @override
  String toString() => 'Series($id, "$name", stickers=$stickerCount)';
}

/// Hand-written Hive adapter (no `hive_generator`: it requires a newer Dart SDK
/// and would add codegen maintenance on a pinned toolchain).
/// 手写 Hive 适配器（不使用 `hive_generator`：它需要更新的 Dart SDK，
/// 并会在被锁定的工具链上增加代码生成的维护成本）。
///
/// Field order is part of the on-disk format — append only, never reorder.
/// 字段顺序属于磁盘格式的一部分——只可追加，不可重排。
class SeriesAdapter extends TypeAdapter<Series> {
  @override
  final int typeId = HiveTypeIds.series;

  @override
  Series read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    final DateTime fallback = DateUtils.nowUtc();
    return Series(
      id: (fields[0] as String?) ?? '',
      name: (fields[1] as String?) ?? '',
      description: (fields[2] as String?) ?? '',
      coverImagePath: fields[3] as String?,
      categoryIds: _readStringList(fields[4]),
      tagIds: _readStringList(fields[5]),
      note: (fields[6] as String?) ?? '',
      stickerCount: (fields[7] as int?) ?? 0,
      createdAt: _readDate(fields[8], fallback),
      updatedAt: _readDate(fields[9], fallback),
      // Field 10 arrived later; older records have no entry, so default false.
      // 字段 10 是后加的，旧记录没有该项，因此默认 false。
      isDeleted: (fields[10] as bool?) ?? false,
      // Fields 11 / 12 are the newest additions (author, source).
      // 字段 11 / 12 是最新追加的（作者、来源）。
      author: (fields[11] as String?) ?? '',
      source: (fields[12] as String?) ?? '',
      // Fields 13 / 14: pinning and favourite flags.
      // 字段 13 / 14：置顶与收藏标记。
      pinned: (fields[13] as bool?) ?? false,
      favorite: (fields[14] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Series obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.coverImagePath)
      ..writeByte(4)
      ..write(obj.categoryIds)
      ..writeByte(5)
      ..write(obj.tagIds)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.stickerCount)
      ..writeByte(8)
      ..write(DateUtils.toEpochMs(obj.createdAt))
      ..writeByte(9)
      ..write(DateUtils.toEpochMs(obj.updatedAt))
      ..writeByte(10)
      ..write(obj.isDeleted)
      ..writeByte(11)
      ..write(obj.author)
      ..writeByte(12)
      ..write(obj.source)
      ..writeByte(13)
      ..write(obj.pinned)
      ..writeByte(14)
      ..write(obj.favorite);
  }

  static List<String> _readStringList(Object? raw) {
    if (raw is! List) return <String>[];
    return raw.whereType<String>().toList();
  }

  static DateTime _readDate(Object? raw, DateTime fallback) {
    if (raw is int) return DateUtils.fromEpochMs(raw);
    return fallback;
  }
}

/// JSON helpers shared by every model, kept next to the adapter they serve.
/// 各模型共用的 JSON 辅助函数，与其服务的适配器放在一起。
String encodeJson(Object? value) => jsonEncode(value);

Map<String, dynamic> decodeJsonMap(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is Map<String, dynamic>) return decoded;
  return <String, dynamic>{};
}
