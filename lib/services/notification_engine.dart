import '../models/batch_model.dart';
import '../models/invoice_model.dart';
import '../models/product_model.dart';
import '../models/purchase_order_model.dart';

/// How loud an alert is. Drives icon, colour, and whether it is allowed to
/// raise a system-tray notification.
enum AlertSeverity { info, warning, critical }

/// Stable identifiers for the alert kinds this engine can raise. Stored on the
/// notification document as `type`, so renaming one orphans existing rows —
/// add a new value instead.
class AlertType {
  static const String outOfStock = 'out_of_stock';
  static const String lowStock = 'low_stock';
  static const String batchExpired = 'batch_expired';
  static const String batchExpiring = 'batch_expiring';
  static const String invoiceOverdue = 'invoice_overdue';
  static const String purchaseOrderOverdue = 'po_overdue';

  /// Every type the engine emits, in the order the settings screen lists them.
  static const List<String> all = [
    outOfStock,
    lowStock,
    batchExpiring,
    batchExpired,
    invoiceOverdue,
    purchaseOrderOverdue,
  ];

  static String label(String type) => switch (type) {
    outOfStock => 'Out of stock',
    lowStock => 'Low stock',
    batchExpired => 'Expired batches',
    batchExpiring => 'Batches nearing expiry',
    invoiceOverdue => 'Overdue invoices',
    purchaseOrderOverdue => 'Late purchase orders',
    _ => 'Other',
  };

  static String description(String type) => switch (type) {
    outOfStock => 'A product has no sellable stock left.',
    lowStock => 'A product has fallen to or below its reorder point.',
    batchExpired => 'An active batch is past its expiry date.',
    batchExpiring => 'An active batch expires within the warning window.',
    invoiceOverdue => 'An invoice is unpaid past its due date.',
    purchaseOrderOverdue => 'A sent order has not arrived by its expected date.',
    _ => '',
  };
}

/// An alert the engine believes should exist right now.
///
/// [id] doubles as the Firestore document id and the dedupe key, so writing the
/// same candidate twice is a no-op rather than a duplicate row. It embeds a
/// time bucket (see [NotificationEngine._bucket]) so a condition that stays
/// true re-raises at most once per cooldown window instead of every scan.
class NotificationCandidate {
  const NotificationCandidate({
    required this.id,
    required this.type,
    required this.title,
    required this.severity,
    this.message = '',
    this.entityType = '',
    this.entityId = '',
  });

  final String id;
  final String type;
  final String title;
  final String message;
  final AlertSeverity severity;
  final String entityType;
  final String entityId;

  @override
  String toString() => 'NotificationCandidate($id)';
}

/// Tunables for a scan. Mirrors what the notification settings screen exposes.
class AlertScanConfig {
  const AlertScanConfig({
    this.enabledTypes = const {
      AlertType.outOfStock,
      AlertType.lowStock,
      AlertType.batchExpiring,
      AlertType.batchExpired,
      AlertType.invoiceOverdue,
      AlertType.purchaseOrderOverdue,
    },
    this.expiryWarningDays = 30,
    this.summaryThreshold = 5,
    this.maxPerType = 5,
  });

  /// Alert types the user still wants. Anything outside this set is skipped
  /// before any work is done for it.
  final Set<String> enabledTypes;

  /// A batch expiring within this many days is worth warning about.
  final int expiryWarningDays;

  /// Above this many findings of one type, the engine emits a single summary
  /// row instead of one row per item — the difference between a useful inbox
  /// and 300 unread notifications after the first Excel import.
  final int summaryThreshold;

  /// Hard cap on individual rows per type, applied when under
  /// [summaryThreshold] is not what happened but a summary is undesirable.
  final int maxPerType;

  AlertScanConfig copyWith({
    Set<String>? enabledTypes,
    int? expiryWarningDays,
    int? summaryThreshold,
    int? maxPerType,
  }) {
    return AlertScanConfig(
      enabledTypes: enabledTypes ?? this.enabledTypes,
      expiryWarningDays: expiryWarningDays ?? this.expiryWarningDays,
      summaryThreshold: summaryThreshold ?? this.summaryThreshold,
      maxPerType: maxPerType ?? this.maxPerType,
    );
  }
}

/// Derives in-app alerts from data the app has already loaded.
///
/// Deliberately pure: it takes plain model lists and returns candidates, with
/// no Firestore, no clock of its own (callers pass [now]), and no side effects.
/// That keeps the interesting part — what counts as an alert and how often it
/// may repeat — unit-testable without the network.
class NotificationEngine {
  const NotificationEngine();

  /// Cooldown per type. A condition that stays true re-raises once per window
  /// rather than on every scan.
  static const Map<String, int> _cooldownDays = {
    AlertType.outOfStock: 3,
    AlertType.lowStock: 3,
    AlertType.batchExpiring: 7,
    AlertType.batchExpired: 7,
    AlertType.invoiceOverdue: 7,
    AlertType.purchaseOrderOverdue: 7,
  };

  /// Which bucket [now] falls in for [type]. Two scans in the same bucket
  /// produce identical candidate ids, so the second one writes nothing.
  static int _bucket(String type, DateTime now) {
    final cooldown = _cooldownDays[type] ?? 1;
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(1970))
        .inDays;
    return days ~/ cooldown;
  }

  /// Firestore document ids may not contain '/' and may not be '.' or '..'.
  /// Model ids are Firestore ids already, but user-supplied fallbacks (an
  /// invoice number, say) are not, so everything gets scrubbed.
  static String _safeSegment(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  static String _id(String type, String key, DateTime now) =>
      '${type}__${_safeSegment(key)}__${_bucket(type, now)}';

  /// Everything that should be alerted on, given this snapshot of the data.
  ///
  /// Pass whatever is loaded; empty lists simply contribute nothing. [now] is
  /// injected so tests can pin the clock.
  List<NotificationCandidate> scan({
    required DateTime now,
    List<ProductModel> products = const [],
    List<BatchModel> batches = const [],
    List<InvoiceModel> invoices = const [],
    List<PurchaseOrderModel> purchaseOrders = const [],
    AlertScanConfig config = const AlertScanConfig(),
  }) {
    return [
      ..._stockAlerts(now: now, products: products, config: config),
      ..._batchAlerts(now: now, batches: batches, config: config),
      ..._invoiceAlerts(now: now, invoices: invoices, config: config),
      ..._orderAlerts(now: now, orders: purchaseOrders, config: config),
    ];
  }

  /// Collapses [items] into either one row each or a single summary row,
  /// depending on how many there are. [summaryBuilder] is only called when the
  /// count is over the threshold, so callers can build the summary lazily.
  List<NotificationCandidate> _collapse<T>({
    required String type,
    required List<T> items,
    required DateTime now,
    required AlertScanConfig config,
    required NotificationCandidate Function(T item) itemBuilder,
    required NotificationCandidate Function(int count) summaryBuilder,
  }) {
    if (items.isEmpty) return const [];
    if (items.length > config.summaryThreshold) {
      return [summaryBuilder(items.length)];
    }
    return items.take(config.maxPerType).map(itemBuilder).toList();
  }

  String _summaryId(String type, DateTime now) => _id(type, 'summary', now);

  List<NotificationCandidate> _stockAlerts({
    required DateTime now,
    required List<ProductModel> products,
    required AlertScanConfig config,
  }) {
    final out = <NotificationCandidate>[];

    if (config.enabledTypes.contains(AlertType.outOfStock)) {
      // isOutOfStock is availability-based (on-hand minus held), which is what
      // a picker actually cares about.
      final empty = products.where((p) => p.isOutOfStock).toList();
      out.addAll(
        _collapse(
          type: AlertType.outOfStock,
          items: empty,
          now: now,
          config: config,
          itemBuilder: (p) => NotificationCandidate(
            id: _id(AlertType.outOfStock, p.id, now),
            type: AlertType.outOfStock,
            title: '${p.name} is out of stock',
            message: 'No units available to sell or despatch.',
            severity: AlertSeverity.critical,
            entityType: 'product',
            entityId: p.id,
          ),
          summaryBuilder: (count) => NotificationCandidate(
            id: _summaryId(AlertType.outOfStock, now),
            type: AlertType.outOfStock,
            title: '$count products are out of stock',
            message: 'Tap to review and reorder.',
            severity: AlertSeverity.critical,
            entityType: 'low_stock_list',
          ),
        ),
      );
    }

    if (config.enabledTypes.contains(AlertType.lowStock)) {
      // isLowStock excludes the zero case so a product never raises both a
      // low-stock and an out-of-stock alert for the same scan.
      final low = products.where((p) => p.isLowStock).toList();
      out.addAll(
        _collapse(
          type: AlertType.lowStock,
          items: low,
          now: now,
          config: config,
          itemBuilder: (p) => NotificationCandidate(
            id: _id(AlertType.lowStock, p.id, now),
            type: AlertType.lowStock,
            title: '${p.name} is running low',
            message:
                '${p.availableQuantity} ${p.unit} left · reorder point '
                '${p.lowStockThreshold}',
            severity: AlertSeverity.warning,
            entityType: 'product',
            entityId: p.id,
          ),
          summaryBuilder: (count) => NotificationCandidate(
            id: _summaryId(AlertType.lowStock, now),
            type: AlertType.lowStock,
            title: '$count products are running low',
            message: 'Tap to review reorder suggestions.',
            severity: AlertSeverity.warning,
            entityType: 'low_stock_list',
          ),
        ),
      );
    }

    return out;
  }

  List<NotificationCandidate> _batchAlerts({
    required DateTime now,
    required List<BatchModel> batches,
    required AlertScanConfig config,
  }) {
    final out = <NotificationCandidate>[];
    // A recalled or already-written-off batch is not news.
    final active = batches
        .where((b) => b.status == BatchStatus.active && b.quantity > 0)
        .toList();

    if (config.enabledTypes.contains(AlertType.batchExpired)) {
      final expired = active.where((b) => b.expiryDate.isBefore(now)).toList()
        ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      out.addAll(
        _collapse(
          type: AlertType.batchExpired,
          items: expired,
          now: now,
          config: config,
          itemBuilder: (b) => NotificationCandidate(
            id: _id(AlertType.batchExpired, b.id, now),
            type: AlertType.batchExpired,
            title: '${_batchLabel(b)} has expired',
            message: '${b.quantity} units still marked active.',
            severity: AlertSeverity.critical,
            entityType: 'batch',
            entityId: b.id,
          ),
          summaryBuilder: (count) => NotificationCandidate(
            id: _summaryId(AlertType.batchExpired, now),
            type: AlertType.batchExpired,
            title: '$count batches have expired',
            message: 'Tap to write them off or dispose of them.',
            severity: AlertSeverity.critical,
            entityType: 'expiry_list',
          ),
        ),
      );
    }

    if (config.enabledTypes.contains(AlertType.batchExpiring)) {
      final cutoff = now.add(Duration(days: config.expiryWarningDays));
      final soon =
          active
              .where(
                (b) =>
                    !b.expiryDate.isBefore(now) && b.expiryDate.isBefore(cutoff),
              )
              .toList()
            ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      out.addAll(
        _collapse(
          type: AlertType.batchExpiring,
          items: soon,
          now: now,
          config: config,
          itemBuilder: (b) {
            final days = b.expiryDate.difference(now).inDays;
            return NotificationCandidate(
              id: _id(AlertType.batchExpiring, b.id, now),
              type: AlertType.batchExpiring,
              title: '${_batchLabel(b)} expires soon',
              message: days <= 0
                  ? 'Expires today · ${b.quantity} units'
                  : 'Expires in $days ${days == 1 ? 'day' : 'days'} · '
                        '${b.quantity} units',
              severity: AlertSeverity.warning,
              entityType: 'batch',
              entityId: b.id,
            );
          },
          summaryBuilder: (count) => NotificationCandidate(
            id: _summaryId(AlertType.batchExpiring, now),
            type: AlertType.batchExpiring,
            title: '$count batches expire within '
                '${config.expiryWarningDays} days',
            message: 'Tap to plan sell-through or returns.',
            severity: AlertSeverity.warning,
            entityType: 'expiry_list',
          ),
        ),
      );
    }

    return out;
  }

  static String _batchLabel(BatchModel b) {
    if (b.productName.isNotEmpty && b.batchNumber.isNotEmpty) {
      return '${b.productName} (${b.batchNumber})';
    }
    if (b.productName.isNotEmpty) return b.productName;
    if (b.batchNumber.isNotEmpty) return 'Batch ${b.batchNumber}';
    return 'A batch';
  }

  List<NotificationCandidate> _invoiceAlerts({
    required DateTime now,
    required List<InvoiceModel> invoices,
    required AlertScanConfig config,
  }) {
    if (!config.enabledTypes.contains(AlertType.invoiceOverdue)) {
      return const [];
    }
    // Drafts were never issued and cancelled/paid ones owe nothing, so due
    // date alone is not enough — amountDue is the real test.
    final overdue =
        invoices
            .where(
              (i) =>
                  !i.isDraft &&
                  !i.isCancelled &&
                  !i.isPaid &&
                  i.amountDue > 0.005 &&
                  i.dueDate.isBefore(now),
            )
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return _collapse(
      type: AlertType.invoiceOverdue,
      items: overdue,
      now: now,
      config: config,
      itemBuilder: (i) {
        final days = now.difference(i.dueDate).inDays;
        final who = i.isPurchase ? i.vendorName : i.customerName;
        return NotificationCandidate(
          id: _id(AlertType.invoiceOverdue, i.id, now),
          type: AlertType.invoiceOverdue,
          title: 'Invoice ${i.invoiceNumber} is overdue',
          message: [
            if (who.isNotEmpty) who,
            days <= 0
                ? 'due today'
                : '$days ${days == 1 ? 'day' : 'days'} overdue',
          ].join(' · '),
          severity: AlertSeverity.warning,
          entityType: 'invoice',
          entityId: i.id,
        );
      },
      summaryBuilder: (count) => NotificationCandidate(
        id: _summaryId(AlertType.invoiceOverdue, now),
        type: AlertType.invoiceOverdue,
        title: '$count invoices are overdue',
        message: 'Tap to chase payment.',
        severity: AlertSeverity.warning,
        entityType: 'invoice_list',
      ),
    );
  }

  List<NotificationCandidate> _orderAlerts({
    required DateTime now,
    required List<PurchaseOrderModel> orders,
    required AlertScanConfig config,
  }) {
    if (!config.enabledTypes.contains(AlertType.purchaseOrderOverdue)) {
      return const [];
    }
    // Only orders actually placed with a vendor can be late; drafts and
    // fully-received ones cannot.
    final late =
        orders
            .where(
              (o) =>
                  (o.status == POStatus.sent || o.status == POStatus.partial) &&
                  o.expectedDate.isBefore(now),
            )
            .toList()
          ..sort((a, b) => a.expectedDate.compareTo(b.expectedDate));

    return _collapse(
      type: AlertType.purchaseOrderOverdue,
      items: late,
      now: now,
      config: config,
      itemBuilder: (o) {
        final days = now.difference(o.expectedDate).inDays;
        return NotificationCandidate(
          id: _id(AlertType.purchaseOrderOverdue, o.id, now),
          type: AlertType.purchaseOrderOverdue,
          title: 'Order from ${o.vendorName.isEmpty ? 'vendor' : o.vendorName} '
              'is late',
          message: days <= 0
              ? 'Expected today'
              : 'Expected $days ${days == 1 ? 'day' : 'days'} ago',
          severity: AlertSeverity.info,
          entityType: 'purchase_order',
          entityId: o.id,
        );
      },
      summaryBuilder: (count) => NotificationCandidate(
        id: _summaryId(AlertType.purchaseOrderOverdue, now),
        type: AlertType.purchaseOrderOverdue,
        title: '$count purchase orders are late',
        message: 'Tap to follow up with vendors.',
        severity: AlertSeverity.info,
        entityType: 'purchase_order_list',
      ),
    );
  }
}
