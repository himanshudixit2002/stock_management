import 'dart:async';
import 'package:flutter/material.dart';
import '../models/invoice_model.dart';
import '../models/purchase_order_model.dart';
import '../models/sales_order_model.dart';
import '../utils/error_helpers.dart';
import '../utils/invoice_search.dart';
import '../utils/invoice_totals.dart';
import '../utils/purchase_order_bill_sync.dart';
import '../utils/sales_order_invoice_sync.dart';
import '../services/database_service.dart';

class BillingProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<InvoiceModel> _invoices = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _invoicesSubscription;
  bool _checkingOverdue = false;

  List<InvoiceModel> get invoices => _invoices;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<InvoiceModel> get salesInvoices =>
      _invoices.where((i) => i.invoiceType == InvoiceType.sales).toList();

  /// Credit notes raised against sales invoices. Excluded from receivables:
  /// a credit reduces the balance of the invoice it references rather than
  /// standing as its own claim.
  List<InvoiceModel> get creditNotes =>
      _invoices.where((i) => i.isCreditNote).toList();

  /// Credit notes raised against a specific invoice, newest first.
  List<InvoiceModel> creditNotesForInvoice(String invoiceId) =>
      _invoices
          .where((i) => i.isCreditNote && i.creditedInvoiceId == invoiceId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<InvoiceModel> get purchaseInvoices =>
      _invoices.where((i) => i.invoiceType == InvoiceType.purchase).toList();

  List<InvoiceModel> invoicesByStatus(InvoiceStatus status) =>
      _invoices.where((i) => i.status == status).toList();

  List<InvoiceModel> invoicesForCustomer(String customerId) =>
      _invoices.where((i) => i.customerId == customerId && i.isSales).toList();

  List<InvoiceModel> invoicesForVendor(String vendorId) =>
      _invoices.where((i) => i.vendorId == vendorId && i.isPurchase).toList();

  InvoiceModel? getInvoiceById(String id) {
    for (final inv in _invoices) {
      if (inv.id == id) return inv;
    }
    return null;
  }

  /// Resolves a human-readable invoice/bill number (or compact variant) to a
  /// loaded invoice. Returns null if ambiguous (e.g. duplicate trailing seq).
  InvoiceModel? getInvoiceByInvoiceNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    InvoiceModel? exactCi;
    for (final inv in _invoices) {
      if (inv.invoiceNumber.toLowerCase() == trimmed.toLowerCase()) {
        exactCi = inv;
        break;
      }
    }
    if (exactCi != null) return exactCi;

    final qNorm = normalizeInvoiceSearchQuery(trimmed);
    final qCompact = compactInvoiceKey(qNorm);
    if (qCompact.isNotEmpty) {
      for (final inv in _invoices) {
        final invCompact = compactInvoiceKey(
          normalizeInvoiceSearchQuery(inv.invoiceNumber),
        );
        if (invCompact == qCompact) return inv;
      }
    }

    if (RegExp(r'^\d+$').hasMatch(qNorm)) {
      final qVal = int.tryParse(qNorm);
      if (qVal == null) return null;
      InvoiceModel? match;
      for (final inv in _invoices) {
        final m = RegExp(r'(\d+)\s*$').firstMatch(inv.invoiceNumber.trim());
        if (m == null) continue;
        final suffix = int.tryParse(m.group(1)!);
        if (suffix == qVal) {
          if (match != null) return null;
          match = inv;
        }
      }
      return match;
    }

    return null;
  }

  double get totalSalesInvoiced => _invoices
      .where((i) => !i.isCancelled && i.invoiceType == InvoiceType.sales)
      .fold(0.0, (s, i) => s + i.grandTotal);

  double get totalSalesReceived => _invoices
      .where((i) => !i.isCancelled && i.invoiceType == InvoiceType.sales)
      .fold(0.0, (s, i) => s + i.amountPaid);

  double get totalAccountsReceivable => totalSalesInvoiced - totalSalesReceived;

  double get totalPurchaseInvoiced => _invoices
      .where((i) => !i.isCancelled && i.invoiceType == InvoiceType.purchase)
      .fold(0.0, (s, i) => s + i.grandTotal);

  double get totalPurchasePaid => _invoices
      .where((i) => !i.isCancelled && i.invoiceType == InvoiceType.purchase)
      .fold(0.0, (s, i) => s + i.amountPaid);

  double get totalAccountsPayable => totalPurchaseInvoiced - totalPurchasePaid;
  
  // Keep legacy for compatibility if they are used elsewhere, but ideally remove them
  double get totalInvoiced => totalSalesInvoiced;
  double get totalReceived => totalSalesReceived;
  double get totalOutstanding => totalAccountsReceivable;

  int get overdueCount => _invoices
      .where(
        (i) =>
            i.isOverdue || (i.overdueDays > 0 && !i.isPaid && !i.isCancelled),
      )
      .length;

  List<InvoiceModel> get overdueInvoices => _invoices
      .where(
        (i) =>
            i.isOverdue || (i.overdueDays > 0 && !i.isPaid && !i.isCancelled),
      )
      .toList();

  double revenueForPeriod(DateTime start, DateTime end) {
    return _invoices
        .where(
          (i) =>
              !i.isCancelled &&
              i.invoiceDate.isAfter(
                start.subtract(const Duration(seconds: 1)),
              ) &&
              i.invoiceDate.isBefore(end.add(const Duration(days: 1))),
        )
        .fold(0.0, (s, i) => s + i.grandTotal);
  }

  double customerOutstanding(String customerId) {
    return invoicesForCustomer(customerId)
        .where((i) => !i.isCancelled && !i.isPaid)
        .fold(0.0, (s, i) => s + i.amountDue);
  }

  double vendorOutstanding(String vendorId) {
    return invoicesForVendor(vendorId)
        .where((i) => !i.isCancelled && !i.isPaid)
        .fold(0.0, (s, i) => s + i.amountDue);
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _invoicesSubscription?.cancel();
    _isLoading = true;
    _invoicesSubscription = _databaseService.getInvoices().listen(
      (invoices) {
        _invoices = invoices;
        _errorMessage = null;
        _checkOverdue();
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load invoices.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _checkOverdue() async {
    if (_checkingOverdue) return;
    _checkingOverdue = true;
    try {
      final now = DateTime.now();
      final overdue = _invoices
          .where(
            (inv) =>
                (inv.status == InvoiceStatus.sent ||
                    inv.status == InvoiceStatus.partiallyPaid) &&
                now.isAfter(inv.dueDate),
          )
          .toList();

      for (final inv in overdue) {
        await _databaseService.updateInvoice(
          inv.copyWith(status: InvoiceStatus.overdue, updatedAt: now),
        );
      }
    } finally {
      _checkingOverdue = false;
    }
  }

  void reset() {
    _invoicesSubscription?.cancel();
    _invoicesSubscription = null;
    _invoices = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> addInvoice(
    InvoiceModel invoice, {
    String userId = '',
    String userName = '',
    String defaultLocation = 'Main',
    bool autoCreateStandaloneSalesOrder = false,
    bool autoCreateStandalonePurchaseOrder = false,
  }) async {
    _errorMessage = null;
    final operationLocation = defaultLocation.trim().isEmpty
        ? 'Main'
        : defaultLocation.trim();
    try {
      final id = await _databaseService.addInvoice(invoice);

      // C2: Link invoice to sales/purchase order
      if (invoice.linkedSalesOrderId.isNotEmpty) {
        await _databaseService.setSalesOrderInvoiceId(
          invoice.linkedSalesOrderId,
          id,
        );
      }
      if (invoice.linkedPurchaseOrderId.isNotEmpty) {
        await _databaseService.setPurchaseOrderInvoiceId(
          invoice.linkedPurchaseOrderId,
          id,
        );
      }

      final now = DateTime.now();
      final runStockAndSoSync =
          invoice.invoiceType == InvoiceType.sales &&
          !invoice.isDraft &&
          invoice.items.isNotEmpty;

      if (runStockAndSoSync) {
        var shouldDeductStock = false;

        if (invoice.linkedSalesOrderId.isEmpty) {
          shouldDeductStock = true;
        } else {
          final so = await _databaseService.getSalesOrderById(
            invoice.linkedSalesOrderId,
          );
          if (so != null &&
              so.status != SOStatus.dispatched &&
              so.status != SOStatus.delivered) {
            shouldDeductStock = true;
          }
        }

        if (shouldDeductStock) {
          // Lines already taken out of stock, so a failure part-way through can
          // be undone. Without this the invoice was saved, some lines were
          // silently deducted, stockDeducted stayed false (so cancelling would
          // never put them back), and the caller was still handed a success id.
          final applied = <_AppliedDeduction>[];
          try {
            for (final item in invoice.items) {
              if (item.quantity <= 0 || item.productId.isEmpty) continue;
              final itemLocation = item.location.trim().isNotEmpty
                  ? item.location.trim()
                  : operationLocation;
              final consumedHold = await _databaseService
                  .consumeHeldStockForOutbound(
                    productId: item.productId,
                    productName: item.productName,
                    quantity: item.quantity,
                    location: itemLocation,
                    userId: userId,
                    userName: userName,
                    sourceType: 'invoice',
                    sourceId: id,
                    reason: 'INV #${invoice.invoiceNumber} hold consumed',
                  );
              if (consumedHold > 0) {
                applied.add(
                  _AppliedDeduction(
                    productId: item.productId,
                    productName: item.productName,
                    location: itemLocation,
                    quantity: consumedHold,
                  ),
                );
              }
              final remainingQty = item.quantity - consumedHold;
              if (remainingQty <= 0) continue;
              await _databaseService.removeStock(
                productId: item.productId,
                productName: item.productName,
                quantity: remainingQty,
                location: itemLocation,
                userId: userId,
                userName: userName,
                reason: 'INV #${invoice.invoiceNumber}',
              );
              applied.add(
                _AppliedDeduction(
                  productId: item.productId,
                  productName: item.productName,
                  location: itemLocation,
                  quantity: remainingQty,
                ),
              );
            }
            await _databaseService.setInvoiceStockDeducted(id, true);

            if (invoice.linkedSalesOrderId.isNotEmpty) {
              final so = await _databaseService.getSalesOrderById(
                invoice.linkedSalesOrderId,
              );
              if (so != null) {
                final updated = applyInvoiceFulfillment(so, invoice.items, now);
                await _databaseService.updateSalesOrder(updated);
              }
            } else if (autoCreateStandaloneSalesOrder) {
              final template = _buildAutoSalesOrderFromInvoice(
                invoice,
                invoiceId: id,
                userId: userId,
                userName: userName,
              );
              await _databaseService.createSalesOrderLinkedToInvoice(
                invoiceId: id,
                orderWithoutDocId: template,
              );
            }
          } catch (stockErr) {
            // Put back whatever already left stock, and park the invoice as a
            // draft so it is never presented as a completed sale that moved no
            // goods. The user can fix the cause and re-issue it.
            final undone = await _rollbackDeductions(
              applied,
              userId: userId,
              userName: userName,
              reason: 'Rolled back INV #${invoice.invoiceNumber}',
            );
            await _parkInvoiceAsDraft(id, invoice);
            _errorMessage = undone
                ? 'Could not deduct stock for this invoice, so it was saved as '
                      'a draft and no stock was moved: $stockErr'
                : 'Could not deduct stock for this invoice ($stockErr), and '
                      'reversing the partial deduction also failed. Check '
                      'stock levels for this invoice before re-issuing it.';
            notifyListeners();
            return null;
          }
        }
      }

      final runStockAndPoSync =
          invoice.invoiceType == InvoiceType.purchase &&
          !invoice.isDraft &&
          invoice.items.isNotEmpty;

      if (runStockAndPoSync) {
        var shouldAddStock = false;

        if (invoice.linkedPurchaseOrderId.isEmpty) {
          shouldAddStock = true;
        } else {
          final po = await _databaseService.getPurchaseOrderById(
            invoice.linkedPurchaseOrderId,
          );
          if (po != null && !_purchaseOrderFullyReceived(po)) {
            shouldAddStock = true;
          }
        }

        if (shouldAddStock) {
          final applied = <_AppliedDeduction>[];
          try {
            for (final item in invoice.items) {
              if (item.quantity <= 0 || item.productId.isEmpty) continue;
              final itemLocation = item.location.trim().isNotEmpty
                  ? item.location.trim()
                  : operationLocation;
              await _databaseService.addStock(
                productId: item.productId,
                productName: item.productName,
                quantity: item.quantity,
                location: itemLocation,
                userId: userId,
                userName: userName,
                reason: 'BILL #${invoice.invoiceNumber}',
              );
              applied.add(
                _AppliedDeduction(
                  productId: item.productId,
                  productName: item.productName,
                  location: itemLocation,
                  quantity: item.quantity,
                ),
              );
            }
            await _databaseService.setInvoiceStockDeducted(id, true);

            if (invoice.linkedPurchaseOrderId.isNotEmpty) {
              final po = await _databaseService.getPurchaseOrderById(
                invoice.linkedPurchaseOrderId,
              );
              if (po != null) {
                final updated = applyBillReceipt(po, invoice.items, now);
                await _databaseService.updatePurchaseOrder(updated);
              }
            } else if (autoCreateStandalonePurchaseOrder) {
              final template = _buildAutoPurchaseOrderFromInvoice(
                invoice,
                invoiceId: id,
                userId: userId,
                userName: userName,
              );
              await _databaseService.createPurchaseOrderLinkedToInvoice(
                invoiceId: id,
                orderWithoutDocId: template,
              );
            }
          } catch (stockErr) {
            // A bill adds stock, so rolling back means taking it out again.
            final undone = await _rollbackDeductions(
              applied,
              userId: userId,
              userName: userName,
              reason: 'Rolled back BILL #${invoice.invoiceNumber}',
              inbound: true,
            );
            await _parkInvoiceAsDraft(id, invoice);
            _errorMessage = undone
                ? 'Could not receive stock for this bill, so it was saved as a '
                      'draft and no stock was moved: $stockErr'
                : 'Could not receive stock for this bill ($stockErr), and '
                      'reversing the partial receipt also failed. Check stock '
                      'levels for this bill before re-issuing it.';
            notifyListeners();
            return null;
          }
        }
      }

      return id;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to create invoice.');
      notifyListeners();
      return null;
    }
  }

  /// Reverses stock movements already applied for an invoice whose remaining
  /// lines failed. [inbound] true means the original movements *added* stock
  /// (a purchase bill), so undoing them removes it again.
  ///
  /// Reversing a consumed hold restores the on-hand count but not the
  /// reservation — the hold stays consumed. Stock totals end up correct; a
  /// reservation may need re-creating by hand.
  Future<bool> _rollbackDeductions(
    List<_AppliedDeduction> applied, {
    required String userId,
    required String userName,
    required String reason,
    bool inbound = false,
  }) async {
    var allUndone = true;
    for (final entry in applied.reversed) {
      try {
        if (inbound) {
          await _databaseService.removeStock(
            productId: entry.productId,
            productName: entry.productName,
            quantity: entry.quantity,
            location: entry.location,
            userId: userId,
            userName: userName,
            reason: reason,
          );
        } else {
          await _databaseService.addStock(
            productId: entry.productId,
            productName: entry.productName,
            quantity: entry.quantity,
            location: entry.location,
            userId: userId,
            userName: userName,
            reason: reason,
          );
        }
      } catch (_) {
        allUndone = false;
      }
    }
    return allUndone;
  }

  /// Parks an invoice back as a draft after its stock leg failed, so it is
  /// never left looking like a completed document that moved no goods.
  Future<void> _parkInvoiceAsDraft(String id, InvoiceModel invoice) async {
    try {
      await _databaseService.updateInvoice(
        invoice.copyWith(
          id: id,
          status: InvoiceStatus.draft,
          stockDeducted: false,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Best effort: the caller already surfaces the underlying stock error.
    }
  }

  /// Raises a credit note against [sourceInvoiceId], reducing that invoice's
  /// balance. Returns the credit note id, or null on failure.
  Future<String?> issueCreditNote({
    required String sourceInvoiceId,
    required InvoiceModel creditNote,
  }) async {
    _errorMessage = null;
    try {
      return await _databaseService.issueCreditNote(
        sourceInvoiceId: sourceInvoiceId,
        creditNote: creditNote,
      );
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to issue credit note.',
      );
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateInvoice(InvoiceModel invoice) async {
    _errorMessage = null;
    try {
      await _databaseService.updateInvoice(invoice);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update invoice.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteInvoice(String id) async {
    _errorMessage = null;
    try {
      await _databaseService.deleteInvoice(id);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete invoice.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAsSent(String id) async {
    final inv = getInvoiceById(id);
    if (inv == null) return false;
    return updateInvoice(
      inv.copyWith(status: InvoiceStatus.sent, updatedAt: DateTime.now()),
    );
  }

  Future<bool> markAsCancelled(
    String id, {
    String userId = '',
    String userName = '',
    String defaultLocation = 'Main',
  }) async {
    final inv = getInvoiceById(id);
    if (inv == null) return false;
    
    // Check the money, not the status: a part-paid invoice that is past due
    // carries status `overdue`, so a status-based guard would let it through
    // and strand the cash (cancelled invoices are excluded from both
    // totalInvoiced and totalReceived).
    if (inv.amountPaid > 0.01) {
      _errorMessage =
          'This invoice has payments recorded against it. Refund or issue a '
          'credit note instead of cancelling it.';
      notifyListeners();
      return false;
    }
    
    final operationLocation = defaultLocation.trim().isEmpty
        ? 'Main'
        : defaultLocation.trim();

    final success = await updateInvoice(
      inv.copyWith(status: InvoiceStatus.cancelled, updatedAt: DateTime.now()),
    );

    if (!success) return false;

    var didReverseSalesStock = false;
    if (inv.stockDeducted && inv.isSales) {
      try {
        for (final item in inv.items) {
          if (item.quantity <= 0 || item.productId.isEmpty) continue;
          final itemLocation = item.location.trim().isNotEmpty
              ? item.location.trim()
              : operationLocation;
          await _databaseService.addStock(
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            location: itemLocation,
            userId: userId,
            userName: userName,
            reason: 'Cancelled INV #${inv.invoiceNumber}',
          );
        }
        await _databaseService.setInvoiceStockDeducted(id, false);
        didReverseSalesStock = true;
      } catch (e) {
        _errorMessage = 'Invoice cancelled but stock reversal failed: $e';
        notifyListeners();
      }
    }

    var didReversePurchaseStock = false;
    if (inv.stockDeducted && inv.isPurchase) {
      try {
        for (final item in inv.items) {
          if (item.quantity <= 0 || item.productId.isEmpty) continue;
          final itemLocation = item.location.trim().isNotEmpty
              ? item.location.trim()
              : operationLocation;
          await _databaseService.removeStock(
            productId: item.productId,
            productName: item.productName,
            quantity: item.quantity,
            location: itemLocation,
            userId: userId,
            userName: userName,
            reason: 'Cancelled BILL #${inv.invoiceNumber}',
          );
        }
        await _databaseService.setInvoiceStockDeducted(id, false);
        didReversePurchaseStock = true;
      } catch (e) {
        _errorMessage =
            'Invoice cancelled but purchase stock reversal failed: $e';
        notifyListeners();
      }
    }

    try {
      if (inv.linkedSalesOrderId.isNotEmpty) {
        if (didReverseSalesStock) {
          final so = await _databaseService.getSalesOrderById(
            inv.linkedSalesOrderId,
          );
          if (so != null) {
            final now = DateTime.now();
            if (so.originInvoiceId == inv.id) {
              await _databaseService.updateSalesOrder(
                so.copyWith(
                  status: SOStatus.cancelled,
                  invoiceId: '',
                  updatedAt: now,
                ),
              );
            } else {
              final reverted = revertInvoiceFulfillment(so, inv.items, now);
              await _databaseService.updateSalesOrder(
                reverted.copyWith(invoiceId: '', updatedAt: now),
              );
            }
          } else {
            await _databaseService.clearSalesOrderInvoiceId(
              inv.linkedSalesOrderId,
            );
          }
        } else {
          await _databaseService.clearSalesOrderInvoiceId(
            inv.linkedSalesOrderId,
          );
        }
      }
      if (inv.linkedPurchaseOrderId.isNotEmpty) {
        if (didReversePurchaseStock) {
          final po = await _databaseService.getPurchaseOrderById(
            inv.linkedPurchaseOrderId,
          );
          if (po != null) {
            final now = DateTime.now();
            if (po.originInvoiceId == inv.id) {
              await _databaseService.updatePurchaseOrder(
                po.copyWith(
                  status: POStatus.cancelled,
                  invoiceId: '',
                  updatedAt: now,
                ),
              );
            } else {
              final reverted = revertBillReceipt(po, inv.items, now);
              await _databaseService.updatePurchaseOrder(
                reverted.copyWith(invoiceId: '', updatedAt: now),
              );
            }
          } else {
            await _databaseService.clearPurchaseOrderInvoiceId(
              inv.linkedPurchaseOrderId,
            );
          }
        } else {
          await _databaseService.clearPurchaseOrderInvoiceId(
            inv.linkedPurchaseOrderId,
          );
        }
      }
    } catch (_) {}

    return true;
  }

  Future<bool> recordPayment(String invoiceId, PaymentRecord payment) async {
    _errorMessage = null;
    try {
      await _databaseService.recordPaymentOnInvoice(
        invoiceId,
        payment,
      );
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to record payment.');
      notifyListeners();
      return false;
    }
  }

  Future<String?> getNextInvoiceNumber(
    String prefix, {
    InvoiceType type = InvoiceType.sales,
  }) async {
    try {
      if (type == InvoiceType.purchase) {
        return await _databaseService.getNextPurchaseInvoiceNumber(prefix);
      }
      return await _databaseService.getNextInvoiceNumber(prefix);
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to generate invoice number.',
      );
      notifyListeners();
      return null;
    }
  }

  InvoiceModel createFromSalesOrder({
    required SalesOrderModel order,
    required String invoiceNumber,
    required String taxLabel,
    required double defaultTaxRate,
    required String termsText,
    required String createdBy,
    required String createdByName,
    required DateTime dueDate,
  }) {
    final now = DateTime.now();
    final items = order.items
        .map(
          (i) => InvoiceItem(
            productId: i.productId,
            productName: i.productName,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
            taxRate: defaultTaxRate,
          ),
        )
        .toList();
    final totals = calculateInvoiceTotals(
      lines: items.map((i) => InvoiceTotalsLineInput(
        quantity: i.quantity,
        unitPrice: i.unitPrice,
        lineDiscountPercent: i.discountPercent,
        lineTaxRate: i.taxRate,
      )).toList(),
      invoiceDiscountPercent: 0,
      invoiceDiscountAmount: 0,
      taxEnabled: defaultTaxRate > 0 || items.any((i) => i.taxRate > 0),
      discountEnabled: items.any((i) => i.discountPercent > 0),
    );
    return InvoiceModel(
      id: '',
      invoiceNumber: invoiceNumber,
      customerId: order.customerId,
      customerName: order.customerName,
      status: InvoiceStatus.draft,
      items: items,
      taxLabel: taxLabel,
      subtotal: totals.subtotal,
      totalTax: totals.totalTax,
      grandTotal: totals.grandTotal,
      amountDue: totals.grandTotal,
      totalDiscount: totals.totalDiscount,
      invoiceDiscount: totals.invoiceDiscount,
      invoiceDate: now,
      dueDate: dueDate,
      termsText: termsText,
      linkedSalesOrderId: order.id,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: now,
      updatedAt: now,
    );
  }

  InvoiceModel createFromPurchaseOrder({
    required PurchaseOrderModel order,
    required String invoiceNumber,
    required String taxLabel,
    required double defaultTaxRate,
    required String termsText,
    required String notes,
    required String createdBy,
    required String createdByName,
    required DateTime dueDate,
  }) {
    final now = DateTime.now();
    final items = order.items
        .map(
          (i) => InvoiceItem(
            productId: i.productId,
            productName: i.productName,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
            taxRate: defaultTaxRate,
          ),
        )
        .toList();
    final totals = calculateInvoiceTotals(
      lines: items.map((i) => InvoiceTotalsLineInput(
        quantity: i.quantity,
        unitPrice: i.unitPrice,
        lineDiscountPercent: i.discountPercent,
        lineTaxRate: i.taxRate,
      )).toList(),
      invoiceDiscountPercent: 0,
      invoiceDiscountAmount: 0,
      taxEnabled: defaultTaxRate > 0 || items.any((i) => i.taxRate > 0),
      discountEnabled: items.any((i) => i.discountPercent > 0),
    );
    return InvoiceModel(
      id: '',
      invoiceType: InvoiceType.purchase,
      invoiceNumber: invoiceNumber,
      customerId: '',
      vendorId: order.vendorId,
      vendorName: order.vendorName,
      status: InvoiceStatus.draft,
      items: items,
      taxLabel: taxLabel,
      subtotal: totals.subtotal,
      totalTax: totals.totalTax,
      grandTotal: totals.grandTotal,
      amountDue: totals.grandTotal,
      totalDiscount: totals.totalDiscount,
      invoiceDiscount: totals.invoiceDiscount,
      invoiceDate: now,
      dueDate: dueDate,
      termsText: termsText,
      notes: notes,
      linkedPurchaseOrderId: order.id,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: now,
      updatedAt: now,
    );
  }

  InvoiceModel duplicateInvoice({
    required InvoiceModel source,
    required String invoiceNumber,
  }) {
    final now = DateTime.now();
    final daysDiff = source.dueDate.difference(source.invoiceDate).inDays;
    return source.copyWith(
      id: '',
      invoiceNumber: invoiceNumber,
      status: InvoiceStatus.draft,
      amountPaid: 0,
      amountDue: source.grandTotal,
      payments: [],
      invoiceDate: now,
      dueDate: now.add(Duration(days: daysDiff > 0 ? daysDiff : 0)),
      linkedSalesOrderId: '',
      linkedPurchaseOrderId: '',
      linkedCreditNoteId: '',
      stockDeducted: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool _purchaseOrderFullyReceived(PurchaseOrderModel po) {
    if (po.status == POStatus.received) return true;
    if (po.items.isEmpty) return false;
    return po.items.every(
      (l) => l.quantity <= 0 || l.receivedQuantity >= l.quantity,
    );
  }

  PurchaseOrderModel _buildAutoPurchaseOrderFromInvoice(
    InvoiceModel invoice, {
    required String invoiceId,
    required String userId,
    required String userName,
  }) {
    final now = DateTime.now();
    final items = invoice.items
        .map(
          (i) => POItem(
            productId: i.productId,
            productName: i.productName,
            quantity: i.quantity,
            receivedQuantity: i.quantity,
            unitPrice: i.unitPrice,
          ),
        )
        .toList();
    return PurchaseOrderModel(
      id: '',
      vendorId: invoice.vendorId,
      vendorName: invoice.vendorName,
      status: POStatus.received,
      items: items,
      totalAmount: invoice.grandTotal,
      expectedDate: invoice.invoiceDate,
      receivedDate: now,
      notes: 'Auto-generated from bill ${invoice.invoiceNumber}',
      invoiceId: '',
      originInvoiceId: invoiceId,
      createdBy: userId,
      createdByName: userName,
      createdAt: now,
      updatedAt: now,
    );
  }

  SalesOrderModel _buildAutoSalesOrderFromInvoice(
    InvoiceModel invoice, {
    required String invoiceId,
    required String userId,
    required String userName,
  }) {
    final now = DateTime.now();
    final items = invoice.items
        .map(
          (i) => SOItem(
            productId: i.productId,
            productName: i.productName,
            quantity: i.quantity,
            dispatchedQuantity: i.quantity,
            unitPrice: i.unitPrice,
          ),
        )
        .toList();
    return SalesOrderModel(
      id: '',
      customerId: invoice.customerId,
      customerName: invoice.customerName,
      status: SOStatus.dispatched,
      items: items,
      totalAmount: invoice.grandTotal,
      notes: 'Auto-generated from invoice ${invoice.invoiceNumber}',
      invoiceId: '',
      originInvoiceId: invoiceId,
      createdBy: userId,
      createdByName: userName,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  void dispose() {
    _invoicesSubscription?.cancel();
    super.dispose();
  }
}

/// One stock movement already applied while posting an invoice, kept so it can
/// be reversed if a later line fails.
class _AppliedDeduction {
  final String productId;
  final String productName;
  final String location;
  final int quantity;

  const _AppliedDeduction({
    required this.productId,
    required this.productName,
    required this.location,
    required this.quantity,
  });
}
