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

  /// The action most recently passed to [run], retained so [flushNow] can fire
  /// it without the caller having to remember what it was.
  /// 最近一次传给 [run] 的动作，保留下来使 [flushNow] 无需调用方记住内容即可执行。
  void Function()? _pending;

  /// Whether an action is currently pending.
  /// 当前是否有待执行的动作。
  bool get isPending => _timer?.isActive ?? false;

  /// Schedule [action], replacing any previously scheduled one.
  /// 安排 [action]，并替换之前已安排的动作。
  void run(void Function() action) {
    _timer?.cancel();
    _pending = action;
    _timer = Timer(delay, () {
      final void Function()? action = _pending;
      _pending = null;
      action?.call();
    });
  }

  /// Fire the pending action immediately, if any.
  /// 立即执行待处理的动作（若有）。
  void flush(void Function() action) {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    action();
  }

  /// Fire whatever [run] last scheduled, without re-supplying it.
  /// 执行 [run] 最近安排的动作，无需再次传入。
  void flushNow() {
    final void Function()? action = _pending;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    action?.call();
  }

  /// Cancel any pending action without running it.
  /// 取消待处理的动作且不执行。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void dispose() => cancel();
}
