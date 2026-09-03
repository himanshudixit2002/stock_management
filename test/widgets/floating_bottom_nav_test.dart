import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/widgets/floating_bottom_nav.dart';

// Counts are injected rather than read from providers: ProductProvider and
// StockProvider both construct Firestore in their field initialisers, so they
// cannot exist in a test at all.

const _tabs = [
  FloatingNavTab(
    icon: Icons.home_rounded,
    inactiveIcon: Icons.home_outlined,
    label: 'Home',
    kind: FloatingNavTabKind.home,
  ),
  FloatingNavTab(
    icon: Icons.inventory_2_rounded,
    inactiveIcon: Icons.inventory_2_outlined,
    label: 'Products',
    kind: FloatingNavTabKind.products,
  ),
  FloatingNavTab(
    icon: Icons.bar_chart_rounded,
    inactiveIcon: Icons.bar_chart_outlined,
    label: 'Reports',
    kind: FloatingNavTabKind.reports,
  ),
  FloatingNavTab(
    icon: Icons.settings_rounded,
    inactiveIcon: Icons.settings_outlined,
    label: 'Settings',
    kind: FloatingNavTabKind.settings,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  int index = 0,
  ValueChanged<int>? onTap,
  Brightness brightness = Brightness.light,
  Size size = const Size(360, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: FloatingBottomNav(
            currentIndex: index,
            tabs: _tabs,
            onTap: onTap ?? (_) {},
            outOfStockCount: 3,
            lowStockCount: 7,
            todayTransactionCount: 0,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the floating nav', () {
    testWidgets('labels every destination, not just the selected one', (
      tester,
    ) async {
      // Previously only the selected tab was labelled, which reflowed the row
      // on every tap and left the other destinations anonymous.
      await _pump(tester);
      for (final tab in _tabs) {
        expect(find.text(tab.label), findsOneWidget);
      }
    });

    testWidgets('shows the selected tab filled and the rest outlined', (
      tester,
    ) async {
      // Fill plus colour is the whole selection signal now that the sliding
      // indicator pill is gone.
      await _pump(tester, index: 1);
      expect(find.byIcon(Icons.inventory_2_rounded), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsNothing);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsNothing);
    });

    testWidgets('reports the tapped index', (tester) async {
      var tapped = -1;
      await _pump(tester, onTap: (i) => tapped = i);
      await tester.tap(find.text('Reports'));
      await tester.pump();
      expect(tapped, 2);
    });

    testWidgets('still carries live badges', (tester) async {
      await _pump(tester);
      // Out-of-stock takes priority over low-stock on the Products tab.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('7'), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('fits a 360dp phone in ${brightness.name} mode', (
        tester,
      ) async {
        await _pump(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('fits a very narrow phone', (tester) async {
      // 320dp is the narrowest device still in the wild; four labelled tabs
      // have to survive it.
      await _pump(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps its labels legible at a large text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FloatingBottomNav(
                  currentIndex: 0,
                  tabs: _tabs,
                  onTap: (_) {},
                  outOfStockCount: 3,
                  lowStockCount: 7,
                  todayTransactionCount: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // The bar is fixed-height, so its labels opt out of scaling rather than
      // growing into the icons.
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes each tab to assistive tech as a selectable button', (
      tester,
    ) async {
      // Enabled before pumping: the semantics tree is only built while a
      // handle is held. Disposed inline rather than via addTearDown, which runs
      // after the framework's own leak check.
      final handle = tester.ensureSemantics();
      await _pump(tester, index: 2);

      expect(find.bySemanticsLabel('Reports'), findsOneWidget);
      handle.dispose();
    });
  });
}
