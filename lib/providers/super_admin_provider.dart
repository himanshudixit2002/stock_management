import 'dart:async';

import 'package:flutter/material.dart';

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
  bool _isLoading = false;
  String? _errorMessage;
  List<CompanyModel> _companies = [];
  StreamSubscription? _companiesSubscription;

  /// Per-company counts, filled in on demand so opening the dashboard does not
  /// fire an aggregation query for every tenant at once.
  final Map<String, CompanyStats> _stats = {};
  final Set<String> _statsInFlight = {};

  bool get isSuperAdmin => _isSuperAdmin;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<CompanyModel> get companies => _companies;

  /// Companies that are neither suspended nor deleted.
  List<CompanyModel> get activeCompanies =>
      _companies.where((c) => c.isActive).toList();

  int get suspendedCount => _companies.where((c) => c.isSuspended).length;
  int get deletedCount => _companies.where((c) => c.isDeleted).length;

  CompanyStats? statsFor(String companyId) => _stats[companyId];

  CompanyModel? companyById(String id) {
    for (final c in _companies) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Resolves whether this user is a super admin. Called once after sign-in.
  Future<void> resolveSuperAdmin(String uid) async {
    final result = await _service.isSuperAdmin(uid);
    if (result == _isSuperAdmin) return;
    _isSuperAdmin = result;
    notifyListeners();
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
