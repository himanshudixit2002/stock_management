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
    if (stockTake.status == StockTakeStatus.completed) return true;

    try {
      _errorMessage = null;

      final scopedLocation = stockTake.locationFilter.trim();

      for (final item in stockTake.items) {
        final variance = item.countedQty - item.expectedQty;
        if (variance == 0) continue;

        final location = scopedLocation.isNotEmpty
            ? scopedLocation
            : await _resolveUnscopedLocation(item.productId, item.productName);

        await _databaseService.recordAdjustment(
          productId: item.productId,
          productName: item.productName,
          adjustmentDelta: variance,
          location: location,
          userId: userId,
          userName: userName,
          reason: 'Stock Take: ${stockTake.name}',
        );
      }

      final completed = stockTake.copyWith(
        status: StockTakeStatus.completed,
        completedAt: DateTime.now(),
      );
      await _databaseService.updateStockTake(completed);

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

  /// Picks the location a variance belongs to when the stock take was not
  /// scoped to one.
  ///
  /// This used to post everything to the literal string 'Default' — a bucket
  /// no product actually holds stock in, so every shortage threw "would result
  /// in negative stock" and every surplus invented a phantom location. Resolve
  /// it from the product instead, and refuse rather than guess when the stock
  /// is genuinely spread across several locations.
  Future<String> _resolveUnscopedLocation(
    String productId,
    String productName,
  ) async {
    final product = await _databaseService.getProduct(productId);
    final stocked = product == null
        ? const <String>[]
        : product.locationQuantities.entries
              .where((e) => e.value > 0)
              .map((e) => e.key)
              .toList();

    if (stocked.length == 1) return stocked.first;
    // Nothing on hand anywhere: a surplus has to land somewhere, and 'Main' is
    // what DatabaseService._normalizeLocation treats as the default bucket.
    if (stocked.isEmpty) return 'Main';

    throw Exception(
      '$productName holds stock in ${stocked.length} locations, so this count '
      'cannot be applied to one of them. Run a stock take scoped to a single '
      'location for this product.',
    );
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
