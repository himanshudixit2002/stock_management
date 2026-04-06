import 'dart:async';
import 'package:flutter/material.dart';
import '../models/return_model.dart';
import '../utils/error_helpers.dart';
import '../utils/order_return_sync.dart';
import '../services/database_service.dart';

class ReturnProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<ReturnModel> _returns = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _returnsSubscription;

  List<ReturnModel> get returns => _returns;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<ReturnModel> returnsByType(ReturnType type) =>
      _returns.where((r) => r.type == type).toList();

  List<ReturnModel> returnsByStatus(ReturnStatus status) =>
      _returns.where((r) => r.status == status).toList();

  ReturnModel? getReturnById(String id) {
    for (final r in _returns) {
      if (r.id == id) return r;
    }
    return null;
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _returnsSubscription?.cancel();
    _isLoading = true;
    _returnsSubscription = _databaseService.getReturns().listen(
      (returns) {
        _returns = returns;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load returns.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void reset() {
    _returnsSubscription?.cancel();
    _returnsSubscription = null;
    _returns = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> addReturn(ReturnModel returnModel) async {
    if (_isLoading) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addReturn(returnModel);
      _isLoading = false;
      notifyListeners();
      return id;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to create return.');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateReturn(ReturnModel returnModel) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateReturn(returnModel);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update return.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> processReturn({
    required ReturnModel returnModel,
    required String userId,
    required String userName,
    required String location,
    required DatabaseService db,
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      for (final item in returnModel.items) {
        if (item.quantity <= 0) continue;
        if (returnModel.type == ReturnType.customerReturn) {
          await db.addStock(
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            location: location,
            userId: userId,
            userName: userName,
            reason: 'Return #${returnModel.id.substring(0, 6)}',
          );
        } else {
          await db.removeStock(
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            location: location,
            userId: userId,
            userName: userName,
            reason: 'Vendor Return #${returnModel.id.substring(0, 6)}',
          );
        }
      }

      final now = DateTime.now();
      if (returnModel.relatedOrderId.isNotEmpty) {
        if (returnModel.type == ReturnType.customerReturn) {
          final so = await db.getSalesOrderById(returnModel.relatedOrderId);
          if (so != null) {
            final synced = applyCustomerReturnToSalesOrder(
              so,
              returnModel.items,
              now,
            );
            await _databaseService.updateSalesOrder(synced);
          }
        } else {
          final po = await db.getPurchaseOrderById(returnModel.relatedOrderId);
          if (po != null) {
            final synced = applyVendorReturnToPurchaseOrder(
              po,
              returnModel.items,
              now,
            );
            await _databaseService.updatePurchaseOrder(synced);
          }
        }
      }

      final updated = returnModel.copyWith(
        status: ReturnStatus.processed,
        updatedAt: now,
      );
      await _databaseService.updateReturn(updated);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to process return.');
      _isLoading = false;
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
    _returnsSubscription?.cancel();
    super.dispose();
  }
}
