import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

extension UppercaseText on String {
  String get upper => toUpperCase();
}

abstract final class EdenTypography {
  static final _displayFont = GoogleFonts.bebasNeue().fontFamily;
  static final _bodyFont = GoogleFonts.oswald().fontFamily;

  static TextTheme get textTheme => ThemeData.dark().textTheme.apply(
    fontFamily: _bodyFont,
    fontFamilyFallback: const ['NotoNastaliqUrdu'],
  ).copyWith(
    displayLarge: GoogleFonts.bebasNeue(fontSize: 40, color: AppColors.textPrimary),
    displayMedium: GoogleFonts.bebasNeue(fontSize: 32, color: AppColors.textPrimary),
    displaySmall: GoogleFonts.bebasNeue(fontSize: 28, color: AppColors.textPrimary),
    headlineLarge: GoogleFonts.bebasNeue(fontSize: 32, color: AppColors.textPrimary),
    headlineMedium: GoogleFonts.bebasNeue(fontSize: 24, color: AppColors.textPrimary),
    titleLarge: GoogleFonts.bebasNeue(fontSize: 22, color: AppColors.textPrimary),
    titleMedium: GoogleFonts.bebasNeue(fontSize: 18, color: AppColors.textPrimary),
    bodyLarge: GoogleFonts.oswald(fontSize: 16, color: AppColors.textPrimary),
    bodyMedium: GoogleFonts.oswald(fontSize: 14, color: AppColors.textPrimary),
    bodySmall: GoogleFonts.oswald(fontSize: 13, color: AppColors.textSecondary),
    labelLarge: GoogleFonts.bebasNeue(fontSize: 15, color: AppColors.textPrimary),
  );

  static TextStyle get amount => GoogleFonts.oswald(
    fontSize: 24,
    color: AppColors.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}