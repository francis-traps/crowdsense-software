import 'package:flutter/material.dart';

class AppColors {
  // Primary Brand Colors
  // Primary Brand Colors
  static const Color primaryBlue = Color(0xFF3B82F6); // Vibrant Blue
  static const Color primaryDark = Color(0xFF1A1F2C); // Main Background

  // Secondary/Accent
  static const Color accentBlue = Color(0xFF60A5FA); // Light Blue
  static const Color accentCyan = Color(0xFF06B6D4); // Cyan accent

  // Backgrounds & Surface
  static const Color backgroundDark = Color(0xFF0F172A); // Deep Navy/Slate (Slate 900)
  static const Color surfaceDark = Color(0xFF1E293B); // Dark Slate Blue (Slate 800)
  static const Color backgroundLight = Color(0xFFF8FAFC); // Very soft cool white
  static const Color surfaceLight = Color(0xFFFFFFFF); // Pure white cards
  static const Color surfaceGlass = Color(0x1AFFFFFF); // Semi-transparent white for glassmorphism

  // Text Colors
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFF9CA3AF);
  static const Color textDark = Color(0xFF1E1E2C);

  // Status Colors
  static const Color statusSafe = Color(0xFF10B981);    // Emerald Green
  static const Color statusWarning = Color(0xFFF59E0B); // Amber
  static const Color statusDanger = Color(0xFFEF4444);  // Red
  static const Color statusInactive = Color(0xFF6B7280); // Gray

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryBlue, accentBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient darkGradient = LinearGradient(
    colors: [backgroundDark, Color(0xFF1E293B)], // Navy to Slate Blue
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient lightGradient = LinearGradient(
    colors: [Color(0xFFF9FAFB), Color(0xFFDDE6ED)], // Slight light slate and slightly more opaque cool slate
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
