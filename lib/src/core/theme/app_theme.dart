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
    required this.secondary,
    required this.background,
    required this.surface,
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
  final Color secondary;
  final Color background;
  final Color surface;
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
      label: '理性蓝灰',
      description: '克制、平衡，适合长期使用。',
      preview: [Color(0xFF64748B), Color(0xFF3B82F6), Color(0xFFF8FAFC)],
      primary: Color(0xFF64748B),
      secondary: Color(0xFF4F8CFF),
      background: Color(0xFFF8FAFC),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1E293B),
      textMuted: Color(0xFF64748B),
      outline: Color(0xFFE8EEF6),
      outlineSoft: Color(0xFFF3F8FF),
      navIndicator: Color(0xFFE8EEF6),
      chipBackground: Color(0xFFF1F5F9),
      chipSelected: Color(0xFFE8EEF6),
      heroBackground: Color(0xFF475569),
      heroMutedText: Color(0xFFD7E3F1),
      heroAvatarBackground: Color(0xFFF3F8FF),
      heroAvatarForeground: Color(0xFF475569),
    ),
    AppThemePreset.mist: const AppThemePalette(
      id: AppThemePreset.mist,
      label: '晨雾蓝',
      description: '更柔和、更亮一点的办公感。',
      preview: [Color(0xFF7C8EA3), Color(0xFF60A5FA), Color(0xFFF8FBFF)],
      primary: Color(0xFF7C8EA3),
      secondary: Color(0xFF5AA2FF),
      background: Color(0xFFF8FBFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF223046),
      textMuted: Color(0xFF6B7D94),
      outline: Color(0xFFE6EEF8),
      outlineSoft: Color(0xFFF4F8FD),
      navIndicator: Color(0xFFEAF2FD),
      chipBackground: Color(0xFFF3F7FC),
      chipSelected: Color(0xFFE6EEF8),
      heroBackground: Color(0xFF5E738C),
      heroMutedText: Color(0xFFDCE7F4),
      heroAvatarBackground: Color(0xFFF4F8FD),
      heroAvatarForeground: Color(0xFF5E738C),
    ),
    AppThemePreset.sky: const AppThemePalette(
      id: AppThemePreset.sky,
      label: '晴空蓝',
      description: '强调更清晰，界面更明快。',
      preview: [Color(0xFF5F7FA6), Color(0xFF2563EB), Color(0xFFF7FAFF)],
      primary: Color(0xFF5F7FA6),
      secondary: Color(0xFF3B82F6),
      background: Color(0xFFF7FAFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1F2E43),
      textMuted: Color(0xFF61748E),
      outline: Color(0xFFE1EAF7),
      outlineSoft: Color(0xFFF1F6FF),
      navIndicator: Color(0xFFE4EEFE),
      chipBackground: Color(0xFFF0F5FE),
      chipSelected: Color(0xFFE1EAF7),
      heroBackground: Color(0xFF44638A),
      heroMutedText: Color(0xFFD9E5F6),
      heroAvatarBackground: Color(0xFFF1F6FF),
      heroAvatarForeground: Color(0xFF44638A),
    ),
    AppThemePreset.sand: const AppThemePalette(
      id: AppThemePreset.sand,
      label: '轻砂米白',
      description: '更温和的中性浅色，不刺眼。',
      preview: [Color(0xFF8A8174), Color(0xFF4F8CBF), Color(0xFFFCFAF6)],
      primary: Color(0xFF8A8174),
      secondary: Color(0xFF5B9BD5),
      background: Color(0xFFFCFAF6),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF332E27),
      textMuted: Color(0xFF7B746A),
      outline: Color(0xFFEEE6DB),
      outlineSoft: Color(0xFFF8F3EB),
      navIndicator: Color(0xFFF1EBE1),
      chipBackground: Color(0xFFF7F2EA),
      chipSelected: Color(0xFFEEE6DB),
      heroBackground: Color(0xFF71675A),
      heroMutedText: Color(0xFFF0E7D7),
      heroAvatarBackground: Color(0xFFF8F3EB),
      heroAvatarForeground: Color(0xFF71675A),
    ),
  };

  final SharedPreferences _preferences;
  AppThemePreset _preset = AppThemePreset.rational;

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
    _preset = AppThemePreset.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => AppThemePreset.rational,
    );
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
