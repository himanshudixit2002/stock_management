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

/// A super admin whose cross-tenant streams all fail, the way they did before
/// the platform-admin read rule on /users existed.
class _DeniedStreamService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<Map<String, dynamic>>> getAllUsersGlobal({int? limit}) =>
      Stream.error(Exception('permission-denied'));

  @override
  Stream<List<Map<String, dynamic>>> watchCompanyUsers(String companyId) =>
      Stream.error(Exception('permission-denied'));
}

/// A super admin whose company streams never emit, so a section stays pending.
class _SilentStreamService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Stream<List<Map<String, dynamic>>> watchCompanyUsers(String companyId) =>
      const Stream.empty();

  @override
  Future<CompanyStats> expandedCompanyStats(String companyId) async =>
      CompanyStats.empty;

  @override
  Future<Map<String, dynamic>?> getCompanySettings(String companyId) async =>
      null;
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

  group('SuperAdminProvider cross-tenant stream failures', () {
    test('a denied global users stream reports an error, not an empty list',
        () async {
      // Before this, startWatchingGlobalUsers had no onError: the denial was
      // swallowed, the list stayed empty, and the UI spun forever — which is
      // why a missing security rule looked like a hang for weeks.
      final provider = SuperAdminProvider(service: _DeniedStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingGlobalUsers();
      await Future<void>.delayed(Duration.zero);

      expect(provider.globalUsers, isEmpty);
      expect(provider.globalUsersLoading, isFalse);
      expect(provider.globalUsersError, isNotNull);
    });

    test('a denied section stream reports an error and stops loading',
        () async {
      final provider = SuperAdminProvider(service: _DeniedStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingCompanyDetail('c1');
      provider.watchSection(SuperAdminSection.users);
      await Future<void>.delayed(Duration.zero);

      expect(provider.sectionError(SuperAdminSection.users), isNotNull);
      expect(provider.sectionLoading(SuperAdminSection.users), isFalse);
    });
  });

  group('SuperAdminProvider company detail sections', () {
    test('a subscribed section with no snapshot yet reads as loading, not empty',
        () async {
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingCompanyDetail('c1');

      expect(provider.sectionLoading(SuperAdminSection.users), isFalse);
      provider.watchSection(SuperAdminSection.users);
      expect(provider.sectionLoading(SuperAdminSection.users), isTrue);
    });

    test('only the sections actually asked for are subscribed', () async {
      // Opening a workspace used to start all eight streams at once; each tab
      // now pays only for itself.
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingCompanyDetail('c1');
      provider.watchSection(SuperAdminSection.users);

      expect(provider.sectionLoading(SuperAdminSection.users), isTrue);
      expect(provider.sectionLoading(SuperAdminSection.products), isFalse);
      expect(provider.sectionData(SuperAdminSection.products), isEmpty);
    });

    test('stopWatchingCompanyDetail clears every section', () async {
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingCompanyDetail('c1');
      provider.watchSection(SuperAdminSection.users);
      provider.stopWatchingCompanyDetail();

      expect(provider.sectionLoading(SuperAdminSection.users), isFalse);
      expect(provider.sectionData(SuperAdminSection.users), isEmpty);
      expect(provider.companySettings, isNull);
    });
  });

  group('SuperAdminProvider workspace inspection', () {
    final company = CompanyModel.fromMap({'companyName': 'Acme'}, 'c1');

    test('entering and leaving a workspace flips the inspection state',
        () async {
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');

      expect(provider.isInspecting, isFalse);
      provider.enterWorkspace(company);
      expect(provider.isInspecting, isTrue);
      expect(provider.inspectCompanyId, 'c1');
      expect(provider.inspectCompanyName, 'Acme');

      provider.exitWorkspace();
      expect(provider.isInspecting, isFalse);
      expect(provider.inspectCompanyId, isNull);
    });

    test('a normal user cannot enter a workspace', () async {
      // app.dart routes on this flag, so a non-admin must never be able to set
      // it and boot the shell into someone else's tenant.
      final provider = SuperAdminProvider(service: _FakeService(const {}));
      await provider.resolveSuperAdmin('normal');
      provider.enterWorkspace(company);
      expect(provider.isInspecting, isFalse);
    });

    test('signing out drops an active inspection', () async {
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');
      provider.enterWorkspace(company);
      provider.reset();
      expect(provider.isInspecting, isFalse);
      expect(provider.isSuperAdmin, isFalse);
    });
  });

  group('SuperAdminProvider refreshing counts', () {
    test('loadStats does not re-fetch a company it already has', () async {
      final service = _CountingStatsService();
      final provider = SuperAdminProvider(service: service);
      await provider.loadStats('a');
      await provider.loadStats('a');
      expect(service.calls['a'], 1);
    });

    test('reloadAllStats actually re-fetches', () async {
      // The console's refresh buttons sit on top of this. Built on loadAllStats
      // they were silent no-ops after the first load, because loadStats returns
      // early for anything already cached.
      final service = _CountingStatsService();
      final provider = SuperAdminProvider(service: service);
      await provider.resolveSuperAdmin('root');
      await provider.loadStats('a');
      expect(service.calls['a'], 1);

      await provider.reloadAllStats();
      await provider.loadStats('a');
      expect(service.calls['a'], 2);
    });

    test('a failed count is reported as unknown, not as zero', () async {
      // Storing CompanyStats.empty made an unreadable workspace look like an
      // empty one — the same class of bug as the denied user count reading 0.
      final provider = SuperAdminProvider(service: _ThrowingStatsService());
      await provider.loadStats('a');
      expect(provider.statsFailedFor('a'), isTrue);
      expect(provider.statsFailedFor('b'), isFalse);
    });

    test('a successful count carries no failure marker', () async {
      final provider = SuperAdminProvider(service: _CountingStatsService());
      await provider.loadStats('a');
      expect(provider.statsFailedFor('a'), isFalse);
    });
  });

  group('SuperAdminProvider scoped detail teardown', () {
    test('stopWatchingCompanyDetail ignores a company it is not watching',
        () async {
      // The detail screen tears down from a post-frame callback, by which point
      // another workspace may already be bound. An unconditional clear left the
      // new screen with no streams and every tab claiming the workspace was
      // empty.
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingCompanyDetail('current');
      provider.watchSection(SuperAdminSection.users);

      provider.stopWatchingCompanyDetail('previous');
      expect(provider.sectionLoading(SuperAdminSection.users), isTrue);

      provider.stopWatchingCompanyDetail('current');
      expect(provider.sectionLoading(SuperAdminSection.users), isFalse);
    });

    test('an unscoped stop still clears everything', () async {
      final provider = SuperAdminProvider(service: _SilentStreamService());
      await provider.resolveSuperAdmin('root');
      provider.startWatchingCompanyDetail('c1');
      provider.watchSection(SuperAdminSection.users);
      provider.stopWatchingCompanyDetail();
      expect(provider.sectionLoading(SuperAdminSection.users), isFalse);
    });
  });

  group('SuperAdminProvider global user cap', () {
    test('an empty list is not reported as truncated', () async {
      final provider = SuperAdminProvider(service: _SilentStreamService());
      expect(provider.globalUsersTruncated, isFalse);
    });
  });
}

/// Counts how many times each company's stats were fetched.
class _CountingStatsService extends SuperAdminService {
  final Map<String, int> calls = {};

  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Future<CompanyStats> companyStats(String companyId) async {
    calls[companyId] = (calls[companyId] ?? 0) + 1;
    return const CompanyStats(products: 3);
  }
}

/// Fails every count lookup.
class _ThrowingStatsService extends SuperAdminService {
  @override
  Future<bool> isSuperAdmin(String uid) async => true;

  @override
  Future<CompanyStats> companyStats(String companyId) async =>
      throw Exception('denied');
}
