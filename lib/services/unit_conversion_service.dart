import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/constants.dart';
import '../models/audit_log_model.dart';
import '../models/product_model.dart';
import '../models/quotation_model.dart';
import '../models/stock_transaction_model.dart';
import '../utils/error_helpers.dart';
import '../utils/parse_helpers.dart';
import '../utils/unit_conversion.dart';
import 'unit_conversion_planner.dart';

/// A unit conversion stopping something, in words for the person who asked:
/// why a conversion did not happen, or why a stock write was refused because
/// of one.
class UnitConversionException implements UserFacingException {
  const UnitConversionException(this.message);

  /// Putting back a document's stock after its products were converted.
  factory UnitConversionException.convertedSince(List<String> names) =>
      UnitConversionException(
        '${names.join(', ')} ${names.length == 1 ? 'was' : 'were'} converted '
        'to new units after this document was made, so its quantities are in '
        'the old unit. Adjust the stock by hand instead.',
      );

  @override
  final String message;

  @override
  String toString() => message;
}

/// What one apply did.
class UnitConversionReport {
  const UnitConversionReport({
    required this.repacked,
    required this.converted,
    required this.failures,
  });

  final int repacked;
  final int converted;

  /// Product name → why it was left as it was.
  final Map<String, String> failures;
}

/// Carries Settings › Unit conversions through to the catalog.
///
/// [planUnitChanges] decides what each product needs; this does it. A repack
/// only moves pack fields, so it is a field-scoped batch write. A stock
/// conversion re-counts every quantity the product has, wherever it is
/// stored, so each one is a single transaction — and it waits while any open
/// document still counts the product in the old unit ([findBlockers]).
class UnitConversionService {
  UnitConversionService({required this.companyId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String companyId;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _company =>
      _firestore.collection('companies').doc(companyId);

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _company.collection(name);

  // --- What has to close first -------------------------------------------

  /// The open documents that still count each of [productIds] in its current
  /// unit, as labels to show ("PO-1A2B3C", "INV #1042"), keyed by product.
  ///
  /// Lines live in arrays that cannot be queried by product, so each
  /// collection is loaded once by its open statuses and searched here. A
  /// product with a serial number is listed too: each serial is one unit, and
  /// re-counting the stock would leave nine of every ten units without one.
  Future<Map<String, List<String>>> findBlockers(Set<String> productIds) async {
    final blockers = <String, List<String>>{};
    if (productIds.isEmpty) return blockers;

    void block(String productId, String label) {
      if (!productIds.contains(productId)) return;
      final labels = blockers.putIfAbsent(productId, () => []);
      if (!labels.contains(label)) labels.add(label);
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> open(
      String collection,
      List<String> statuses,
    ) async => (await _collection(
      collection,
    ).where('status', whereIn: statuses).get()).docs;

    String shortId(String prefix, String id) =>
        '$prefix-${id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()}';

    void blockLines(
      Map<String, dynamic> data,
      String field,
      String label, {
      bool Function(Map<String, dynamic> line)? where,
    }) {
      final lines = data[field];
      if (lines is! List) return;
      for (final line in lines) {
        if (line is! Map) continue;
        final map = Map<String, dynamic>.from(line);
        if (where != null && !where(map)) continue;
        block(safeString(map['productId']), label);
      }
    }

    for (final doc in await open('purchaseOrders', [
      'draft',
      'sent',
      'partial',
    ])) {
      blockLines(doc.data(), 'items', shortId('PO', doc.id));
    }
    for (final doc in await open('salesOrders', ['draft', 'confirmed'])) {
      blockLines(doc.data(), 'items', shortId('SO', doc.id));
    }
    for (final doc in await open('quotations', [
      'draft',
      'sent',
      'accepted',
      'expired',
    ])) {
      // Reuse the model's own idea of a quote that can still become an order.
      final quote = QuotationModel.fromMap(doc.data(), doc.id);
      if (!quote.isOpen && !quote.canConvert && !quote.canDecide) continue;
      blockLines(doc.data(), 'lines', 'Quote ${quote.quoteNumber}');
    }
    for (final doc in await open('transferOrders', ['draft', 'dispatched'])) {
      final ref = safeString(doc.data()['referenceNumber']);
      blockLines(doc.data(), 'lines', 'Transfer $ref');
    }
    for (final doc in await open('requisitions', [
      'draft',
      'submitted',
      'approved',
      'rejected',
    ])) {
      final ref = safeString(doc.data()['referenceNumber']);
      blockLines(doc.data(), 'lines', 'Requisition $ref');
    }
    for (final doc in await open('shipments', ['draft', 'picking', 'packed'])) {
      final ref = safeString(doc.data()['shipmentNumber']);
      blockLines(doc.data(), 'lines', 'Shipment $ref');
    }
    for (final doc in await open('jobWorkOrders', [
      'draft',
      'issued',
      'partiallyReceived',
    ])) {
      final label = 'Job work ${safeString(doc.data()['referenceNumber'])}';
      blockLines(doc.data(), 'components', label);
      block(safeString(doc.data()['outputProductId']), label);
    }
    for (final doc in await open('serviceJobs', [
      'received',
      'diagnosed',
      'inProgress',
      'awaitingParts',
      'resolved',
    ])) {
      // Parts already issued left stock in the old unit and are history; the
      // ones still to issue would leave it in the new one.
      blockLines(
        doc.data(),
        'parts',
        'Service job ${safeString(doc.data()['jobNumber'])}',
        where: (part) => !safeBool(part['issued']),
      );
    }
    for (final doc in await open('returns', ['pending', 'approved'])) {
      blockLines(doc.data(), 'items', shortId('RET', doc.id));
    }
    // A draft invoice moves stock when it is issued. Issued ones that never
    // moved stock (raised against a dispatched order) never will.
    for (final doc in await open('invoices', ['draft'])) {
      final number = safeString(doc.data()['invoiceNumber']);
      blockLines(doc.data(), 'items', 'Draft invoice $number');
    }
    for (final doc in await open('stockTakes', ['draft', 'inProgress'])) {
      final name = safeString(doc.data()['name']);
      blockLines(doc.data(), 'items', 'Stock take $name');
    }
    for (final doc in await open('landedCosts', ['draft'])) {
      // A draft allocates by quantity when applied, so converting one line of
      // it would shift the split between products.
      final ref = safeString(doc.data()['referenceNumber']);
      blockLines(doc.data(), 'lines', 'Draft landed cost $ref');
    }
    for (final productId in productIds) {
      final serials = await _collection(
        'serials',
      ).where('productId', isEqualTo: productId).limit(1).get();
      if (serials.docs.isNotEmpty) block(productId, 'Serial numbers');
    }
    return blockers;
  }

  // --- Applying ------------------------------------------------------------

  /// Writes [changes]: every [UnitChangeKind.repack] in batches, then every
  /// [UnitChangeKind.convertStock] one product at a time. Anything else in the
  /// list is ignored. One product failing does not stop the rest.
  Future<UnitConversionReport> apply(
    List<UnitChange> changes, {
    required String userId,
    required String userName,
    void Function(int done, int total)? onProgress,
  }) async {
    final repacks = changes
        .where((c) => c.kind == UnitChangeKind.repack)
        .toList();
    final conversions = changes
        .where((c) => c.kind == UnitChangeKind.convertStock)
        .toList();
    final total = repacks.length + conversions.length;
    final failures = <String, String>{};
    var done = 0;

    final repacked = await _repack(
      repacks,
      userId: userId,
      userName: userName,
      failures: failures,
      onProgress: (n) => onProgress?.call(done += n, total),
    );

    var converted = 0;
    if (conversions.isNotEmpty) {
      // Looked up once for the whole run rather than once per product.
      final blockers = await findBlockers({
        for (final c in conversions) c.product.id,
      });
      final shared = await _SharedRecords.load(this);
      for (final change in conversions) {
        final open = blockers[change.product.id];
        try {
          if (open != null) {
            throw UnitConversionException('Waiting for ${open.join(', ')}');
          }
          await _convert(
            change,
            shared,
            userId: userId,
            userName: userName,
            at: DateTime.now(),
          );
          converted++;
        } on UnitConversionException catch (e) {
          failures[change.product.name] = e.message;
        } catch (e) {
          failures[change.product.name] = 'Could not convert: $e';
        }
        onProgress?.call(++done, total);
      }
    }

    return UnitConversionReport(
      repacked: repacked,
      converted: converted,
      failures: failures,
    );
  }

  Future<int> _repack(
    List<UnitChange> changes, {
    required String userId,
    required String userName,
    required Map<String, String> failures,
    required void Function(int committed) onProgress,
  }) async {
    var written = 0;
    for (var start = 0; start < changes.length; start += kFirestoreBatchLimit) {
      final chunk = changes.skip(start).take(kFirestoreBatchLimit).toList();
      final batch = _firestore.batch();
      final now = Timestamp.now();
      for (final change in chunk) {
        batch.update(_collection('products').doc(change.product.id), {
          ...repackFields(change.rule!),
          'updatedAt': now,
          'updatedBy': userId,
          'updatedByName': userName,
        });
      }
      try {
        await batch.commit();
        written += chunk.length;
      } catch (e) {
        for (final change in chunk) {
          failures[change.product.name] = 'Could not update: $e';
        }
      }
      onProgress(chunk.length);
    }
    return written;
  }

  /// Re-counts one product's stock in its rule's base unit, together with
  /// every open record of its quantity or price.
  ///
  /// [UnitChange.product] is the snapshot the person reviewed. The transaction
  /// refuses if the product has moved since — converted already, re-labelled,
  /// or stock moved in or out — so running it twice can never multiply twice,
  /// and a quantity typed on another device is never scaled by mistake.
  Future<void> convertStock(
    UnitChange change, {
    required String userId,
    required String userName,
    DateTime? now,
  }) async {
    final productId = change.product.id;
    final open = (await findBlockers({productId}))[productId];
    if (open != null) {
      throw UnitConversionException('Waiting for ${open.join(', ')}');
    }
    await _convert(
      change,
      await _SharedRecords.load(this),
      userId: userId,
      userName: userName,
      at: now ?? DateTime.now(),
    );
  }

  Future<void> _convert(
    UnitChange change,
    _SharedRecords shared, {
    required String userId,
    required String userName,
    required DateTime at,
  }) async {
    final rule = change.rule!;
    final snapshot = change.product;
    final productId = snapshot.id;
    final factor = rule.unitsPerPack;

    // Transactions read documents, not queries, so find the related ones
    // first and re-read each inside.
    final holds = await _collection(
      'stockHolds',
    ).where('productId', isEqualTo: productId).get();
    final batches = await _collection(
      'batches',
    ).where('productId', isEqualTo: productId).get();
    final related = [
      for (final d in holds.docs) d.reference,
      for (final d in batches.docs) d.reference,
      ...shared.naming(productId),
    ];

    final productRef = _collection('products').doc(productId);
    await _firestore.runTransaction((txn) async {
      final productDoc = await txn.get(productRef);
      final data = productDoc.data();
      if (!productDoc.exists || data == null) {
        throw const UnitConversionException('Product no longer exists');
      }
      final current = ProductModel.fromMap(data, productId);
      if (!sameLabel(current.baseUnit, rule.packUnit)) {
        throw UnitConversionException(
          'Already counted in ${current.baseUnit}, not ${rule.packUnit}',
        );
      }
      if (current.quantity != snapshot.quantity ||
          current.heldQuantity != snapshot.heldQuantity) {
        throw const UnitConversionException(
          'Stock moved since the review — review again',
        );
      }

      // Every read before any write, as Firestore transactions require.
      final relatedDocs = [for (final ref in related) await txn.get(ref)];

      final writes =
          <DocumentReference<Map<String, dynamic>>, Map<String, Object?>>{};
      for (final doc in relatedDocs) {
        final docData = doc.data();
        if (docData == null) continue;
        final fields = switch (doc.reference.parent.id) {
          'stockHolds' =>
            _isOpenHold(docData) ? convertedHoldFields(docData, factor) : null,
          'batches' => convertedBatchFields(docData, factor),
          'priceLists' => convertedPriceListFields(docData, productId, factor),
          'boms' => convertedBomFields(
            docData,
            productId,
            factor,
            rule.baseUnit,
          ),
          'recurringInvoices' => convertedRecurringInvoiceFields(
            docData,
            productId,
            factor,
            rule.baseUnit,
          ),
          'landedCosts' => convertedLandedCostFields(
            docData,
            productId,
            factor,
          ),
          _ => null,
        };
        if (fields != null) writes[doc.reference] = fields;
      }

      final productFields = convertedProductFields(current, rule, at: at);
      final after = productFields['quantity']! as int;
      txn.update(productRef, {
        ...productFields,
        'updatedAt': Timestamp.fromDate(at),
        'updatedBy': userId,
        'updatedByName': userName,
      });
      writes.forEach(txn.update);

      final delta = after - current.quantity;
      txn.set(
        _collection('transactions').doc(),
        StockTransactionModel(
          id: '',
          productId: productId,
          productName: current.name,
          type: TransactionType.unitConversion,
          quantity: delta.abs(),
          quantityDelta: delta,
          fromUnit: current.baseUnit,
          toUnit: rule.baseUnit,
          factor: factor,
          reason: rule.label,
          userId: userId,
          userName: userName,
          date: at,
        ).toMap(),
      );
      txn.set(
        _collection('auditLogs').doc(),
        AuditLogModel(
          id: '',
          action: 'unit_conversion',
          entityType: 'Product',
          entityId: productId,
          entityName: current.name,
          userId: userId,
          userName: userName,
          changes: {
            'from': '${current.quantity} ${current.baseUnit}',
            'to': '$after ${rule.baseUnit}',
            'conversion': rule.label,
            'relatedRecords': writes.length,
          },
          timestamp: at,
        ).toMap(),
      );
    });
  }

  static bool _isOpenHold(Map<String, dynamic> hold) {
    final status = safeString(hold['status'], 'active');
    return status == 'active' || status == 'partially_consumed';
  }
}

/// The records a conversion may touch that cannot be found by product id —
/// their lines are arrays — loaded once per run and searched per product.
class _SharedRecords {
  _SharedRecords(this._docs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  static Future<_SharedRecords> load(UnitConversionService service) async {
    final results = await Future.wait([
      service._collection('priceLists').get(),
      service._collection('boms').get(),
      service
          ._collection('recurringInvoices')
          .where('status', whereIn: ['active', 'paused'])
          .get(),
      // Applied ones only: a draft blocks the conversion instead.
      service
          ._collection('landedCosts')
          .where('status', isEqualTo: 'applied')
          .get(),
    ]);
    return _SharedRecords([for (final r in results) ...r.docs]);
  }

  /// The loaded documents that name [productId] anywhere a quantity or price
  /// of it is kept.
  Iterable<DocumentReference<Map<String, dynamic>>> naming(
    String productId,
  ) sync* {
    bool inLines(Map<String, dynamic> data, String field) {
      final lines = data[field];
      return lines is List &&
          lines.any((l) => l is Map && safeString(l['productId']) == productId);
    }

    for (final doc in _docs) {
      final data = doc.data();
      final names = switch (doc.reference.parent.id) {
        'priceLists' => inLines(data, 'entries'),
        'boms' =>
          inLines(data, 'components') ||
              safeString(data['outputProductId']) == productId,
        'recurringInvoices' => inLines(data, 'items'),
        'landedCosts' => inLines(data, 'lines'),
        _ => false,
      };
      if (names) yield doc.reference;
    }
  }
}
