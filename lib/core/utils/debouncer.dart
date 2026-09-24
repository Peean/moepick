import 'dart:async';

/// Trailing-edge debouncer.
/// 尾沿触发防抖器。
///
/// Every call to [run] restarts the timer, so the action only fires once the
/// caller stops invoking it for [delay]. Used to avoid sync storms while the
/// user edits several items in a row.
///
/// 每次调用 [run] 都会重置计时器，只有在 [delay] 内不再被调用时才真正执行。
/// 用于避免用户连续编辑多条数据时反复触发同步。
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  /// Whether an action is currently pending.
  /// 当前是否有待执行的动作。
  bool get isPending => _timer?.isActive ?? false;

  /// Schedule [action], replacing any previously scheduled one.
  /// 安排 [action]，并替换之前已安排的动作。
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Fire the pending action immediately, if any.
  /// 立即执行待处理的动作（若有）。
  void flush(void Function() action) {
    _timer?.cancel();
    _timer = null;
    action();
  }

  /// Cancel any pending action without running it.
  /// 取消待处理的动作且不执行。
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
