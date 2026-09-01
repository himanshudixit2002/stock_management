import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/company_model.dart';
import 'package:stock_management/models/company_plan_model.dart';

void main() {
  group('CompanyModel.fromMap backwards compatibility', () {
    test('a doc with no status and no plan reads as active and free', () {
      // This is exactly the shape of all 14 production company docs. If this
      // ever regresses, every existing workspace reads as suspended or
      // plan-less and the whole tenant base is locked out.
      final company = CompanyModel.fromMap({
        'companyName': 'Acme',
        'adminUid': 'u1',
        'permanentJoinCode': 'ABC123',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      }, 'c1');

      expect(company.status, CompanyStatus.active);
      expect(company.isUsable, isTrue);
      expect(company.plan.planId, PlanCatalog.freeId);
      expect(company.plan.status, PlanStatus.active);
      expect(company.plan.label, 'Free');
    });

    test('an entirely empty doc still yields a usable free company', () {
      final company = CompanyModel.fromMap({}, 'c1');
      expect(company.isUsable, isTrue);
      expect(company.plan.planId, PlanCatalog.freeId);
      expect(company.displayName, 'Unnamed workspace');
    });

    test('reads an explicit suspended status', () {
      final company = CompanyModel.fromMap(
        {'companyName': 'Acme', 'status': 'suspended', 'statusNote': 'unpaid'},
        'c1',
      );
      expect(company.status, CompanyStatus.suspended);
      expect(company.isUsable, isFalse);
      expect(company.statusNote, 'unpaid');
    });

    test('an unrecognised status falls back to active, never locking out', () {
      final company = CompanyModel.fromMap({'status': 'banana'}, 'c1');
      expect(company.status, CompanyStatus.active);
    });

    test('round-trips through toMap', () {
      final original = CompanyModel(
        id: 'c1',
        companyName: 'Acme',
        adminUid: 'u1',
        permanentJoinCode: 'ABC123',
        status: CompanyStatus.suspended,
        plan: const CompanyPlan(planId: 'free', note: 'trial'),
        createdAt: DateTime(2026, 1, 1),
        statusNote: 'unpaid',
      );
      final restored = CompanyModel.fromMap(original.toMap(), 'c1');

      expect(restored.companyName, 'Acme');
      expect(restored.status, CompanyStatus.suspended);
      expect(restored.plan.planId, 'free');
      expect(restored.plan.note, 'trial');
      expect(restored.statusNote, 'unpaid');
      expect(restored.createdAt, DateTime(2026, 1, 1));
    });

    test('toMap does not carry a settings key', () {
      // Company docs also hold a `settings` map owned by SettingsProvider and
      // BillingSettingsProvider. toMap must never claim to represent it, so
      // callers cannot accidentally clobber it with a whole-document write.
      expect(CompanyModel.fromMap({}, 'c1').toMap().containsKey('settings'),
          isFalse);
    });
  });

  group('CompanyPlan', () {
    test('a null plan map yields the free plan', () {
      final plan = CompanyPlan.fromMap(null);
      expect(plan.planId, PlanCatalog.freeId);
      expect(plan.isActive, isTrue);
    });

    test('an unknown planId still resolves to a usable definition', () {
      final plan = CompanyPlan.fromMap({'planId': 'enterprise-2030'});
      expect(plan.planId, 'enterprise-2030');
      // The id is preserved, but the definition falls back so nothing crashes
      // on a plan this build does not know about.
      expect(plan.definition.id, PlanCatalog.freeId);
      expect(plan.label, 'Free');
    });

    test('round-trips status and note', () {
      const original = CompanyPlan(
        planId: 'free',
        status: PlanStatus.pastDue,
        note: 'card expired',
      );
      final restored = CompanyPlan.fromMap(original.toMap());
      expect(restored.status, PlanStatus.pastDue);
      expect(restored.note, 'card expired');
      expect(restored.isActive, isFalse);
    });

    test('catalog ships free only, and byId falls back to it', () {
      expect(PlanCatalog.all, hasLength(1));
      expect(PlanCatalog.all.first.id, PlanCatalog.freeId);
      expect(PlanCatalog.byId('nope').id, PlanCatalog.freeId);
    });

    test('the free plan applies no limits', () {
      // Plans are infrastructure only for now; nothing reads limits yet.
      expect(PlanCatalog.free.limits, isEmpty);
    });
  });
}
