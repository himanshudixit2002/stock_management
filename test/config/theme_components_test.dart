import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';

/// The global component themes are applied to every screen at once, so a bad
/// one breaks pages nobody edited. These pump the widgets the densest screens
/// are built from — Reports is a scrollable TabBar with no Scaffold, Settings
/// is hundreds of dense ListTiles — and assert they still lay out.
Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: child,
    );

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('a scrollable TabBar lays out in ${brightness.name}', (
      tester,
    ) async {
      // Mirrors reports_screen.dart: a scrollable TabBar in a bare Column.
      // It renders inside the shell's Scaffold, which is what supplies the
      // Material ancestor here.
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          Scaffold(
            body: DefaultTabController(
            length: 4,
            child: Column(
              children: const [
                SafeArea(child: SizedBox.shrink()),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Analytics & Charts'),
                    Tab(text: 'Predictive Forecasting'),
                    Tab(text: 'Custom Report Builder'),
                  ],
                ),
                Expanded(child: TabBarView(children: [
                  SizedBox.shrink(),
                  SizedBox.shrink(),
                  SizedBox.shrink(),
                  SizedBox.shrink(),
                ])),
              ],
            ),
          ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dense ListTiles lay out in ${brightness.name}', (
      tester,
    ) async {
      // Settings sets dense + a negative visualDensity on its own tiles. A
      // global `minVerticalPadding` or `shape` in listTileTheme fights that,
      // which is why the theme deliberately sets neither.
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 12; i++)
                  ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: const Icon(Icons.settings_rounded),
                    title: Text('Setting $i'),
                    subtitle: const Text('A description that runs a little on'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('an ExpansionTile lays out in ${brightness.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          Scaffold(
            body: ListView(
              children: const [
                ExpansionTile(
                  title: Text('A group'),
                  children: [ListTile(title: Text('An item'))],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bottom sheet has exactly one drag handle in '
        '${brightness.name}', (tester) async {
      // SlideUpSheet draws its own handle, so the global
      // `showDragHandle` must stay off or those sheets get two.
      expect(
        (brightness == Brightness.dark
                ? AppTheme.darkTheme
                : AppTheme.lightTheme)
            .bottomSheetTheme
            .showDragHandle,
        isNot(true),
      );
    });
  }
}
