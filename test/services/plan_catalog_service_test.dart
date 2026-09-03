import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/company_plan_model.dart';
import 'package:stock_management/services/plan_catalog_service.dart';

/// Returns a fixed catalog, including one document the parser must survive.
class _FakeCatalogService extends PlanCatalogService {
  _FakeCatalogService(this.raw);

  final Map<String, Map<String, dynamic>> raw;

  @override
  Future<List<PlanDefinition>> fetchPlans() async {
    final out = <PlanDefinition>[];
    raw.forEach((id, data) {
      try {
        out.add(PlanDefinition.fromMap(data, id));
      } catch (_) {
        // Mirrors the real implementation: skip the bad tier, keep the rest.
      }
    });
    return out;
  }
}

void main() {
  tearDown(PlanCatalog.resetToSeed);

  test('a published catalog replaces the compiled tiers', () async {
    final service = _FakeCatalogService({
      'lite': {'label': 'Lite', 'sortOrder': 1},
      'heavy': {'label': 'Heavy', 'sortOrder': 2},
    });

    PlanCatalog.hydrate(await service.fetchPlans());

    expect(PlanCatalog.all.map((p) => p.label), ['Lite', 'Heavy']);
  });

  test('one malformed tier does not take the catalog down with it', () async {
    // These documents are edited by hand from the console, so a single bad
    // value must not leave every tenant with no plan information at all.
    final service = _FakeCatalogService({
      'good': {'label': 'Good', 'sortOrder': 1},
      'bad': {'label': 'Bad', 'limits': 'not a map', 'sortOrder': 2},
    });

    final plans = await service.fetchPlans();
    PlanCatalog.hydrate(plans);

    expect(plans, hasLength(2));
    expect(PlanCatalog.byId('bad').limits, isEmpty);
    expect(PlanCatalog.byId('good').label, 'Good');
  });

  test('an empty catalog leaves the compiled tiers in place', () async {
    final service = _FakeCatalogService({});
    PlanCatalog.hydrate(await service.fetchPlans());
    expect(PlanCatalog.all, PlanCatalog.seedDefaults);
  });

  test('a published catalog without MAX still resolves the default', () async {
    // Every company doc with no plan field reads as the default tier. If the
    // console publishes a catalog that omits it, byId must still answer.
    final service = _FakeCatalogService({
      'lite': {'label': 'Lite'},
    });
    PlanCatalog.hydrate(await service.fetchPlans());

    expect(PlanCatalog.byId(PlanCatalog.defaultId).id, PlanCatalog.maxId);
    expect(CompanyPlan.fromMap(null).label, PlanCatalog.maxTier.label);
  });
}
