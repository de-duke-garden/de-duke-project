/// De-Duke two-layer elevation/shadow system -- branding.md "Shadows &
/// Elevation". Every non-flat surface uses a tight contact shadow plus a
/// soft ambient shadow (two `BoxShadow`s), never a single flat shadow --
/// this is what separates "designed" elevation from default Material.
import 'package:flutter/material.dart';

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> none = [];

  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0D12201C), offset: Offset(0, 1), blurRadius: 1),
    BoxShadow(color: Color(0x0A12201C), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x1212201C), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0D12201C), offset: Offset(0, 4), blurRadius: 10),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x1412201C), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x1412201C), offset: Offset(0, 8), blurRadius: 20),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1A12201C), offset: Offset(0, 4), blurRadius: 8),
    BoxShadow(
        color: Color(0x2412201C), offset: Offset(0, 16), blurRadius: 36),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(color: Color(0x1F12201C), offset: Offset(0, 8), blurRadius: 16),
    BoxShadow(
        color: Color(0x2912201C), offset: Offset(0, 24), blurRadius: 48),
  ];

  static const List<BoxShadow> xsDark = [
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 1),
    BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> smDark = [
    BoxShadow(color: Color(0x73000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4), blurRadius: 10),
  ];

  static const List<BoxShadow> mdDark = [
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 8), blurRadius: 20),
  ];

  static const List<BoxShadow> lgDark = [
    BoxShadow(color: Color(0x8C000000), offset: Offset(0, 4), blurRadius: 8),
    BoxShadow(
        color: Color(0x8C000000), offset: Offset(0, 16), blurRadius: 36),
  ];

  static const List<BoxShadow> xlDark = [
    BoxShadow(color: Color(0x99000000), offset: Offset(0, 8), blurRadius: 16),
    BoxShadow(
        color: Color(0x99000000), offset: Offset(0, 24), blurRadius: 48),
  ];

  /// Returns the correct light/dark shadow list for a given token.
  static List<BoxShadow> of(List<BoxShadow> light, List<BoxShadow> dark,
          bool isDark) =>
      isDark ? dark : light;
}
