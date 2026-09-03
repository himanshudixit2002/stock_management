import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/models/company_model.dart';
import 'package:stock_management/providers/super_admin_provider.dart';
import 'package:stock_management/screens/super_admin/super_admin_company_screen.dart';
import 'package:stock_management/services/super_admin_service.dart';

/// A super admin whose company streams never emit, so the screen mounts
/// without needing Firebase.
class _SilentService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<Map<String, dynamic>>> watchCompanyUsers(String companyId) =>
      const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> watchCompanyRoles(String companyId) =>
      const Stream.empty();

  @override
  Future<CompanyStats> expandedCompanyStats(String companyId) async =>
      CompanyStats.empty;

  @override
  Future<Map<String, dynamic>?> getCompanySettings(String companyId) async =>
      const {};
}

void main() {
  final company = CompanyModel.fromMap({'companyName': 'Acme'}, 'c1');

  Future<SuperAdminProvider> readyProvider() async {
    final provider = SuperAdminProvider(service: _SilentService());
    await provider.resolveSuperAdmin('root');
    return provider;
  }

  testWidgets('opens and closes without throwing', (tester) async {
    // Regression: dispose() read the provider off the BuildContext, and
    // StatefulElement.unmount() marks the element defunct *before* calling
    // dispose — so leaving this screen threw "Looking up a deactivated widget's
    // ancestor is unsafe" every single time.
    final provider = await readyProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<SuperAdminProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SuperAdminCompanyScreen(company: company),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Acme'), findsWidgets);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a long workspace name does not overflow the app bar', (
    tester,
  ) async {
    // AppBarTitleRow was a Row of bare Text with mainAxisSize.min, and this
    // screen feeds it a user-supplied name.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = await readyProvider();
    final longName = CompanyModel.fromMap(
      {'companyName': 'A' * 120},
      'c2',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SuperAdminProvider>.value(
        value: provider,
        child: MaterialApp(
          home: SuperAdminCompanyScreen(company: longName),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-super-admin is refused', (tester) async {
    final provider = SuperAdminProvider(service: _SilentService());

    await tester.pumpWidget(
      ChangeNotifierProvider<SuperAdminProvider>.value(
        value: provider,
        child: MaterialApp(
          home: SuperAdminCompanyScreen(company: company),
        ),
      ),
    );
    // Pumped past the empty state's entrance animation rather than settled:
    // its flutter_animate driver leaves a timer pumpAndSettle never clears.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Not available'), findsOneWidget);
  });
}
