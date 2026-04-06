import '../models/invoice_model.dart';
import '../models/purchase_order_model.dart';

/// Increases [POItem.receivedQuantity] from bill lines (matched by [InvoiceItem.productId]),
/// capped per line by remaining quantity. Sets [POStatus.received] when every line is fully
/// received; downgrades [POStatus.received] to [POStatus.partial] when partially received after apply.
///
/// No-ops for [POStatus.cancelled] or [POStatus.received] (bill path does not add stock again for a fully received PO).
PurchaseOrderModel applyBillReceipt(
  PurchaseOrderModel po,
  List<InvoiceItem> billItems,
  DateTime updatedAt,
) {
  if (po.status == POStatus.cancelled || po.status == POStatus.received) {
    return po.copyWith(updatedAt: updatedAt);
  }
  if (billItems.isEmpty) return po.copyWith(updatedAt: updatedAt);

  final supply = <String, int>{};
  for (final inv in billItems) {
    if (inv.productId.isEmpty || inv.quantity <= 0) continue;
    supply[inv.productId] = (supply[inv.productId] ?? 0) + inv.quantity;
  }
  if (supply.isEmpty) return po.copyWith(updatedAt: updatedAt);

  final newItems = po.items.map((e) => e).toList();
  for (var i = 0; i < newItems.length; i++) {
    final line = newItems[i];
    if (line.productId.isEmpty) continue;
    final need = supply[line.productId] ?? 0;
    if (need <= 0) continue;
    final cap = line.quantity - line.receivedQuantity;
    if (cap <= 0) continue;
    final add = need < cap ? need : cap;
    newItems[i] = line.copyWith(
      receivedQuantity: line.receivedQuantity + add,
    );
    supply[line.productId] = need - add;
  }

  final allFulfilled = newItems.isNotEmpty &&
      newItems.every((l) => l.quantity > 0 && l.receivedQuantity >= l.quantity);

  var newStatus = po.status;
  var addedReceipt = false;
  for (var i = 0; i < newItems.length && i < po.items.length; i++) {
    if (newItems[i].receivedQuantity > po.items[i].receivedQuantity) {
      addedReceipt = true;
      break;
    }
  }

  if (allFulfilled) {
    if (po.status != POStatus.cancelled) {
      newStatus = POStatus.received;
    }
  } else {
    if (po.status == POStatus.received) {
      newStatus = POStatus.partial;
    } else if ((po.status == POStatus.sent || po.status == POStatus.draft) &&
        addedReceipt) {
      newStatus = POStatus.partial;
    }
  }

  final newReceivedDate = allFulfilled
      ? (po.receivedDate ?? updatedAt)
      : null;
  final clearReceived = !allFulfilled && po.receivedDate != null;

  return po.copyWith(
    items: newItems,
    status: newStatus,
    updatedAt: updatedAt,
    receivedDate: newReceivedDate,
    clearReceivedDate: clearReceived,
  );
}

/// Subtracts billed quantities from [POItem.receivedQuantity] (by [InvoiceItem.productId]),
/// floored at zero. Downgrades [POStatus.received] / [POStatus.partial] toward [POStatus.sent]
/// when no longer fully received.
PurchaseOrderModel revertBillReceipt(
  PurchaseOrderModel po,
  List<InvoiceItem> billItems,
  DateTime updatedAt,
) {
  if (po.status == POStatus.cancelled) {
    return po.copyWith(updatedAt: updatedAt);
  }
  if (billItems.isEmpty) return po.copyWith(updatedAt: updatedAt);

  final toRemove = <String, int>{};
  for (final inv in billItems) {
    if (inv.productId.isEmpty || inv.quantity <= 0) continue;
    toRemove[inv.productId] = (toRemove[inv.productId] ?? 0) + inv.quantity;
  }
  if (toRemove.isEmpty) return po.copyWith(updatedAt: updatedAt);

  final newItems = po.items.map((e) => e).toList();
  for (var i = 0; i < newItems.length; i++) {
    final line = newItems[i];
    final rem = toRemove[line.productId] ?? 0;
    if (rem <= 0) continue;
    final sub = rem < line.receivedQuantity ? rem : line.receivedQuantity;
    if (sub <= 0) continue;
    newItems[i] = line.copyWith(
      receivedQuantity: line.receivedQuantity - sub,
    );
    toRemove[line.productId] = rem - sub;
  }

  final allFulfilled = newItems.isNotEmpty &&
      newItems.every((l) => l.quantity > 0 && l.receivedQuantity >= l.quantity);

  var newStatus = po.status;
  if (!allFulfilled) {
    if (po.status == POStatus.received || po.status == POStatus.partial) {
      final anyReceived = newItems.any((l) => l.receivedQuantity > 0);
      newStatus = anyReceived ? POStatus.partial : POStatus.sent;
    }
  } else {
    newStatus = POStatus.received;
  }

  final clearReceived = !allFulfilled && po.receivedDate != null;

  return po.copyWith(
    items: newItems,
    status: newStatus,
    updatedAt: updatedAt,
    clearReceivedDate: clearReceived,
  );
}
