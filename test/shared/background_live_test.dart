import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moepick/core/storage/hive_store.dart';
import 'package:moepick/core/storage/secure_store.dart';
import 'package:moepick/core/utils/path_utils.dart';
import 'package:moepick/data/models/app_settings.dart';
import 'package:moepick/features/settings/application/settings_providers.dart';
import 'package:moepick/features/settings/application/storage_providers.dart';
import 'package:moepick/moepick_app.dart';
import 'package:moepick/shared/widgets/background_layer.dart';

/// Locks in that background config changes are reflected live — no restart
/// required. This is the regression guard for the reported bug where dragging
/// the opacity / scrim sliders (or switching the display mode) had no effect
/// until the app was relaunched.
///
/// 锁定「背景配置变化实时生效——无需重启」。这是针对所报告 bug 的回归保护：
/// 拖动不透明度/遮罩滑杆（或切换显示模式）此前需重启应用才生效。
void main() {
  late Directory root;
  late HiveStore store;
  late ProviderContainer container;

  Future<void> openStore(WidgetTester tester) async {
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('moepick_bg_');
      PathUtils.debugOverrideRoot(root.path);
      store = await HiveStore.open(overrideRootPath: root.path);
    });
    container = ProviderContainer(
      overrides: <Override>[
        hiveStoreProvider.overrideWithValue(store),
        secureStoreProvider.overrideWithValue(SecureStore()),
      ],
    );
  }

  Future<void> closeStore() async {
    container.dispose();
    try {
      await store.close();
    } catch (_) {}
    PathUtils.debugOverrideRoot(null);
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MoePickApp(),
    ));
    await tester.pumpAndSettle();
  }

  BackgroundLayer layer(WidgetTester tester) =>
      tester.widget<BackgroundLayer>(find.byType(BackgroundLayer).first);

  group('live background config', () {
    testWidgets('opacity change reaches the background layer immediately',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);
      await pumpApp(tester);

      expect(layer(tester).config.opacity, BackgroundConfig.defaults().opacity);

      await tester.runAsync(() =>
          container.read(backgroundConfigProvider.notifier).setOpacity(0.8));
      await tester.pumpAndSettle();

      expect(layer(tester).config.opacity, 0.8);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrim opacity change reaches the layer immediately',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);
      await pumpApp(tester);

      await tester.runAsync(() => container
          .read(backgroundConfigProvider.notifier)
          .setScrimOpacity(0.6));
      await tester.pumpAndSettle();

      expect(layer(tester).config.scrimOpacity, 0.6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mode change reaches the layer immediately',
        (WidgetTester tester) async {
      await openStore(tester);
      addTearDown(closeStore);
      await pumpApp(tester);

      expect(layer(tester).config.mode, BackgroundMode.card);

      await tester.runAsync(() => container
          .read(backgroundConfigProvider.notifier)
          .setMode(BackgroundMode.fullscreen));
      await tester.pumpAndSettle();

      expect(layer(tester).config.mode, BackgroundMode.fullscreen);
      expect(tester.takeException(), isNull);
    });
  });
}
