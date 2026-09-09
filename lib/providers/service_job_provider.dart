import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/service_job_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Repairs and warranty jobs.
class ServiceJobProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<ServiceJobModel> _jobs = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<ServiceJobModel> get jobs => _jobs;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  List<ServiceJobModel> get open =>
      _jobs.where((j) => j.isOpen).toList(growable: false);

  List<ServiceJobModel> get overdue =>
      _jobs.where((j) => j.isOverdue).toList(growable: false);

  List<ServiceJobModel> get awaitingParts => _jobs
      .where((j) => j.isOpen && j.hasUnissuedParts)
      .toList(growable: false);

  /// Every job raised against one serialised unit, newest first — the history a
  /// counter needs when the same machine comes back for the third time.
  List<ServiceJobModel> forSerial(String serialId) {
    if (serialId.isEmpty) return const [];
    return _jobs.where((j) => j.serialId == serialId).toList(growable: false);
  }

  List<ServiceJobModel> forCustomer(String customerId) {
    if (customerId.isEmpty) return const [];
    return _jobs
        .where((j) => j.customerId == customerId)
        .toList(growable: false);
  }

  /// Value sitting in open jobs — work done but not yet billed.
  double get openBillableValue =>
      open.fold(0.0, (acc, j) => acc + j.billableTotal);

  ServiceJobModel? byId(String id) {
    final idx = _jobs.indexWhere((j) => j.id == id);
    return idx == -1 ? null : _jobs[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _jobs = [];
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _databaseService.getServiceJobs().listen(
      (jobs) {
        _jobs = jobs;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load service jobs.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addJob(ServiceJobModel job) async {
    final result = await _run(
      () => _databaseService.addServiceJob(job),
      'Failed to save the job.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateJob(ServiceJobModel job) async {
    final result = await _run(
      () => _databaseService.updateServiceJob(job),
      'Failed to update the job.',
    );
    return result != null;
  }

  Future<bool> deleteJob(String id) async {
    final result = await _run(
      () => _databaseService.deleteServiceJob(id),
      'Failed to delete the job.',
    );
    return result != null;
  }

  /// Takes the job's unissued parts out of stock. Returns the units issued, or
  /// null on failure — the caller reports "Issued 3 parts", which a bool cannot
  /// carry.
  Future<int?> issueParts({
    required ServiceJobModel job,
    required String location,
    required String userId,
    required String userName,
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.issueServiceParts(
        job: job,
        location: location,
        userId: userId,
        userName: userName,
      );
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not issue the parts.');
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> setStatus({
    required ServiceJobModel job,
    required ServiceJobStatus status,
    required String userId,
    required String userName,
    String resolution = '',
  }) async {
    final result = await _run(
      () => _databaseService.setServiceJobStatus(
        job: job,
        status: status,
        userId: userId,
        userName: userName,
        resolution: resolution,
      ),
      'Could not update the job.',
    );
    return result != null;
  }

  Future<Object?> _run(
    Future<Object?> Function() action,
    String fallback,
  ) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action() ?? true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
