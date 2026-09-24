import 'package:uuid/uuid.dart';

/// UUID v4 generator.
/// UUID v4 生成器。
///
/// All ids are lowercase so that they stay valid on case-insensitive file
/// systems (NTFS on Windows) and case-sensitive ones (ext4 on Android) alike.
/// 所有 id 均为小写，以便在大小写不敏感（Windows NTFS）与敏感（Android ext4）
/// 的文件系统上都保持一致。
class IdUtils {
  IdUtils._();

  static const Uuid _uuid = Uuid();

  /// Generate a new random id.
  /// 生成一个新的随机 id。
  static String newId() => _uuid.v4();

  /// Short id, useful for building readable conflict suffixes.
  /// 短 id，用于生成可读的冲突后缀。
  static String shortId(String id, {int length = 8}) =>
      id.length <= length ? id : id.substring(0, length);
}
