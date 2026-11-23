import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      // Apply Inter globally
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoNastaliqUrdu'],
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        brightness: Brightness.dark,
      ),
      
      scaffoldBackgroundColor: AppColors.background,
      
      textTheme: TextTheme(
        displayLarge: GoogleFonts.bebasNeue(fontSize: 40, color: AppColors.textPrimary),
        displayMedium: GoogleFonts.bebasNeue(fontSize: 32, color: AppColors.textPrimary),
        displaySmall: GoogleFonts.bebasNeue(fontSize: 28, color: AppColors.textPrimary),
        headlineLarge: GoogleFonts.bebasNeue(fontSize: 24, color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.bebasNeue(fontSize: 20, color: AppColors.textPrimary),
        titleLarge: GoogleFonts.bebasNeue(fontSize: 18, color: AppColors.textPrimary),
        
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
        
        labelLarge: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.bebasNeue(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF111111),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.bebasNeue(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}