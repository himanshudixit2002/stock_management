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
          // Release any holds the partial reservation may have created so they
          // don't outlive the order, then remove the order itself.
          try {
            await _databaseService.releaseHoldsForSource(
              sourceType: 'sales_order',
              sourceId: id,
              userId: createdOrder.createdBy,
              userName: createdOrder.createdByName,
              reason: 'SO reservation failed',
            );
          } catch (_) {}
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
      try {
        await _databaseService.syncSalesOrderHoldsOnConfirmOrEdit(
          order: order,
          previousOrder: previousOrder,
          userId: order.createdBy,
          userName: order.createdByName,
          defaultLocation: defaultLocation,
        );
      } catch (holdSyncErr) {
        // The status/items change was already persisted; roll it back so the
        // order doesn't end up confirmed-but-unreserved.
        if (previousOrder != null) {
          try {
            await _databaseService.updateSalesOrder(previousOrder);
          } catch (_) {}
        }
        // Only release holds when the previous state held none (e.g. a
        // draft/cancelled order being confirmed): any holds present were
        // created by this failed run. If the previous order was already
        // confirmed its holds are valid and must be left intact.
        final previousHeldStock = previousOrder?.status == SOStatus.confirmed;
        if (!previousHeldStock) {
          try {
            await _databaseService.releaseHoldsForSource(
              sourceType: 'sales_order',
              sourceId: order.id,
              userId: order.createdBy,
              userName: order.createdByName,
              reason: 'SO reservation failed',
            );
          } catch (_) {}
        }
        throw Exception('Could not reserve stock: $holdSyncErr');
      }
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

  /// Dispatch the entire remaining quantity of every line. Asks the caller for
  /// a single source location (used when the held location can't fully cover a
  /// line). Convenience wrapper around [dispatchOrderItems].
  Future<bool> dispatchOrder({
    required SalesOrderModel order,
    required String userId,
    required String userName,
    required String location,
    required DatabaseService db,
  }) async {
    final dispatchByIndex = <int, int>{};
    for (var i = 0; i < order.items.length; i++) {
      final remaining = order.items[i].remainingToDispatch;
      if (remaining > 0) dispatchByIndex[i] = remaining;
    }
    return dispatchOrderItems(
      order: order,
      dispatchByItemIndex: dispatchByIndex,
      userId: userId,
      userName: userName,
      location: location,
      db: db,
    );
  }

  /// Partially (or fully) dispatch a sales order. [dispatchByItemIndex] maps an
  /// item index to the number of units to dispatch now (capped at that line's
  /// remaining). Lines not present (or mapped to 0) are left untouched and stay
  /// reserved. The order becomes [SOStatus.dispatched] only once every line is
  /// fully dispatched; otherwise it stays [SOStatus.confirmed] (partial).
  Future<bool> dispatchOrderItems({
    required SalesOrderModel order,
    required Map<int, int> dispatchByItemIndex,
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
      final shortId = order.id.length >= 6 ? order.id.substring(0, 6) : order.id;
      final newItems = List<SOItem>.from(order.items);
      var anyDispatched = false;

      for (final entry in dispatchByItemIndex.entries) {
        final index = entry.key;
        if (index < 0 || index >= newItems.length) continue;
        final item = newItems[index];
        var qty = entry.value;
        if (qty <= 0) continue;
        if (qty > item.remainingToDispatch) qty = item.remainingToDispatch;
        if (qty <= 0) continue;

        // Consume this order's reserved units from the exact locations they
        // were held at first (avoids leaving phantom held/on-hand when the
        // dispatch location differs from the hold location), bounded by qty.
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
        for (final loc in heldByLocation.entries) {
          if (remainingQty <= 0) break;
          final take =
              loc.value < remainingQty ? loc.value : remainingQty;
          final consumed = await db.consumeHeldStockForOutbound(
            productId: item.productId,
            productName: item.productName,
            quantity: take,
            location: loc.key,
            userId: userId,
            userName: userName,
            sourceType: 'sales_order',
            sourceId: order.id,
            reason: 'SO #$shortId hold consumed',
          );
          remainingQty -= consumed;
        }

        if (remainingQty > 0) {
          await db.removeStock(
            productId: item.productId,
            productName: item.productName,
            quantity: remainingQty,
            location: location,
            userId: userId,
            userName: userName,
            reason: 'SO #$shortId',
          );
        }

        newItems[index] = item.copyWith(
          dispatchedQuantity: item.dispatchedQuantity + qty,
        );
        anyDispatched = true;
      }

      if (!anyDispatched) {
        _errorMessage = 'Select at least one item and quantity to dispatch.';
        _isMutating = false;
        notifyListeners();
        return false;
      }

      final fullyDispatched =
          newItems.isNotEmpty && newItems.every((i) => i.remainingToDispatch <= 0);
      final updated = order.copyWith(
        status: fullyDispatched ? SOStatus.dispatched : SOStatus.confirmed,
        items: newItems,
        updatedAt: DateTime.now(),
      );
      await _databaseService.updateSalesOrder(updated);

      // On full dispatch the order no longer needs holds, so let the sync
      // release any leftover reservations. On a partial dispatch the holds were
      // already reduced precisely by consumeHeldStockForOutbound, so re-syncing
      // would double-count; skip it.
      if (fullyDispatched) {
        await _databaseService.syncSalesOrderHoldsOnConfirmOrEdit(
          order: updated,
          previousOrder: order,
          userId: userId,
          userName: userName,
          defaultLocation: location,
        );
      }
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
