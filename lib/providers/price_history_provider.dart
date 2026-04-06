import 'dart:async';
import 'package:flutter/material.dart';
import '../models/price_history_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class PriceHistoryProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<PriceHistoryModel> _history = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _historySubscription;

  List<PriceHistoryModel> get history => _history;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<PriceHistoryModel> historyForProduct(String productId) {
    return _history.where((h) => h.productId == productId).toList();
  }

  void reset() {
    _historySubscription?.cancel();
    _historySubscription = null;
    _history = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _historySubscription?.cancel();
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    _historySubscription = _databaseService.getPriceHistory().listen(
      (history) {
        _history = history;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load price history.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<bool> logPriceChange({
    required String productId,
    required String productName,
    required String field,
    required double oldValue,
    required double newValue,
    required String changedBy,
    required String changedByName,
  }) async {
    _errorMessage = null;
    try {
      final entry = PriceHistoryModel(
        id: '',
        productId: productId,
        productName: productName,
        field: field,
        oldValue: oldValue,
        newValue: newValue,
        changedBy: changedBy,
        changedByName: changedByName,
        timestamp: DateTime.now(),
      );
      await _databaseService.addPriceHistory(entry);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to log price change.');
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    super.dispose();
  }
}
