import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sales_order_model.dart';
import '../utils/error_helpers.dart';
import '../services/database_service.dart';

class SalesOrderProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<SalesOrderModel> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _ordersSubscription;

  List<SalesOrderModel> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<SalesOrderModel> ordersByStatus(SOStatus status) =>
      _orders.where((o) => o.status == status).toList();

  SalesOrderModel? getOrderById(String id) {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _ordersSubscription?.cancel();
    _isLoading = true;
    _ordersSubscription = _databaseService.getSalesOrders().listen(
      (orders) {
        _orders = orders;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load sales orders.',
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

  Future<String?> addOrder(SalesOrderModel order) async {
    if (_isLoading) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addSalesOrder(order);
      _isLoading = false;
      notifyListeners();
      return id;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to create sales order.');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateOrder(SalesOrderModel order) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateSalesOrder(order);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update sales order.');
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
      await _databaseService.deleteSalesOrder(id);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete sales order.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> dispatchOrder({
    required SalesOrderModel order,
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
      for (final item in order.items) {
        final qty = item.quantity - item.dispatchedQuantity;
        if (qty <= 0) continue;
        await db.removeStock(
          productId: item.productId,
          productName: item.productName,
          quantity: qty,
          location: location,
          userId: userId,
          userName: userName,
          reason: 'SO #${order.id.substring(0, 6)}',
        );
      }
      final updated = order.copyWith(
        status: SOStatus.dispatched,
        items: order.items
            .map((i) => i.copyWith(dispatchedQuantity: i.quantity))
            .toList(),
        updatedAt: DateTime.now(),
      );
      await _databaseService.updateSalesOrder(updated);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to dispatch sales order.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelOrder({
    required SalesOrderModel order,
    required String userId,
    required String userName,
    String defaultLocation = 'Main',
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Reverse stock if order was dispatched or delivered
      if (order.status == SOStatus.dispatched ||
          order.status == SOStatus.delivered) {
        for (final item in order.items) {
          final qty = item.dispatchedQuantity;
          if (qty <= 0 || item.productId.isEmpty) continue;
          await _databaseService.addStock(
            productId: item.productId,
            productName: item.productName,
            quantity: qty,
            location: defaultLocation,
            userId: userId,
            userName: userName,
            reason: 'Cancelled SO #${order.id.substring(0, 6)}',
          );
        }
      }

      // Cancel linked invoice if exists
      if (order.invoiceId.isNotEmpty) {
        try {
          await _databaseService.clearSalesOrderInvoiceId(order.id);
        } catch (_) {}
      }

      final updated = order.copyWith(
        status: SOStatus.cancelled,
        updatedAt: DateTime.now(),
      );
      await _databaseService.updateSalesOrder(updated);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to cancel sales order.');
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
