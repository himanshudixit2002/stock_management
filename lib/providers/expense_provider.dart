import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/expense_model.dart';
import '../services/database_service.dart';
import '../services/expense_summary_service.dart';
import '../utils/error_helpers.dart';

/// Operating spend: what leaves the business that is not stock.
class ExpenseProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<ExpenseModel> _expenses = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<ExpenseModel> get expenses => _expenses;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  /// Bills entered but not yet settled.
  List<ExpenseModel> get unpaid =>
      _expenses.where((e) => !e.isPaid).toList(growable: false);

  double get unpaidTotal => unpaid.fold(0.0, (acc, e) => acc + e.total);

  /// This calendar month, which is what the screen opens on.
  ExpenseSummary get currentMonth {
    final now = DateTime.now();
    return summaryFor(
      from: DateTime(now.year, now.month),
      to: DateTime(now.year, now.month + 1),
    );
  }

  ExpenseSummary summaryFor({DateTime? from, DateTime? to}) =>
      ExpenseSummaryService.summarise(_expenses, from: from, to: to);

  ExpenseModel? byId(String id) {
    final idx = _expenses.indexWhere((e) => e.id == id);
    return idx == -1 ? null : _expenses[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _expenses = [];
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

    _subscription = _databaseService.getExpenses().listen(
      (expenses) {
        _expenses = expenses;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load expenses.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addExpense(ExpenseModel expense) async {
    final result = await _run(
      () => _databaseService.addExpense(expense),
      'Failed to save the expense.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateExpense(ExpenseModel expense) async {
    final result = await _run(
      () => _databaseService.updateExpense(expense),
      'Failed to update the expense.',
    );
    return result != null;
  }

  Future<bool> deleteExpense(String id) async {
    final result = await _run(
      () => _databaseService.deleteExpense(id),
      'Failed to delete the expense.',
    );
    return result != null;
  }

  /// Marks an expense settled today.
  Future<bool> markPaid(ExpenseModel expense, {String method = ''}) async {
    return updateExpense(
      expense.copyWith(
        status: ExpenseStatus.paid,
        paidAt: DateTime.now(),
        paymentMethod: method.isEmpty ? expense.paymentMethod : method,
        updatedAt: DateTime.now(),
      ),
    );
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
