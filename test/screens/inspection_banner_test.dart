import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_management/models/company_model.dart';
import 'package:stock_management/providers/auth_provider.dart';
import 'package:stock_management/providers/super_admin_provider.dart';
import 'package:stock_management/screens/super_admin/inspection_banner.dart';
import 'package:stock_management/services/super_admin_service.dart';

/// A platform admin whose audit entries are recorded here instead of written.
class _Service extends SuperAdminService {
  final List<String> logged = [];

  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Future<void> logInspection({
    required PlatformActor? actor,
    required String companyId,
    required String companyName,
    required bool entering,
  }) async {
    logged.add('${entering ? 'enter' : 'exit'} $companyId');
  }
}

/// Only what the banner touches: ending the session's inspection.
class _Auth implements AuthProvider {
  bool inspectionEnded = false;

  @override
  void endInspection() => inspectionEnded = true;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Service service;
  late SuperAdminProvider superAdmin;
  late _Auth auth;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = _Service();
    superAdmin = SuperAdminProvider(service: service);
    await superAdmin.resolveSuperAdmin('root');
    superAdmin.enterWorkspace(
      CompanyModel.fromMap({'companyName': 'Acme'}, 'c1'),
    );
    auth = _Auth();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  /// The banner where the app puts it: in MaterialApp.builder, above the
  /// navigator, with a tenant screen pushed over Home.
  Future<void> pumpInspecting(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SuperAdminProvider>.value(value: superAdmin),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) =>
              InspectionBanner(navigatorKey: navigatorKey, child: child!),
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Tenant screen')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Return to console ends the inspection and pops to the root', (
    tester,
  ) async {
    await pumpInspecting(tester);
    expect(find.text('Tenant screen'), findsOneWidget);

    await tester.tap(find.text('Return to console'));
    await tester.pumpAndSettle();

    // It used to look up a Navigator above itself, throw, and end nothing.
    expect(tester.takeException(), isNull);
    expect(superAdmin.isInspecting, isFalse);
    expect(auth.inspectionEnded, isTrue);
    expect(service.logged, ['enter c1', 'exit c1']);
    expect(find.text('Tenant screen'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('the banner stays in the accessibility tree under a page', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpInspecting(tester);

    expect(find.bySemanticsLabel(RegExp('Inspecting Acme')), findsOneWidget);
    expect(find.bySemanticsLabel('Return to console'), findsOneWidget);
    semantics.dispose();
  });
}
