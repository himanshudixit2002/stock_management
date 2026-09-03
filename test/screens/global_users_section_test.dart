import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_management/providers/super_admin_provider.dart';
import 'package:stock_management/screens/super_admin/sections/global_users_section.dart';
import 'package:stock_management/services/super_admin_service.dart';

import '../helpers/test_helpers.dart';

/// A super admin whose global user query is denied — the exact state the
/// console was in before the platform-admin read rule on /users existed.
class _DeniedService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<Map<String, dynamic>>> getAllUsersGlobal({int? limit}) =>
      Stream.error(Exception('permission-denied'));
}

/// A super admin whose workspace genuinely has no users.
class _EmptyService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<Map<String, dynamic>>> getAllUsersGlobal({int? limit}) =>
      Stream.value(const []);
}

/// A super admin who can see users across more than one workspace.
class _PopulatedService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<Map<String, dynamic>>> getAllUsersGlobal({int? limit}) =>
      Stream.value(const [
        {
          'id': 'u1',
          'name': 'Asha',
          'email': 'asha@one.test',
          'role': 'admin',
          'companyName': 'One',
        },
        {
          'id': 'u2',
          'name': 'Bo',
          'email': 'bo@two.test',
          'role': 'staff',
          'companyName': 'Two',
        },
      ]);
}

Future<SuperAdminProvider> _readyProvider(SuperAdminService service) async {
  final provider = SuperAdminProvider(service: service);
  await provider.resolveSuperAdmin('root');
  return provider;
}

Widget _wrap(SuperAdminProvider provider) => createTestApp(
  child: ChangeNotifierProvider<SuperAdminProvider>.value(
    value: provider,
    child: const Scaffold(body: GlobalUsersSection()),
  ),
);

void main() {
  testWidgets('a denied query shows the error, not an endless spinner', (
    tester,
  ) async {
    // The first version rendered a spinner whenever the list was empty, so a
    // permission failure was indistinguishable from still loading — which is
    // how a missing security rule stayed invisible.
    final provider = await _readyProvider(_DeniedService());
    await pumpAndSettle(tester, _wrap(provider));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets('an empty result reads as empty, not as a failure', (
    tester,
  ) async {
    final provider = await _readyProvider(_EmptyService());
    await pumpAndSettle(tester, _wrap(provider));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No users found'), findsOneWidget);
  });

  testWidgets('users from more than one workspace are listed together', (
    tester,
  ) async {
    final provider = await _readyProvider(_PopulatedService());
    await pumpAndSettle(tester, _wrap(provider));

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);
  });
}
