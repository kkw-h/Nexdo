import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreset { rational, mist, sky, sand }

class AppThemePalette {
  const AppThemePalette({
    required this.id,
    required this.label,
    required this.description,
    required this.preview,
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

  final AppThemePreset id;
  final String label;
  final String description;
  final List<Color> preview;
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

class AppThemeController extends ChangeNotifier {
  AppThemeController._(this._preferences);

  static const _storageKey = 'app.theme.preset';

  static final Map<AppThemePreset, AppThemePalette> palettes = {
    AppThemePreset.rational: const AppThemePalette(
      id: AppThemePreset.rational,
      label: '策展薄荷',
      description: 'Editorial Mint 标准版，平静、克制、适合长期使用。',
      preview: [Color(0xFF006C5A), Color(0xFF8CECD3), Color(0xFFF1FBF9)],
      primary: Color(0xFF006C5A),
      primaryDim: Color(0xFF005E4F),
      onPrimary: Color(0xFFE3FFF5),
      primaryContainer: Color(0xFF8CECD3),
      secondary: Color(0xFF005E4F),
      background: Color(0xFFF1FBF9),
      surface: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFE8F7F4),
      surfaceBright: Color(0xFFF7FFFD),
      onSurface: Color(0xFF233634),
      textMuted: Color(0xFF4F6361),
      outline: Color(0x26A1B6B4),
      outlineSoft: Color(0xFFE8F7F4),
      navIndicator: Color(0xFF8CECD3),
      chipBackground: Color(0xFFD1E7E4),
      chipSelected: Color(0xFF8CECD3),
      heroBackground: Color(0xFF006C5A),
      heroMutedText: Color(0xFFCDEFE7),
      heroAvatarBackground: Color(0xFFF7FFFD),
      heroAvatarForeground: Color(0xFF006C5A),
    ),
    AppThemePreset.mist: const AppThemePalette(
      id: AppThemePreset.mist,
      label: '晨雾薄荷',
      description: '更轻、更亮的 frosted 版本，页面呼吸感更强。',
      preview: [Color(0xFF0A7663), Color(0xFFA2F2DD), Color(0xFFF5FCFB)],
      primary: Color(0xFF0A7663),
      primaryDim: Color(0xFF066857),
      onPrimary: Color(0xFFF0FFF9),
      primaryContainer: Color(0xFFA2F2DD),
      secondary: Color(0xFF066857),
      background: Color(0xFFF5FCFB),
      surface: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFEDF8F6),
      surfaceBright: Color(0xFFFBFEFE),
      onSurface: Color(0xFF223734),
      textMuted: Color(0xFF58706B),
      outline: Color(0x26ABC0BC),
      outlineSoft: Color(0xFFEDF8F6),
      navIndicator: Color(0xFFA2F2DD),
      chipBackground: Color(0xFFD9ECE8),
      chipSelected: Color(0xFFA2F2DD),
      heroBackground: Color(0xFF0A7663),
      heroMutedText: Color(0xFFD7F1EA),
      heroAvatarBackground: Color(0xFFFBFEFE),
      heroAvatarForeground: Color(0xFF0A7663),
    ),
    AppThemePreset.sky: const AppThemePalette(
      id: AppThemePreset.sky,
      label: '青岚薄荷',
      description: '更偏青蓝一点的植物薄荷，信息感更清晰。',
      preview: [Color(0xFF0C6F68), Color(0xFF8DE4E0), Color(0xFFF0FBFA)],
      primary: Color(0xFF0C6F68),
      primaryDim: Color(0xFF095F59),
      onPrimary: Color(0xFFE8FFFD),
      primaryContainer: Color(0xFF8DE4E0),
      secondary: Color(0xFF095F59),
      background: Color(0xFFF0FBFA),
      surface: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFE6F6F4),
      surfaceBright: Color(0xFFF7FDFC),
      onSurface: Color(0xFF213937),
      textMuted: Color(0xFF4D6765),
      outline: Color(0x269EB8B4),
      outlineSoft: Color(0xFFE6F6F4),
      navIndicator: Color(0xFF8DE4E0),
      chipBackground: Color(0xFFD3E9E6),
      chipSelected: Color(0xFF8DE4E0),
      heroBackground: Color(0xFF0C6F68),
      heroMutedText: Color(0xFFD2EFED),
      heroAvatarBackground: Color(0xFFF7FDFC),
      heroAvatarForeground: Color(0xFF0C6F68),
    ),
    AppThemePreset.sand: const AppThemePalette(
      id: AppThemePreset.sand,
      label: '琥珀薄荷',
      description: '保留薄荷底色，加入更温暖的编辑感点缀。',
      preview: [Color(0xFF006C5A), Color(0xFFFDB64B), Color(0xFFF6FBF8)],
      primary: Color(0xFF006C5A),
      primaryDim: Color(0xFF005C4D),
      onPrimary: Color(0xFFE3FFF5),
      primaryContainer: Color(0xFF97E8D3),
      secondary: Color(0xFF005C4D),
      background: Color(0xFFF6FBF8),
      surface: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFEAF7F2),
      surfaceBright: Color(0xFFFBFEFC),
      onSurface: Color(0xFF243733),
      textMuted: Color(0xFF556764),
      outline: Color(0x26A6B9B1),
      outlineSoft: Color(0xFFEAF7F2),
      navIndicator: Color(0xFFDDEDD2),
      chipBackground: Color(0xFFD8E8E1),
      chipSelected: Color(0xFF97E8D3),
      heroBackground: Color(0xFF006C5A),
      heroMutedText: Color(0xFFE8D7A9),
      heroAvatarBackground: Color(0xFFFFF4D8),
      heroAvatarForeground: Color(0xFF8C5A00),
    ),
  };

  final SharedPreferences _preferences;
  AppThemePreset _preset = AppThemePreset.mist;

  AppThemePreset get preset => _preset;
  AppThemePalette get palette => palettes[_preset]!;

  static Future<AppThemeController> create() async {
    final preferences = await SharedPreferences.getInstance();
    final controller = AppThemeController._(preferences);
    controller._restore();
    return controller;
  }

  void _restore() {
    final raw = _preferences.getString(_storageKey);
    _preset = raw == AppThemePreset.mist.name
        ? AppThemePreset.mist
        : AppThemePreset.mist;
  }

  Future<void> updatePreset(AppThemePreset preset) async {
    if (_preset == preset) {
      return;
    }
    _preset = preset;
    await _preferences.setString(_storageKey, preset.name);
    notifyListeners();
  }
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope not found in context');
    return scope!.notifier!;
  }
}
