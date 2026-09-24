import 'package:hive/hive.dart';

import '../../core/constants/hive_type_ids.dart';
import '../../core/utils/date_utils.dart';

/// A single sticker (image) inside a series.
/// 系列中的单个表情包（图片）。
class Sticker {
  Sticker({
    required this.id,
    required this.seriesId,
    this.name = '',
    required this.relativePath,
    this.thumbPath,
    this.width = 0,
    this.height = 0,
    this.byteSize = 0,
    this.sha256 = '',
    List<String>? categoryIds,
    List<String>? tagIds,
    this.note = '',
    this.sortIndex = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  })  : categoryIds = categoryIds ?? <String>[],
        tagIds = tagIds ?? <String>[];

  final String id;

  /// Owning series. Every sticker belongs to exactly one series.
  /// 所属系列。每个表情包必须且只能归属一个系列。
  final String seriesId;

  /// Optional display name. When empty, the series name is shown instead
  /// (handled in `EffectiveMeta`, never written back to storage).
  /// 可选的显示名。为空时改显示系列名（由 `EffectiveMeta` 处理，不回写存储）。
  final String name;

  /// Stored *relative* path to the original image.
  /// 原图的**相对**存储路径。
  final String relativePath;

  /// Stored relative path to the generated thumbnail, if one exists.
  /// 已生成缩略图的相对路径（若存在）。
  final String? thumbPath;

  final int width;
  final int height;
  final int byteSize;

  /// Content hash, used for import de-duplication and sync integrity.
  /// 内容哈希，用于导入去重与同步校验。
  final String sha256;

  /// Sticker-level category ids. Non-empty means "override the series".
  /// 表情包级分类 id。非空表示「覆盖系列」。
  final List<String> categoryIds;

  /// Sticker-level tag ids, unioned with the series tags.
  /// 表情包级标签 id，与系列标签取并集。
  final List<String> tagIds;

  final String note;

  /// Ordering inside the series.
  /// 系列内的排序序号。
  final int sortIndex;

  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  factory Sticker.empty({
    required String id,
    required String seriesId,
    required String relativePath,
  }) {
    final DateTime now = DateUtils.nowUtc();
    return Sticker(
      id: id,
      seriesId: seriesId,
      relativePath: relativePath,
      createdAt: now,
      updatedAt: now,
    );
  }

  Sticker copyWith({
    String? seriesId,
    String? name,
    String? relativePath,
    Object? thumbPath = _unset,
    int? width,
    int? height,
    int? byteSize,
    String? sha256,
    List<String>? categoryIds,
    List<String>? tagIds,
    String? note,
    int? sortIndex,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Sticker(
      id: id,
      seriesId: seriesId ?? this.seriesId,
      name: name ?? this.name,
      relativePath: relativePath ?? this.relativePath,
      thumbPath:
          identical(thumbPath, _unset) ? this.thumbPath : thumbPath as String?,
      width: width ?? this.width,
      height: height ?? this.height,
      byteSize: byteSize ?? this.byteSize,
      sha256: sha256 ?? this.sha256,
      categoryIds: categoryIds ?? List<String>.from(this.categoryIds),
      tagIds: tagIds ?? List<String>.from(this.tagIds),
      note: note ?? this.note,
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'seriesId': seriesId,
        'name': name,
        'relativePath': relativePath,
        'thumbPath': thumbPath,
        'width': width,
        'height': height,
        'byteSize': byteSize,
        'sha256': sha256,
        'categoryIds': categoryIds,
        'tagIds': tagIds,
        'note': note,
        'sortIndex': sortIndex,
        'createdAt': DateUtils.toIso(createdAt),
        'updatedAt': DateUtils.toIso(updatedAt),
        'isDeleted': isDeleted,
      };

  static Sticker fromJson(Map<String, dynamic> json) {
    final DateTime fallback = DateUtils.nowUtc();
    return Sticker(
      id: (json['id'] as String?) ?? '',
      seriesId: (json['seriesId'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      relativePath: (json['relativePath'] as String?) ?? '',
      thumbPath: json['thumbPath'] as String?,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
      sha256: (json['sha256'] as String?) ?? '',
      categoryIds: _stringList(json['categoryIds']),
      tagIds: _stringList(json['tagIds']),
      note: (json['note'] as String?) ?? '',
      sortIndex: (json['sortIndex'] as num?)?.toInt() ?? 0,
      createdAt: DateUtils.parseOr(json['createdAt'], fallback),
      updatedAt: DateUtils.parseOr(json['updatedAt'], fallback),
      isDeleted: (json['isDeleted'] as bool?) ?? false,
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return <String>[];
    return raw.whereType<String>().toList();
  }

  @override
  String toString() => 'Sticker($id, series=$seriesId, "$name")';
}

/// Hand-written Hive adapter. Append fields only — never reorder.
/// 手写 Hive 适配器。只可追加字段，不可重排。
class StickerAdapter extends TypeAdapter<Sticker> {
  @override
  final int typeId = HiveTypeIds.sticker;

  @override
  Sticker read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    final DateTime fallback = DateUtils.nowUtc();
    return Sticker(
      id: (fields[0] as String?) ?? '',
      seriesId: (fields[1] as String?) ?? '',
      name: (fields[2] as String?) ?? '',
      relativePath: (fields[3] as String?) ?? '',
      thumbPath: fields[4] as String?,
      width: (fields[5] as int?) ?? 0,
      height: (fields[6] as int?) ?? 0,
      byteSize: (fields[7] as int?) ?? 0,
      sha256: (fields[8] as String?) ?? '',
      categoryIds: _readStringList(fields[9]),
      tagIds: _readStringList(fields[10]),
      note: (fields[11] as String?) ?? '',
      sortIndex: (fields[12] as int?) ?? 0,
      createdAt: _readDate(fields[13], fallback),
      updatedAt: _readDate(fields[14], fallback),
      isDeleted: (fields[15] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Sticker obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.seriesId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.relativePath)
      ..writeByte(4)
      ..write(obj.thumbPath)
      ..writeByte(5)
      ..write(obj.width)
      ..writeByte(6)
      ..write(obj.height)
      ..writeByte(7)
      ..write(obj.byteSize)
      ..writeByte(8)
      ..write(obj.sha256)
      ..writeByte(9)
      ..write(obj.categoryIds)
      ..writeByte(10)
      ..write(obj.tagIds)
      ..writeByte(11)
      ..write(obj.note)
      ..writeByte(12)
      ..write(obj.sortIndex)
      ..writeByte(13)
      ..write(DateUtils.toEpochMs(obj.createdAt))
      ..writeByte(14)
      ..write(DateUtils.toEpochMs(obj.updatedAt))
      ..writeByte(15)
      ..write(obj.isDeleted);
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
