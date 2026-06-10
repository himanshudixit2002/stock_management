import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sales_order_model.dart';
import '../utils/error_helpers.dart';
import '../services/database_service.dart';

class SalesOrderProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<SalesOrderModel> _orders = [];
  bool _isLoading = false;
  bool _isMutating = false;
  String? _errorMessage;
  StreamSubscription? _ordersSubscription;

  List<SalesOrderModel> get orders => _orders;
  bool get isLoading => _isLoading || _isMutating;
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
    _isMutating = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> addOrder(
    SalesOrderModel order, {
    String defaultLocation = 'Main',
  }) async {
    if (_isMutating) return null;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addSalesOrder(order);
      final createdOrder = order.copyWith(id: id);
      if (createdOrder.status == SOStatus.confirmed) {
        try {
          await _databaseService.syncSalesOrderHoldsOnConfirmOrEdit(
            order: createdOrder,
            previousOrder: null,
            userId: createdOrder.createdBy,
            userName: createdOrder.createdByName,
            defaultLocation: defaultLocation,
          );
        } catch (holdSyncErr) {
          try {
            await _databaseService.deleteSalesOrder(id);
          } catch (_) {}
          throw Exception('Could not reserve stock: $holdSyncErr');
        }
      }
      _isMutating = false;
      notifyListeners();
      return id;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to create sales order.',
      );
      _isMutating = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateOrder(
    SalesOrderModel order, {
    String defaultLocation = 'Main',
  }) async {
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final previousOrder = getOrderById(order.id);
      await _databaseService.updateSalesOrder(order);
      await _databaseService.syncSalesOrderHoldsOnConfirmOrEdit(
        order: order,
        previousOrder: previousOrder,
        userId: order.createdBy,
        userName: order.createdByName,
        defaultLocation: defaultLocation,
      );
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to update sales order.',
      );
      _isMutating = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteOrder(String id) async {
    if (_isMutating) return false;
    final order = getOrderById(id);
    if (order != null && order.invoiceId.isNotEmpty) {
      _errorMessage =
          'Cannot delete an order with a linked invoice. Cancel the order instead.';
      notifyListeners();
      return false;
    }
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.deleteSalesOrder(id);
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to delete sales order.',
      );
      _isMutating = false;
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
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      for (final item in order.items) {
        final qty = item.quantity - item.dispatchedQuantity;
        if (qty <= 0) continue;

        // Despatch this order's reserved units from the exact locations they
        // were held at first (avoids leaving phantom held/on-hand when the
        // dispatch location differs from the hold location).
        final holds = await db.getActiveHoldsForSource(
          sourceType: 'sales_order',
          sourceId: order.id,
          productId: item.productId,
        );
        final heldByLocation = <String, int>{};
        for (final hold in holds) {
          if (hold.remainingQuantity <= 0) continue;
          heldByLocation[hold.location] =
              (heldByLocation[hold.location] ?? 0) + hold.remainingQuantity;
        }

        var remainingQty = qty;
        for (final entry in heldByLocation.entries) {
          if (remainingQty <= 0) break;
          final take = entry.value < remainingQty ? entry.value : remainingQty;
          final consumed = await db.consumeHeldStockForOutbound(
            productId: item.productId,
            productName: item.productName,
            quantity: take,
            location: entry.key,
            userId: userId,
            userName: userName,
            sourceType: 'sales_order',
            sourceId: order.id,
            reason: 'SO #${order.id.substring(0, 6)} hold consumed',
          );
          remainingQty -= consumed;
        }

        if (remainingQty <= 0) continue;
        await db.removeStock(
          productId: item.productId,
          productName: item.productName,
          quantity: remainingQty,
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
      await _databaseService.syncSalesOrderHoldsOnConfirmOrEdit(
        order: updated,
        previousOrder: order,
        userId: userId,
        userName: userName,
        defaultLocation: location,
      );
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to dispatch sales order.',
      );
      _isMutating = false;
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
    if (_isMutating) return false;
    _isMutating = true;
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
      await _databaseService.syncSalesOrderHoldsOnConfirmOrEdit(
        order: order.copyWith(status: SOStatus.cancelled),
        previousOrder: order,
        userId: userId,
        userName: userName,
        defaultLocation: defaultLocation,
      );

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
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to cancel sales order.',
      );
      _isMutating = false;
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
