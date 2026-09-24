import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/shared/widgets/common.dart';

/// `contextIsAlive` protects post-`await` UI work, so it must be correct at the
/// single moment it matters: after the widget is gone.
/// `contextIsAlive` 用于保护 `await` 之后的 UI 操作，因此它必须在其唯一关键的
/// 时刻——组件消失之后——保持正确。
void main() {
  group('contextIsAlive', () {
    testWidgets('reports true while the element is mounted',
        (WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      ));

      expect(contextIsAlive(captured), isTrue);
    });

    testWidgets('reports false once the element is unmounted',
        (WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      ));
      expect(contextIsAlive(captured), isTrue);

      // Swapping the whole tree deactivates the old element.
      // 整体替换组件树会使旧 element 被 deactivate。
      await tester.pumpWidget(const MaterialApp(home: Placeholder()));

      // The naive `findRenderObject() == null` guard would throw here instead
      // of returning, so this assertion is the real regression protection.
      // 朴素的 `findRenderObject() == null` 守卫会在此抛异常而非返回，
      // 因此这条断言才是真正的回归保护。
      expect(contextIsAlive(captured), isFalse);
    });

    testWidgets('reports false for a deactivated element after a real await',
        (WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      ));

      await tester.pumpWidget(const MaterialApp(home: Placeholder()));

      // `tester.pump` advances the binding's fake clock, so a real timer can
      // elapse without stalling the test. A bare `Future.delayed` would hang
      // here forever: widget tests run inside a FakeAsync zone where only the
      // pumped clock moves.
      // `tester.pump` 会推进 binding 的模拟时钟，因此真实计时器能正常走完而不
      // 会卡住测试。裸用 `Future.delayed` 会在此永久挂起：widget 测试运行在
      // FakeAsync 区域中，只有被 pump 的时钟才会前进。
      await tester.pump(const Duration(milliseconds: 20));

      expect(contextIsAlive(captured), isFalse);
    });
  });
}
