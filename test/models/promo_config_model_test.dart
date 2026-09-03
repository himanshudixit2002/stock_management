import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/company_plan_model.dart';
import 'package:stock_management/models/promo_config_model.dart';

void main() {
  group('PromoConfig', () {
    test('a missing document yields a disabled offer', () {
      // The banner keys off `enabled`, so the safe default is "show nothing"
      // rather than advertising an offer nobody configured.
      final promo = PromoConfig.fromMap(null);
      expect(promo.enabled, isFalse);
      expect(promo.grantPlanId, PlanCatalog.maxId);
    });

    test('round-trips through toMap and fromMap', () {
      const original = PromoConfig(
        enabled: true,
        headline: 'Founding member',
        subtext: 'First 1000 workspaces',
        capCount: 1000,
        claimedCount: 250,
      );
      final restored = PromoConfig.fromMap(original.toMap());
      expect(restored.enabled, isTrue);
      expect(restored.headline, 'Founding member');
      expect(restored.capCount, 1000);
      expect(restored.claimedCount, 250);
    });

    test('reports progress and how many are left', () {
      const promo = PromoConfig(capCount: 1000, claimedCount: 250);
      expect(promo.progress, 0.25);
      expect(promo.remaining, 750);
      expect(promo.isFull, isFalse);
    });

    test('is full at the cap, and stays full past it', () {
      expect(
        const PromoConfig(capCount: 1000, claimedCount: 1000).isFull,
        isTrue,
      );
      expect(
        const PromoConfig(capCount: 1000, claimedCount: 1200).isFull,
        isTrue,
      );
    });

    test('an over-subscribed cohort clamps its progress bar', () {
      const promo = PromoConfig(capCount: 100, claimedCount: 400);
      expect(promo.progress, 1);
      expect(promo.remaining, 0);
    });

    test('an uncapped offer reports no progress rather than a full bar', () {
      const promo = PromoConfig(capCount: 0, claimedCount: 50);
      expect(promo.progress, isNull);
      expect(promo.isFull, isFalse);
    });

    test('the copy switches when the cohort fills', () {
      const promo = PromoConfig(
        headline: 'Join now',
        subtext: 'Free MAX',
        fullHeadline: 'Cohort full',
        fullSubtext: 'Still free for now',
        capCount: 10,
        claimedCount: 10,
      );
      expect(promo.activeHeadline, 'Cohort full');
      expect(promo.activeSubtext, 'Still free for now');
    });

    test('a malformed count reads as zero rather than throwing', () {
      // These documents are hand-edited from the console.
      final promo = PromoConfig.fromMap(const {
        'enabled': true,
        'capCount': 'lots',
        'claimedCount': null,
      });
      expect(promo.enabled, isTrue);
      expect(promo.capCount, 1000); // falls back to the default
      expect(promo.claimedCount, 0);
    });
  });
}
