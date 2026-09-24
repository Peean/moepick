import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/platform/image_picker_service.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/path_utils.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/moe_scaffold.dart';
import '../application/settings_providers.dart';

/// Background customisation: image, opacity, scrim and blur.
/// 背景自定义：图片、不透明度、遮罩与模糊。
///
/// LIVE PREVIEW WITHOUT PER-FRAME COST: sliders write to the persisted config
/// immediately (so the real app behind this page repaints and the user sees the
/// true result), but the expensive part — regenerating the pre-blurred bitmap —
/// is debounced by [AppConstants.backgroundDebounce]. Dragging the blur slider
/// therefore updates a cheap local preview every frame while only spawning the
/// isolate once the user pauses.
///
/// 实时预览且不产生每帧开销：滑杆立即写入持久化配置（因此本页背后的真实界面会重绘，
/// 用户看到的是真实效果），但代价高昂的部分——重新生成预模糊位图——按
/// [AppConstants.backgroundDebounce] 防抖。因此拖动模糊滑杆时每帧只更新廉价的本地预览，
/// 仅在用户停手后才启动 isolate。
class BackgroundSettingsPage extends ConsumerStatefulWidget {
  const BackgroundSettingsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<BackgroundSettingsPage> createState() =>
      _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState
    extends ConsumerState<BackgroundSettingsPage> {
  /// Debounces expensive blur-cache regeneration.
  /// 对昂贵的模糊缓存重建做防抖。
  final Debouncer _blurDebouncer = Debouncer(
    AppConstants.backgroundDebounce,
  );

  /// A cheap, in-memory preview of the source image, decoded once. Used to give
  /// immediate slider feedback while the persisted (pre-blurred) version is
  /// still being generated off-thread.
  /// 源图的廉价内存预览，只解码一次。用于在后台生成持久化（预模糊）版本期间
  /// 立即给出滑杆反馈。
  ui.Image? _previewImage;
  String? _previewKey;
  bool _busy = false;

  /// Local value shown on the blur slider while the debounce is pending; null
  /// means "follow the persisted config".
  /// 防抖待定时模糊滑杆显示的本地值；null 表示「跟随持久化配置」。
  double? _pendingSigma;

  @override
  void dispose() {
    _blurDebouncer.dispose();
    _previewImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BackgroundConfig config = ref.watch(backgroundConfigProvider);
    final BackgroundConfigNotifier notifier =
        ref.read(backgroundConfigProvider.notifier);

    // Keep the cheap preview bitmap in sync with the chosen source image.
    // 使廉价预览位图与所选源图保持同步。
    _syncPreview(config);

    final double sigma = _pendingSigma ?? config.blurSigma;

    return MoeScaffold(
      appBar: AppBar(
        title: const Text('背景图片'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RoutePaths.settings),
        ),
        actions: <Widget>[
          if (config.hasImage)
            IconButton(
              tooltip: '移除背景',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeImage(notifier),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _PreviewPane(
            config: config,
            previewImage: _previewImage,
            busy: _busy,
          ),
          const SizedBox(height: 12),
          _ImageActions(
            hasImage: config.hasImage,
            busy: _busy,
            onPick: () => _pickImage(notifier),
            onClear: config.hasImage ? () => _removeImage(notifier) : null,
          ),

          const SectionHeader(
            '显示模式',
            subtitle: '决定背景在界面中的透出方式',
          ),
          _ModeSelector(
            mode: config.mode,
            onChanged: notifier.setMode,
          ),

          const SectionHeader('不透明度'),
          _SliderRow(
            label: '图片不透明度',
            value: config.opacity,
            min: 0.0,
            max: 1.0,
            display: '${(config.opacity * 100).round()}%',
            enabled: config.hasImage,
            onChanged: notifier.setOpacity,
          ),

          const SectionHeader(
            '遮罩层',
            subtitle: '在图片上叠加一层颜色，压暗图案以突出文字',
          ),
          _ScrimPicker(
            colorValue: config.scrimColorValue,
            onColorChanged: notifier.setScrimColor,
          ),
          const SizedBox(height: 8),
          _SliderRow(
            label: '遮罩强度',
            value: config.scrimOpacity,
            min: 0.0,
            max: 1.0,
            display: '${(config.scrimOpacity * 100).round()}%',
            enabled: config.hasImage,
            onChanged: notifier.setScrimOpacity,
          ),

          const SectionHeader(
            '模糊',
            subtitle: '模糊在后台一次性完成并缓存，因此不会影响滚动流畅度',
          ),
          _SwitchCard(
            label: '启用模糊',
            description: config.hasImage
                ? '关闭后仍会记住模糊强度'
                : '请先选择一张背景图片',
            value: config.useBlur,
            enabled: config.hasImage,
            onChanged: (bool value) {
              setState(() => _pendingSigma = null);
              notifier.setBlurEnabled(value);
            },
          ),
          const SizedBox(height: 12),
          _SliderRow(
            label: '模糊强度',
            value: sigma,
            min: 0.0,
            max: 40.0,
            display: sigma.toStringAsFixed(0),
            // Greyed out rather than hidden, so the user can see the control
            // exists and understand why it is unavailable.
            // 置灰而非隐藏，使用户能看到控件存在，并理解为何不可用。
            enabled: config.hasImage && config.useBlur,
            onChanged: (double value) {
              // Cheap path: local state only, so the slider tracks the finger.
              // 廉价路径：只改本地状态，使滑杆跟手。
              setState(() => _pendingSigma = value);
              _blurDebouncer.run(() {
                if (!mounted) return;
                notifier.setBlurSigma(value).then((_) {
                  if (mounted) setState(() => _pendingSigma = null);
                });
              });
            },
            onChangeEnd: (double value) {
              // Commit immediately on release instead of waiting out the delay.
              // 松手时立即提交，而不必等满防抖时间。
              _blurDebouncer.flushNow();
            },
          ),

          const SizedBox(height: 20),
          _StorageNote(config: config),
        ],
      ),
    );
  }

  /// Decode a small preview of the source image for immediate slider feedback.
  /// 解码源图的小尺寸预览，用于滑杆的即时反馈。
  void _syncPreview(BackgroundConfig config) {
    final String? source = config.imageRelativePath;
    if (source == null || source.isEmpty) {
      if (_previewKey != null) {
        _previewKey = null;
        _previewImage?.dispose();
        _previewImage = null;
      }
      return;
    }
    if (_previewKey == source) return;

    _previewKey = source;
    // Decode after the frame: this runs during build, and starting file I/O
    // mid-build would be both illegal and pointless.
    // 在帧后解码：此处在 build 中调用，在 build 中启动文件 I/O 既非法也无意义。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ui.Image? image = await loadUiImage(
        await PathUtils.resolve(source),
        cacheWidth: AppConstants.backgroundPreviewMaxSize,
      );
      if (!mounted) {
        image?.dispose();
        return;
      }
      setState(() {
        _previewImage?.dispose();
        _previewImage = image;
      });
    });
  }

  Future<void> _pickImage(BackgroundConfigNotifier notifier) async {
    setState(() => _busy = true);
    try {
      final String? path = await ImagePickerService.pickSingle();
      if (path == null) return;
      await notifier.setImageFromPath(path);
      if (mounted) showToast(context, '背景已更新');
    } catch (e) {
      if (mounted) showToast(context, '选择图片失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage(BackgroundConfigNotifier notifier) async {
    final bool ok = await confirm(
      context,
      title: '移除背景图片',
      message: '背景图片及其模糊缓存会被删除，透明度与遮罩设置将保留。',
      confirmLabel: '移除',
      destructive: true,
    );
    if (!ok) return;
    await notifier.clearImage();
    if (mounted) showToast(context, '已移除背景图片');
  }
}

/// A live preview that mirrors the real background rendering: the same source
/// bitmap, opacity and scrim the app applies behind the UI.
/// 实时预览，镜像真实的背景渲染：与应用在界面背后使用的同一张位图、
/// 同一不透明度与遮罩。
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.config,
    required this.previewImage,
    required this.busy,
  });

  final BackgroundConfig config;
  final ui.Image? previewImage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const double height = 210;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: theme.colorScheme.surface),

            if (previewImage != null)
              RawImage(
                image: previewImage,
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

            if (previewImage == null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.image_outlined,
                      size: 36,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '还没有背景图片',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),

            // Sample content so the user judges readability, not just the image.
            // 示例内容，让用户判断的是可读性而不仅是图片本身。
            if (previewImage != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '示例系列',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: const <Shadow>[
                            Shadow(blurRadius: 6, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '文字在背景上的可读性大致如此',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                          shadows: const <Shadow>[
                            Shadow(blurRadius: 6, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (busy)
              ColoredBox(
                color: Colors.black.withOpacity(0.35),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pick / clear buttons under the preview.
/// 预览下方的选择与清除按钮。
class _ImageActions extends StatelessWidget {
  const _ImageActions({
    required this.hasImage,
    required this.busy,
    required this.onPick,
    required this.onClear,
  });

  final bool hasImage;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        ElevatedButton.icon(
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(hasImage ? '更换图片' : '选择图片'),
        ),
        if (onClear != null)
          OutlinedButton.icon(
            onPressed: busy ? null : onClear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('移除'),
          ),
      ],
    );
  }
}

/// Card / fullscreen mode selector.
/// 卡片 / 全屏模式选择器。
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final BackgroundMode mode;
  final ValueChanged<BackgroundMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ModeOption(
            label: '卡片式',
            description: '内容区不透明\n背景透出在边缘',
            icon: Icons.view_agenda_outlined,
            selected: mode == BackgroundMode.card,
            onTap: () => onChanged(BackgroundMode.card),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeOption(
            label: '全屏',
            description: '背景铺满整屏\n内容浮于其上',
            icon: Icons.wallpaper_outlined,
            selected: mode == BackgroundMode.fullscreen,
            onTap: () => onChanged(BackgroundMode.fullscreen),
          ),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.10),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              size: 24,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.55),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? theme.colorScheme.primary : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled slider with a numeric readout.
/// 带数值读数的标签滑杆。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.enabled,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double clamped = value.clamp(min, max);

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: MoeCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(label, style: theme.textTheme.bodyMedium),
                ),
                Text(
                  display,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: clamped,
              min: min,
              max: max,
              divisions: max <= 1.0 ? 20 : max.round(),
              label: display,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Swatch row for the scrim colour.
/// 遮罩颜色的色块行。
class _ScrimPicker extends StatelessWidget {
  const _ScrimPicker({required this.colorValue, required this.onColorChanged});

  final int colorValue;
  final ValueChanged<int> onColorChanged;

  /// Scrim colours chosen to darken artwork without shifting its hue much.
  /// 遮罩颜色，选在能压暗图案而不过多改变其色相的范围。
  static const List<ScrimChoice> choices = <ScrimChoice>[
    ScrimChoice('纯黑', 0xFF000000),
    ScrimChoice('深灰', 0xFF33363B),
    ScrimChoice('藏蓝', 0xFF1B2A4A),
    ScrimChoice('深紫', 0xFF33203F),
    ScrimChoice('墨绿', 0xFF16332A),
    ScrimChoice('棕褐', 0xFF3A2A1C),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MoeCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: choices.map((ScrimChoice choice) {
          final bool selected = choice.colorValue == colorValue;
          return GestureDetector(
            onTap: () => onColorChanged(choice.colorValue),
            child: Column(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color(choice.colorValue),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.15),
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: choice.colorValue == 0xFF000000
                              ? Colors.white
                              : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(height: 5),
                Text(
                  choice.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A named scrim colour.
/// 具名遮罩颜色。
class ScrimChoice {
  const ScrimChoice(this.label, this.colorValue);

  final String label;
  final int colorValue;
}

/// A label plus a switch with an enable flag.
/// 带启用开关的标签行。
class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.label,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: MoeCard(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodyLarge),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small note explaining where the background data lives.
/// 说明背景数据存放位置的小提示。
class _StorageNote extends StatelessWidget {
  const _StorageNote({required this.config});

  final BackgroundConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String cacheState;
    if (config.cachedBlurRelativePath != null) {
      cacheState = '模糊缓存已就绪，绘制时不消耗额外算力';
    } else if (config.useBlur && config.blurSigma > 0) {
      cacheState = '模糊缓存正在生成，暂时使用原图';
    } else {
      cacheState = '未启用模糊';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.info_outline,
          size: 15,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '背景图片保存在应用数据目录中，并会随完整备份一起导出。\n$cacheState',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
