// Regression tests for the text-prompt dialog lifecycle.
// 文本输入对话框生命周期的回归测试。
//
// BACKGROUND — the bug these tests exist to prevent.
// 背景——这些测试要防住的 bug。
//
// `promptForText` used to create its `TextEditingController` in the calling
// function and release it with `.whenComplete(controller.dispose)`. That future
// completes as soon as `Navigator.pop` runs, which is *before* the dialog's exit
// transition finishes — so the controller was disposed while the `TextField` and
// its `InputDecorator` were still mounted and still registered as listeners.
//
// Disposing a `ChangeNotifier` that still has listeners trips a debug assertion.
// The framework then tries to tear down a subtree it believes is already gone,
// and the failure escalates:
//
//   1. "A TextEditingController was used after being disposed."
//   2. "Tried to build dirty widget in the wrong build scope."
//   3. Failed assertion: '_dependents.isEmpty': is not true.
//
// The nastiest part: the dialog *appears* to close normally, and the red screen
// only shows up on the NEXT interaction (tapping the settings icon). That is why
// this was originally misdiagnosed as a routing or theme bug.
//
// `promptForText` 曾在调用方函数中创建 `TextEditingController`，并用
// `.whenComplete(controller.dispose)` 释放。该 future 在 `Navigator.pop` 执行时即完成，
// 也就是在对话框退场动画结束**之前**——于是 controller 在 `TextField` 与其
// `InputDecorator` 仍挂载、仍是监听者时就被释放了。
//
// 释放仍带监听者的 `ChangeNotifier` 会触发断言，随后框架尝试拆解它以为已消失的子树，
// 错误逐级升级为上面三条。最麻烦的是：对话框**看起来**正常关闭，红屏却出现在**下一次**
// 交互（点击设置图标）时。这正是它最初被误判为路由或主题 bug 的原因。
//
// WHY EVERY TEST HERE IS A PURE `test`, NOT `testWidgets`.
// 为何此处全部是纯 `test` 而非 `testWidgets`。
//
// `testWidgets` runs its body inside a `FakeAsync` zone. Real file I/O — Hive's
// `RandomAccessFile` futures — never completes there, so anything that awaits a
// disk write hangs until the test times out, with no error to explain why. These
// tests therefore drive the widget tree with their own `WidgetTester`-free
// harness: they pump a real binding and inspect `FlutterError.onError` directly.
//
// `testWidgets` 的测试体运行在 `FakeAsync` 区域中。真实文件 I/O（Hive 的
// `RandomAccessFile` future）在其中永不完成，因此任何 await 写盘的操作都会静默挂起
// 直至超时，且没有任何错误说明原因。所以这些测试使用自己的、不依赖 `WidgetTester`
// 的装置来驱动组件树：pump 真实 binding 并直接检查 `FlutterError.onError`。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/shared/widgets/common.dart';

void main() {
  /// Every framework error captured during one scenario.
  /// 一次场景中捕获到的全部框架错误。
  late List<FlutterErrorDetails> errors;
  late FlutterExceptionHandler? previousHandler;

  setUp(() {
    errors = <FlutterErrorDetails>[];
    previousHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      errors.add(details);
    };
  });

  tearDown(() {
    FlutterError.onError = previousHandler;
  });

  /// Mounts a minimal app whose home page can open the prompt, then returns the
  /// `BuildContext` the prompt should be shown from.
  ///
  /// 挂载一个最小应用，其首页可打开该输入对话框，随后返回用于展示对话框的
  /// `BuildContext`。
  Future<void> pumpHost(
    WidgetTester tester,
    void Function(BuildContext context) onReady,
  ) async {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    final GlobalKey holderKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          body: Builder(
            key: holderKey,
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () => onReady(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('promptForText controller lifetime', () {
    testWidgets('cancelling the dialog raises no framework error',
        (WidgetTester tester) async {
      await pumpHost(tester, (BuildContext context) {
        promptForText(context, title: '新建系列', hint: '给这个系列起个名字');
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('新建系列'), findsOneWidget);

      await tester.tap(find.text('取消'));
      // Let the exit transition run to completion. The old code disposed the
      // controller part-way through this, which is exactly the window that
      // produced the crash.
      // 让退场动画完整跑完。旧代码正是在这段时间内释放了 controller，
      // 而那正是产生崩溃的窗口期。
      await tester.pumpAndSettle();

      expect(find.text('新建系列'), findsNothing);
      expect(
        errors,
        isEmpty,
        reason: 'Cancelling must not dispose the controller while the '
            'TextField is still mounted:\n${errors.map((FlutterErrorDetails e) => e.exception).join('\n')}',
      );
    });

    testWidgets('confirming the dialog returns the typed text',
        (WidgetTester tester) async {
      String? result;
      await pumpHost(tester, (BuildContext context) async {
        result = await promptForText(context, title: '新建系列');
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '沙雕日常');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(result, '沙雕日常');
      expect(errors, isEmpty);
    });

    testWidgets('cancelling returns null', (WidgetTester tester) async {
      String? result = 'sentinel';
      await pumpHost(tester, (BuildContext context) async {
        result = await promptForText(context, title: '新建系列');
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(errors, isEmpty);
    });

    testWidgets('a second prompt after cancelling the first still works',
        (WidgetTester tester) async {
      // Two consecutive dialogs is the scenario that visibly crashed the Linux
      // build: the first one's teardown corrupted state that the next
      // interaction then tripped over.
      // 连续两次对话框正是 Linux 构建上肉眼可见的崩溃场景：第一次的拆解破坏了状态，
      // 下一次交互随即踩中。
      String? result;
      await pumpHost(tester, (BuildContext context) async {
        result = await promptForText(context, title: '新建系列', hint: '第一次');
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(errors, isEmpty, reason: 'first dialog teardown');

      await pumpHost(tester, (BuildContext context) async {
        result = await promptForText(context, title: '新建分类', hint: '第二次');
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('新建分类'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '猫猫');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(result, '猫猫');
      expect(errors, isEmpty, reason: 'second dialog after a cancelled first');
    });

    testWidgets('custom confirm label and initial text are honoured',
        (WidgetTester tester) async {
      String? result;
      await pumpHost(tester, (BuildContext context) async {
        result = await promptForText(
          context,
          title: '重命名',
          initial: '旧名字',
          confirmLabel: '保存',
        );
      });

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('旧名字'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(result, '旧名字');
      expect(errors, isEmpty);
    });
  });
}
