import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/auth/presentation/auth_gate.dart';

class NexdoApp extends StatelessWidget {
  const NexdoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF126A5A),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF126A5A),
          onPrimary: Colors.white,
          secondary: const Color(0xFFE58A3A),
          onSecondary: Colors.white,
          surface: const Color(0xFFFFFCF7),
          onSurface: const Color(0xFF16322C),
          surfaceContainerHighest: const Color(0xFFE9F0EA),
          outline: const Color(0xFFD6E0DA),
          outlineVariant: const Color(0xFFE6ECE8),
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
        scaffoldBackgroundColor: const Color(0xFFF7F4EC),
        canvasColor: const Color(0xFFF7F4EC),
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
            color: const Color(0xFF23433B),
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            height: 1.4,
            color: const Color(0xFF476058),
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            height: 1.35,
            color: const Color(0xFF60716B),
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
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            textStyle: baseTextTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: baseTextTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: BorderSide(color: colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: baseTextTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFCF7),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE4EAE4)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16322C),
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
              color: selected
                  ? const Color(0xFF126A5A)
                  : const Color(0xFF60716B),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 22,
              color: selected
                  ? const Color(0xFF126A5A)
                  : const Color(0xFF60716B),
            );
          }),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          backgroundColor: const Color(0xFFFFFCF7),
          indicatorColor: const Color(0xFFE3EEE9),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFFFFFCF7),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFFFFFCF7),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF2F5F1),
          selectedColor: const Color(0xFFDCEEE6),
          surfaceTintColor: Colors.transparent,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          labelStyle: baseTextTheme.bodySmall?.copyWith(
            color: const Color(0xFF476058),
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFCF7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          labelStyle: baseTextTheme.bodyMedium?.copyWith(
            color: const Color(0xFF60716B),
            height: 1.1,
          ),
          floatingLabelStyle: baseTextTheme.bodySmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE1E7E2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE1E7E2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFB85C38)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFB85C38), width: 1.4),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
