import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/providers/super_admin_provider.dart';
import 'package:stock_management/services/super_admin_service.dart';

/// Answers from a fixed allowlist, and records every uid it was asked about.
class _FakeService extends SuperAdminService {
  _FakeService(this.superAdmins);

  final Set<String> superAdmins;
  final List<String> asked = [];

  @override
  Future<bool> isSuperAdmin(String uid) async {
    asked.add(uid);
    return superAdmins.contains(uid);
  }
}

/// Always throws, to check an unresolvable check still settles.
class _BrokenService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => throw Exception('offline');
}

void main() {
  group('SuperAdminProvider.resolveSuperAdmin', () {
    test('resolves true for a super admin', () async {
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('root');
      expect(provider.isResolvedFor('root'), isTrue);
      expect(provider.isSuperAdmin, isTrue);
    });

    test('resolves false for a normal user', () async {
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('normal');
      expect(provider.isResolvedFor('normal'), isTrue);
      expect(provider.isSuperAdmin, isFalse);
    });

    test('a second user does NOT inherit the first ones answer', () async {
      // The reported bug: signing in as another user opened the super admin
      // dashboard instead of their inventory, because the answer was cached
      // without reference to who it was for.
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('root');
      expect(provider.isSuperAdmin, isTrue);

      await provider.resolveSuperAdmin('normal');
      expect(provider.isSuperAdmin, isFalse,
          reason: 'a normal user must never be routed to the dashboard');
      expect(provider.isResolvedFor('normal'), isTrue);
    });

    test('a previous users answer is not reported as resolved', () async {
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('root');
      // Routing asks about the user who is signed in NOW.
      expect(provider.isResolvedFor('normal'), isFalse);
    });

    test('going back to a super admin resolves true again', () async {
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('root');
      await provider.resolveSuperAdmin('normal');
      await provider.resolveSuperAdmin('root');
      expect(provider.isSuperAdmin, isTrue);
    });

    test('does not re-ask for a uid it already answered', () async {
      final service = _FakeService({'root'});
      final provider = SuperAdminProvider(service: service);
      await provider.resolveSuperAdmin('root');
      await provider.resolveSuperAdmin('root');
      await provider.resolveSuperAdmin('root');
      expect(service.asked, ['root']);
    });

    test('ignores an empty uid', () async {
      final service = _FakeService({'root'});
      final provider = SuperAdminProvider(service: service);
      await provider.resolveSuperAdmin('');
      expect(service.asked, isEmpty);
      expect(provider.isResolvedFor(''), isFalse);
    });

    test('a failing check settles as not-a-super-admin', () async {
      // Must never leave routing stuck on the spinner.
      final provider = SuperAdminProvider(service: _BrokenService());
      await provider.resolveSuperAdmin('someone');
      expect(provider.isResolvedFor('someone'), isTrue);
      expect(provider.isSuperAdmin, isFalse);
    });

    test('reset clears the answer so the next session re-checks', () async {
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('root');
      provider.reset();
      expect(provider.isSuperAdmin, isFalse);
      expect(provider.isResolvedFor('root'), isFalse);
    });

    test('switching users clears companies loaded for the previous one',
        () async {
      final provider = SuperAdminProvider(service: _FakeService({'root'}));
      await provider.resolveSuperAdmin('root');
      await provider.resolveSuperAdmin('normal');
      expect(provider.companies, isEmpty);
      expect(provider.statsFor('anything'), isNull);
    });
  });
}
