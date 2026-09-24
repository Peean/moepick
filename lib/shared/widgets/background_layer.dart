import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/app_settings.dart';

/// Paints the configured background image plus its scrim overlay.
/// 绘制配置的背景图及其遮罩层。
///
/// This layer contains nothing else, so it can be wrapped in a single
/// [RepaintBoundary]: scrolling the content above it then never re-rasterises
/// the background.
///
/// 该层不含其他内容，因此可用单个 [RepaintBoundary] 包裹：
/// 其上方内容滚动时不会重绘背景。
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({
    Key? key,
    required this.config,
    this.image,
  }) : super(key: key);

  final BackgroundConfig config;

  /// Bitmap to paint, already blurred if a blur cache exists.
  /// 用于绘制的位图；若存在模糊缓存则已模糊。
  final ui.Image? image;

  @override
  Widget build(BuildContext context) {
    // No image: the ordinary scaffold colour is already painted behind us.
    // 无图片：其后的普通 scaffold 背景色已经绘制，这里无需再画。
    if (image == null) {
      return const SizedBox.expand();
    }

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // RawImage paints an already-decoded ui.Image directly. Using it
          // instead of Image.asset/file avoids re-running decode or filter work
          // during the frame.
          // RawImage 直接绘制已解码的 ui.Image。相比 Image.file，
          // 它避免在帧内重复执行解码或滤镜运算。
          RawImage(
            image: image,
            fit: BoxFit.cover,
            opacity: AlwaysStoppedAnimation<double>(
              config.opacity.clamp(0.0, 1.0),
            ),
            filterQuality: FilterQuality.low,
          ),
          if (config.scrimOpacity > 0)
            ColoredBox(
              color: Color(config.scrimColorValue)
                  .withOpacity(config.scrimOpacity.clamp(0.0, 1.0)),
            ),
        ],
      ),
    );
  }
}

/// How content surfaces should be tinted so they stay readable over a
/// background image.
/// 内容表面为在背景图上保持可读性所需的着色方式。
class BackgroundSurfaceStyle {
  const BackgroundSurfaceStyle({
    required this.surfaceOpacity,
    required this.useBlurBehindAppBar,
  });

  /// Opacity of content surfaces stacked over the background.
  /// 叠加在背景之上的内容表面的不透明度。
  final double surfaceOpacity;

  /// Reserved for future use; currently informational only.
  /// 预留字段，目前仅作说明用途。
  final bool useBlurBehindAppBar;

  /// Card mode: surfaces are near-opaque so text stays crisp and the image
  /// shows only around the edges.
  /// 卡片模式：表面接近不透明，保证文字清晰，图片仅在边缘透出。
  static const BackgroundSurfaceStyle card = BackgroundSurfaceStyle(
    surfaceOpacity: 0.92,
    useBlurBehindAppBar: false,
  );

  /// Fullscreen mode: surfaces are translucent so the image reads through.
  /// 全屏模式：表面半透明，使图片透出。
  static const BackgroundSurfaceStyle fullscreen = BackgroundSurfaceStyle(
    surfaceOpacity: 0.72,
    useBlurBehindAppBar: true,
  );

  static BackgroundSurfaceStyle of(BackgroundMode mode) {
    return mode == BackgroundMode.fullscreen ? fullscreen : card;
  }
}
