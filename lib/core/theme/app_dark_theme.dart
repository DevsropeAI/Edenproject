import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class EdenDarkTheme {
  static final data = _build();

  static ThemeData _build() {
    const colors = ColorScheme.dark(
      primary: EdenDarkColors.accent,
      onPrimary: EdenDarkColors.text,
      secondary: EdenDarkColors.accent,
      surface: EdenDarkColors.surface,
      onSurface: EdenDarkColors.text,
      error: EdenDarkColors.error,
    );

    final fontFamily = GoogleFonts.bebasNeue().fontFamily;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['NotoNastaliqUrdu'],
      textTheme: EdenTypography.textTheme,
      scaffoldBackgroundColor: EdenDarkColors.background,
    );

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(EdenRadius.field),
      borderSide: BorderSide(color: color),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: GoogleFonts.bebasNeue(
          color: EdenDarkColors.text,
          fontSize: 22,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EdenDarkColors.glass,
        contentPadding: const EdgeInsets.all(EdenSpacing.screen),
        constraints: const BoxConstraints(minHeight: EdenSpacing.control),
        border: border(EdenDarkColors.strongGlass),
        enabledBorder: border(EdenDarkColors.strongGlass),
        focusedBorder: border(EdenDarkColors.accent),
        errorBorder: border(EdenDarkColors.error),
        focusedErrorBorder: border(EdenDarkColors.error),
        labelStyle: GoogleFonts.bebasNeue(color: EdenDarkColors.secondary),
        prefixIconColor: EdenDarkColors.secondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(GoogleFonts.bebasNeue(fontSize: 18)),
          minimumSize: const WidgetStatePropertyAll(
            Size(48, EdenSpacing.control),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled))
              return EdenDarkColors.strongGlass;
            if (states.contains(WidgetState.pressed))
              return EdenDarkColors.pressed;
            return EdenDarkColors.accent;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: EdenDarkColors.text,
          minimumSize: const Size(48, EdenSpacing.control),
          side: const BorderSide(color: EdenDarkColors.outline),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.bebasNeue(fontSize: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, EdenSpacing.target),
          textStyle: GoogleFonts.bebasNeue(fontSize: 16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: EdenDarkColors.surface,
        contentTextStyle: GoogleFonts.bebasNeue(color: EdenDarkColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EdenRadius.field),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: EdenDarkColors.surface,
        titleTextStyle: GoogleFonts.bebasNeue(fontSize: 22, color: EdenDarkColors.text),
        contentTextStyle: GoogleFonts.bebasNeue(fontSize: 16, color: EdenDarkColors.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EdenRadius.card),
          side: const BorderSide(color: EdenDarkColors.strongGlass),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: EdenDarkColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(EdenRadius.card),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.bebasNeue(fontSize: 14, color: EdenDarkColors.text),
        ),
      ),
      textTheme: EdenTypography.textTheme,
    );
  }
}