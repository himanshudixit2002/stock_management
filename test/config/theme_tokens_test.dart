import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';

/// Relative luminance per WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// A host that reports the requested brightness, so the `AppTheme.*(context)`
/// helpers can be exercised for both themes without pumping a whole app.
Future<BuildContext> _contextFor(WidgetTester tester, Brightness b) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: b == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  // MaterialApp lerps between themes via AnimatedTheme, so a test that builds
  // both brightnesses in turn reads a half-interpolated theme without this.
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('semantic colours are legible on their own ground', () {
    // The reason this test exists: the previous palette used a single hex for
    // each semantic colour on both themes, so danger and warning were
    // contrast-marginal against the dark background. Every one of them is now
    // a light/dark pair, and this is what stops that regressing.
    for (final brightness in Brightness.values) {
      testWidgets('in ${brightness.name} mode', (tester) async {
        final context = await _contextFor(tester, brightness);
        final ground = AppTheme.bg(context);

        final checks = <String, Color>{
          'primary': AppTheme.primary(context),
          'success': AppTheme.success(context),
          'warning': AppTheme.warning(context),
          'danger': AppTheme.danger(context),
          'info': AppTheme.info(context),
        };

        checks.forEach((name, color) {
          // 3:1 is the WCAG AA floor for large text and UI components, which is
          // what these are used for — status pills, icons, chart marks.
          expect(
            _contrast(color, ground),
            greaterThanOrEqualTo(3.0),
            reason:
                '$name (${color.toARGB32().toRadixString(16)}) against the '
                '${brightness.name} background is too low to read',
          );
        });
      });
    }
  });

  group('body and heading text clears AA on its own surface', () {
    for (final brightness in Brightness.values) {
      testWidgets('in ${brightness.name} mode', (tester) async {
        final context = await _contextFor(tester, brightness);
        final surface = AppTheme.surface(context);

        // 4.5:1 is the AA floor for body-size text.
        expect(
          _contrast(AppTheme.textPri(context), surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(AppTheme.textSec(context), surface),
          greaterThanOrEqualTo(4.5),
        );
        // Tertiary carries secondary information at body size, so it is held to
        // the same bar rather than the 3:1 large-text one.
        expect(
          _contrast(AppTheme.textTer(context), surface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('the type scale is complete', () {
    // Six slots used to be left null and silently fell back to the Material 3
    // baseline, which ignores the app's colours entirely.
    for (final entry in {
      'light': AppTheme.lightTheme,
      'dark': AppTheme.darkTheme,
    }.entries) {
      test('every TextTheme slot is defined in ${entry.key}', () {
        final t = entry.value.textTheme;
        final slots = <String, TextStyle?>{
          'displayLarge': t.displayLarge,
          'displayMedium': t.displayMedium,
          'displaySmall': t.displaySmall,
          'headlineLarge': t.headlineLarge,
          'headlineMedium': t.headlineMedium,
          'headlineSmall': t.headlineSmall,
          'titleLarge': t.titleLarge,
          'titleMedium': t.titleMedium,
          'titleSmall': t.titleSmall,
          'bodyLarge': t.bodyLarge,
          'bodyMedium': t.bodyMedium,
          'bodySmall': t.bodySmall,
          'labelLarge': t.labelLarge,
          'labelMedium': t.labelMedium,
          'labelSmall': t.labelSmall,
        };
        slots.forEach((name, style) {
          expect(style, isNotNull, reason: '$name is undefined');
          expect(style!.color, isNotNull, reason: '$name has no colour');
          expect(style.fontSize, isNotNull, reason: '$name has no size');
        });
      });

      test('${entry.key} uses the bundled typeface', () {
        // pubspec declares the family; if this drifts the app silently falls
        // back to the platform default, which is what it did before.
        expect(entry.value.textTheme.bodyMedium?.fontFamily, 'Inter');
      });
    }
  });

  group('elevation', () {
    testWidgets('is a shadow in light and nothing in dark', (tester) async {
      // On a near-black ground a drop shadow is invisible; depth there comes
      // from the tonal step between bg/surface/card plus the border.
      final light = await _contextFor(tester, Brightness.light);
      expect(AppTheme.shadowFor(light, level: 1), isNotEmpty);

      final dark = await _contextFor(tester, Brightness.dark);
      expect(AppTheme.shadowFor(dark, level: 1), isEmpty);
      expect(AppTheme.shadowFor(dark, level: 3), isEmpty);
    });

    testWidgets('dark mode separates its surfaces tonally', (tester) async {
      final context = await _contextFor(tester, Brightness.dark);
      // bg < surface < card, so stacked panels stay distinguishable without
      // shadows doing the work.
      expect(
        _luminance(AppTheme.surface(context)),
        greaterThan(_luminance(AppTheme.bg(context))),
      );
      expect(
        _luminance(AppTheme.card(context)),
        greaterThan(_luminance(AppTheme.surface(context))),
      );
    });
  });

  group('chart ramp', () {
    test('has a dark variant of the same length', () {
      expect(
        AppTheme.chartRampDark,
        hasLength(AppTheme.chartRampLight.length),
      );
    });

    testWidgets('every slice colour is visible on its own ground', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        final context = await _contextFor(tester, brightness);
        final ground = AppTheme.surface(context);
        for (final color in AppTheme.chartRamp(context)) {
          expect(
            _contrast(color, ground),
            greaterThanOrEqualTo(1.6),
            reason:
                '${color.toARGB32().toRadixString(16)} disappears into the '
                '${brightness.name} surface',
          );
        }
      }
    });
  });
}
