import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/budget_model.dart';
import '../models/expense_model.dart';
import '../models/invoice_model.dart';
import '../models/purchase_order_model.dart';
import '../services/budget_variance_service.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Period budgets, and how they are tracking.
class BudgetProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<BudgetModel> _budgets = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<BudgetModel> get budgets => _budgets;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  /// Budgets covering today, newest period first.
  List<BudgetModel> get current =>
      _budgets.where((b) => b.isActive && b.isCurrent).toList(growable: false);

  BudgetModel? byId(String id) {
    final idx = _budgets.indexWhere((b) => b.id == id);
    return idx == -1 ? null : _budgets[idx];
  }

  BudgetVarianceReport varianceFor({
    required BudgetModel budget,
    required List<InvoiceModel> invoices,
    required List<PurchaseOrderModel> purchaseOrders,
    required List<ExpenseModel> expenses,
  }) => BudgetVarianceService.analyse(
    budget: budget,
    invoices: invoices,
    purchaseOrders: purchaseOrders,
    expenses: expenses,
  );

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _budgets = [];
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

    _subscription = _databaseService.getBudgets().listen(
      (budgets) {
        _budgets = budgets;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load budgets.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addBudget(BudgetModel budget) async {
    final result = await _run(
      () => _databaseService.addBudget(budget),
      'Failed to save the budget.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateBudget(BudgetModel budget) async {
    final result = await _run(
      () => _databaseService.updateBudget(budget),
      'Failed to update the budget.',
    );
    return result != null;
  }

  Future<bool> deleteBudget(String id) async {
    final result = await _run(
      () => _databaseService.deleteBudget(id),
      'Failed to delete the budget.',
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
