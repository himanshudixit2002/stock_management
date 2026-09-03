import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/company_model.dart';
import 'package:stock_management/models/company_plan_model.dart';

void main() {
  group('CompanyModel.fromMap backwards compatibility', () {
    test('a doc with no status and no plan reads as active on the MAX tier', () {
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
      expect(company.plan.planId, PlanCatalog.maxId);
      expect(company.plan.status, PlanStatus.active);
      expect(company.plan.label, 'MAX Tier');
    });

    test('an entirely empty doc still yields a usable company', () {
      final company = CompanyModel.fromMap({}, 'c1');
      expect(company.isUsable, isTrue);
      expect(company.plan.planId, PlanCatalog.maxId);
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
    test('a company doc with no plan field still reads as the MAX tier', () {
      // Nothing writes a plan map on company creation, so every workspace that
      // exists today has no `plan` field at all. If the fallback were a lower
      // tier, introducing paid tiers would silently downgrade the entire tenant
      // base and start refusing their writes at the first limit.
      final plan = CompanyPlan.fromMap(null);
      expect(plan.planId, PlanCatalog.maxId);
      expect(PlanCatalog.defaultId, PlanCatalog.maxId);
      expect(plan.isActive, isTrue);
      expect(plan.effectiveLimits, isEmpty);
    });

    test('an unknown planId still resolves to a usable definition', () {
      final plan = CompanyPlan.fromMap({'planId': 'enterprise-2030'});
      expect(plan.planId, 'enterprise-2030');
      // The id is preserved, but the definition falls back so nothing crashes
      // on a plan this build does not know about.
      expect(plan.definition.id, PlanCatalog.maxId);
      expect(plan.label, 'MAX Tier');
    });

    test('round-trips status and note', () {
      const original = CompanyPlan(
        planId: PlanCatalog.starterId,
        status: PlanStatus.pastDue,
        note: 'card expired',
      );
      final restored = CompanyPlan.fromMap(original.toMap());
      expect(restored.planId, PlanCatalog.starterId);
      expect(restored.status, PlanStatus.pastDue);
      expect(restored.note, 'card expired');
      expect(restored.isActive, isFalse);
    });

    test('round-trips a trial end date and limit overrides', () {
      final original = CompanyPlan(
        planId: PlanCatalog.growthId,
        trialEndsAt: DateTime(2026, 3, 1),
        limitOverrides: const {PlanLimitKeys.products: 5000},
      );
      final restored = CompanyPlan.fromMap(original.toMap());
      expect(restored.trialEndsAt, DateTime(2026, 3, 1));
      expect(restored.limitOverrides[PlanLimitKeys.products], 5000);
    });

    test('the catalog carries every tier and byId falls back to MAX', () {
      expect(PlanCatalog.all.map((p) => p.id), [
        PlanCatalog.starterId,
        PlanCatalog.growthId,
        PlanCatalog.proId,
        PlanCatalog.maxId,
      ]);
      expect(PlanCatalog.byId('nope').id, PlanCatalog.maxId);
    });

    test('the MAX tier applies no limits', () {
      expect(PlanCatalog.maxTier.limits, isEmpty);
      expect(PlanCatalog.maxTier.lockedFeatures, isEmpty);
    });

    test('an override wins over the tier limit', () {
      const plan = CompanyPlan(
        planId: PlanCatalog.starterId,
        limitOverrides: {PlanLimitKeys.products: 900},
      );
      expect(PlanCatalog.starter.limits[PlanLimitKeys.products], 250);
      expect(plan.limitFor(PlanLimitKeys.products), 900);
      // Keys with no override keep the tier value.
      expect(plan.limitFor(PlanLimitKeys.users), 3);
    });

    test('a negative override removes the cap entirely', () {
      // A plain absence cannot say "unlimited for this one workspace" — it
      // means "inherit the tier" — so -1 is the escape hatch.
      const plan = CompanyPlan(
        planId: PlanCatalog.starterId,
        limitOverrides: {PlanLimitKeys.products: -1},
      );
      expect(plan.limitFor(PlanLimitKeys.products), isNull);
    });

    test('overrides written as a double are read back as ints', () {
      // Firestore hands numbers back as num; a hard cast would throw and lose
      // the whole plan map.
      final plan = CompanyPlan.fromMap({
        'planId': PlanCatalog.proId,
        'limitOverrides': {PlanLimitKeys.users: 12.0},
      });
      expect(plan.limitOverrides[PlanLimitKeys.users], 12);
    });

    test('a trial is on or expired depending on the date', () {
      final future = CompanyPlan(
        trialEndsAt: DateTime.now().add(const Duration(days: 3)),
      );
      final past = CompanyPlan(
        trialEndsAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(future.isOnTrial, isTrue);
      expect(future.trialExpired, isFalse);
      expect(past.isOnTrial, isFalse);
      expect(past.trialExpired, isTrue);
    });

    test('a tier can lock a feature the MAX tier carries', () {
      const starter = CompanyPlan(planId: PlanCatalog.starterId);
      const max = CompanyPlan(planId: PlanCatalog.maxId);
      expect(starter.allowsFeature('aiAssistant'), isFalse);
      expect(max.allowsFeature('aiAssistant'), isTrue);
    });
  });

  group('PlanCatalog hydration', () {
    tearDown(PlanCatalog.resetToSeed);

    test('starts on the tiers compiled into the build', () {
      expect(PlanCatalog.all, PlanCatalog.seedDefaults);
    });

    test('hydrate replaces the catalog and sorts by sortOrder', () {
      PlanCatalog.hydrate(const [
        PlanDefinition(id: 'b', label: 'Bee', description: '', sortOrder: 2),
        PlanDefinition(id: 'a', label: 'Ay', description: '', sortOrder: 1),
      ]);
      expect(PlanCatalog.all.map((p) => p.id), ['a', 'b']);
    });

    test('an empty publish is ignored rather than blanking the catalog', () {
      // A database that has never been seeded must not leave the app with no
      // tiers at all — every plan lookup would fall through to the default.
      PlanCatalog.hydrate(const []);
      expect(PlanCatalog.all, PlanCatalog.seedDefaults);
    });

    test('a tier deleted from the catalog still resolves to MAX', () {
      // Companies keep their planId on their own document. If the console
      // deletes that tier, byId must not strand them or hand them whichever
      // tier happens to sort first.
      PlanCatalog.hydrate(const [
        PlanDefinition(id: 'aardvark', label: 'Aardvark', description: ''),
      ]);
      expect(PlanCatalog.byId('starter').id, PlanCatalog.maxId);
      expect(PlanCatalog.byId('aardvark').id, 'aardvark');
    });

    test('the default tier is still MAX after hydration', () {
      // The no-silent-downgrade invariant: a company doc with no plan field
      // must keep reading as MAX no matter what the console publishes.
      PlanCatalog.hydrate(const [
        PlanDefinition(id: 'cheap', label: 'Cheap', description: ''),
      ]);
      expect(PlanCatalog.defaultId, PlanCatalog.maxId);
      expect(CompanyPlan.fromMap(null).planId, PlanCatalog.maxId);
    });

    test('archived tiers stay readable but are not assignable', () {
      PlanCatalog.hydrate(const [
        PlanDefinition(id: 'old', label: 'Old', description: '', archived: true),
        PlanDefinition(id: 'new', label: 'New', description: ''),
      ]);
      expect(PlanCatalog.all, hasLength(2));
      expect(PlanCatalog.assignable.map((p) => p.id), ['new']);
      expect(PlanCatalog.byId('old').label, 'Old');
    });

    test('resetToSeed restores the built-in tiers', () {
      PlanCatalog.hydrate(const [
        PlanDefinition(id: 'x', label: 'X', description: ''),
      ]);
      PlanCatalog.resetToSeed();
      expect(PlanCatalog.all, PlanCatalog.seedDefaults);
    });
  });

  group('PlanDefinition serialisation', () {
    test('round-trips through toMap and fromMap', () {
      const original = PlanDefinition(
        id: 'growth',
        label: 'Growth',
        description: 'Mid tier',
        nominalPrice: 2999,
        promotionalPrice: 0,
        limits: {PlanLimitKeys.users: 10, PlanLimitKeys.products: 2000},
        lockedFeatures: {'aiAssistant'},
        sortOrder: 3,
        archived: true,
      );
      final restored = PlanDefinition.fromMap(original.toMap(), 'growth');

      expect(restored.label, 'Growth');
      expect(restored.nominalPrice, 2999);
      expect(restored.promotionalPrice, 0);
      expect(restored.limits[PlanLimitKeys.users], 10);
      expect(restored.lockedFeatures, {'aiAssistant'});
      expect(restored.sortOrder, 3);
      expect(restored.archived, isTrue);
    });

    test('a doc with nothing but an id still yields a usable tier', () {
      // These documents are hand-edited from the console; a missing field must
      // degrade, not throw.
      final plan = PlanDefinition.fromMap(const {}, 'mystery');
      expect(plan.id, 'mystery');
      expect(plan.label, 'mystery');
      expect(plan.limits, isEmpty);
      expect(plan.archived, isFalse);
    });

    test('numbers written as doubles are read back as ints', () {
      final plan = PlanDefinition.fromMap(const {
        'label': 'Odd',
        'nominalPrice': 999.0,
        'limits': {PlanLimitKeys.products: 250.0},
        'sortOrder': 2.0,
      }, 'odd');
      expect(plan.nominalPrice, 999);
      expect(plan.limits[PlanLimitKeys.products], 250);
      expect(plan.sortOrder, 2);
    });

    test('a limits value of the wrong type is dropped, not crashed on', () {
      final plan = PlanDefinition.fromMap(const {
        'label': 'Broken',
        'limits': {PlanLimitKeys.products: 'lots', PlanLimitKeys.users: 5},
        'lockedFeatures': ['aiAssistant', 7],
      }, 'broken');
      expect(plan.limits.containsKey(PlanLimitKeys.products), isFalse);
      expect(plan.limits[PlanLimitKeys.users], 5);
      expect(plan.lockedFeatures, {'aiAssistant'});
    });
  });
}
