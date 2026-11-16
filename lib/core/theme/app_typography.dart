import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class EdenTypography {
  static TextTheme get textTheme => ThemeData.dark().textTheme
      .apply(fontFamily: GoogleFonts.inter().fontFamily)
      .copyWith(
        headlineLarge: GoogleFonts.montserrat(
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.montserrat(
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(fontSize: 15),
        bodyMedium: GoogleFonts.inter(fontSize: 14),
        bodySmall: GoogleFonts.inter(
          fontSize: 13,
          color: EdenDarkColors.secondary,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );

  static TextStyle get amount => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
