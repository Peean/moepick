import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Hashing helpers.
/// 哈希工具。
///
/// sha256 is used for two distinct purposes:
///   1. Content de-duplication when importing stickers.
///   2. Backup integrity + fast "did anything change?" comparison.
/// sha256 有两个用途：
///   1. 导入表情包时的内容去重。
///   2. 备份完整性校验 + 快速判断「是否有变更」。
class HashUtils {
  HashUtils._();

  /// Hash of a byte payload.
  /// 字节数据的哈希。
  static String ofBytes(List<int> bytes) => sha256.convert(bytes).toString();

  /// Hash of a file's contents, streamed to avoid loading huge files at once.
  /// 文件内容的哈希，采用流式读取以避免一次性载入大文件。
  static Future<String> ofFile(File file) async {
    if (!await file.exists()) {
      throw ArgumentError('File does not exist: ${file.path}');
    }
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Hash of a UTF-8 string.
  /// UTF-8 字符串的哈希。
  static String ofString(String input) => ofBytes(utf8.encode(input));

  /// Stable hash of a JSON-encodable object.
  /// 可 JSON 序列化对象的稳定哈希。
  ///
  /// Relies on [jsonEncode] preserving insertion order of map literals, so the
  /// caller must build the map in a deterministic order.
  /// 依赖 [jsonEncode] 保留 map 字面量的插入顺序，因此调用方必须按确定顺序构建 map。
  static String ofJson(Object? jsonable) => ofString(jsonEncode(jsonable));
}
