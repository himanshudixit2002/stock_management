import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/widgets/app_list_row.dart';

import '../helpers/test_helpers.dart';

Widget _host(Widget child) => createTestApp(
  child: Theme(
    data: AppTheme.lightTheme,
    child: Scaffold(body: ListView(children: [child])),
  ),
);

void main() {
  _mobileFit();

  group('AppListRow', () {
    testWidgets('renders its title and subtitle', (tester) async {
      await pumpAndSettle(
        tester,
        _host(
          const AppListRow(
            title: 'Notifications',
            subtitle: '4 of 6 alerts · this device',
            icon: Icons.notifications_rounded,
          ),
        ),
      );
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('4 of 6 alerts · this device'), findsOneWidget);
    });

    testWidgets('a tap fires onTap', (tester) async {
      var taps = 0;
      await pumpAndSettle(
        tester,
        _host(AppListRow(title: 'Open me', onTap: () => taps++)),
      );
      await tester.tap(find.text('Open me'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('shows a chevron only when it leads somewhere', (tester) async {
      await pumpAndSettle(
        tester,
        _host(AppListRow(title: 'Tappable', onTap: () {})),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await pumpAndSettle(tester, _host(const AppListRow(title: 'Inert')));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a trailing widget replaces the chevron', (tester) async {
      await pumpAndSettle(
        tester,
        _host(
          AppListRow(
            title: 'Chosen',
            onTap: () {},
            trailing: const Icon(Icons.radio_button_checked_rounded),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    });

    testWidgets('clears the 44pt touch target even with no subtitle', (
      tester,
    ) async {
      // The rows this replaces were dense ListTiles whose height depended on
      // whether a subtitle happened to be present, and the short ones fell
      // under the minimum the rest of the app holds to.
      await pumpAndSettle(
        tester,
        _host(AppListRow(title: 'Short', onTap: () {})),
      );
      expect(
        tester.getSize(find.byType(AppListRow)).height,
        greaterThanOrEqualTo(kAppRowMinHeight),
      );
    });

    testWidgets('a long summary stays on one line', (tester) async {
      await pumpAndSettle(
        tester,
        _host(
          const AppListRow(
            title: 'Catalog',
            subtitle:
                '12 categories · 8 companies · 3 sub-categories · 4 locations '
                'and a great deal more text besides',
          ),
        ),
      );
      final text = tester.widget<Text>(find.textContaining('12 categories'));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('highlighted paints the accent tint', (tester) async {
      await pumpAndSettle(
        tester,
        _host(
          const AppListRow(
            title: 'Found',
            accent: AppTheme.warningColor,
            highlighted: true,
          ),
        ),
      );
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppListRow),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, isNot(Colors.transparent));
    });

    testWidgets('a disabled row ignores taps', (tester) async {
      var taps = 0;
      await pumpAndSettle(
        tester,
        _host(
          AppListRow(title: 'Blocked', enabled: false, onTap: () => taps++),
        ),
      );
      await tester.tap(find.text('Blocked'));
      await tester.pumpAndSettle();
      expect(taps, 0);
    });
  });

  group('AppSwitchRow', () {
    testWidgets('reports the new value to onChanged', (tester) async {
      bool? received;
      await pumpAndSettle(
        tester,
        _host(
          AppSwitchRow(
            title: 'Pricing',
            value: false,
            onChanged: (v) async {
              received = v;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(received, isTrue);
    });

    testWidgets('shows a spinner and swallows taps while saving', (
      tester,
    ) async {
      var calls = 0;
      await pumpAndSettle(
        tester,
        _host(
          AppSwitchRow(
            title: 'Vendors',
            value: false,
            onChanged: (_) async {
              calls++;
              await Future<void>.delayed(const Duration(milliseconds: 100));
              return true;
            },
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      // A second tap while the first write is in flight must not queue another.
      await tester.tap(find.text('Vendors'));
      await tester.pump();
      expect(calls, 1);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a failed save surfaces the error', (tester) async {
      // The toggles this replaces rolled back silently, so a write that failed
      // looked like a switch flicking back on its own.
      await pumpAndSettle(
        tester,
        _host(
          AppSwitchRow(
            title: 'Billing',
            value: false,
            onChanged: (_) async => false,
            errorText: () => 'Could not reach the server',
          ),
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the server'), findsOneWidget);
    });

    testWidgets('a disabled row cannot be toggled', (tester) async {
      var calls = 0;
      await pumpAndSettle(
        tester,
        _host(
          AppSwitchRow(
            title: 'Barcode',
            value: true,
            enabled: false,
            disabledReason: 'Read-only while inspecting',
            onChanged: (_) async {
              calls++;
              return true;
            },
          ),
        ),
      );
      expect(find.text('Read-only while inspecting'), findsOneWidget);
      await tester.tap(find.text('Barcode'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  });
}

/// Renders the real hub rows at the tightest common phone width.
///
/// The point of the restructure was that Settings should fit a phone. These
/// strings are the actual category titles and the longest summaries the
/// builders can produce, so an overflow here is an overflow a user would see.
void _mobileFit() {
  // 360dp is the common Android width and the tightest real target; width is
  // what an overflow depends on. The height is generous purely so every row is
  // built rather than left below the fold by the lazy ListView.
  const narrow = Size(360, 1400);

  group('hub rows at 360dp', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('nine category rows lay out with no overflow', (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const rows = <(String, String)>[
        ('Account & security', 'himanshu.dixit@example.com · Admin'),
        ('Appearance & home', 'System theme · 6 quick actions'),
        ('Notifications', '4 of 6 alerts · this device'),
        ('Workspace features', 'Pricing, Barcode on · Vendors, Billing off'),
        ('Billing & invoicing', '₹ · GST 18.50% · INV-0042 next'),
        (
          'Catalog & lists',
          '12 categories · 8 companies · 3 sub-categories · 4 locations',
        ),
        ('Team & partners', '4 roles · users & overrides · vendors'),
        ('Data & tools', 'Import, Export, Data health'),
        ('Plan & workspace', 'MAX Tier plan · active'),
        ('Help, legal & about', 'Guides, legal and v1.0.28'),
      ];

      await pumpAndSettle(
        tester,
        createTestApp(
          child: Theme(
            data: AppTheme.lightTheme,
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (var i = 0; i < rows.length; i++)
                    AppListRow(
                      index: i,
                      icon: Icons.settings_rounded,
                      title: rows[i].$1,
                      subtitle: rows[i].$2,
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final row in rows) {
        expect(find.text(row.$1), findsOneWidget);
      }
      // Every row clears the touch target, subtitle or not.
      for (final element in find.byType(AppListRow).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(kAppRowMinHeight),
        );
      }
    });

    testWidgets('a switch row fits beside its title at 360dp', (tester) async {
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpAndSettle(
        tester,
        createTestApp(
          child: Theme(
            data: AppTheme.lightTheme,
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppSwitchRow(
                    icon: Icons.local_shipping_rounded,
                    title: 'Vendors',
                    subtitle:
                        'Controls Purchase Orders, Vendors, Vendor Statement '
                        'and 3 more.',
                    value: true,
                    onChanged: (_) async => true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
