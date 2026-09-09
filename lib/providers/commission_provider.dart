import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/commission_plan_model.dart';
import '../models/invoice_model.dart';
import '../models/product_model.dart';
import '../services/commission_calculator.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Commission schemes, and the statements computed from them.
class CommissionProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<CommissionPlanModel> _plans = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<CommissionPlanModel> get plans => _plans;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  List<CommissionPlanModel> get activePlans =>
      _plans.where((p) => p.isActive).toList(growable: false);

  CommissionPlanModel? byId(String id) {
    final idx = _plans.indexWhere((p) => p.id == id);
    return idx == -1 ? null : _plans[idx];
  }

  /// What everybody earned over a period.
  ///
  /// Computed on demand rather than stored: a commission figure recomputed from
  /// the invoices is always the current truth, and a stored one is a snapshot
  /// nobody knows how to reproduce.
  CommissionRun runFor({
    required List<InvoiceModel> invoices,
    required List<ProductModel> products,
    required DateTime from,
    required DateTime to,
    Map<String, String> userNames = const {},
  }) => CommissionCalculator.run(
    invoices: invoices,
    plans: _plans,
    products: products,
    from: from,
    to: to,
    userNames: userNames,
  );

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _plans = [];
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

    _subscription = _databaseService.getCommissionPlans().listen(
      (plans) {
        _plans = plans;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load commission plans.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addPlan(CommissionPlanModel plan) async {
    final result = await _run(
      () => _databaseService.addCommissionPlan(plan),
      'Failed to save the commission plan.',
    );
    return result is String ? result : null;
  }

  Future<bool> updatePlan(CommissionPlanModel plan) async {
    final result = await _run(
      () => _databaseService.updateCommissionPlan(plan),
      'Failed to update the commission plan.',
    );
    return result != null;
  }

  Future<bool> deletePlan(String id) async {
    final result = await _run(
      () => _databaseService.deleteCommissionPlan(id),
      'Failed to delete the commission plan.',
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
