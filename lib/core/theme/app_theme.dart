import 'package:flutter/material.dart';

/// Builds the app's [ThemeData] from a seed colour.
/// 根据种子色构建应用的 [ThemeData]。
///
/// `useMaterial3` is deliberately false: this project targets Flutter 3.0,
/// where the Material 3 component set is still incomplete and tends to produce
/// inconsistent spacing and elevation. We still borrow `ColorScheme.fromSeed`
/// for the generated palette, which is the most stable combination on 3.0.
///
/// 有意将 `useMaterial3` 设为 false：本项目面向 Flutter 3.0，
/// 该版本的 Material 3 组件集尚不完整，容易出现间距与高度不一致。
/// 但仍借用 `ColorScheme.fromSeed` 生成配色，这是 3.0 上最稳的组合。
class AppTheme {
  AppTheme._();

  /// Preset accents offered in the theme picker.
  /// 主题选择器中提供的预设主色。
  static const List<ThemePreset> presets = <ThemePreset>[
    ThemePreset('樱粉', 0xFFE38FB1),
    ThemePreset('薄荷', 0xFF5FBF9F),
    ThemePreset('天空', 0xFF6C9FE8),
    ThemePreset('暖橘', 0xFFE8945F),
    ThemePreset('薰衣草', 0xFF9B8FE0),
    ThemePreset('柠檬', 0xFFD9B53F),
    ThemePreset('珊瑚', 0xFFE07070),
    ThemePreset('石墨', 0xFF6E7A88),
  ];

  /// The preset matching [colorValue], or null when it is a custom colour.
  /// 与 [colorValue] 匹配的预设；若为自定义颜色则返回 null。
  static ThemePreset? presetFor(int colorValue) {
    for (final ThemePreset preset in presets) {
      if (preset.colorValue == colorValue) return preset;
    }
    return null;
  }

  /// Build a light or dark theme around [seedColor].
  /// 围绕 [seedColor] 构建浅色或深色主题。
  static ThemeData build({
    required Color seedColor,
    required Brightness brightness,
  }) {
    ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // `fromSeed` occasionally produces a low-contrast surface or an accent that
    // does not read as "the user's colour". Pin the accent and lift the surface
    // so the chosen seed stays visually dominant.
    // `fromSeed` 偶尔会生成对比度不足的表面色，或让主色不再像「用户选的颜色」。
    // 固定主色并抬高表面色，使用户所选主色在视觉上保持主导。
    scheme = scheme.copyWith(
      primary: seedColor,
      secondary: _shift(seedColor, brightness),
    );

    final Color surface = brightness == Brightness.light
        ? const Color(0xFFFAF7F9)
        : const Color(0xFF1C1B1F);

    final Color onSurface = brightness == Brightness.light
        ? const Color(0xFF1F1B1E)
        : const Color(0xFFE6E1E5);

    return ThemeData(
      useMaterial3: false,
      brightness: brightness,
      colorScheme: scheme.copyWith(surface: surface, onSurface: onSurface),
      scaffoldBackgroundColor: surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: surface,
        foregroundColor: onSurface,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: onSurface.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.primary.withOpacity(0.10),
        selectedColor: scheme.primary.withOpacity(0.22),
        labelStyle: TextStyle(fontSize: 12, color: onSurface),
        secondaryLabelStyle: TextStyle(fontSize: 12, color: onSurface),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: onSurface.withOpacity(0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: onSurface.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          primary: scheme.primary,
          onPrimary: _onColor(scheme.primary),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(primary: scheme.primary),
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withOpacity(0.08),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurface.withOpacity(0.7),
        textColor: onSurface,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  /// Slightly rotate the hue to produce a companion accent colour.
  /// 轻微旋转色相以产生互补的强调色。
  static Color _shift(Color base, Brightness brightness) {
    final HSLColor hsl = HSLColor.fromColor(base);
    final double hue = (hsl.hue + 28) % 360;
    return hsl
        .withHue(hue)
        .withLightness((hsl.lightness + (brightness == Brightness.light ? 0.08 : 0.02))
            .clamp(0.2, 0.9))
        .toColor();
  }

  /// Pick black or white text for a background, using perceived luminance
  /// rather than the raw channel average so mid-tones resolve correctly.
  /// 为准选择黑或白文字，使用感知亮度而非简单通道均值，使中间色判断正确。
  static Color _onColor(Color background) {
    return background.computeLuminance() > 0.55
        ? const Color(0xFF1F1B1E)
        : Colors.white;
  }
}

/// A named accent colour offered in the theme picker.
/// 主题选择器中的具名主色。
class ThemePreset {
  const ThemePreset(this.label, this.colorValue);

  final String label;

  /// 0xAARRGGBB.
  final int colorValue;

  Color get color => Color(colorValue);
}
