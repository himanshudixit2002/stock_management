import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_model.dart';
import '../services/super_admin_service.dart';
import '../utils/error_helpers.dart';

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
  Future<void> loadAllStats() async {
    for (final company in _companies) {
      await loadStats(company.id);
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
  Future<void> resolveSuperAdmin(String uid) async {
    if (uid.isEmpty) return;
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
    _isSuperAdmin = false;
    _resolvedForUid = null;
    _companies = [];
    _stats.clear();
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
      notifyListeners();
    } catch (_) {
      // Counts are informational; a failure must not blank the dashboard.
      _stats[companyId] = CompanyStats.empty;
      notifyListeners();
    } finally {
      _statsInFlight.remove(companyId);
    }
  }

  /// Re-reads counts for one company after a change.
  Future<void> refreshStats(String companyId) async {
    _stats.remove(companyId);
    await loadStats(companyId);
  }

  Future<bool> setPlan({
    required String companyId,
    required String planId,
    String note = '',
  }) async {
    return _run(
      () => _service.setPlan(companyId: companyId, planId: planId, note: note),
      'Failed to change the plan.',
    );
  }

  Future<bool> setStatus({
    required String companyId,
    required CompanyStatus status,
    String note = '',
  }) async {
    return _run(
      () =>
          _service.setStatus(companyId: companyId, status: status, note: note),
      'Failed to change the company status.',
    );
  }

  /// Permanently deletes a company and everything under it. Irreversible.
  Future<bool> purgeCompany({
    required String companyId,
    void Function(String collection, int deleted)? onProgress,
  }) async {
    final ok = await _run(
      () => _service.purgeCompany(companyId: companyId, onProgress: onProgress),
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
    _isSuperAdmin = false;
    _resolvedForUid = null;
    _resolvingUid = null;
    _isLoading = false;
    _errorMessage = null;
    _companies = [];
    _stats.clear();
    _statsInFlight.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _companiesSubscription?.cancel();
    super.dispose();
  }
}
