import 'package:flutter/material.dart';

class C {
  static const cream = Color(0xFFFAF8F2);
  static const ink = Color(0xFF232421);
  static const muted = Color(0xFF6B6D65);
  static const sage = Color(0xFFDCEFD2);
  static const sky = Color(0xFFDCEEFB);
  static const peach = Color(0xFFFDE3CF);
  static const lavender = Color(0xFFEAE2F8);
  static const butter = Color(0xFFFDF2C5);
  static const night = Color(0xFF2B3544);
  static const btn = Color(0xFF1F201D);
  static const tangerine = Color(0xFFF28C38);
  static const crimson = Color(0xFFC0392B);
  static const leaf = Color(0xFF5E9E4A);
}

TextStyle hs(double size, {Color color = C.ink, FontWeight w = FontWeight.w800}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color, height: 1.15);

TextStyle cap({double size = 13, Color color = C.muted, FontWeight w = FontWeight.w500}) =>
    TextStyle(fontSize: size, color: color, height: 1.3, fontWeight: w);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: C.cream,
      colorScheme: ColorScheme.fromSeed(seedColor: C.tangerine, surface: C.cream),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFF3F0E6),
        indicatorColor: C.peach,
        labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: C.ink)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.7),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
