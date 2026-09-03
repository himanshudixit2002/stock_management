import 'dart:async';
import 'package:flutter/material.dart';
import '../models/invoice_model.dart';
import '../models/return_model.dart';
import '../utils/error_helpers.dart';
import '../utils/order_return_sync.dart';
import '../services/database_service.dart';

class ReturnProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<ReturnModel> _returns = [];
  bool _isLoading = false;

  /// In-flight guard for mutations, kept separate from [_isLoading].
  ///
  /// The two were the same flag, and the returns snapshot listener sets
  /// [_isLoading] false — so a mutation's own write coming back down the stream
  /// released the guard while the call was still running.
  bool _isMutating = false;
  String? _errorMessage;
  StreamSubscription? _returnsSubscription;

  List<ReturnModel> get returns => _returns;
  bool get isLoading => _isLoading || _isMutating;
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
    _isMutating = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> addReturn(ReturnModel returnModel) async {
    if (_isMutating) return null;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addReturn(returnModel);
      _isMutating = false;
      notifyListeners();
      return id;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to create return.');
      _isMutating = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateReturn(ReturnModel returnModel) async {
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateReturn(returnModel);
      _isMutating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update return.');
      _isMutating = false;
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
    if (_isMutating) return false;
    // Taken *before* the first await. It used to be set after the status read
    // below, which left a window where two overlapping calls both saw
    // `approved` and both moved stock.
    _isMutating = true;
    // finally, not a clear at each exit: every early return below would
    // otherwise leave the guard set and lock out all later mutations.
    try {
      return await _processReturnGuarded(
        returnModel: returnModel,
        userId: userId,
        userName: userName,
        location: location,
        db: db,
      );
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> _processReturnGuarded({
    required ReturnModel returnModel,
    required String userId,
    required String userName,
    required String location,
    required DatabaseService db,
  }) async {
    // Guard against double-processing: re-running would add/remove stock a
    // second time and double-count. Only an unprocessed return adjusts stock.
    final latestSnap = await _databaseService.getReturnById(returnModel.id);
    if (latestSnap == null) {
      _errorMessage = 'Return not found.';
      return false;
    }
    if (latestSnap.status == ReturnStatus.processed) {
      _errorMessage = 'This return has already been processed.';
      return false;
    }
    // Only an approved return may move stock. Previously anything that was not
    // already processed went through — including a *rejected* return, which
    // would happily push refused goods back into sellable stock.
    if (latestSnap.status != ReturnStatus.approved) {
      _errorMessage = latestSnap.status == ReturnStatus.rejected
          ? 'This return was rejected and cannot be processed.'
          : 'Approve this return before processing it.';
      return false;
    }
    final actualReturn = latestSnap;
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
      var refund = 0.0;
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

            // The money leg. Restoring stock without it left the customer
            // owing the full amount for goods they had sent back — and
            // refundAmount, which the detail screen displays, was never
            // assigned anywhere in the app.
            refund = await _issueRefundCreditNote(
              db: db,
              invoiceId: so.invoiceId,
              returnModel: actualReturn,
              userId: userId,
              userName: userName,
              now: now,
            );
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
        refundAmount: refund,
        updatedAt: now,
      );
      await _databaseService.updateReturn(updated);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to process return.');
      return false;
    }
  }

  /// Credits the source invoice for what came back, returning the amount.
  ///
  /// Prices the returned lines from the invoice itself, so the customer is
  /// credited what they were actually charged — including any per-line
  /// discount — rather than today's list price.
  ///
  /// Deliberately routed through `issueCreditNote`, the same path the Credit
  /// Note screen uses: it validates inside a transaction that the credit does
  /// not exceed `grandTotal - amountPaid - creditedAmount`, and it updates the
  /// invoice's balance and status. Duplicating that here would have been a
  /// second, unvalidated way to move money.
  ///
  /// Best-effort: the goods are already back on the shelf by this point, so a
  /// billing failure must not roll that back or block the return. It surfaces
  /// as a warning instead, and the credit can be raised by hand.
  Future<double> _issueRefundCreditNote({
    required DatabaseService db,
    required String invoiceId,
    required ReturnModel returnModel,
    required String userId,
    required String userName,
    required DateTime now,
  }) async {
    if (invoiceId.isEmpty) return 0;
    try {
      final invoice = await db.getInvoiceById(invoiceId);
      if (invoice == null || invoice.isCancelled || invoice.isDraft) return 0;

      final priceByProduct = <String, double>{};
      for (final line in invoice.items) {
        if (line.quantity <= 0) continue;
        // Per unit, after the line's own discount — what this customer paid.
        priceByProduct[line.productId] = line.lineTaxable / line.quantity;
      }

      var amount = 0.0;
      for (final item in returnModel.items) {
        final unit = priceByProduct[item.productId];
        if (unit == null || unit <= 0) continue;
        amount += unit * item.quantity;
      }
      amount = (amount * 100).roundToDouble() / 100;
      if (amount <= 0) return 0;

      // Never credit more than is still outstanding on the invoice.
      final creditable = invoice.grandTotal -
          invoice.amountPaid -
          invoice.creditedAmount;
      if (creditable <= 0.01) return 0;
      if (amount > creditable) amount = creditable;

      final number = await db.getNextCreditNoteNumber('CN');
      await db.issueCreditNote(
        sourceInvoiceId: invoice.id,
        creditNote: InvoiceModel(
          id: '',
          invoiceType: InvoiceType.creditNote,
          invoiceNumber: number,
          customerId: invoice.customerId,
          customerName: invoice.customerName,
          customerPhone: invoice.customerPhone,
          customerAddress: invoice.customerAddress,
          status: InvoiceStatus.sent,
          subtotal: amount,
          grandTotal: amount,
          amountDue: 0,
          notes: 'Return #${returnModel.id.substring(0, 6)}',
          invoiceDate: now,
          dueDate: now,
          createdBy: userId,
          createdByName: userName,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return amount;
    } catch (e) {
      _errorMessage =
          'Stock was returned, but the credit note could not be raised: '
          '${friendlyError(e, fallback: 'billing error')}. '
          'Issue it manually from the invoice.';
      return 0;
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
