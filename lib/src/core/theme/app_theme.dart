import 'package:flutter/widgets.dart';

class AppThemePalette {
  const AppThemePalette({
    required this.primary,
    required this.primaryDim,
    required this.onPrimary,
    required this.primaryContainer,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceBright,
    required this.onSurface,
    required this.textMuted,
    required this.outline,
    required this.outlineSoft,
    required this.navIndicator,
    required this.chipBackground,
    required this.chipSelected,
    required this.heroBackground,
    required this.heroMutedText,
    required this.heroAvatarBackground,
    required this.heroAvatarForeground,
  });

  final Color primary;
  final Color primaryDim;
  final Color onPrimary;
  final Color primaryContainer;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceBright;
  final Color onSurface;
  final Color textMuted;
  final Color outline;
  final Color outlineSoft;
  final Color navIndicator;
  final Color chipBackground;
  final Color chipSelected;
  final Color heroBackground;
  final Color heroMutedText;
  final Color heroAvatarBackground;
  final Color heroAvatarForeground;
}

class AppThemeScope extends InheritedWidget {
  const AppThemeScope({super.key, required this.palette, required super.child});

  static const AppThemePalette prototypePalette = AppThemePalette(
    primary: Color(0xFF10B981),
    primaryDim: Color(0xFF059669),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD1FAE5),
    secondary: Color(0xFF047857),
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F5F4),
    surfaceBright: Color(0xFFFFFFFF),
    onSurface: Color(0xFF111827),
    textMuted: Color(0xFF6B7280),
    outline: Color(0xFFE5E7EB),
    outlineSoft: Color(0xFFF1F5F4),
    navIndicator: Color(0xFFD1FAE5),
    chipBackground: Color(0xFFEFF6F4),
    chipSelected: Color(0xFFD1FAE5),
    heroBackground: Color(0xFF10B981),
    heroMutedText: Color(0xFFE7FFF4),
    heroAvatarBackground: Color(0xFFE7FFF4),
    heroAvatarForeground: Color(0xFF047857),
  );

  final AppThemePalette palette;

  static AppThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope not found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) {
    return oldWidget.palette != palette;
  }
}
