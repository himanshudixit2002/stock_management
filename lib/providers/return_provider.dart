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
    // Guard against double-processing: re-running would add/remove stock a
    // second time and double-count. Only an unprocessed return adjusts stock.
    final latestSnap = await _databaseService.getReturnById(returnModel.id);
    if (latestSnap == null) {
      _errorMessage = 'Return not found.';
      notifyListeners();
      return false;
    }
    if (latestSnap.status == ReturnStatus.processed) {
      _errorMessage = 'This return has already been processed.';
      notifyListeners();
      return false;
    }
    // Only an approved return may move stock. Previously anything that was not
    // already processed went through — including a *rejected* return, which
    // would happily push refused goods back into sellable stock.
    if (latestSnap.status != ReturnStatus.approved) {
      _errorMessage = latestSnap.status == ReturnStatus.rejected
          ? 'This return was rejected and cannot be processed.'
          : 'Approve this return before processing it.';
      notifyListeners();
      return false;
    }
    final actualReturn = latestSnap;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      for (final item in actualReturn.items) {
        if (item.quantity <= 0) continue;
        if (returnModel.type == ReturnType.customerReturn) {
          final ref = 'Return #${returnModel.id.substring(0, 6)}';
          // Goods always come back onto the books first, so the ledger shows
          // what was physically received...
          await db.addStock(
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            location: location,
            userId: userId,
            userName: userName,
            reason: ref,
          );
          // ...then unsellable goods are written straight off again, rather
          // than silently rejoining sellable stock. An unset condition keeps
          // the previous behaviour, so existing returns are unaffected.
          if (_isUnsellable(item.condition)) {
            await db.recordDamage(
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              location: location,
              userId: userId,
              userName: userName,
              reason: '$ref — returned ${item.condition.trim().toLowerCase()}',
            );
          }
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
      if (actualReturn.relatedOrderId.isNotEmpty) {
        if (returnModel.type == ReturnType.customerReturn) {
          final so = await db.getSalesOrderById(actualReturn.relatedOrderId);
          if (so != null) {
            final synced = applyCustomerReturnToSalesOrder(
              so,
              actualReturn.items,
              now,
            );
            await _databaseService.updateSalesOrder(synced);
          }
        } else {
          final po = await db.getPurchaseOrderById(actualReturn.relatedOrderId);
          if (po != null) {
            final synced = applyVendorReturnToPurchaseOrder(
              po,
              actualReturn.items,
              now,
            );
            await _databaseService.updatePurchaseOrder(synced);
          }
        }
      }

      final updated = actualReturn.copyWith(
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

  /// Conditions that mean returned goods must not rejoin sellable stock.
  /// Anything else (including an unset condition) is treated as resaleable.
  static bool _isUnsellable(String condition) {
    const unsellable = {'damaged', 'defective', 'expired', 'broken'};
    return unsellable.contains(condition.trim().toLowerCase());
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
