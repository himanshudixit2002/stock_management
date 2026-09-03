import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/config/plan_limits.dart';
import 'package:stock_management/models/company_plan_model.dart';

void main() {
  group('PlanLimits.check', () {
    const starter = CompanyPlan(planId: PlanCatalog.starterId);
    const max = CompanyPlan(planId: PlanCatalog.maxId);

    test('a key the tier does not cap is always ok and reports no fraction', () {
      final result = PlanLimits.check(max, PlanLimitKeys.products, 999999);
      expect(result.state, PlanLimitState.ok);
      expect(result.isCapped, isFalse);
      expect(result.limit, isNull);
      expect(result.fraction, isNull);
      expect(result.usageText, '999999');
    });

    test('usage below four fifths of the cap is ok', () {
      // Starter caps products at 250; 199 is under the 200 warning threshold.
      final result = PlanLimits.check(starter, PlanLimitKeys.products, 199);
      expect(result.state, PlanLimitState.ok);
      expect(result.usageText, '199 / 250');
    });

    test('usage at exactly four fifths of the cap warns', () {
      final result = PlanLimits.check(starter, PlanLimitKeys.products, 200);
      expect(result.state, PlanLimitState.warning);
    });

    test('usage at the cap is blocked, not merely warned', () {
      // The boundary matters: enforce() runs before a write, so "at the cap"
      // has to refuse the next record rather than allow one more.
      final result = PlanLimits.check(starter, PlanLimitKeys.products, 250);
      expect(result.state, PlanLimitState.blocked);
      expect(result.isBlocked, isTrue);
    });

    test('usage past the cap clamps its fraction to 1', () {
      final result = PlanLimits.check(starter, PlanLimitKeys.products, 400);
      expect(result.state, PlanLimitState.blocked);
      expect(result.fraction, 1);
    });

    test('an override is what gets measured, not the tier value', () {
      const withHeadroom = CompanyPlan(
        planId: PlanCatalog.starterId,
        limitOverrides: {PlanLimitKeys.products: 1000},
      );
      final result = PlanLimits.check(
        withHeadroom,
        PlanLimitKeys.products,
        400,
      );
      expect(result.state, PlanLimitState.ok);
      expect(result.limit, 1000);
    });
  });

  group('PlanLimits.checkAll', () {
    test('reports every known cap, treating a missing usage key as zero', () {
      final results = PlanLimits.checkAll(
        const CompanyPlan(planId: PlanCatalog.starterId),
        const {PlanLimitKeys.products: 10},
      );
      expect(results, hasLength(PlanLimitKeys.all.length));
      final users = results.firstWhere((r) => r.key == PlanLimitKeys.users);
      expect(users.current, 0);
      expect(users.limit, 3);
    });
  });

  group('PlanLimits.enforce', () {
    test('lets a write through while there is headroom', () {
      expect(
        () => PlanLimits.enforce(
          const CompanyPlan(planId: PlanCatalog.starterId),
          PlanLimitKeys.products,
          10,
        ),
        returnsNormally,
      );
    });

    test('throws at the cap, naming the tier and the number', () {
      expect(
        () => PlanLimits.enforce(
          const CompanyPlan(planId: PlanCatalog.starterId),
          PlanLimitKeys.products,
          250,
        ),
        throwsA(
          isA<PlanLimitException>()
              .having((e) => e.limit, 'limit', 250)
              .having((e) => e.planLabel, 'planLabel', 'Starter')
              .having((e) => e.message, 'message', contains('Products')),
        ),
      );
    });

    test('never throws on a plan-less company, whatever the usage', () {
      // Every existing company doc has no plan field and reads as MAX. If this
      // regressed, introducing tiers would start refusing writes across the
      // whole tenant base.
      expect(
        () => PlanLimits.enforce(
          CompanyPlan.fromMap(null),
          PlanLimitKeys.products,
          1000000,
        ),
        returnsNormally,
      );
    });
  });
}
