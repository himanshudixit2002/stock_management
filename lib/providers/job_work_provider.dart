import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/job_work_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Work sent out to subcontractors, and the stock that is with them.
class JobWorkProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<JobWorkOrderModel> _orders = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<JobWorkOrderModel> get orders => _orders;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  /// Jobs whose components are physically with a vendor right now.
  List<JobWorkOrderModel> get atVendor =>
      _orders.where((o) => o.isOut).toList(growable: false);

  List<JobWorkOrderModel> get overdue =>
      _orders.where((o) => o.isOverdue).toList(growable: false);

  /// Component units sitting in the vendor bucket across every open job.
  int get unitsAtVendor =>
      atVendor.fold(0, (acc, o) => acc + o.componentUnitsAtVendor);

  /// Finished units still expected back.
  int get outputAwaited =>
      atVendor.fold(0, (acc, o) => acc + o.remainingOutput);

  List<JobWorkOrderModel> forVendor(String vendorId) {
    if (vendorId.isEmpty) return const [];
    return _orders.where((o) => o.vendorId == vendorId).toList(growable: false);
  }

  JobWorkOrderModel? byId(String id) {
    final idx = _orders.indexWhere((o) => o.id == id);
    return idx == -1 ? null : _orders[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _orders = [];
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

    _subscription = _databaseService.getJobWorkOrders().listen(
      (orders) {
        _orders = orders;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load job work orders.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addOrder(JobWorkOrderModel order) async {
    final result = await _run(
      () => _databaseService.addJobWorkOrder(order),
      'Failed to save the job work order.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateOrder(JobWorkOrderModel order) async {
    final result = await _run(
      () => _databaseService.updateJobWorkOrder(order),
      'Failed to update the job work order.',
    );
    return result != null;
  }

  Future<bool> deleteOrder(String id) async {
    final result = await _run(
      () => _databaseService.deleteJobWorkOrder(id),
      'Failed to delete the job work order.',
    );
    return result != null;
  }

  Future<bool> issue({
    required JobWorkOrderModel order,
    required String userId,
    required String userName,
  }) async {
    final result = await _run(
      () => _databaseService.issueJobWork(
        order: order,
        userId: userId,
        userName: userName,
      ),
      'Could not issue the components.',
    );
    return result != null;
  }

  /// Receives finished goods. Returns the cost per unit that was computed, or
  /// null on failure — the detail screen reports it back to the user.
  Future<double?> receive({
    required JobWorkOrderModel order,
    required int units,
    required String userId,
    required String userName,
    bool closeShort = false,
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.receiveJobWork(
        order: order,
        units: units,
        userId: userId,
        userName: userName,
        closeShort: closeShort,
      );
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not receive the goods.');
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> close({
    required JobWorkOrderModel order,
    required String userId,
    required String userName,
  }) async {
    final result = await _run(
      () => _databaseService.closeJobWorkOrder(
        order: order,
        userId: userId,
        userName: userName,
      ),
      'Could not close the job.',
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
