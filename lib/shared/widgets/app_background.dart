import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../features/settings/application/background_service.dart';
import '../../features/settings/application/settings_providers.dart';
import 'background_layer.dart';

/// Mounts the configured background behind the entire app.
/// 在整个应用背后挂载配置的背景。
///
/// Wired into `MaterialApp.router`'s `builder` so every route shares one
/// background instance instead of each page mounting its own copy (which would
/// reload and re-boundary the image on every navigation).
///
/// 接入 `MaterialApp.router` 的 `builder`，使所有路由共享同一个背景实例，
/// 而非每页各挂一份（那会导致每次导航都重新加载图片并重建绘制边界）。
class AppBackground extends ConsumerStatefulWidget {
  const AppBackground({Key? key, required this.child}) : super(key: key);

  final Widget child;

  @override
  ConsumerState<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends ConsumerState<AppBackground> {
  /// Decoded bitmap for the current configuration.
  /// 当前配置对应的已解码位图。
  ui.Image? _image;

  /// Config the current [_image] was decoded for, used to skip redundant work.
  /// 当前 [_image] 对应的配置，用于跳过多余的解码工作。
  String _loadedKey = '';

  @override
  Widget build(BuildContext context) {
    final BackgroundConfig config = ref.watch(backgroundConfigProvider);
    final bool dark = ref.watch(isDarkModeProvider);

    _syncImage(config);

    // Card mode: the background is drawn behind the scaffold, and each page
    // paints an opaque-ish surface on top, so the image reads as a frame around
    // the content.
    // 卡片模式：背景绘制在 scaffold 之后，各页在其上绘制接近不透明的表面，
    // 使图片呈现为内容四周的边框效果。
    if (config.mode == BackgroundMode.card) {
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: BackgroundLayer(config: config, image: _image),
          ),
          widget.child,
        ],
      );
    }

    // Fullscreen mode: the app sits above the background, and pages use
    // transparent scaffolds so the image is visible through them.
    // 全屏模式：应用位于背景之上，页面使用透明 scaffold，使图片透出。
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: BackgroundLayer(config: config, image: _image),
        ),
        // A second, theme-aware veil keeps text legible over busy artwork.
        // 再叠一层随主题变化的薄纱，使文字在复杂图案上保持可读。
        Positioned.fill(
          child: ColoredBox(
            color: (dark ? Colors.black : Colors.white).withOpacity(
              config.hasImage ? 0.06 : 0.0,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }

  /// Decode (or re-decode) the bitmap when the configuration demands it.
  /// 当配置需要时解码（或重新解码）位图。
  ///
  /// Runs after the frame because decoding is async and must not happen during
  /// build. The extra frame is imperceptible and avoids blocking the first
  /// layout.
  ///
  /// 在帧结束后执行，因为解码是异步的、不能在 build 期间进行。
  /// 多出的一帧不可感知，却避免了阻塞首次布局。
  void _syncImage(BackgroundConfig config) {
    final String key = _keyOf(config);
    if (key == _loadedKey) return;
    _loadedKey = key;

    if (!config.hasImage) {
      if (_image != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _image = null);
        });
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ui.Image? loaded =
          await ref.read(backgroundImageServiceProvider).loadForPaint(config);
      if (!mounted || _loadedKey != key) return;
      setState(() => _image = loaded);
    });
  }

  /// Identity of the rendered output: everything that changes what is painted.
  /// 渲染结果的标识：所有会影响绘制结果的因素。
  ///
  /// Opacity and scrim are excluded because they are applied at paint time from
  /// [config] directly, so changing them must not trigger a re-decode.
  /// 不包含 opacity 与遮罩，因为它们在绘制时直接从 [config] 取值，
  /// 修改它们不应触发重新解码。
  String _keyOf(BackgroundConfig config) {
    return '${config.imageRelativePath ?? ''}'
        '|${config.useBlur ? config.blurSigma.toStringAsFixed(1) : '0'}'
        '|${config.cachedBlurRelativePath ?? ''}';
  }
}
