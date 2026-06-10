import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/stock_take_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class StockTakeProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<StockTakeModel> _stockTakes = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<StockTakeModel> get stockTakes => _stockTakes;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _stockTakes = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _subscription = _databaseService.getStockTakes().listen(
      (stockTakes) {
        _stockTakes = stockTakes;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load stock takes.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<bool> addStockTake(StockTakeModel stockTake) async {
    try {
      _errorMessage = null;
      await _databaseService.addStockTake(stockTake);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to create stock take.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStockTake(StockTakeModel stockTake) async {
    try {
      _errorMessage = null;
      await _databaseService.updateStockTake(stockTake);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to update stock take.',
      );
      notifyListeners();
      return false;
    }
  }

  /// Finalizes a stock take: marks it completed, then records stock adjustments
  /// for every item whose counted qty differs from the expected qty.
  Future<bool> completeStockTake({
    required StockTakeModel stockTake,
    required String userId,
    required String userName,
  }) async {
    try {
      _errorMessage = null;

      final completed = stockTake.copyWith(
        status: StockTakeStatus.completed,
        completedAt: DateTime.now(),
      );
      await _databaseService.updateStockTake(completed);

      for (final item in stockTake.items) {
        final variance = item.countedQty - item.expectedQty;
        if (variance == 0) continue;

        await _databaseService.recordAdjustment(
          productId: item.productId,
          productName: item.productName,
          adjustmentDelta: variance,
          location: stockTake.locationFilter.isNotEmpty
              ? stockTake.locationFilter
              : 'Default',
          userId: userId,
          userName: userName,
          reason: 'Stock Take: ${stockTake.name}',
        );
      }

      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to complete stock take.',
      );
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
    _subscription?.cancel();
    super.dispose();
  }
}
