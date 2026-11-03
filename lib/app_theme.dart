import 'package:flutter/material.dart';

/// Material 3 官方基线种子色（默认紫色）。
const Color kMaterial3Seed = Color(0xFF6750A4);

/// 亮色主题：完全使用 Material 3 默认色彩体系。
ThemeData buildLightTheme() => _buildTheme(Brightness.light);

/// 暗色主题：完全使用 Material 3 默认色彩体系。
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kMaterial3Seed,
    brightness: brightness,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    extensions: [AppPalette.fromScheme(scheme)],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Segoe UI',
        'PingFang SC',
      ],
    ),
    // 使用 Material 3 标准角色色构造填充式输入框。
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      isDense: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    // SnackBar 使用当前主题的容器色，亮 / 暗模式下明确跟随切换。
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(fontSize: 12.5, color: scheme.onSurface),
      actionTextColor: scheme.primary,
      closeIconColor: scheme.onSurfaceVariant,
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

/// 语义色板：所有值都直接取自 Material 3 [ColorScheme] 的标准角色，
/// 不包含任何自定义色值，亮色 / 暗色主题下自动保持可读性。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentAlt,
    required this.accentSoft,
    required this.horizontalLine,
    required this.verticalLine,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.danger,
  });

  factory AppPalette.fromScheme(ColorScheme scheme) {
    return AppPalette(
      background: scheme.surface,
      surface: scheme.surface,
      surfaceAlt: scheme.surfaceContainerLow,
      surfaceHigh: scheme.surfaceContainerHigh,
      border: scheme.outlineVariant,
      borderStrong: scheme.outline,
      accent: scheme.primary,
      accentAlt: scheme.tertiary,
      accentSoft: scheme.primary.withValues(alpha: 0.14),
      horizontalLine: scheme.primary,
      verticalLine: scheme.tertiary,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textMuted: scheme.onSurfaceVariant,
      success: scheme.tertiary,
      danger: scheme.error,
    );
  }

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;
  final Color border;
  final Color borderStrong;
  final Color accent;
  final Color accentAlt;
  final Color accentSoft;
  final Color horizontalLine;
  final Color verticalLine;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color danger;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHigh,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentAlt,
    Color? accentSoft,
    Color? horizontalLine,
    Color? verticalLine,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? danger,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentAlt: accentAlt ?? this.accentAlt,
      accentSoft: accentSoft ?? this.accentSoft,
      horizontalLine: horizontalLine ?? this.horizontalLine,
      verticalLine: verticalLine ?? this.verticalLine,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentAlt: Color.lerp(accentAlt, other.accentAlt, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      horizontalLine: Color.lerp(horizontalLine, other.horizontalLine, t)!,
      verticalLine: Color.lerp(verticalLine, other.verticalLine, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// 当前主题的语义色板（来源于 Material 3 ColorScheme）。
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        AppPalette.fromScheme(theme.colorScheme);
  }
}
