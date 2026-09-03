import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_model.dart';
import '../models/company_plan_model.dart';
import '../services/super_admin_service.dart';
import '../utils/error_helpers.dart';

/// The per-company data streams the console can open.
///
/// Named so the detail screen can subscribe to only the tab in view. Opening
/// all of them at once — which is what the first version did — meant eight
/// live listeners per workspace visit, most of them feeding a tab nobody
/// looked at.
enum SuperAdminSection {
  users,
  roles,
  products,
  invoices,
  salesOrders,
  purchaseOrders,
  transactions,
  auditLogs,
}

/// Cross-tenant oversight. Inert unless the signed-in user holds a
/// `superAdmins/{uid}` doc — [isSuperAdmin] gates the UI, and the security
/// rules gate the data.
class SuperAdminProvider extends ChangeNotifier {
  SuperAdminProvider({SuperAdminService? service})
    : _service = service ?? SuperAdminService();

  final SuperAdminService _service;

  bool _isSuperAdmin = false;

  /// The uid the current answer belongs to, or null if nothing is resolved.
  ///
  /// Keyed by uid rather than a bare bool: signing out and back in as someone
  /// else reuses this provider instance, and an answer that ignored the uid
  /// meant the second user inherited the first one's — a normal user landing
  /// on the super admin dashboard with no way back.
  String? _resolvedForUid;
  String? _resolvingUid;

  /// Last *known* answer for this uid, restored from local storage.
  ///
  /// The `superAdmins/{uid}` read is a network round-trip, and gating the whole
  /// shell on it charged every ordinary user a serial wait to spare the handful
  /// of platform admins one frame of the normal app. This remembers the previous
  /// answer so the wait is imposed only on someone already known to be an admin.
  bool _cachedIsSuperAdmin = false;
  String? _cachedForUid;
  bool _isLoading = false;
  String? _errorMessage;
  List<CompanyModel> _companies = [];
  StreamSubscription? _companiesSubscription;

  /// Per-company counts, filled in on demand so opening the dashboard does not
  /// fire an aggregation query for every tenant at once.
  final Map<String, CompanyStats> _stats = {};
  final Set<String> _statsInFlight = {};

  /// Companies whose counts could not be read. Their entry in [_stats] is a
  /// placeholder, not a measurement, and the UI renders it as "—".
  final Set<String> _statsFailed = {};

  // Active company detail streams, one per section actually being looked at.
  String? _watchingCompanyId;
  final Map<SuperAdminSection, StreamSubscription> _detailSubscriptions = {};
  final Map<SuperAdminSection, List<Map<String, dynamic>>> _sectionData = {};
  final Map<SuperAdminSection, String> _sectionErrors = {};
  Map<String, dynamic>? _companySettings;

  final Map<String, CompanyStats> _expandedStats = {};

  // Global Users
  StreamSubscription? _globalUsersSubscription;
  List<Map<String, dynamic>> _globalUsers = [];
  bool _globalUsersLoading = false;
  String? _globalUsersError;

  // Platform audit log
  StreamSubscription? _auditSubscription;
  List<Map<String, dynamic>> _platformAuditLogs = [];
  String? _platformAuditError;
  bool _platformAuditLoading = false;

  // Company settings, which have their own loading/error state: null alone
  // cannot say whether the read is pending, failed, or genuinely found nothing.
  bool _companySettingsLoading = false;
  String? _companySettingsError;

  /// Who is acting, for the audit trail. Null until [resolveSuperAdmin] runs.
  PlatformActor? _actor;

  /// The workspace currently being inspected read-only, if any.
  String? _inspectCompanyId;
  String? _inspectCompanyName;

  bool get isSuperAdmin => _isSuperAdmin;

  /// True once the check has completed *for this user*. Routing depends on it,
  /// so it must never report a previous user's answer.
  bool isResolvedFor(String uid) => _resolvedForUid == uid;

  /// Whether this uid was a super admin the last time we asked, per the local
  /// cache. Used to decide whether routing may render optimistically while
  /// [resolveSuperAdmin] is still in flight — never as the answer itself.
  bool wasSuperAdmin(String uid) => _cachedForUid == uid && _cachedIsSuperAdmin;

  static String _cacheKey(String uid) => 'super_admin_$uid';

  /// Restores the cached answer for [uid]. Cheap and local; call it before the
  /// first routing decision so the shell knows whether it may render early.
  Future<void> primeFromCache(String uid) async {
    if (uid.isEmpty || _cachedForUid == uid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedIsSuperAdmin = prefs.getBool(_cacheKey(uid)) ?? false;
    } catch (_) {
      // No local storage (private mode, quota) — fall back to "not an admin",
      // which just means an admin sees one frame of the normal app.
      _cachedIsSuperAdmin = false;
    }
    _cachedForUid = uid;
  }
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<CompanyModel> get companies => _companies;

  /// Companies that are neither suspended nor deleted.
  List<CompanyModel> get activeCompanies =>
      _companies.where((c) => c.isActive).toList();

  int get suspendedCount => _companies.where((c) => c.isSuspended).length;
  int get deletedCount => _companies.where((c) => c.isDeleted).length;

  /// Rows loaded for [section], or an empty list if it is not being watched.
  List<Map<String, dynamic>> sectionData(SuperAdminSection section) =>
      _sectionData[section] ?? const [];

  /// Why [section] failed to load, or null.
  String? sectionError(SuperAdminSection section) => _sectionErrors[section];

  /// True while [section] is subscribed but has not produced its first
  /// snapshot. Distinguishing this from "loaded and empty" is the whole reason
  /// the console can tell a denied query from an empty workspace.
  bool sectionLoading(SuperAdminSection section) =>
      _detailSubscriptions.containsKey(section) &&
      !_sectionData.containsKey(section) &&
      !_sectionErrors.containsKey(section);

  List<Map<String, dynamic>> get companyUsers =>
      sectionData(SuperAdminSection.users);
  List<Map<String, dynamic>> get companyRoles =>
      sectionData(SuperAdminSection.roles);
  List<Map<String, dynamic>> get companyProducts =>
      sectionData(SuperAdminSection.products);
  List<Map<String, dynamic>> get companyInvoices =>
      sectionData(SuperAdminSection.invoices);
  List<Map<String, dynamic>> get companySalesOrders =>
      sectionData(SuperAdminSection.salesOrders);
  List<Map<String, dynamic>> get companyPurchaseOrders =>
      sectionData(SuperAdminSection.purchaseOrders);
  List<Map<String, dynamic>> get companyTransactions =>
      sectionData(SuperAdminSection.transactions);
  List<Map<String, dynamic>> get companyAuditLogs =>
      sectionData(SuperAdminSection.auditLogs);
  Map<String, dynamic>? get companySettings => _companySettings;

  /// How many user documents the global list will fetch.
  ///
  /// Exposed because several health checks are only sound when the list is
  /// complete: past this cap, "this workspace's owner has no user document"
  /// really means "their document is on a page we did not read".
  static const int globalUsersLimit = 500;

  List<Map<String, dynamic>> get globalUsers => _globalUsers;
  bool get globalUsersLoading => _globalUsersLoading;
  String? get globalUsersError => _globalUsersError;

  /// True when the global user list hit its cap, so it may not be the whole
  /// platform.
  bool get globalUsersTruncated => _globalUsers.length >= globalUsersLimit;

  List<Map<String, dynamic>> get platformAuditLogs => _platformAuditLogs;
  String? get platformAuditError => _platformAuditError;
  bool get platformAuditLoading => _platformAuditLoading;

  bool get companySettingsLoading => _companySettingsLoading;
  String? get companySettingsError => _companySettingsError;

  String? get inspectCompanyId => _inspectCompanyId;
  String? get inspectCompanyName => _inspectCompanyName;
  bool get isInspecting => _inspectCompanyId != null;

  CompanyStats? expandedStatsFor(String companyId) => _expandedStats[companyId];

  CompanyStats? statsFor(String companyId) => _stats[companyId];

  /// Counts summed across every company whose stats have loaded.
  ///
  /// Stats arrive per company as tiles scroll into view, so this grows as they
  /// land — [statsLoadedCount] says how much of the estate it covers, because
  /// a total that silently represents half the tenants would be misleading.
  CompanyStats get totalsAcrossCompanies {
    var users = 0, products = 0, invoices = 0, so = 0, po = 0;
    for (final s in _stats.values) {
      users += s.users;
      products += s.products;
      invoices += s.invoices;
      so += s.salesOrders;
      po += s.purchaseOrders;
    }
    return CompanyStats(
      users: users,
      products: products,
      invoices: invoices,
      salesOrders: so,
      purchaseOrders: po,
    );
  }

  /// How many companies have their counts loaded.
  int get statsLoadedCount => _stats.length;

  /// Loads counts for every company, so the totals cover the whole estate
  /// rather than only the tiles that happened to be scrolled past.
  /// Loaded in chunks rather than one company at a time: each call is five
  /// aggregation queries, and serialising them across the whole estate made the
  /// hero totals arrive minutes after the list did.
  static const int _statsChunkSize = 8;

  Future<void> loadAllStats() async {
    final ids = _companies.map((c) => c.id).toList();
    for (var i = 0; i < ids.length; i += _statsChunkSize) {
      final end = (i + _statsChunkSize).clamp(0, ids.length);
      await Future.wait(ids.sublist(i, end).map(loadStats));
    }
  }

  CompanyModel? companyById(String id) {
    for (final c in _companies) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Resolves whether this user is a super admin. Called once after sign-in.
  ///
  /// Routing depends on the answer, so this must run before the app decides
  /// what to render — and it must settle even on failure, or a transient error
  /// would leave the user staring at a spinner forever.
  Future<void> resolveSuperAdmin(String uid, {String actorEmail = ''}) async {
    if (uid.isEmpty) return;
    _actor = PlatformActor(uid: uid, email: actorEmail);
    if (_resolvedForUid == uid || _resolvingUid == uid) return;

    // A different user: drop the previous answer and anything streamed under
    // it before asking again.
    if (_resolvedForUid != null && _resolvedForUid != uid) {
      _clearForUserChange();
    }

    _resolvingUid = uid;
    var result = false;
    try {
      result = await _service.isSuperAdmin(uid);
    } catch (_) {
      // Treat an unresolvable check as "not a super admin": the normal app is
      // the safe fallback, and the rules deny the dashboard regardless.
      result = false;
    } finally {
      // Ignore a late reply for a user who is no longer signed in, or the
      // answer for the previous account could still land on the new one.
      if (_resolvingUid == uid) {
        _resolvingUid = null;
        _isSuperAdmin = result;
        _resolvedForUid = uid;
        _cachedIsSuperAdmin = result;
        _cachedForUid = uid;
        unawaited(_persistCache(uid, result));
        notifyListeners();
      }
    }
  }

  Future<void> _persistCache(String uid, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheKey(uid), value);
    } catch (_) {
      // Best-effort: losing the cache only costs a frame on the next launch.
    }
  }

  /// Drops everything tied to the previously resolved user.
  void _clearForUserChange() {
    _companiesSubscription?.cancel();
    _companiesSubscription = null;
    stopWatchingCompanyDetail();
    stopWatchingGlobalUsers();
    stopWatchingPlatformAudit();
    _inspectCompanyId = null;
    _inspectCompanyName = null;
    _actor = null;
    _isSuperAdmin = false;
    _resolvedForUid = null;
    _companies = [];
    _stats.clear();
    _statsFailed.clear();
    _expandedStats.clear();
    _statsInFlight.clear();
    _errorMessage = null;
    _isLoading = false;
  }

  /// Starts streaming the company list. No-op unless this user is a super
  /// admin, so a normal session never attempts a query the rules would deny.
  void startWatching() {
    if (!_isSuperAdmin || _companiesSubscription != null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _companiesSubscription = _service.watchCompanies().listen(
      (companies) {
        _companies = companies;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load companies.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Loads counts for one company, once. Safe to call from a build method.
  Future<void> loadStats(String companyId) async {
    if (_stats.containsKey(companyId) || _statsInFlight.contains(companyId)) {
      return;
    }
    _statsInFlight.add(companyId);
    try {
      final stats = await _service.companyStats(companyId);
      _stats[companyId] = stats;
      _statsFailed.remove(companyId);
      notifyListeners();
    } catch (_) {
      // Counts are informational; a failure must not blank the dashboard. It
      // must not be reported as zeros either — storing CompanyStats.empty here
      // turned an unreadable workspace into a confidently empty one, which is
      // exactly the failure mode `usersUnknown` exists to prevent.
      _stats[companyId] = CompanyStats.empty;
      _statsFailed.add(companyId);
      notifyListeners();
    } finally {
      _statsInFlight.remove(companyId);
    }
  }

  /// Whether the counts held for [companyId] came from a failed read.
  bool statsFailedFor(String companyId) => _statsFailed.contains(companyId);

  /// Re-reads counts for one company after a change.
  Future<void> refreshStats(String companyId) async {
    _stats.remove(companyId);
    _statsFailed.remove(companyId);
    await loadStats(companyId);
  }

  /// Re-reads counts for the whole estate.
  ///
  /// [loadAllStats] delegates to [loadStats], which returns early for anything
  /// already cached — so the console's refresh buttons, built on it, did
  /// nothing at all after the first load. This drops the cache first.
  Future<void> reloadAllStats() async {
    _stats.clear();
    _statsFailed.clear();
    notifyListeners();
    await loadAllStats();
  }

  Future<bool> setPlan({
    required String companyId,
    required String planId,
    PlanStatus status = PlanStatus.active,
    DateTime? trialEndsAt,
    Map<String, int> limitOverrides = const {},
    String note = '',
  }) async {
    final company = companyById(companyId);
    return _run(
      () => _service.setPlan(
        companyId: companyId,
        planId: planId,
        status: status,
        trialEndsAt: trialEndsAt,
        limitOverrides: limitOverrides,
        note: note,
        actor: _actor,
        previous: company?.plan,
        companyName: company?.displayName,
      ),
      'Failed to change the plan.',
    );
  }

  Future<bool> setStatus({
    required String companyId,
    required CompanyStatus status,
    String note = '',
  }) async {
    final company = companyById(companyId);
    return _run(
      () => _service.setStatus(
        companyId: companyId,
        status: status,
        note: note,
        actor: _actor,
        previous: company?.status,
        companyName: company?.displayName,
      ),
      'Failed to change the company status.',
    );
  }

  /// Permanently deletes a company and everything under it. Irreversible.
  Future<bool> purgeCompany({
    required String companyId,
    void Function(String collection, int deleted)? onProgress,
  }) async {
    final company = companyById(companyId);
    final ok = await _run(
      () => _service.purgeCompany(
        companyId: companyId,
        onProgress: onProgress,
        actor: _actor,
        companyName: company?.displayName,
      ),
      'Failed to purge the company.',
    );
    if (ok) _stats.remove(companyId);
    return ok;
  }

  Future<bool> _run(Future<void> Function() action, String fallback) async {
    _errorMessage = null;
    try {
      await action();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clears everything on sign-out. The [isSuperAdmin] flag especially must not
  /// survive into the next session.
  void reset() {
    _companiesSubscription?.cancel();
    _companiesSubscription = null;
    stopWatchingCompanyDetail();
    stopWatchingGlobalUsers();
    stopWatchingPlatformAudit();
    _inspectCompanyId = null;
    _inspectCompanyName = null;
    _actor = null;
    _isSuperAdmin = false;
    _resolvedForUid = null;
    _resolvingUid = null;
    _isLoading = false;
    _errorMessage = null;
    _companies = [];
    _stats.clear();
    _statsFailed.clear();
    _expandedStats.clear();
    _statsInFlight.clear();
    notifyListeners();
  }

  /// Streams every user across every tenant.
  ///
  /// This is the query the platform-admin branch on `/users` in the rules
  /// exists for. Before that branch it was denied outright, and because there
  /// was no [onError] the failure showed up as a permanent spinner rather than
  /// a message — which is exactly why the console looked like it could only see
  /// one workspace.
  void startWatchingGlobalUsers() {
    if (!_isSuperAdmin || _globalUsersSubscription != null) return;
    _globalUsersLoading = true;
    _globalUsersError = null;
    notifyListeners();
    _globalUsersSubscription = _service
        .getAllUsersGlobal(limit: globalUsersLimit)
        .listen(
          (users) {
            _globalUsers = users;
            _globalUsersLoading = false;
            _globalUsersError = null;
            notifyListeners();
          },
          onError: (Object error) {
            _globalUsersLoading = false;
            _globalUsersError = friendlyError(
              error,
              fallback: 'Could not load users across workspaces.',
            );
            notifyListeners();
          },
        );
  }

  void stopWatchingGlobalUsers() {
    _globalUsersSubscription?.cancel();
    _globalUsersSubscription = null;
    _globalUsers = [];
    _globalUsersLoading = false;
    _globalUsersError = null;
  }

  void startWatchingPlatformAudit() {
    if (!_isSuperAdmin || _auditSubscription != null) return;
    // An explicit loading flag, because "no rows yet" is a legitimate state for
    // this log: inferring loading from an empty list left a platform with no
    // recorded actions spinning forever.
    _platformAuditLoading = true;
    _platformAuditError = null;
    notifyListeners();
    _auditSubscription = _service
        .watchPlatformAuditLogs()
        .listen(
          (logs) {
            _platformAuditLogs = logs;
            _platformAuditLoading = false;
            _platformAuditError = null;
            notifyListeners();
          },
          onError: (Object error) {
            _platformAuditLoading = false;
            _platformAuditError = friendlyError(
              error,
              fallback: 'Could not load the platform audit log.',
            );
            notifyListeners();
          },
        );
  }

  void stopWatchingPlatformAudit() {
    _auditSubscription?.cancel();
    _auditSubscription = null;
    _platformAuditLogs = [];
    _platformAuditError = null;
    _platformAuditLoading = false;
  }

  /// Drops and re-opens the platform audit stream, for a retry action.
  void retryPlatformAudit() {
    stopWatchingPlatformAudit();
    startWatchingPlatformAudit();
  }

  /// Drops and re-opens the global users stream, for a retry action.
  void retryGlobalUsers() {
    stopWatchingGlobalUsers();
    startWatchingGlobalUsers();
  }

  /// Drops and re-opens one company section, for a retry action.
  void retrySection(SuperAdminSection section) {
    _detailSubscriptions.remove(section)?.cancel();
    _sectionData.remove(section);
    _sectionErrors.remove(section);
    watchSection(section);
  }

  /// Binds the console to [companyId] and loads the parts every tab needs.
  ///
  /// Per-section streams are opened lazily by [watchSection] as tabs are
  /// entered, so visiting a workspace no longer opens eight listeners at once.
  void startWatchingCompanyDetail(String companyId) {
    if (!_isSuperAdmin) return;
    if (_watchingCompanyId == companyId) return;

    stopWatchingCompanyDetail();
    _watchingCompanyId = companyId;

    _loadExpandedStats(companyId);
    _loadSettings(companyId);
  }

  /// Subscribes to one section of the company currently being watched.
  ///
  /// Idempotent, so a tab may call it from every build.
  void watchSection(SuperAdminSection section) {
    final companyId = _watchingCompanyId;
    if (!_isSuperAdmin || companyId == null) return;
    if (_detailSubscriptions.containsKey(section)) return;

    _sectionErrors.remove(section);
    _detailSubscriptions[section] = _streamFor(companyId, section).listen(
      (data) {
        _sectionData[section] = data;
        _sectionErrors.remove(section);
        notifyListeners();
      },
      onError: (Object error) {
        _sectionErrors[section] = friendlyError(
          error,
          fallback: 'Could not load this data.',
        );
        notifyListeners();
      },
    );
    notifyListeners();
  }

  Stream<List<Map<String, dynamic>>> _streamFor(
    String companyId,
    SuperAdminSection section,
  ) => switch (section) {
    SuperAdminSection.users => _service.watchCompanyUsers(companyId),
    SuperAdminSection.roles => _service.watchCompanyRoles(companyId),
    SuperAdminSection.products => _service.watchCompanyProducts(
      companyId,
      limit: 200,
    ),
    SuperAdminSection.invoices => _service.watchCompanyInvoices(
      companyId,
      limit: 200,
    ),
    SuperAdminSection.salesOrders => _service.watchCompanySalesOrders(
      companyId,
      limit: 200,
    ),
    SuperAdminSection.purchaseOrders => _service.watchCompanyPurchaseOrders(
      companyId,
      limit: 200,
    ),
    SuperAdminSection.transactions => _service.watchCompanyTransactions(
      companyId,
      limit: 200,
    ),
    SuperAdminSection.auditLogs => _service.watchCompanyAuditLogs(
      companyId,
      limit: 200,
    ),
  };

  /// Closes the company detail streams.
  ///
  /// [companyId] scopes the teardown: the detail screen tears down from a
  /// post-frame callback, by which point a *different* company may already be
  /// bound, and an unconditional clear left that new screen with no streams and
  /// every tab showing a false "this workspace has none".
  void stopWatchingCompanyDetail([String? companyId]) {
    if (companyId != null && _watchingCompanyId != companyId) return;
    for (final sub in _detailSubscriptions.values) {
      sub.cancel();
    }
    _detailSubscriptions.clear();
    _sectionData.clear();
    _sectionErrors.clear();
    _watchingCompanyId = null;
    _companySettings = null;
    _companySettingsLoading = false;
    _companySettingsError = null;
    notifyListeners();
  }

  Future<void> _loadExpandedStats(String companyId) async {
    try {
      _expandedStats[companyId] = await _service.expandedCompanyStats(
        companyId,
      );
      notifyListeners();
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not load counts.');
      notifyListeners();
    }
  }

  Future<void> _loadSettings(String companyId) async {
    _companySettingsLoading = true;
    _companySettingsError = null;
    notifyListeners();
    try {
      _companySettings = await _service.getCompanySettings(companyId);
      _companySettingsLoading = false;
      notifyListeners();
    } catch (e) {
      _companySettingsLoading = false;
      _companySettingsError = friendlyError(
        e,
        fallback: 'Could not load workspace settings.',
      );
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Read-only workspace inspection
  // ---------------------------------------------------------------------------

  /// Enters [company] as a read-only observer.
  ///
  /// The app shell reads [inspectCompanyId] and boots the ordinary tenant UI
  /// bound to it, which is why the console does not reimplement a single tenant
  /// screen. Writes are refused by the security rules, which grant a platform
  /// admin only read and delete under `companies/{id}` — the view-only
  /// permission map the shell applies is convenience, the rule is the control.
  void enterWorkspace(CompanyModel company) {
    if (!_isSuperAdmin) return;
    _inspectCompanyId = company.id;
    _inspectCompanyName = company.displayName;
    unawaited(
      _service.logInspection(
        actor: _actor,
        companyId: company.id,
        companyName: company.displayName,
        entering: true,
      ),
    );
    notifyListeners();
  }

  void exitWorkspace() {
    final id = _inspectCompanyId;
    final name = _inspectCompanyName;
    if (id == null) return;
    _inspectCompanyId = null;
    _inspectCompanyName = null;
    unawaited(
      _service.logInspection(
        actor: _actor,
        companyId: id,
        companyName: name ?? id,
        entering: false,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _companiesSubscription?.cancel();
    _globalUsersSubscription?.cancel();
    _auditSubscription?.cancel();
    for (final sub in _detailSubscriptions.values) {
      sub.cancel();
    }
    _detailSubscriptions.clear();
    super.dispose();
  }
}
