import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/providers/super_admin_provider.dart';
import 'package:stock_management/models/company_model.dart';
import 'package:stock_management/services/super_admin_service.dart';

/// Answers from a fixed allowlist, and records every uid it was asked about.
class _FakeService extends SuperAdminService {
  _FakeService(this.superAdmins);

  final Set<String> superAdmins;
  final List<String> asked = [];

  /// Per-company counts this fake will report.
  Map<String, CompanyStats> stats = const {};
  final List<String> statsAsked = [];

  @override
  Future<bool> isSuperAdmin(String uid) async {
    asked.add(uid);
    return superAdmins.contains(uid);
  }

  @override
  Future<CompanyStats> companyStats(String companyId) async {
    statsAsked.add(companyId);
    return stats[companyId] ?? CompanyStats.empty;
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

  group('totalsAcrossCompanies', () {
    test('is zero before any counts have loaded', () {
      final provider = SuperAdminProvider(service: _FakeService({}));
      expect(provider.totalsAcrossCompanies.products, 0);
      expect(provider.statsLoadedCount, 0);
    });

    test('sums every loaded company', () async {
      final service = _FakeService({})
        ..stats = {
          'a': const CompanyStats(
            users: 2, products: 10, invoices: 3,
            salesOrders: 1, purchaseOrders: 4,
          ),
          'b': const CompanyStats(
            users: 5, products: 7, invoices: 2,
            salesOrders: 6, purchaseOrders: 0,
          ),
        };
      final provider = SuperAdminProvider(service: service);
      await provider.loadStats('a');
      await provider.loadStats('b');

      final totals = provider.totalsAcrossCompanies;
      expect(totals.users, 7);
      expect(totals.products, 17);
      expect(totals.invoices, 5);
      expect(totals.salesOrders, 7);
      expect(totals.purchaseOrders, 4);
      expect(provider.statsLoadedCount, 2);
    });

    test('counts each company once however often it is requested', () async {
      final service = _FakeService({})
        ..stats = {'a': const CompanyStats(products: 10)};
      final provider = SuperAdminProvider(service: service);
      await provider.loadStats('a');
      await provider.loadStats('a');
      await provider.loadStats('a');

      // statsLoadedCount feeds the "n of m loaded" caveat on the totals card,
      // so double counting would misreport how complete the figure is.
      expect(service.statsAsked, ['a']);
      expect(provider.statsLoadedCount, 1);
      expect(provider.totalsAcrossCompanies.products, 10);
    });

    test('a failed count still marks the company as covered', () async {
      // Otherwise the card would claim to be waiting on it forever.
      final provider = SuperAdminProvider(service: _ThrowingStatsService());
      await provider.loadStats('a');
      expect(provider.statsLoadedCount, 1);
      expect(provider.totalsAcrossCompanies.products, 0);
    });
  });
}

/// Fails every count lookup.
class _ThrowingStatsService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Future<CompanyStats> companyStats(String companyId) async =>
      throw Exception('denied');
}
