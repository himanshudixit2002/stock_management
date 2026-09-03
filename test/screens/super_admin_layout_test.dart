import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/models/company_model.dart';
import 'package:stock_management/providers/plan_catalog_provider.dart';
import 'package:stock_management/providers/promo_provider.dart';
import 'package:stock_management/providers/super_admin_provider.dart';
import 'package:stock_management/screens/super_admin/sections/global_users_section.dart';
import 'package:stock_management/screens/super_admin/sections/health_section.dart';
import 'package:stock_management/screens/super_admin/sections/overview_section.dart';
import 'package:stock_management/screens/super_admin/sections/plans_section.dart';
import 'package:stock_management/screens/super_admin/sections/platform_audit_section.dart';
import 'package:stock_management/screens/super_admin/sections/workspaces_section.dart';
import 'package:stock_management/models/company_plan_model.dart';
import 'package:stock_management/models/promo_config_model.dart';
import 'package:stock_management/services/plan_catalog_service.dart';
import 'package:stock_management/services/promo_service.dart';
import 'package:stock_management/services/super_admin_service.dart';

/// A populated platform, with the kinds of values that broke the layout:
/// very long names, and counts wide enough to blow out a fixed row.
class _PopulatedService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<CompanyModel>> watchCompanies() => Stream.value([
    CompanyModel.fromMap({
      'companyName':
          'A Very Long Workspace Name That Would Certainly Overflow A Row',
      'adminUid': 'owner-with-a-long-uid-000000000000',
      'permanentJoinCode': 'ABC123',
      'status': 'suspended',
      'statusNote': 'Suspended by platform admin',
    }, 'c1'),
    CompanyModel.fromMap({'companyName': 'Two'}, 'c2'),
  ]);

  @override
  Future<CompanyStats> companyStats(String companyId) async =>
      const CompanyStats(
        users: 123456,
        products: 987654,
        invoices: 456789,
        salesOrders: 33333,
        purchaseOrders: 44444,
      );

  @override
  Stream<List<Map<String, dynamic>>> getAllUsersGlobal({int? limit}) =>
      Stream.value([
        {
          'id': 'u1',
          'name': 'Somebody With A Rather Long Display Name Indeed',
          'email': 'somebody.with.a.long.address@example-company.test',
          'role': 'admin',
          'companyName': 'A Very Long Workspace Name',
          'companyId': 'c1',
        },
      ]);

  @override
  Stream<List<Map<String, dynamic>>> watchPlatformAuditLogs({int limit = 200}) =>
      Stream.value([
        {
          'id': 'l1',
          'action': 'plan.set',
          'targetName': 'A Very Long Workspace Name That Keeps Going',
          'actorEmail': 'platform.administrator@example-company.test',
        },
      ]);
}

/// Publishes nothing, so the compiled tiers stand — without touching Firestore.
class _FakeCatalogService extends PlanCatalogService {
  @override
  Stream<List<PlanDefinition>> watchPlans() => const Stream.empty();
}

/// A live offer, without reaching Firestore.
///
/// PlansSection loads the promo on mount; left to the real service it would sit
/// on an uninitialised Firebase channel and the test would hang rather than
/// fail.
class _FakePromoService extends PromoService {
  @override
  Future<PromoConfig?> fetch() async => const PromoConfig(
    enabled: true,
    headline: 'Founding member offer with a deliberately long headline',
    capCount: 1000,
    claimedCount: 250,
  );
}

Widget _wrap(SuperAdminProvider provider, Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SuperAdminProvider>.value(value: provider),
    ChangeNotifierProvider<PromoProvider>(
      create: (_) => PromoProvider(service: _FakePromoService()),
    ),
    ChangeNotifierProvider<PlanCatalogProvider>(
      create: (_) => PlanCatalogProvider(service: _FakeCatalogService()),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  /// Renders [child] on a 360dp phone and fails if anything overflows.
  ///
  /// The audit's layout findings were all width-dependent — unflexed Rows of
  /// counts, a bulk action bar wider than the screen, badges carrying
  /// user-supplied text — and every one of them surfaces as a RenderFlex
  /// exception at this width.
  Future<void> expectNoOverflow(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = SuperAdminProvider(service: _PopulatedService());
    await provider.resolveSuperAdmin('root');
    provider.startWatching();
    // A microtask, not Future.delayed: testWidgets runs under a fake clock, so
    // a real timer here never fires and the test deadlocks instead of failing.
    await Future<void>.microtask(() {});
    await provider.loadAllStats();

    await tester.pumpWidget(_wrap(provider, child));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  }

  testWidgets('the overview fits a 360dp phone', (tester) async {
    await expectNoOverflow(
      tester,
      OverviewSection(onOpenWorkspaces: () {}),
    );
  });

  testWidgets('the workspace list fits a 360dp phone', (tester) async {
    await expectNoOverflow(tester, const WorkspacesSection());
  });

  testWidgets('the global user list fits a 360dp phone', (tester) async {
    await expectNoOverflow(tester, const GlobalUsersSection());
  });

  testWidgets('the plans page fits a 360dp phone', (tester) async {
    await expectNoOverflow(tester, const PlansSection());
  });

  testWidgets('the audit log fits a 360dp phone', (tester) async {
    await expectNoOverflow(tester, const PlatformAuditSection());
  });

  testWidgets('the health page fits a 360dp phone', (tester) async {
    await expectNoOverflow(tester, const HealthSection());
  });
}
