import 'package:hive/hive.dart';

import '../../core/constants/hive_type_ids.dart';
import '../../core/utils/date_utils.dart';

/// A category — a low-cardinality grouping applied to a series or a sticker.
/// 分类——应用于系列或表情包的低基数组别。
///
/// Semantics note: categories use *override* inheritance (a sticker's own
/// categories replace the series'), because mutual-exclusion grouping should
/// not silently accumulate. Tags, by contrast, are unioned.
/// 语义说明：分类采用**覆盖式**继承（表情包自身的分类替换系列的），
/// 因为互斥归类不应静默叠加。标签则相反，采用并集。
class Category {
  Category({
    required this.id,
    required this.name,
    this.colorValue = 0xFF7E9CD8,
    this.sortIndex = 0,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String name;

  /// Display colour as 0xAARRGGBB.
  /// 展示色，格式 0xAARRGGBB。
  final int colorValue;

  final int sortIndex;
  final DateTime updatedAt;
  final bool isDeleted;

  factory Category.empty({required String id, required String name}) {
    return Category(id: id, name: name, updatedAt: DateUtils.nowUtc());
  }

  Category copyWith({
    String? name,
    int? colorValue,
    int? sortIndex,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      sortIndex: sortIndex ?? this.sortIndex,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'sortIndex': sortIndex,
        'updatedAt': DateUtils.toIso(updatedAt),
        'isDeleted': isDeleted,
      };

  static Category fromJson(Map<String, dynamic> json) {
    return Category(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF7E9CD8,
      sortIndex: (json['sortIndex'] as num?)?.toInt() ?? 0,
      updatedAt: DateUtils.parseOr(json['updatedAt'], DateUtils.nowUtc()),
      isDeleted: (json['isDeleted'] as bool?) ?? false,
    );
  }

  @override
  String toString() => 'Category($id, "$name")';
}

/// Hand-written Hive adapter.
/// 手写 Hive 适配器。
class CategoryAdapter extends TypeAdapter<Category> {
  @override
  final int typeId = HiveTypeIds.category;

  @override
  Category read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Category(
      id: (fields[0] as String?) ?? '',
      name: (fields[1] as String?) ?? '',
      colorValue: (fields[2] as int?) ?? 0xFF7E9CD8,
      sortIndex: (fields[3] as int?) ?? 0,
      updatedAt: fields[4] is int
          ? DateUtils.fromEpochMs(fields[4] as int)
          : DateUtils.nowUtc(),
      isDeleted: (fields[5] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Category obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.colorValue)
      ..writeByte(3)
      ..write(obj.sortIndex)
      ..writeByte(4)
      ..write(DateUtils.toEpochMs(obj.updatedAt))
      ..writeByte(5)
      ..write(obj.isDeleted);
  }
}
