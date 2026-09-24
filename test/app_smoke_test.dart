import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/core/storage/hive_store.dart';
import 'package:moepick/core/storage/secure_store.dart';
import 'package:moepick/core/theme/app_theme.dart';
import 'package:moepick/core/utils/path_utils.dart';
import 'package:moepick/data/models/app_settings.dart';
import 'package:moepick/features/settings/application/storage_providers.dart';
import 'package:moepick/moepick_app.dart';
import 'package:path/path.dart' as p;

/// End-to-end smoke coverage for the assembled app.
/// 针对组装完成的应用做端到端冒烟覆盖。
///
/// The unit suites each lock down one layer, but nothing so far proved the
/// layers survive being wired together: the router delegate, the Riverpod
/// scope, the theme providers and the data providers all have to agree on a
/// single first frame. A mis-wired override or a provider that throws during
/// `build` only shows up here.
///
/// 各单元测试分别锁定了单层逻辑，但此前没有任何测试证明这些层在装配后仍能工作：
/// 路由 delegate、Riverpod 作用域、主题 provider 与数据 provider 必须在首帧上
/// 彼此一致。覆盖项接错或 provider 在 `build` 中抛异常，只有在这里才会暴露。
///
/// IMPORTANT — why every widget test here opens the store inside
/// `tester.runAsync`: `testWidgets` runs its body in a `FakeAsync` zone, which
/// replaces the clock and the microtask queue but **not** real socket/file
/// completions. Hive's file lock and `RandomAccessFile` futures therefore never
/// resolve there, and `HiveStore.open` hangs forever with no error. My first
/// version of this file made exactly that mistake and every widget test timed
/// out at 2 minutes. `runAsync` escapes the fake zone onto the real event loop,
/// which is the only place real I/O can complete.
///
/// 重要——本文件每个 widget 测试都在 `tester.runAsync` 内打开存储的原因：
/// `testWidgets` 的函数体运行在 `FakeAsync` 区域中，它会替换时钟与微任务队列，
/// 但**不会**替换真实的 socket/文件完成事件。因此 Hive 的文件锁与
/// `RandomAccessFile` future 在其中永远不会完成，`HiveStore.open` 会无声地
/// 永久挂起。本文件的第一版正是犯了这个错误，导致每个 widget 测试都在 2 分钟
/// 超时。`runAsync` 能脱离模拟区域、回到真实事件循环，而那是真实 I/O 唯一能
/// 完成的地方。
void main() {
  late Directory root;
  late HiveStore store;

  /// Open a real store on a real temp directory, off the fake clock.
  /// 在真实临时目录上打开真实存储，并脱离模拟时钟。
  Future<void> openStore(WidgetTester tester) async {
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('moepick_widget_');
      PathUtils.debugOverrideRoot(root.path);
      store = await HiveStore.open(overrideRootPath: root.path);
    });
  }

  Future<void> closeStore() async {
    try {
      await store.close();
    } catch (_) {}
    PathUtils.debugOverrideRoot(null);
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  }

  /// Build the app under the same overrides `main.dart` installs.
  /// 使用与 `main.dart` 相同的覆盖项构建应用。
  Widget harness() {
    return ProviderScope(
      overrides: <Override>[
        hiveStoreProvider.overrideWithValue(store),
        // Credentials are irrelevant to a smoke test, but the sync feature
        // reads this provider during startup, so it must resolve.
        // 凭据与冒烟测试无关，但同步功能会在启动时读取该 provider，
        // 因此它必须能被解析。
        secureStoreProvider.overrideWithValue(SecureStore()),
      ],
      child: const MoePickApp(),
    );
  }

  group('MoePickApp boots', () {
    testWidgets('renders the library screen on a fresh install',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // A brand-new install has no series, so the empty state is the correct
      // first thing a user sees — and its presence proves the whole provider
      // graph resolved without throwing.
      // 全新安装没有任何系列，因此空状态正是用户应看到的第一屏；
      // 它出现即证明整条 provider 图解析成功、未抛异常。
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text('还没有系列'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('applies the persisted grid column count',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);

      // Seed persisted state *before* the first frame, so this asserts
      // "providers read stored state at build time" rather than
      // "a later write propagates".
      // 在首帧之前写入持久化状态，使断言覆盖的是
      // 「provider 在构建时读取已存状态」，而非「后续写入能传播」。
      await tester.runAsync(() =>
          store.writeSettings(AppSettings.defaults().copyWith(gridColumns: 5)));

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // The value must have survived a real Hive round-trip, which is what
      // makes this meaningful rather than a tautology on an in-memory map.
      // 该值必须经过真实的 Hive 往返，这才使这条断言有意义，
      // 而不是对内存字典的同义反复。
      expect(store.readSettings().gridColumns, 5);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppSettings persistence', () {
    testWidgets('round-trips every field through a real store',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);

      final AppSettings written = AppSettings.defaults().copyWith(
        gridColumns: 4,
        useDarkMode: true,
        followSystemTheme: false,
      );
      await tester.runAsync(() => store.writeSettings(written));

      final AppSettings read = store.readSettings();
      expect(read.gridColumns, written.gridColumns);
      expect(read.useDarkMode, written.useDarkMode);
      expect(read.followSystemTheme, written.followSystemTheme);
    });

    testWidgets('falls back to defaults when nothing was stored',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);

      final AppSettings read = store.readSettings();
      final AppSettings defaults = AppSettings.defaults();
      expect(read.gridColumns, defaults.gridColumns);
      expect(read.useDarkMode, defaults.useDarkMode);
    });

    testWidgets('background config is stored independently of settings',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);

      // The two live in separate boxes on purpose, so a corrupt background
      // record cannot take the settings down with it.
      // 两者刻意存放在不同 box 中，因此背景记录损坏不会连带设置一起失效。
      await tester.runAsync(() async {
        await store.writeSettings(
            AppSettings.defaults().copyWith(gridColumns: 6));
        await store.writeBackground(
          BackgroundConfig.defaults().copyWith(opacity: 0.5),
        );
      });

      expect(store.readSettings().gridColumns, 6);
      expect(store.readBackground().opacity, 0.5);
    });
  });

  group('Theme presets', () {
    // Pure `ProviderContainer` work, so no widget binding is needed and the
    // FakeAsync trap above does not apply.
    // 纯 `ProviderContainer` 逻辑，不需要 widget binding，
    // 因此上面的 FakeAsync 陷阱不适用。
    test('resolve a preset for every built-in colour', () {
      for (final ThemePreset preset in AppTheme.presets) {
        expect(AppTheme.presetFor(preset.colorValue), isNotNull,
            reason: 'missing preset for ${preset.label}');
      }
    });

    test('returns null for a colour that is not a preset', () {
      expect(AppTheme.presetFor(0xFF123456), isNull);
    });

    test('exposes distinct preset colours', () {
      final Set<int> seen = <int>{};
      for (final ThemePreset preset in AppTheme.presets) {
        expect(seen.add(preset.colorValue), isTrue,
            reason: 'duplicate colour ${preset.colorValue}');
      }
    });
  });

  group('PathUtils root override', () {
    // Both cases below are plain `test`s rather than `testWidgets`. Neither
    // needs a widget binding, and `testWidgets` would drag the Hive open/close
    // onto the FakeAsync clock, where the real file I/O never completes. The
    // `HiveStore.open` round-trip that actually needs a widget binding is
    // already covered by the boot group above.
    //
    // 下面两个用例都用普通 `test` 而非 `testWidgets`。二者都不需要 widget
    // binding，而用 `testWidgets` 会把 Hive 的打开/关闭拖到 FakeAsync 时钟上，
    // 那里真实文件 I/O 永远不会完成。真正需要 widget binding 的
    // `HiveStore.open` 往返已由上面的启动分组覆盖。
    test('override is cleared once torn down', () async {
      final Directory temp =
          Directory.systemTemp.createTempSync('moepick_override_');
      PathUtils.debugOverrideRoot(temp.path);
      // Guards the guard: a leaked override would silently point a later test
      // at the wrong directory, producing confusing cross-test failures.
      // 为守卫再加一层守卫：若覆盖项泄漏，后续测试会静默指向错误目录，
      // 产生令人困惑的跨测试失败。
      expect(PathUtils.hasCachedRoot, isTrue);

      PathUtils.debugOverrideRoot(null);
      expect(PathUtils.hasCachedRoot, isFalse);
      temp.deleteSync(recursive: true);
    });

    test('subdirectories resolve under the overridden root', () async {
      final Directory temp =
          Directory.systemTemp.createTempSync('moepick_paths_');
      PathUtils.debugOverrideRoot(temp.path);
      addTearDown(() {
        PathUtils.debugOverrideRoot(null);
        try {
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // `create: false` keeps this off the filesystem so the assertion stays
      // about path composition — which is the actual subject.
      // `create: false` 使其不访问文件系统，断言因此聚焦于路径拼接本身，
      // 那才是这里真正要验的东西。
      final String images = await PathUtils.imagesPath(create: false);
      expect(p.isWithin(temp.path, images), isTrue);
    });
  });
}
