import 'package:flutter/material.dart';

/// Per-source accent colors so a source is recognizable at a glance
/// (badge dot, category-style tinting) without hardcoding per-screen logic.
const Map<String, Color> sourceAccentColors = {
  'bbc-news': Color(0xFFE6423A),
  'al-jazeera': Color(0xFFE8A33D),
  'npr-news': Color(0xFF3D7FE8),
  'the-guardian': Color(0xFF0A6E4B),
  'techcrunch': Color(0xFF23B26D),
};

Color sourceAccent(String sourceId) =>
    sourceAccentColors[sourceId] ?? const Color(0xFF6C7BFF);

class AppTheme {
  static const _seed = Color(0xFF3D5AFE);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, scheme);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide.none,
        labelStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 3, color: scheme.primary),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        height: 1.15,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        height: 1.2,
      ),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      labelSmall: base.labelSmall?.copyWith(
        letterSpacing: 0.2,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
