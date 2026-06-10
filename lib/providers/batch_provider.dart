import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/batch_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class BatchProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<BatchModel> _batches = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<BatchModel> get batches => _batches;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _batches = [];
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

    _subscription = _databaseService.getBatches().listen(
      (batches) {
        _batches = batches;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load batches.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<bool> addBatch(BatchModel batch) async {
    try {
      _errorMessage = null;
      await _databaseService.addBatch(batch);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to add batch.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateBatch(BatchModel batch) async {
    try {
      _errorMessage = null;
      await _databaseService.updateBatch(batch);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update batch.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteBatch(String batchId) async {
    try {
      _errorMessage = null;
      await _databaseService.deleteBatch(batchId);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete batch.');
      notifyListeners();
      return false;
    }
  }

  List<BatchModel> getExpiringBatches(int days) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: days));
    return _batches
        .where(
          (b) =>
              b.status == BatchStatus.active &&
              b.expiryDate.isAfter(now) &&
              b.expiryDate.isBefore(cutoff),
        )
        .toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
  }

  List<BatchModel> get expiredBatches {
    final now = DateTime.now();
    return _batches
        .where(
          (b) => b.status == BatchStatus.active && b.expiryDate.isBefore(now),
        )
        .toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
  }

  List<BatchModel> get recalledBatches {
    return _batches.where((b) => b.status == BatchStatus.recalled).toList();
  }

  List<BatchModel> get activeBatches {
    final now = DateTime.now();
    return _batches
        .where(
          (b) => b.status == BatchStatus.active && b.expiryDate.isAfter(now),
        )
        .toList();
  }

  List<BatchModel> getBatchesByProduct(String productId) {
    return _batches.where((b) => b.productId == productId).toList();
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
