import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_management/models/product_model.dart';
import 'package:stock_management/models/unit_conversion_rule.dart';
import 'package:stock_management/services/unit_conversion_planner.dart';
import 'package:stock_management/services/unit_conversion_service.dart';

/// A stock conversion rewrites quantities in seven collections at once. These
/// pin what it writes, that it writes it exactly once, and that it refuses
/// when the product or its open documents say it should not.
void main() {
  const rule = UnitConversionRule(
    id: 'r',
    categoryId: 'tiles',
    packUnit: 'box',
    unitsPerPack: 10,
    baseUnit: 'pcs',
  );

  late FakeFirebaseFirestore firestore;
  late DocumentReference<Map<String, dynamic>> company;
  late UnitConversionService service;

  CollectionReference<Map<String, dynamic>> col(String name) =>
      company.collection(name);

  Future<Map<String, dynamic>> read(String collection, String id) async =>
      (await col(collection).doc(id).get()).data()!;

  Future<List<UnitChange>> plan() async {
    final products = [
      for (final d in (await col('products').get()).docs)
        ProductModel.fromMap(d.data(), d.id),
    ];
    return planUnitChanges(products, [rule]);
  }

  UnitChange changeFor(List<UnitChange> changes, String id) =>
      changes.singleWhere((c) => c.product.id == id);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    company = firestore.collection('companies').doc('c1');
    service = UnitConversionService(companyId: 'c1', firestore: firestore);

    // Counted in boxes: needs its stock converted.
    await col('products').doc('boxed').set({
      'name': 'Floor tile',
      'categoryId': 'tiles',
      'quantity': 50,
      'heldQuantity': 8,
      'unit': 'box',
      'baseUnit': 'box',
      'packUnit': 'box',
      'unitsPerPack': 1,
      'locationQuantities': {'Main': 45, 'In transit': 5},
      'heldLocationQuantities': {'Main': 3, '(unassigned)': 5},
      'lowStockThreshold': 4,
      'costPrice': 100.0,
      'sellingPrice': 120.0,
      'vendorPrices': {'v1': 90.0},
    });
    // Counted in pieces: only its pack changes.
    await col('products').doc('loose').set({
      'name': 'Wall tile',
      'categoryId': 'tiles',
      'quantity': 37,
      'unit': 'pcs',
      'baseUnit': 'pcs',
      'packUnit': 'box',
      'unitsPerPack': 6,
      'locationQuantities': {'Main': 37},
      'costPrice': 7.5,
    });

    await col('stockHolds').doc('open').set({
      'productId': 'boxed',
      'quantity': 8,
      'consumedQuantity': 0,
      'releasedQuantity': 0,
      'status': 'active',
    });
    await col('stockHolds').doc('released').set({
      'productId': 'boxed',
      'quantity': 3,
      'consumedQuantity': 0,
      'releasedQuantity': 3,
      'status': 'released',
    });
    await col('batches').doc('b1').set({'productId': 'boxed', 'quantity': 20});
    await col('priceLists').doc('trade').set({
      'name': 'Trade',
      'entries': [
        {
          'productId': 'boxed',
          'mode': 'fixedPrice',
          'value': 110.0,
          'minQuantity': 2,
        },
        {
          'productId': 'loose',
          'mode': 'fixedPrice',
          'value': 7.0,
          'minQuantity': 1,
        },
      ],
    });
    await col('boms').doc('kit').set({
      'outputProductId': 'kit',
      'outputQuantity': 1,
      'components': [
        {'productId': 'boxed', 'quantity': 2, 'unit': 'box'},
      ],
    });
    await col('recurringInvoices').doc('monthly').set({
      'status': 'active',
      'items': [
        {
          'productId': 'boxed',
          'quantity': 3,
          'unitPrice': 120.0,
          'unit': 'box',
        },
      ],
    });
    await col('landedCosts').doc('lc1').set({
      'status': 'applied',
      'lines': [
        {
          'productId': 'boxed',
          'quantity': 4,
          'baseUnitCost': 100.0,
          'allocatedAmount': 40.0,
          'previousUnitCost': 95.0,
        },
      ],
    });
  });

  test('plans one repack and one stock conversion', () async {
    final changes = await plan();
    expect(changeFor(changes, 'loose').kind, UnitChangeKind.repack);
    expect(changeFor(changes, 'boxed').kind, UnitChangeKind.convertStock);
  });

  test('a repack writes only the pack fields', () async {
    final changes = await plan();
    final report = await service.apply(
      [changeFor(changes, 'loose')],
      userId: 'u1',
      userName: 'Ada',
    );

    expect(report.repacked, 1);
    final loose = await read('products', 'loose');
    expect(loose['packUnit'], 'box');
    expect(loose['unitsPerPack'], 10);
    expect(loose['quantity'], 37, reason: 'stock is untouched');
    expect(loose['costPrice'], 7.5, reason: 'prices are untouched');
    expect(loose['baseUnit'], 'pcs');
    expect(loose['updatedByName'], 'Ada');
    expect((await col('transactions').get()).docs, isEmpty);
  });

  test('a conversion re-counts the product and every record of it', () async {
    final changes = await plan();
    final report = await service.apply(changes, userId: 'u1', userName: 'Ada');
    expect(report.failures, isEmpty);
    expect(report.converted, 1);

    final boxed = await read('products', 'boxed');
    expect(boxed['quantity'], 500);
    expect(boxed['heldQuantity'], 80);
    expect(boxed['locationQuantities'], {'Main': 450, 'In transit': 50});
    expect(boxed['heldLocationQuantities'], {'Main': 30, '(unassigned)': 50});
    expect(boxed['lowStockThreshold'], 40);
    expect(boxed['costPrice'], 10.0);
    expect(boxed['sellingPrice'], 12.0);
    expect(boxed['vendorPrices'], {'v1': 9.0});
    expect(boxed['baseUnit'], 'pcs');
    expect(boxed['unit'], 'pcs');
    expect(boxed['packUnit'], 'box');
    expect(boxed['unitsPerPack'], 10);
    expect(boxed['unitsConvertedAt'], isA<Timestamp>());

    expect((await read('stockHolds', 'open'))['quantity'], 80);
    expect(
      (await read('stockHolds', 'released'))['quantity'],
      3,
      reason: 'a closed hold is history',
    );
    expect((await read('batches', 'b1'))['quantity'], 200);

    final entries = (await read('priceLists', 'trade'))['entries'] as List;
    expect(entries[0], containsPair('value', 11.0));
    expect(entries[0], containsPair('minQuantity', 20));
    expect(entries[1], containsPair('value', 7.0), reason: 'another product');

    final component =
        ((await read('boms', 'kit'))['components'] as List).single;
    expect(component, containsPair('quantity', 20));
    expect(component, containsPair('unit', 'pcs'));

    final line =
        ((await read('recurringInvoices', 'monthly'))['items'] as List).single;
    expect(line, containsPair('quantity', 30));
    expect(line, containsPair('unitPrice', 12.0));

    final landed = ((await read('landedCosts', 'lc1'))['lines'] as List).single;
    expect(landed, containsPair('previousUnitCost', 9.5));
    expect(landed, containsPair('allocatedAmount', 40.0));

    final ledger = (await col('transactions').get()).docs.single.data();
    expect(ledger['type'], 'unit_conversion');
    expect(ledger['productId'], 'boxed');
    expect(ledger['quantity'], 450);
    expect(ledger['quantityDelta'], 450);
    expect(ledger['fromUnit'], 'box');
    expect(ledger['toUnit'], 'pcs');
    expect(ledger['factor'], 10);

    final audit = (await col('auditLogs').get()).docs.single.data();
    expect(audit['action'], 'unit_conversion');
    expect(audit['entityId'], 'boxed');
    expect(audit['userId'], 'u1');
  });

  test('running the same review twice converts once', () async {
    final changes = await plan();
    await service.apply(changes, userId: 'u1', userName: 'Ada');
    final second = await service.apply(changes, userId: 'u1', userName: 'Ada');

    expect(second.converted, 0);
    expect(second.failures['Floor tile'], contains('Already counted in pcs'));
    expect((await read('products', 'boxed'))['quantity'], 500);
    expect((await read('batches', 'b1'))['quantity'], 200);
    expect((await col('transactions').get()).docs, hasLength(1));
  });

  test('stock that moved since the review is not scaled', () async {
    final changes = await plan();
    // Someone sells a box on another device after the review was built.
    await col('products').doc('boxed').update({'quantity': 49});

    await expectLater(
      service.convertStock(
        changeFor(changes, 'boxed'),
        userId: 'u1',
        userName: 'Ada',
      ),
      throwsA(
        isA<UnitConversionException>().having(
          (e) => e.message,
          'message',
          contains('review again'),
        ),
      ),
    );
    expect((await read('products', 'boxed'))['quantity'], 49);
    expect((await read('batches', 'b1'))['quantity'], 20);
    expect((await col('transactions').get()).docs, isEmpty);
  });

  test('an open purchase order makes the product wait', () async {
    await col('purchaseOrders').doc('abcdef123').set({
      'status': 'sent',
      'items': [
        {'productId': 'boxed', 'quantity': 5},
      ],
    });
    final changes = await plan();
    final report = await service.apply(changes, userId: 'u1', userName: 'Ada');

    expect(report.repacked, 1, reason: 'other products still go ahead');
    expect(report.converted, 0);
    expect(report.failures['Floor tile'], 'Waiting for PO-ABCDEF');
    expect((await read('products', 'boxed'))['quantity'], 50);
  });

  test('closed documents and issued parts do not block', () async {
    await col('purchaseOrders').doc('done').set({
      'status': 'received',
      'items': [
        {'productId': 'boxed', 'quantity': 5},
      ],
    });
    await col('serviceJobs').doc('job').set({
      'status': 'inProgress',
      'jobNumber': 'SJ-1',
      'parts': [
        {'productId': 'boxed', 'quantity': 1, 'issued': true},
      ],
    });
    expect(await service.findBlockers({'boxed'}), isEmpty);
  });

  test('serial-tracked products and draft invoices block', () async {
    await col('serials').doc('s1').set({'productId': 'boxed'});
    await col('invoices').doc('i1').set({
      'status': 'draft',
      'invoiceNumber': '1042',
      'items': [
        {'productId': 'loose', 'quantity': 2},
      ],
    });
    final blockers = await service.findBlockers({'boxed', 'loose'});
    expect(blockers['boxed'], ['Serial numbers']);
    expect(blockers['loose'], ['Draft invoice 1042']);
  });
}
