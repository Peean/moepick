import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Severity of a log entry.
/// 日志条目的级别。
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// Lightweight app logger: console in debug builds, rolling files on disk.
/// 轻量应用日志：debug 构建输出到控制台，磁盘上使用滚动文件。
///
/// WHY HAND-ROLLED / 为什么手写
///
/// This project deliberately avoids heavyweight dependencies; a logger needs
/// only three things — a severity tag, a timestamp and a place to append a
/// line. Dart's `File.writeAsString(append: true)` plus a size-based rotate
/// covers that with no third-party package. The file lives under the app data
/// directory, so a crash on a device without a terminal still leaves a stack
/// trace the user can export from the settings screen.
///
/// 本项目有意避免重型依赖；日志只需三样——级别标签、时间戳、以及一行追加的位置。
/// Dart 的 `File.writeAsString(append: true)` 加上按大小滚动即可覆盖，无需第三方包。
/// 文件位于应用数据目录下，因此无终端环境下崩溃仍会留下堆栈，
/// 用户可从设置页导出。
///
/// WRITE MODEL / 写入模型
///
/// Writes are fire-and-forget but serialised through a single future chain, so
/// two errors logged in the same tick never interleave. This keeps the log
/// readable without blocking the UI thread on every entry.
///
/// 写入是「发后即忘」，但通过单一 future 链串行化，
/// 使同一时刻两条错误不会交错。这样日志可读，又不会让 UI 线程每条都阻塞。
class AppLog {
  AppLog._();

  static const String _dirName = 'logs';
  static const String _fileName = 'app.log';

  /// Rotate once the current file exceeds this size.
  /// 当前文件超过该大小时滚动。
  static const int _maxFileSize = 512 * 1024; // 512 KB

  /// Number of retained rotated files (app.log + .1 … .N).
  /// 保留的滚动文件数量（app.log + .1 … .N）。
  static const int _backupCount = 2;

  static Directory? _dir;
  static Future<void> _pending = Future<void>.value();

  /// Master switch. When false nothing is written to disk or console.
  /// 总开关。为 false 时既不写盘也不打印到控制台。
  static bool _enabled = true;

  /// Entries below this level are dropped.
  /// 低于该等级的条目被丢弃。
  static LogLevel _minLevel = LogLevel.info;

  /// Whether the logger has been pointed at a directory.
  /// 日志器是否已指向某个目录。
  static bool get isReady => _dir != null;

  /// Whether logging is currently enabled.
  /// 当前日志是否启用。
  static bool get enabled => _enabled;

  /// The minimum level currently being recorded.
  /// 当前记录的最低等级。
  static LogLevel get minLevel => _minLevel;

  /// Adjust the master switch and minimum level at runtime.
  /// 运行时调整总开关与最低等级。
  ///
  /// [level] is the numeric form persisted in settings (0=debug, 1=info,
  /// 2=warn, 3=error).
  /// [level] 为设置中持久化的数值形式（0=debug、1=info、2=warn、3=error）。
  static void configure({required bool enabled, required int level}) {
    _enabled = enabled;
    _minLevel = _levelFromInt(level);
  }

  static LogLevel _levelFromInt(int value) {
    switch (value) {
      case 0:
        return LogLevel.debug;
      case 2:
        return LogLevel.warn;
      case 3:
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }

  /// Initialise the log directory under [rootPath]. Safe to call once.
  /// 在 [rootPath] 下初始化日志目录。可安全地调用一次。
  static Future<void> init(String rootPath) async {
    final Directory dir = Directory(p.join(rootPath, _dirName));
    await dir.create(recursive: true);
    _dir = dir;
  }

  static void debug(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.debug, message, error: error, stack: stack);

  static void info(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.info, message, error: error, stack: stack);

  static void warn(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.warn, message, error: error, stack: stack);

  static void error(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.error, message, error: error, stack: stack);

  static void _write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    // Master switch and level gate first: nothing below the configured level,
    // and nothing at all when disabled.
    // 先过总开关与等级门槛：低于配置等级不记录，关闭时一概不记录。
    if (!_enabled || level.index < _minLevel.index) return;

    final String line = _format(level, message, error, stack);

    // Console: everything in debug builds; warn/error even in release, so the
    // tail of a crash is still visible in `adb logcat`.
    // 控制台：debug 构建打印全部；release 仍打印 warn/error，
    // 使崩溃的末尾在 `adb logcat` 中仍可见。
    if (kDebugMode || level.index >= LogLevel.warn.index) {
      debugPrint(line);
    }

    _enqueue(line);
  }

  static String _format(
    LogLevel level,
    String message,
    Object? error,
    StackTrace? stack,
  ) {
    final DateTime now = DateTime.now();
    final String ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final StringBuffer buffer = StringBuffer(
      '[$ts] [${level.name.toUpperCase()}] $message',
    );
    if (error != null) buffer.write('\n  error: $error');
    if (stack != null) buffer.write('\n$stack');
    return buffer.toString();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static void _enqueue(String line) {
    final Directory? dir = _dir;
    if (dir == null) return; // Not initialised; drop rather than throw.
    // 未初始化；直接丢弃而非抛异常。
    _pending = _pending.then((_) => _append(dir, line)).catchError((_) {});
  }

  static Future<void> _append(Directory dir, String line) async {
    try {
      final File file = File(p.join(dir.path, _fileName));
      if (await file.exists() && await file.length() >= _maxFileSize) {
        await _rotate(dir);
      }
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never crash the app it is observing.
      // 日志绝不能让它所观察的应用崩溃。
    }
  }

  static Future<void> _rotate(Directory dir) async {
    // Drop the oldest, then shift every retained file up one slot.
    // 丢弃最旧，然后将每个保留文件上移一个槽位。
    final File oldest = File(p.join(dir.path, '$_fileName.$_backupCount'));
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (int i = _backupCount - 1; i >= 1; i--) {
      final File source = File(p.join(dir.path, '$_fileName.$i'));
      if (await source.exists()) {
        await source.rename(p.join(dir.path, '$_fileName.${i + 1}'));
      }
    }
    final File current = File(p.join(dir.path, _fileName));
    if (await current.exists()) {
      await current.rename(p.join(dir.path, '$_fileName.1'));
    }
  }

  /// Everything currently on disk, oldest first.
  /// 当前磁盘上的全部内容，最旧在前。
  static Future<String> readAll() async {
    final Directory? dir = _dir;
    if (dir == null) return '';
    final StringBuffer buffer = StringBuffer();

    // Rotated files first (older), then the live one.
    // 先读滚动文件（更旧），再读当前文件。
    for (int i = _backupCount; i >= 1; i--) {
      final File file = File(p.join(dir.path, '$_fileName.$i'));
      if (await file.exists()) {
        buffer.write(await file.readAsString());
      }
    }
    final File live = File(p.join(dir.path, _fileName));
    if (await live.exists()) {
      buffer.write(await live.readAsString());
    }
    return buffer.toString();
  }

  /// Delete all log files.
  /// 删除全部日志文件。
  static Future<void> clear() async {
    final Directory? dir = _dir;
    if (dir == null) return;
    await _pending; // Wait for any in-flight write to settle.
    // 等待进行中的写入落定。
    for (final String name in <String>[
      _fileName,
      for (int i = 1; i <= _backupCount; i++) '$_fileName.$i',
    ]) {
      final File file = File(p.join(dir.path, name));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
