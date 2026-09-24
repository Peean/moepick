/// A minimal `Result` type.
/// 精简版 Result 类型。
///
/// Dart 2.17 has no `sealed` classes and no pattern matching / switch
/// expressions, so exhaustiveness cannot be enforced by the compiler. Callers
/// must check [isSuccess] (or use [fold]) before touching [value].
///
/// Dart 2.17 没有 sealed 类，也没有 pattern matching / switch 表达式，编译器无法
/// 强制穷尽检查。调用方必须先判断 [isSuccess]（或使用 [fold]）再访问 [value]。
class Result<T> {
  const Result._(this.value, this.error, this.isSuccess);


  /// Successful result.
  /// 成功结果。
  factory Result.ok(T value) => Result<T>._(value, null, true);

  /// Failed result.
  /// 失败结果。
  factory Result.fail(Object error) => Result<T>._(null, error, false);

  final T? value;
  final Object? error;
  final bool isSuccess;

  /// Collapse both branches into a single value.
  /// 将两个分支收敛为单个值。
  R fold<R>(R Function(T value) onSuccess, R Function(Object error) onFailure) {
    if (isSuccess) {
      return onSuccess(value as T);
    }
    return onFailure(error ?? StateError('Result failed without an error'));
  }
}

/// A `Result` carrying no payload, for operations whose only outcome is
/// success or failure.
/// 无载荷的 Result，用于只关心成功/失败的操作。
class VoidResult extends Result<void> {
  const VoidResult._(Object? error, bool isSuccess)
      : super._(null, error, isSuccess);

  factory VoidResult.ok() => const VoidResult._(null, true);
  factory VoidResult.fail(Object error) => VoidResult._(error, false);
}
