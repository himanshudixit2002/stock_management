import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/transfer_order_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Transfers between locations, including the stock currently on the road.
class TransferOrderProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<TransferOrderModel> _orders = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<TransferOrderModel> get orders => _orders;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  List<TransferOrderModel> get inTransit => _orders
      .where((o) => o.status == TransferOrderStatus.dispatched)
      .toList(growable: false);

  /// Shipments past their expected arrival date — the ones worth chasing.
  List<TransferOrderModel> get overdue =>
      _orders.where((o) => o.isOverdue).toList(growable: false);

  /// Units currently sitting in the in-transit bucket across all orders.
  int get unitsInTransit =>
      inTransit.fold(0, (acc, o) => acc + o.totalInTransit);

  TransferOrderModel? byId(String id) {
    final idx = _orders.indexWhere((o) => o.id == id);
    return idx == -1 ? null : _orders[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _orders = [];
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _databaseService.getTransferOrders().listen(
      (orders) {
        _orders = orders;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load transfer orders.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addOrder(TransferOrderModel order) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.addTransferOrder(order);
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to save the transfer order.',
      );
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> updateOrder(TransferOrderModel order) =>
      _guard(() => _databaseService.updateTransferOrder(order),
          'Failed to update the transfer order.');

  Future<bool> deleteOrder(String id) => _guard(
    () => _databaseService.deleteTransferOrder(id),
    'Failed to delete the transfer order.',
  );

  Future<bool> dispatch({
    required TransferOrderModel order,
    required String userId,
    required String userName,
  }) => _guard(
    () => _databaseService.dispatchTransferOrder(
      order: order,
      userId: userId,
      userName: userName,
    ),
    'Dispatch failed.',
  );

  Future<bool> receive({
    required TransferOrderModel order,
    required Map<String, int> quantities,
    required String userId,
    required String userName,
    bool closeShort = false,
  }) => _guard(
    () => _databaseService.receiveTransferOrder(
      order: order,
      quantities: quantities,
      userId: userId,
      userName: userName,
      closeShort: closeShort,
    ),
    'Receipt failed.',
  );

  Future<bool> cancel({
    required TransferOrderModel order,
    required String userId,
    required String userName,
  }) => _guard(
    () => _databaseService.cancelTransferOrder(
      order: order,
      userId: userId,
      userName: userName,
    ),
    'Could not cancel the transfer order.',
  );

  Future<bool> _guard(Future<void> Function() action, String fallback) async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
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
