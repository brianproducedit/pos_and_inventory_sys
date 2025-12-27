import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/tokens.dart';
import 'dart:math' as math;

double _linearizeChannel(int channel) {
  final c = channel / 255.0;
  return (c <= 0.03928)
      ? (c / 12.92)
      : (math.pow((c + 0.055) / 1.055, 2.4) as double);
}

double _luminance(Color color) {
  final r = _linearizeChannel(color.red);
  final g = _linearizeChannel(color.green);
  final b = _linearizeChannel(color.blue);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final l1 = la > lb ? la : lb;
  final l2 = la > lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

// Dart's math pow requires import

void main() {
  test('Text on background contrast meets WCAG 4.5:1', () {
    final ratio = contrastRatio(AppColors.textBody, AppColors.background);
    expect(ratio >= 4.5, true,
        reason: 'textBody on background contrast $ratio < 4.5');
  });

  test('Primary action foreground (white) on primaryAction meets 4.5:1', () {
    final ratio = contrastRatio(Colors.white, AppColors.primaryAction);
    expect(ratio >= 4.5, true,
        reason: 'white on primaryAction contrast $ratio < 4.5');
  });

  test('Primary brand (AppColors.primaryBrand) works with white foreground',
      () {
    final ratio = contrastRatio(Colors.white, AppColors.primaryBrand);
    expect(ratio >= 4.5, true,
        reason: 'white on primaryBrand contrast $ratio < 4.5');
  });

  test('Secondary accent on background meets 4.5:1', () {
    final ratio =
        contrastRatio(AppColors.secondaryAccent, AppColors.background);
    expect(ratio >= 4.5, true,
        reason: 'secondaryAccent on background contrast $ratio < 4.5');
  });
}
