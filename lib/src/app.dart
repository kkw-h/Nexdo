import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';

class NexdoApp extends StatefulWidget {
  const NexdoApp({super.key});

  @override
  State<NexdoApp> createState() => _NexdoAppState();
}

class _NexdoAppState extends State<NexdoApp> {
  AppThemeController? _themeController;

  @override
  void initState() {
    super.initState();
    _initializeTheme();
  }

  Future<void> _initializeTheme() async {
    final controller = await AppThemeController.create();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeController = controller;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _themeController;
    if (controller == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return AppThemeScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final palette = controller.palette;
          final colorScheme =
              ColorScheme.fromSeed(
                seedColor: palette.primary,
                brightness: Brightness.light,
              ).copyWith(
                primary: palette.primary,
                onPrimary: Colors.white,
                secondary: palette.secondary,
                onSecondary: Colors.white,
                secondaryContainer: palette.outlineSoft,
                onSecondaryContainer: palette.secondary,
                surface: palette.surface,
                onSurface: palette.onSurface,
                surfaceContainerHighest: palette.outline,
                outline: palette.outline,
                outlineVariant: palette.outlineSoft,
              );
          final baseTextTheme = ThemeData(
            useMaterial3: true,
            fontFamily: 'MiSans',
          ).textTheme;

          return MaterialApp(
            title: 'Nexdo',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            theme: ThemeData(
              colorScheme: colorScheme,
              scaffoldBackgroundColor: palette.background,
              canvasColor: palette.background,
              fontFamily: 'MiSans',
              useMaterial3: true,
              textTheme: baseTextTheme.copyWith(
                displaySmall: baseTextTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
                headlineSmall: baseTextTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                titleLarge: baseTextTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                titleMedium: baseTextTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                labelLarge: baseTextTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                bodyLarge: baseTextTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  color: palette.onSurface.withValues(alpha: 0.9),
                ),
                bodyMedium: baseTextTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: palette.textMuted,
                ),
                bodySmall: baseTextTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: palette.textMuted,
                ),
              ),
              appBarTheme: AppBarTheme(
                centerTitle: false,
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                titleTextStyle: baseTextTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.1,
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return colorScheme.secondary.withValues(alpha: 0.45);
                    }
                    if (states.contains(WidgetState.pressed)) {
                      return colorScheme.secondary.withValues(alpha: 0.92);
                    }
                    return colorScheme.secondary;
                  }),
                  foregroundColor: WidgetStateProperty.all(
                    colorScheme.onPrimary,
                  ),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return Colors.white.withValues(alpha: 0.12);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return Colors.white.withValues(alpha: 0.08);
                    }
                    return null;
                  }),
                  elevation: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return 0;
                    }
                    return 3;
                  }),
                  shadowColor: WidgetStateProperty.all(
                    colorScheme.secondary.withValues(alpha: 0.28),
                  ),
                  surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                  textStyle: WidgetStateProperty.all(
                    baseTextTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(const Size(0, 44)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  foregroundColor: WidgetStateProperty.all(palette.secondary),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return palette.outlineSoft.withValues(alpha: 0.9);
                    }
                    return Colors.transparent;
                  }),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return palette.secondary.withValues(alpha: 0.08);
                    }
                    return null;
                  }),
                  textStyle: WidgetStateProperty.all(
                    baseTextTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return BorderSide(
                        color: palette.secondary.withValues(alpha: 0.45),
                      );
                    }
                    return BorderSide(color: colorScheme.outline);
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  foregroundColor: WidgetStateProperty.all(palette.secondary),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return palette.outlineSoft;
                    }
                    return palette.surface;
                  }),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return palette.secondary.withValues(alpha: 0.06);
                    }
                    return null;
                  }),
                  textStyle: WidgetStateProperty.all(
                    baseTextTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              segmentedButtonTheme: SegmentedButtonThemeData(
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return BorderSide(color: palette.outline);
                    }
                    return BorderSide(color: palette.outline);
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return palette.surface;
                    }
                    return palette.background;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return palette.secondary;
                    }
                    return palette.textMuted;
                  }),
                  textStyle: WidgetStateProperty.all(
                    baseTextTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              cardTheme: CardThemeData(
                color: palette.surface,
                elevation: 0,
                margin: EdgeInsets.zero,
                shadowColor: const Color(0x14293B52),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: palette.outline),
                ),
              ),
              snackBarTheme: SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
                backgroundColor: palette.onSurface,
                contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              navigationBarTheme: NavigationBarThemeData(
                height: 72,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return baseTextTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? palette.secondary : palette.textMuted,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: 22,
                    color: selected ? palette.secondary : palette.textMuted,
                  );
                }),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                backgroundColor: palette.surface,
                indicatorColor: palette.navIndicator,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: colorScheme.secondary,
                foregroundColor: Colors.white,
                extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
                elevation: 4,
                focusElevation: 5,
                hoverElevation: 5,
                highlightElevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              iconButtonTheme: IconButtonThemeData(
                style: ButtonStyle(
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return palette.secondary.withValues(alpha: 0.08);
                    }
                    return null;
                  }),
                ),
              ),
              bottomSheetTheme: BottomSheetThemeData(
                backgroundColor: palette.surface,
                surfaceTintColor: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: palette.surface,
                surfaceTintColor: Colors.transparent,
                shadowColor: const Color(0x1A293B52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              chipTheme: ChipThemeData(
                backgroundColor: palette.chipBackground,
                selectedColor: palette.chipSelected,
                surfaceTintColor: Colors.transparent,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                labelStyle: baseTextTheme.bodySmall?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: palette.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                labelStyle: baseTextTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                  height: 1.1,
                ),
                floatingLabelStyle: baseTextTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: palette.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: palette.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFB91C1C)),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Color(0xFFB91C1C),
                    width: 1.4,
                  ),
                ),
              ),
              dividerTheme: DividerThemeData(
                color: palette.outline,
                thickness: 1,
                space: 1,
              ),
            ),
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}
