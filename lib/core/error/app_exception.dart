/// Base class for all application errors.
/// 所有应用错误的基类。
class AppException implements Exception {
  AppException(this.message, {this.cause});

  /// Human-readable, already user-facing message.
  /// 可直接展示给用户的错误信息。
  final String message;

  /// Underlying error, kept for logging.
  /// 底层错误，用于日志记录。
  final Object? cause;

  @override
  String toString() =>
      cause == null ? '$runtimeType: $message' : '$runtimeType: $message ($cause)';
}

/// Local storage / Hive failures.
/// 本地存储 / Hive 失败。
class StorageException extends AppException {
  StorageException(String message, {Object? cause})
      : super(message, cause: cause);
}

/// Image decode / encode / file import failures.
/// 图片解码 / 编码 / 导入失败。
class ImageException extends AppException {
  ImageException(String message, {Object? cause})
      : super(message, cause: cause);
}

/// Backup export / import failures.
/// 备份导出 / 导入失败。
class BackupException extends AppException {
  BackupException(String message, {Object? cause})
      : super(message, cause: cause);
}

/// WebDAV configuration or transfer failures.
/// WebDAV 配置或传输失败。
class SyncException extends AppException {
  SyncException(String message, {Object? cause})
      : super(message, cause: cause);
}
