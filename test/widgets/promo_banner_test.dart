import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/models/promo_config_model.dart';
import 'package:stock_management/providers/promo_provider.dart';
import 'package:stock_management/services/promo_service.dart';
import 'package:stock_management/widgets/promo_banner.dart';

import '../helpers/test_helpers.dart';

/// Pumps past the entrance animation without settling.
///
/// The banner wraps its content in FadeSlideIn, whose flutter_animate driver
/// leaves a periodic timer that pumpAndSettle never considers finished.
Future<void> _pumpBanner(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Returns a fixed offer.
class _FakeService extends PromoService {
  _FakeService(this.config);

  final PromoConfig? config;

  @override
  Future<PromoConfig?> fetch() async => config;
}

/// Stands in for a denied or offline read. PromoService swallows failures and
/// returns null, so this mirrors what the widget actually sees.
class _FailingService extends PromoService {
  @override
  Future<PromoConfig?> fetch() async => null;
}

Widget _wrap(PromoService service, {bool compact = false}) => createTestApp(
  child: ChangeNotifierProvider<PromoProvider>(
    create: (_) => PromoProvider(service: service),
    child: Scaffold(body: PromoBanner(compact: compact)),
  ),
);

void main() {
  testWidgets('renders nothing when no offer is configured', (tester) async {
    await pumpAndSettle(tester, _wrap(_FakeService(null)));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders nothing when the offer is switched off', (tester) async {
    await pumpAndSettle(
      tester,
      _wrap(_FakeService(const PromoConfig(enabled: false, headline: 'Hi'))),
    );
    expect(find.text('Hi'), findsNothing);
  });

  testWidgets('renders nothing when the read fails', (tester) async {
    // A promotion is decoration; a config problem must never sit between
    // someone and a signup.
    await pumpAndSettle(tester, _wrap(_FailingService()));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows the headline and the claimed count under the cap', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      _wrap(
        _FakeService(
          const PromoConfig(
            enabled: true,
            headline: 'Founding member offer',
            subtext: 'Free MAX',
            capCount: 1000,
            claimedCount: 250,
          ),
        ),
      ),
    );
    expect(find.text('Founding member offer'), findsOneWidget);
    expect(find.textContaining('250 of 1000 claimed'), findsOneWidget);
    expect(find.textContaining('750 left'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('switches to the full copy and drops the progress bar at the cap',
      (tester) async {
    await _pumpBanner(
      tester,
      _wrap(
        _FakeService(
          const PromoConfig(
            enabled: true,
            headline: 'Join now',
            fullHeadline: 'The founding cohort is full',
            fullSubtext: 'Still free while it lasts',
            capCount: 100,
            claimedCount: 100,
          ),
        ),
      ),
    );
    expect(find.text('The founding cohort is full'), findsOneWidget);
    expect(find.text('Join now'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('the compact variant shows the headline without the counter', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      _wrap(
        _FakeService(
          const PromoConfig(
            enabled: true,
            headline: 'Founding member offer',
            capCount: 1000,
            claimedCount: 250,
          ),
        ),
        compact: true,
      ),
    );
    expect(find.text('Founding member offer'), findsOneWidget);
    expect(find.textContaining('claimed'), findsNothing);
  });
}
