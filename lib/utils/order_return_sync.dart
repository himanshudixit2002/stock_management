import '../models/purchase_order_model.dart';
import '../models/return_model.dart';
import '../models/sales_order_model.dart';

/// Increases [SOItem.returnedQuantity] from return lines (by [ReturnItem.productId]),
/// capped per line by remaining returnable quantity (preferably against [SOItem.dispatchedQuantity]).
SalesOrderModel applyCustomerReturnToSalesOrder(
  SalesOrderModel so,
  List<ReturnItem> returnItems,
  DateTime updatedAt,
) {
  if (so.status == SOStatus.cancelled) {
    return so.copyWith(updatedAt: updatedAt);
  }
  if (returnItems.isEmpty) return so.copyWith(updatedAt: updatedAt);

  final demand = <String, int>{};
  for (final r in returnItems) {
    if (r.productId.isEmpty || r.quantity <= 0) continue;
    demand[r.productId] = (demand[r.productId] ?? 0) + r.quantity;
  }
  if (demand.isEmpty) return so.copyWith(updatedAt: updatedAt);

  final newItems = so.items.map((e) => e).toList();
  for (var i = 0; i < newItems.length; i++) {
    final line = newItems[i];
    if (line.productId.isEmpty) continue;
    final need = demand[line.productId] ?? 0;
    if (need <= 0) continue;
    final maxReturnable = line.dispatchedQuantity > 0
        ? (line.dispatchedQuantity - line.returnedQuantity)
        : (line.quantity - line.returnedQuantity);
    if (maxReturnable <= 0) continue;
    final add = need < maxReturnable ? need : maxReturnable;
    newItems[i] = line.copyWith(returnedQuantity: line.returnedQuantity + add);
    demand[line.productId] = need - add;
  }

  return so.copyWith(items: newItems, updatedAt: updatedAt);
}

/// Decreases [POItem.receivedQuantity] from vendor return lines (by [ReturnItem.productId]),
/// floored at zero. Adjusts [POStatus] like a partial unreceive.
PurchaseOrderModel applyVendorReturnToPurchaseOrder(
  PurchaseOrderModel po,
  List<ReturnItem> returnItems,
  DateTime updatedAt,
) {
  if (po.status == POStatus.cancelled) {
    return po.copyWith(updatedAt: updatedAt);
  }
  if (returnItems.isEmpty) return po.copyWith(updatedAt: updatedAt);

  final toRemove = <String, int>{};
  for (final r in returnItems) {
    if (r.productId.isEmpty || r.quantity <= 0) continue;
    toRemove[r.productId] = (toRemove[r.productId] ?? 0) + r.quantity;
  }
  if (toRemove.isEmpty) return po.copyWith(updatedAt: updatedAt);

  final newItems = po.items.map((e) => e).toList();
  for (var i = 0; i < newItems.length; i++) {
    final line = newItems[i];
    final rem = toRemove[line.productId] ?? 0;
    if (rem <= 0) continue;
    final sub = rem < line.receivedQuantity ? rem : line.receivedQuantity;
    if (sub <= 0) continue;
    newItems[i] = line.copyWith(receivedQuantity: line.receivedQuantity - sub);
    toRemove[line.productId] = rem - sub;
  }

  final allFulfilled =
      newItems.isNotEmpty &&
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
