import '../models/invoice_model.dart';
import '../models/sales_order_model.dart';

/// Increases [SOItem.dispatchedQuantity] from invoice lines (matched by [InvoiceItem.productId]),
/// capped per line by remaining quantity. Updates [SalesOrderModel.status] to [SOStatus.dispatched]
/// when every line is fully fulfilled; downgrades [SOStatus.dispatched]/[SOStatus.delivered] to
/// [SOStatus.confirmed] when partially fulfilled after apply.
///
/// No-ops for [SOStatus.cancelled] or [SOStatus.delivered] (invoice path never deducts for delivered SO).
SalesOrderModel applyInvoiceFulfillment(
  SalesOrderModel so,
  List<InvoiceItem> invoiceItems,
  DateTime updatedAt,
) {
  if (so.status == SOStatus.cancelled || so.status == SOStatus.delivered) {
    return so.copyWith(updatedAt: updatedAt);
  }
  if (invoiceItems.isEmpty) return so.copyWith(updatedAt: updatedAt);

  final demand = <String, int>{};
  for (final inv in invoiceItems) {
    if (inv.productId.isEmpty || inv.quantity <= 0) continue;
    demand[inv.productId] = (demand[inv.productId] ?? 0) + inv.quantity;
  }
  if (demand.isEmpty) return so.copyWith(updatedAt: updatedAt);

  final newItems = so.items.map((e) => e).toList();
  for (var i = 0; i < newItems.length; i++) {
    final line = newItems[i];
    if (line.productId.isEmpty) continue;
    final need = demand[line.productId] ?? 0;
    if (need <= 0) continue;
    final cap = line.quantity - line.dispatchedQuantity;
    if (cap <= 0) continue;
    final add = need < cap ? need : cap;
    newItems[i] = line.copyWith(
      dispatchedQuantity: line.dispatchedQuantity + add,
    );
    demand[line.productId] = need - add;
  }

  final allFulfilled = newItems.isNotEmpty &&
      newItems.every((l) => l.quantity > 0 && l.dispatchedQuantity >= l.quantity);

  var newStatus = so.status;
  if (allFulfilled) {
    if (so.status != SOStatus.cancelled) {
      newStatus = SOStatus.dispatched;
    }
  } else {
    if (so.status == SOStatus.dispatched || so.status == SOStatus.delivered) {
      newStatus = SOStatus.confirmed;
    }
  }

  return so.copyWith(
    items: newItems,
    status: newStatus,
    updatedAt: updatedAt,
  );
}

/// Subtracts invoiced quantities from [SOItem.dispatchedQuantity] (by [InvoiceItem.productId]),
/// floored at zero. Downgrades status to [SOStatus.confirmed] when no longer fully dispatched.
SalesOrderModel revertInvoiceFulfillment(
  SalesOrderModel so,
  List<InvoiceItem> invoiceItems,
  DateTime updatedAt,
) {
  if (so.status == SOStatus.cancelled) {
    return so.copyWith(updatedAt: updatedAt);
  }
  if (invoiceItems.isEmpty) return so.copyWith(updatedAt: updatedAt);

  final toRemove = <String, int>{};
  for (final inv in invoiceItems) {
    if (inv.productId.isEmpty || inv.quantity <= 0) continue;
    toRemove[inv.productId] = (toRemove[inv.productId] ?? 0) + inv.quantity;
  }
  if (toRemove.isEmpty) return so.copyWith(updatedAt: updatedAt);

  final newItems = so.items.map((e) => e).toList();
  for (var i = 0; i < newItems.length; i++) {
    final line = newItems[i];
    final rem = toRemove[line.productId] ?? 0;
    if (rem <= 0) continue;
    final sub = rem < line.dispatchedQuantity ? rem : line.dispatchedQuantity;
    if (sub <= 0) continue;
    newItems[i] = line.copyWith(
      dispatchedQuantity: line.dispatchedQuantity - sub,
    );
    toRemove[line.productId] = rem - sub;
  }

  final allFulfilled = newItems.isNotEmpty &&
      newItems.every((l) => l.quantity > 0 && l.dispatchedQuantity >= l.quantity);

  var newStatus = so.status;
  if (!allFulfilled) {
    if (so.status == SOStatus.dispatched || so.status == SOStatus.delivered) {
      newStatus = SOStatus.confirmed;
    }
  }

  return so.copyWith(
    items: newItems,
    status: newStatus,
    updatedAt: updatedAt,
  );
}
