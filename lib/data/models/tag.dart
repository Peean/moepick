import 'package:hive/hive.dart';

import '../../core/constants/hive_type_ids.dart';
import '../../core/utils/date_utils.dart';

/// A tag — a free-form descriptor, unioned across series and sticker levels.
/// 标签——自由形式的描述维度，在系列级与表情包级之间取并集。
class Tag {
  Tag({
    required this.id,
    required this.name,
    this.usageCount = 0,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String name;

  /// Cached usage count so the UI can sort by popularity without a full scan.
  /// 冗余的使用计数，使 UI 无需全量扫描即可按热度排序。
  final int usageCount;

  final DateTime updatedAt;
  final bool isDeleted;

  factory Tag.empty({required String id, required String name}) {
    return Tag(id: id, name: name, updatedAt: DateUtils.nowUtc());
  }

  Tag copyWith({
    String? name,
    int? usageCount,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Tag(
      id: id,
      name: name ?? this.name,
      usageCount: usageCount ?? this.usageCount,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'usageCount': usageCount,
        'updatedAt': DateUtils.toIso(updatedAt),
        'isDeleted': isDeleted,
      };

  static Tag fromJson(Map<String, dynamic> json) {
    return Tag(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateUtils.parseOr(json['updatedAt'], DateUtils.nowUtc()),
      isDeleted: (json['isDeleted'] as bool?) ?? false,
    );
  }

  @override
  String toString() => 'Tag($id, "$name", used=$usageCount)';
}

/// Hand-written Hive adapter.
/// 手写 Hive 适配器。
class TagAdapter extends TypeAdapter<Tag> {
  @override
  final int typeId = HiveTypeIds.tag;

  @override
  Tag read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{};
    for (int i = 0; i < fieldCount; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Tag(
      id: (fields[0] as String?) ?? '',
      name: (fields[1] as String?) ?? '',
      usageCount: (fields[2] as int?) ?? 0,
      updatedAt: fields[3] is int
          ? DateUtils.fromEpochMs(fields[3] as int)
          : DateUtils.nowUtc(),
      isDeleted: (fields[4] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, Tag obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.usageCount)
      ..writeByte(3)
      ..write(DateUtils.toEpochMs(obj.updatedAt))
      ..writeByte(4)
      ..write(obj.isDeleted);
  }
}
