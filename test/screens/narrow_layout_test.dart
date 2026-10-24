import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/feature_map.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/screens/home/home_sections.dart';
import 'package:stock_management/widgets/empty_state_widget.dart';
import 'package:stock_management/widgets/feature_tour.dart';
import 'package:stock_management/widgets/tab_context_header.dart';

/// Pumps [child] at [width] with the text scaled by [textScale], and fails on
/// any layout exception (a RenderFlex overflow is reported as one in tests).
Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required double width,
  double height = 800,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
}

/// The quick action grid as Home lays it out: three columns on a phone.
Widget _actionGrid() => LayoutBuilder(
  builder: (context, constraints) {
    const spacing = 10.0;
    final cardWidth = (constraints.maxWidth - spacing * 2) / 3;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final label in const [
          'Fast POS',
          'Hold Dashboard',
          'Billing Reports',
          'Purchase Orders',
          'Release Hold',
          'Customers',
        ])
          SizedBox(
            width: cardWidth,
            child: HomeActionCard(
              icon: Icons.bolt_rounded,
              label: label,
              gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryDark],
              ),
              onTap: () {},
            ),
          ),
      ],
    );
  },
);

/// The two-column feature tiles a phone shows under each Home category.
Widget _tileGrid() => LayoutBuilder(
  builder: (context, constraints) {
    const spacing = 10.0;
    final cardWidth = (constraints.maxWidth - spacing) / 2;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final label in const [
          'Inventory Valuation',
          'Bills of Materials',
          'Purchase Orders',
          'Pick, Pack & Ship',
        ])
          SizedBox(
            width: cardWidth,
            child: HomeNavTile(
              icon: Icons.layers_rounded,
              label: label,
              onTap: () {},
            ),
          ),
      ],
    );
  },
);

void main() {
  for (final width in const [320.0, 360.0, 390.0]) {
    for (final scale in const [1.0, 1.4]) {
      testWidgets('Home quick actions fit $width px at ${scale}x', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          Padding(padding: const EdgeInsets.all(16), child: _actionGrid()),
          width: width,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Home feature tiles fit $width px at ${scale}x', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          Padding(padding: const EdgeInsets.all(16), child: _tileGrid()),
          width: width,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('an empty state scrolls instead of overflowing a short box', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const SizedBox(
        height: 180,
        child: EmptyStateWidget(
          icon: Icons.receipt_long_rounded,
          title: 'No invoices yet',
          subtitle: 'Create your first invoice to get started',
          buttonText: 'New invoice',
          onButtonPressed: _noop,
        ),
      ),
      width: 360,
      textScale: 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tab header with shortcuts fits at 1.4x', (tester) async {
    await _pumpAt(
      tester,
      CompactTabHeader(
        icon: Icons.analytics_rounded,
        title: 'Reports',
        subtitle: 'Select a tab below or choose a deep report shortcut.',
        initiallyExpanded: true,
        shortcuts: [
          for (final id in const ['profitLoss', 'deadStock', 'dashboard'])
            FeatureMap.getById(id)!,
        ],
      ),
      width: 360,
      textScale: 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  group('the first-run tour', () {
    testWidgets('describes only what this user has', (tester) async {
      await _pumpAt(
        tester,
        FeatureTour(
          onComplete: () {},
          navigation: const FeatureTourNavigation(
            tabLabels: ['Home', 'Products', 'Settings'],
            isWide: false,
            hasQuickActions: false,
          ),
        ),
        width: 360,
        height: 700,
        textScale: 1.4,
      );
      expect(tester.takeException(), isNull);
      // No quick actions: the tour starts with the feature tiles.
      expect(find.text('Find Everything'), findsOneWidget);
      expect(find.textContaining('+ button'), findsNothing);
      expect(find.bySemanticsLabel('Next, step 1 of 4'), findsOneWidget);
    });

    testWidgets('names the tabs the user actually has', (tester) async {
      await _pumpAt(
        tester,
        FeatureTour(
          onComplete: () {},
          navigation: const FeatureTourNavigation(
            tabLabels: ['Home', 'Products', 'Settings'],
            isWide: false,
          ),
        ),
        width: 360,
        height: 700,
      );
      // Each step fades out, then the next one is built and fades in.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 800));
      }
      expect(
        find.text(
          'Switch between Home, Products and Settings from the bar at the '
          'bottom.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Reports'), findsNothing);
    });
  });
}

void _noop() {}
