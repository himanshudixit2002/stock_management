import '../models/product_model.dart';
import '../models/stock_hold_model.dart';
import '../models/invoice_model.dart';
import '../models/sales_order_model.dart';

/// How bad a finding is. Drives ordering and colour in the UI.
enum DataHealthSeverity { critical, warning, info }

/// One thing wrong with the data, and enough context to act on it.
class DataHealthFinding {
  final String checkId;
  final String title;

  /// What is wrong, in the user's terms.
  final String detail;

  /// What to do about it.
  final String remedy;
  final DataHealthSeverity severity;

  /// Entity this points at, so the UI can deep-link.
  final String entityType;
  final String entityId;
  final String entityName;

  const DataHealthFinding({
    required this.checkId,
    required this.title,
    required this.detail,
    required this.remedy,
    required this.severity,
    this.entityType = '',
    this.entityId = '',
    this.entityName = '',
  });
}

/// A single check's outcome, so the UI can show checks that passed too —
/// "0 problems" is only reassuring if you can see what was actually looked at.
class DataHealthCheck {
  final String id;
  final String label;
  final String description;
  final List<DataHealthFinding> findings;

  const DataHealthCheck({
    required this.id,
    required this.label,
    required this.description,
    required this.findings,
  });

  bool get passed => findings.isEmpty;
}

/// Scans loaded workspace data for the corruption classes that the stock and
/// billing bugs in this codebase were capable of producing.
///
/// Deliberately pure: it takes already-loaded lists and returns findings, so it
/// can be unit tested without Firebase and re-run cheaply from the UI.
class DataHealthService {
  const DataHealthService();

  List<DataHealthCheck> scan({
    required List<ProductModel> products,
    required List<StockHoldModel> holds,
    required List<InvoiceModel> invoices,
    required List<SalesOrderModel> salesOrders,
  }) {
    return [
      _checkHeldExceedsOnHand(products),
      _checkQuantityMatchesLocations(products),
      _checkHeldWithoutStock(products),
      _checkSuspiciousLocationNames(products),
      _checkOrphanedHolds(holds, products, salesOrders),
      _checkInvoiceProductRefs(invoices, products),
    ];
  }

  /// heldQuantity above the on-hand count means availableQuantity clamps to 0
  /// and the product looks unsellable. Damage/transfer/adjustment used to skip
  /// the held guard, which is how this arises.
  DataHealthCheck _checkHeldExceedsOnHand(List<ProductModel> products) {
    final findings = <DataHealthFinding>[];
    for (final p in products) {
      if (p.heldQuantity > p.quantity) {
        findings.add(
          DataHealthFinding(
            checkId: 'held_exceeds_on_hand',
            title: 'More stock reserved than exists',
            detail:
                '${p.name}: ${p.heldQuantity} reserved but only ${p.quantity} '
                'on hand.',
            remedy:
                'Release the excess holds, then recount this product at each '
                'location.',
            severity: DataHealthSeverity.critical,
            entityType: 'Product',
            entityId: p.id,
            entityName: p.name,
          ),
        );
      }
    }
    return DataHealthCheck(
      id: 'held_exceeds_on_hand',
      label: 'Reservations within stock',
      description: 'Reserved units never exceed the quantity on hand.',
      findings: findings,
    );
  }

  /// The headline total must equal the sum of the per-location buckets. A
  /// mismatch is the signature of a write that updated one and not the other.
  DataHealthCheck _checkQuantityMatchesLocations(List<ProductModel> products) {
    final findings = <DataHealthFinding>[];
    for (final p in products) {
      final summed = p.locationQuantities.values.fold<int>(0, (a, b) => a + b);
      if (summed != p.quantity) {
        findings.add(
          DataHealthFinding(
            checkId: 'quantity_location_mismatch',
            title: 'Total does not match its locations',
            detail:
                '${p.name}: total says ${p.quantity}, locations add up to '
                '$summed.',
            remedy:
                'Run a stock take for this product to reset both to the '
                'counted figure.',
            severity: DataHealthSeverity.critical,
            entityType: 'Product',
            entityId: p.id,
            entityName: p.name,
          ),
        );
      }
    }
    return DataHealthCheck(
      id: 'quantity_location_mismatch',
      label: 'Totals reconcile to locations',
      description: 'Each product total equals the sum of its locations.',
      findings: findings,
    );
  }

  /// A reservation booked against a location that holds no stock. The
  /// unassigned (product-level) bucket is legitimately location-less and is
  /// checked against the product total instead.
  DataHealthCheck _checkHeldWithoutStock(List<ProductModel> products) {
    final findings = <DataHealthFinding>[];
    for (final p in products) {
      for (final entry in p.heldLocationQuantities.entries) {
        if (entry.value <= 0) continue;
        if (entry.key == kUnassignedHoldLocation) {
          if (entry.value > p.quantity) {
            findings.add(
              DataHealthFinding(
                checkId: 'held_without_stock',
                title: 'Unassigned reservation exceeds stock',
                detail:
                    '${p.name}: ${entry.value} reserved without a location, '
                    'but only ${p.quantity} on hand.',
                remedy: 'Release the unassigned holds for this product.',
                severity: DataHealthSeverity.critical,
                entityType: 'Product',
                entityId: p.id,
                entityName: p.name,
              ),
            );
          }
          continue;
        }
        final onHand = p.locationQuantities[entry.key] ?? 0;
        if (entry.value > onHand) {
          findings.add(
            DataHealthFinding(
              checkId: 'held_without_stock',
              title: 'Reservation at a location without the stock',
              detail:
                  '${p.name} at ${entry.key}: ${entry.value} reserved but '
                  '$onHand on hand.',
              remedy:
                  'Release the holds at ${entry.key}, or transfer stock in to '
                  'cover them.',
              severity: DataHealthSeverity.critical,
              entityType: 'Product',
              entityId: p.id,
              entityName: p.name,
            ),
          );
        }
      }
    }
    return DataHealthCheck(
      id: 'held_without_stock',
      label: 'Reservations backed by stock',
      description: 'Every reservation sits where the stock actually is.',
      findings: findings,
    );
  }

  /// Location names that Firestore would read as a field path. Stock written
  /// to these under the old dotted-path code silently vanished; a name like
  /// this surviving in the data means it needs renaming before it is used
  /// again.
  DataHealthCheck _checkSuspiciousLocationNames(List<ProductModel> products) {
    final findings = <DataHealthFinding>[];
    final seen = <String>{};
    const bad = ['.', '/', '~', '*', '[', ']'];
    for (final p in products) {
      for (final loc in {
        ...p.locationQuantities.keys,
        ...p.heldLocationQuantities.keys,
      }) {
        if (loc == kUnassignedHoldLocation) continue;
        if (!bad.any(loc.contains)) continue;
        if (!seen.add(loc)) continue;
        findings.add(
          DataHealthFinding(
            checkId: 'unsafe_location_name',
            title: 'Location name uses a reserved character',
            detail:
                '"$loc" contains a character Firestore treats as a field path '
                'separator. Stock written here before the fix may have been '
                'lost.',
            remedy:
                'Rename this location (Warehouse Zones), moving its stock to '
                'the new name, and recount it.',
            severity: DataHealthSeverity.warning,
            entityType: 'Location',
            entityId: loc,
            entityName: loc,
          ),
        );
      }
    }
    return DataHealthCheck(
      id: 'unsafe_location_name',
      label: 'Location names are safe',
      description: 'No location name contains . / ~ * [ ]',
      findings: findings,
    );
  }

  /// Active reservations whose product or originating order is gone or
  /// cancelled. These quietly subtract from available stock forever.
  DataHealthCheck _checkOrphanedHolds(
    List<StockHoldModel> holds,
    List<ProductModel> products,
    List<SalesOrderModel> salesOrders,
  ) {
    final findings = <DataHealthFinding>[];
    final productIds = {for (final p in products) p.id};
    final orderById = {for (final o in salesOrders) o.id: o};

    for (final h in holds) {
      final active =
          h.status == StockHoldStatus.active ||
          h.status == StockHoldStatus.partiallyConsumed;
      if (!active || h.remainingQuantity <= 0) continue;

      if (!productIds.contains(h.productId)) {
        findings.add(
          DataHealthFinding(
            checkId: 'orphaned_hold',
            title: 'Reservation on a deleted product',
            detail:
                '${h.remainingQuantity} unit(s) still reserved for '
                '"${h.productName}", which no longer exists.',
            remedy: 'Release this hold.',
            severity: DataHealthSeverity.warning,
            entityType: 'StockHold',
            entityId: h.id,
            entityName: h.productName,
          ),
        );
        continue;
      }

      if (h.sourceType == StockHoldSourceType.salesOrder &&
          h.sourceId.isNotEmpty) {
        final order = orderById[h.sourceId];
        if (order == null) {
          findings.add(
            DataHealthFinding(
              checkId: 'orphaned_hold',
              title: 'Reservation for a deleted order',
              detail:
                  '${h.productName}: ${h.remainingQuantity} unit(s) reserved '
                  'for an order that no longer exists.',
              remedy: 'Release this hold.',
              severity: DataHealthSeverity.warning,
              entityType: 'StockHold',
              entityId: h.id,
              entityName: h.productName,
            ),
          );
        } else if (order.status == SOStatus.cancelled) {
          findings.add(
            DataHealthFinding(
              checkId: 'orphaned_hold',
              title: 'Reservation for a cancelled order',
              detail:
                  '${h.productName}: ${h.remainingQuantity} unit(s) still '
                  'reserved for a cancelled order.',
              remedy: 'Release this hold to free the stock.',
              severity: DataHealthSeverity.warning,
              entityType: 'StockHold',
              entityId: h.id,
              entityName: h.productName,
            ),
          );
        }
      }
    }
    return DataHealthCheck(
      id: 'orphaned_hold',
      label: 'No orphaned reservations',
      description: 'Active holds point at a live product and a live order.',
      findings: findings,
    );
  }

  /// Invoices that moved stock for a product that has since been deleted —
  /// cancelling one can no longer reverse it.
  DataHealthCheck _checkInvoiceProductRefs(
    List<InvoiceModel> invoices,
    List<ProductModel> products,
  ) {
    final findings = <DataHealthFinding>[];
    final productIds = {for (final p in products) p.id};
    for (final inv in invoices) {
      if (!inv.stockDeducted || inv.isCancelled) continue;
      final missing = inv.items
          .where((i) => i.productId.isNotEmpty && !productIds.contains(i.productId))
          .map((i) => i.productName.isNotEmpty ? i.productName : i.productId)
          .toSet();
      if (missing.isEmpty) continue;
      findings.add(
        DataHealthFinding(
          checkId: 'invoice_missing_product',
          title: 'Invoice references a deleted product',
          detail:
              '${inv.invoiceNumber} moved stock for ${missing.join(', ')}, '
              'which no longer exists. Cancelling it cannot reverse that '
              'stock.',
          remedy:
              'Re-create the product, or adjust stock manually if this invoice '
              'is ever cancelled.',
          severity: DataHealthSeverity.warning,
          entityType: 'Invoice',
          entityId: inv.id,
          entityName: inv.invoiceNumber,
        ),
      );
    }
    return DataHealthCheck(
      id: 'invoice_missing_product',
      label: 'Invoice product references intact',
      description: 'Every stock-moving invoice still resolves its products.',
      findings: findings,
    );
  }
}
