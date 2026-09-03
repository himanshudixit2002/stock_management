import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/config/theme.dart';
import 'package:stock_management/models/promo_config_model.dart';
import 'package:stock_management/providers/promo_provider.dart';
import 'package:stock_management/screens/landing_screen.dart';
import 'package:stock_management/services/promo_service.dart';

/// A live offer without reaching Firestore — the banner loads on mount, and the
/// real service would sit on an uninitialised Firebase channel.
class _FakePromoService extends PromoService {
  @override
  Future<PromoConfig?> fetch() async => const PromoConfig(
    enabled: true,
    headline: 'Founding member offer — free MAX access',
    subtext:
        'The first 1000 workspaces get the full MAX plan, every feature, '
        'no limits, free.',
    capCount: 1000,
    claimedCount: 250,
  );
}

Widget _wrap(Widget child, {required Brightness brightness}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<PromoProvider>(
      create: (_) => PromoProvider(service: _FakePromoService()),
    ),
  ],
  child: MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    home: child,
  ),
);

void main() {
  // 360dp is the common Android width and the tightest real target. Inter is
  // fractionally wider than the platform fonts the app used to fall back to, so
  // adopting it exposed rows that had been fitting only by a hair — the
  // landing page's capabilities strip overflowed by 6px at this width.
  const narrow = Size(360, 720);

  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    Size size = narrow,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(child, brightness: brightness));
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('the landing page fits a narrow phone', () {
    for (final brightness in Brightness.values) {
      testWidgets('in ${brightness.name} mode', (tester) async {
        await pumpAt(tester, const LandingScreen(), brightness: brightness);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the landing page fits a tablet width', (tester) async {
    await pumpAt(tester, const LandingScreen(), size: const Size(768, 1024));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the landing page survives a large text scale', (tester) async {
    // The app clamps text scaling to 1.4x, so that is the real worst case.
    tester.view.physicalSize = narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PromoProvider>(
            create: (_) => PromoProvider(service: _FakePromoService()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: const LandingScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
  });
}
