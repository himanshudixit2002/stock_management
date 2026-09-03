import 'dart:async';
import 'package:flutter/material.dart';
import '../models/purchase_order_model.dart';
import '../utils/error_helpers.dart';
import '../services/database_service.dart';

class PurchaseOrderProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<PurchaseOrderModel> _orders = [];
  bool _isLoading = false;

  /// In-flight guard for mutations, kept separate from [_isLoading].
  ///
  /// These two used to be the same flag, and the orders snapshot listener sets
  /// [_isLoading] false — so the moment a receipt's own write came back down
  /// the stream, the guard cleared while the call was still awaiting. A second
  /// tap on "Receive" then sailed through and added the stock again, advancing
  /// receivedQuantity twice. SalesOrderProvider already had it right.
  bool _isMutating = false;
  String? _errorMessage;
  StreamSubscription? _ordersSubscription;

  List<PurchaseOrderModel> get orders => _orders;
  bool get isLoading => _isLoading || _isMutating;
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
    _isMutating = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> addOrder(PurchaseOrderModel order) async {
    if (_isMutating) return null;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addPurchaseOrder(order);
      _isMutating = false;
      notifyListeners();
      return id;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to create purchase order.',
      );
      _isMutating = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateOrder(PurchaseOrderModel order) async {
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updatePurchaseOrder(order);
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to update purchase order.',
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
      await _databaseService.deletePurchaseOrder(id);
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to delete purchase order.',
      );
      _isMutating = false;
      notifyListeners();
      return false;
    }
  }

  /// Receives a purchase order. [receivedByItemIndex] carries the per-line
  /// quantities accepted (index into `po.items`); omit it to receive
  /// everything still outstanding.
  Future<bool> receiveOrder({
    required PurchaseOrderModel po,
    required String userId,
    required String userName,
    required String location,
    Map<int, int>? receivedByItemIndex,
  }) async {
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.receivePurchaseOrder(
        po: po,
        userId: userId,
        userName: userName,
        location: location,
        receivedByItemIndex: receivedByItemIndex,
      );
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to receive purchase order.',
      );
      _isMutating = false;
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
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Reverse stock if items were received.
      //
      // Each line is zeroed on the order as its stock comes back out, so a
      // failure partway leaves the order consistent with what actually
      // happened and a retry resumes rather than reversing the earlier lines a
      // second time. Previously the whole loop ran first and the order was only
      // updated afterwards, so an exception on line 3 of 5 left lines 1-2
      // reversed, the order still 'received', and the retry took their stock
      // out again.
      var working = order;
      if (order.status == POStatus.received ||
          order.status == POStatus.partial) {
        for (var i = 0; i < working.items.length; i++) {
          final item = working.items[i];
          final qty = item.receivedQuantity;
          if (qty <= 0 || item.productId.isEmpty) continue;

          // Back to where it was actually put. Falling back to the first
          // configured location — which is all this used to do — either threw
          // ("Not enough available stock at Main") and left the order
          // uncancellable, or silently deleted unrelated stock from it.
          final target = item.receivedLocation.trim().isNotEmpty
              ? item.receivedLocation
              : defaultLocation;

          await _databaseService.removeStock(
            productId: item.productId,
            productName: item.productName,
            quantity: qty,
            location: target,
            userId: userId,
            userName: userName,
            reason: 'Cancelled PO #${order.id.substring(0, 6)}',
          );

          final lines = List.of(working.items);
          lines[i] = item.copyWith(receivedQuantity: 0);
          working = working.copyWith(items: lines);
          await _databaseService.updatePurchaseOrder(working);
        }
      }

      // Clear linked invoice reference if exists
      if (order.invoiceId.isNotEmpty) {
        try {
          await _databaseService.clearPurchaseOrderInvoiceId(order.id);
        } catch (_) {}
      }

      final updated = working.copyWith(
        status: POStatus.cancelled,
        updatedAt: DateTime.now(),
      );
      await _databaseService.updatePurchaseOrder(updated);
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to cancel purchase order.',
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
