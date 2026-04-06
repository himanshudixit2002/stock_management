import 'dart:async';
import 'package:flutter/material.dart';
import '../models/purchase_order_model.dart';
import '../utils/error_helpers.dart';
import '../services/database_service.dart';

class PurchaseOrderProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<PurchaseOrderModel> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _ordersSubscription;

  List<PurchaseOrderModel> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<PurchaseOrderModel> ordersByStatus(POStatus status) =>
      _orders.where((o) => o.status == status).toList();

  PurchaseOrderModel? getOrderById(String id) {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _ordersSubscription?.cancel();
    _isLoading = true;
    _ordersSubscription = _databaseService.getPurchaseOrders().listen(
      (orders) {
        _orders = orders;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load purchase orders.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void reset() {
    _ordersSubscription?.cancel();
    _ordersSubscription = null;
    _orders = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> addOrder(PurchaseOrderModel order) async {
    if (_isLoading) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addPurchaseOrder(order);
      _isLoading = false;
      notifyListeners();
      return id;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to create purchase order.');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateOrder(PurchaseOrderModel order) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updatePurchaseOrder(order);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update purchase order.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteOrder(String id) async {
    if (_isLoading) return false;
    final order = getOrderById(id);
    if (order != null && order.invoiceId.isNotEmpty) {
      _errorMessage = 'Cannot delete an order with a linked invoice. Cancel the order instead.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.deletePurchaseOrder(id);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete purchase order.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> receiveOrder({
    required PurchaseOrderModel po,
    required String userId,
    required String userName,
    required String location,
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.receivePurchaseOrder(
        po: po,
        userId: userId,
        userName: userName,
        location: location,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to receive purchase order.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelOrder({
    required PurchaseOrderModel order,
    required String userId,
    required String userName,
    String defaultLocation = 'Main',
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Reverse stock if items were received
      if (order.status == POStatus.received ||
          order.status == POStatus.partial) {
        for (final item in order.items) {
          final qty = item.receivedQuantity;
          if (qty <= 0 || item.productId.isEmpty) continue;
          await _databaseService.removeStock(
            productId: item.productId,
            productName: item.productName,
            quantity: qty,
            location: defaultLocation,
            userId: userId,
            userName: userName,
            reason: 'Cancelled PO #${order.id.substring(0, 6)}',
          );
        }
      }

      // Clear linked invoice reference if exists
      if (order.invoiceId.isNotEmpty) {
        try {
          await _databaseService.clearPurchaseOrderInvoiceId(order.id);
        } catch (_) {}
      }

      final updated = order.copyWith(
        status: POStatus.cancelled,
        updatedAt: DateTime.now(),
      );
      await _databaseService.updatePurchaseOrder(updated);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to cancel purchase order.');
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
    _ordersSubscription?.cancel();
    super.dispose();
  }
}
