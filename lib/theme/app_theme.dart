import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF003289),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFF0047BA),
        onPrimaryContainer: Color(0xFFAEC1FF),
        secondary: Color(0xFF5B5F62),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFDDE0E3),
        onSecondaryContainer: Color(0xFF5F6366),
        tertiary: Color(0xFF00422B),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFF005C3E),
        onTertiaryContainer: Color(0xFF49DA9F),
        error: Color(0xFFBA1A1A),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF93000A),
        surface: Color(0xFFF8F9FF),
        onSurface: Color(0xFF121C2A),
        surfaceContainerHighest: Color(0xFFD9E3F6),
        onSurfaceVariant: Color(0xFF434653),
        outline: Color(0xFF737685),
        outlineVariant: Color(0xFFC3C6D6),
        inverseSurface: Color(0xFF27313F),
        onInverseSurface: Color(0xFFEAF1FF),
        inversePrimary: Color(0xFFB3C5FF),
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FF),
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF003289),
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFFFFFFFF),
        elevation: 4,
        shadowColor: Color(0x0A000000), // shadow-[0_4px_12px_0_rgba(0,0,0,0.04)]
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)), // rounded-xl mostly
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF003289),
          foregroundColor: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 56), // h-[56px] in HTML
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8F9FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC3C6D6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC3C6D6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF003289)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFB3C5FF),
        onPrimary: Color(0xFF002D7D),
        primaryContainer: Color(0xFF0047BA),
        onPrimaryContainer: Color(0xFFDBE1FF),
        secondary: Color(0xFFC3C7CA),
        onSecondary: Color(0xFF121C2A),
        secondaryContainer: Color(0xFF43474A),
        onSecondaryContainer: Color(0xFFDDE0E3),
        tertiary: Color(0xFF7BD0FF),
        onTertiary: Color(0xFF00354A),
        tertiaryContainer: Color(0xFF005777),
        onTertiaryContainer: Color(0xFF72CEFF),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF121C2A),
        onSurface: Color(0xFFEAF1FF),
        surfaceContainerHighest: Color(0xFF2D3449),
        onSurfaceVariant: Color(0xFFC3C6D6),
        outline: Color(0xFF8D919F),
        outlineVariant: Color(0xFF434653),
        inverseSurface: Color(0xFFEAF1FF),
        onInverseSurface: Color(0xFF121C2A),
        inversePrimary: Color(0xFF003289),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1326), // from dark tailwind config background
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF131B2E), // surface-container-low dark
        foregroundColor: Color(0xFFDAE2FD), // on-surface dark
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF2D3449), // surface-variant
        elevation: 4,
        shadowColor: Color(0x0A000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDBE1FF), // primary-fixed
          foregroundColor: const Color(0xFF00174A), // on-primary-fixed
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 56),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF131B2E), // inverse-surface/50 or similar
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8D919F)), // outline
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8D919F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2156C9)), // inverse-primary
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
