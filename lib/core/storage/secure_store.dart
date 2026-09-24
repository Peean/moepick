import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure credential storage for the WebDAV connection.
/// WebDAV 连接的凭据安全存储。
///
/// On Android, [FlutterSecureStorage] is backed by the Android Keystore. On
/// Windows it uses DPAPI via `flutter_secure_storage_windows`, which has a
/// history of read/write failures on some setups. Rather than letting a
/// credential failure break sync entirely, a read or write error falls back to
/// `SharedPreferences` and sets [isDegraded] so the UI can warn the user that
/// the password is stored unencrypted.
///
/// Android 上 [FlutterSecureStorage] 由 Android Keystore 支撑。Windows 上经由
/// `flutter_secure_storage_windows` 使用 DPAPI，但该实现历史上在某些环境存在
/// 读写失败。为避免凭据故障导致同步完全不可用，读写异常时降级到
/// `SharedPreferences` 并置 [isDegraded]，使 UI 能提示用户密码以非加密方式存储。
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const String _kBaseUrl = 'webdav_base_url';
  static const String _kUsername = 'webdav_username';
  static const String _kPassword = 'webdav_password';
  static const String _kRemoteRoot = 'webdav_remote_root';
  static const String _degradedFlag = 'moepick_secure_degraded';

  bool _degraded = false;

  /// True when secure storage failed and values live in SharedPreferences.
  /// 安全存储失败、值存放于 SharedPreferences 时为 true。
  bool get isDegraded => _degraded;

  /// Load the stored WebDAV credentials.
  /// 读取已存储的 WebDAV 凭据。
  Future<WebDavCredentials> read() async {
    final String baseUrl =
        await _read(_kBaseUrl) ?? '';
    final String username = await _read(_kUsername) ?? '';
    final String password = await _read(_kPassword) ?? '';
    final String remoteRoot = await _read(_kRemoteRoot) ?? 'moepick';
    return WebDavCredentials(
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot.isEmpty ? 'moepick' : remoteRoot,
    );
  }

  /// Persist the WebDAV credentials.
  /// 持久化 WebDAV 凭据。
  Future<void> write(WebDavCredentials credentials) async {
    await _write(_kBaseUrl, credentials.baseUrl.trim());
    await _write(_kUsername, credentials.username.trim());
    await _write(_kPassword, credentials.password);
    await _write(
      _kRemoteRoot,
      credentials.remoteRoot.trim().isEmpty
          ? 'moepick'
          : credentials.remoteRoot.trim(),
    );
  }

  /// Remove every stored credential.
  /// 清除全部已存凭据。
  Future<void> clear() async {
    for (final String key in <String>[
      _kBaseUrl,
      _kUsername,
      _kPassword,
      _kRemoteRoot,
    ]) {
      await _delete(key);
    }
    _degraded = false;
    try {
      await _storage.delete(key: _degradedFlag);
    } catch (_) {
      // Ignore: nothing depends on this flag surviving.
      // 忽略：没有逻辑依赖该标记的持久性。
    }
  }

  Future<String?> _read(String key) async {
    try {
      final String? value = await _storage.read(key: key);
      // A successful secure read means we are not degraded for this key.
      // 安全读取成功即说明该键未处于降级状态。
      if (value != null) return value;
    } catch (e) {
      _degraded = true;
      if (kDebugMode) {
        debugPrint('[SecureStore] secure read failed for $key, falling back: $e');
      }
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return;
    } catch (e) {
      _degraded = true;
      if (kDebugMode) {
        debugPrint('[SecureStore] secure write failed for $key, falling back: $e');
      }
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Fall through to the fallback store.
      // 继续走降级存储。
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// WebDAV connection settings.
/// WebDAV 连接设置。
class WebDavCredentials {
  const WebDavCredentials({
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.remoteRoot = 'moepick',
  });

  final String baseUrl;
  final String username;
  final String password;

  /// Folder created on the server to hold MoePick data.
  /// 在服务器上用于存放拾萌数据的文件夹。
  final String remoteRoot;

  /// Whether enough information is present to attempt a connection.
  /// 信息是否足够发起连接尝试。
  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  WebDavCredentials copyWith({
    String? baseUrl,
    String? username,
    String? password,
    String? remoteRoot,
  }) {
    return WebDavCredentials(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteRoot: remoteRoot ?? this.remoteRoot,
    );
  }

  /// Never expose the password through logging or `toString`.
  /// 绝不在日志或 `toString` 中暴露密码。
  @override
  String toString() =>
      'WebDavCredentials($baseUrl, user=$username, password=***)';
}
