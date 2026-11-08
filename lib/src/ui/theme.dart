import 'package:flutter/material.dart';

import '../core/verdict.dart';

const _seed = Color(0xFF4F46B5);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
  );
}

/// Kararın rengi, simgesi ve kısa açıklaması. Renk tek başına anlam taşımaz:
/// her durumda etiket metni de gösterilir.
class DecisionStyle {
  const DecisionStyle(this.color, this.onColor, this.icon, this.tagline);
  final Color color;
  final Color onColor;
  final IconData icon;
  final String tagline;

  static DecisionStyle of(Decision d, Brightness b) {
    final dark = b == Brightness.dark;
    switch (d) {
      case Decision.selfDo:
        return DecisionStyle(dark ? const Color(0xFF3B2F6E) : const Color(0xFFE9E3FF),
            dark ? const Color(0xFFE9E3FF) : const Color(0xFF2B1D6B), Icons.back_hand_outlined, 'Bu iş senin sesin, senin kasın.');
      case Decision.limited:
        return DecisionStyle(dark ? const Color(0xFF5A4300) : const Color(0xFFFFF0C2),
            dark ? const Color(0xFFFFF0C2) : const Color(0xFF4A3500), Icons.handshake_outlined, 'Önce sen, sonra küçük bir yardım.');
      case Decision.delegate:
        return DecisionStyle(dark ? const Color(0xFF14532D) : const Color(0xFFDDF6E4),
            dark ? const Color(0xFFDDF6E4) : const Color(0xFF0F3D22), Icons.smart_toy_outlined, 'Makine işi; kontrol yine sende.');
    }
  }
}
