import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/constants.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/vendor_model.dart';
import '../models/purchase_order_model.dart';
import '../models/sales_order_model.dart';
import '../models/return_model.dart';
import '../models/customer_model.dart';
import '../models/batch_model.dart';
import '../models/stock_take_model.dart';
import '../models/audit_log_model.dart';
import '../models/app_notification_model.dart';
import '../models/price_history_model.dart';
import '../models/warehouse_zone_model.dart';
import '../models/invoice_model.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _companyId = '';

  String get companyId => _companyId;

  void setCompanyId(String companyId) {
    _companyId = companyId;
  }

  void _ensureCompanyId() {
    if (_companyId.isEmpty) {
      throw StateError(
        'companyId must be set before accessing database. Call setCompanyId first.',
      );
    }
  }

  CollectionReference<Map<String, dynamic>> get _products {
    _ensureCompanyId();
    return _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('products');
  }

  CollectionReference<Map<String, dynamic>> get _categories {
    _ensureCompanyId();
    return _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('categories');
  }

  CollectionReference<Map<String, dynamic>> get _transactions {
    _ensureCompanyId();
    return _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('transactions');
  }

  CollectionReference<Map<String, dynamic>> get _vendors {
    _ensureCompanyId();
    return _firestore
        .collection('companies')
        .doc(_companyId)
        .collection('vendors');
  }

  // ==================== CATEGORIES ====================

  Stream<List<CategoryModel>> getCategories() {
    return _categories
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CategoryModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<CategoryModel>> getCategoriesOnce() async {
    final snapshot = await _categories.orderBy('name').get();
    return snapshot.docs
        .map((doc) => CategoryModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<String> addCategory(CategoryModel category) async {
    final docRef = await _categories.add(category.toMap());
    return docRef.id;
  }

  Future<void> updateCategory(CategoryModel category) async {
    await _categories.doc(category.id).update(category.toMap());

    final products = await _products
        .where('categoryId', isEqualTo: category.id)
        .get();
    if (products.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (var doc in products.docs) {
        batch.update(doc.reference, {'categoryName': category.name});
      }
      await batch.commit();
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    final products = await _products
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();

    if (products.docs.isNotEmpty) {
      throw Exception(
        'Cannot delete category. It is being used by existing products.',
      );
    }

    await _categories.doc(categoryId).delete();
  }

  // ==================== PRODUCTS ====================

  static const int productsPageSize = 200;

  Stream<List<ProductModel>> getProducts() {
    return _products
        .orderBy('name')
        .snapshots(includeMetadataChanges: false)
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Prefix search on product name. Used when client-side search returns no results.
  /// Case-insensitive: runs query for original and title-case variants, merges results.
  /// Cost: up to 2x [limit] reads when variants differ.
  Future<List<ProductModel>> searchProductsByName(
    String query, {
    int limit = 100,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final lowerCase = trimmed.toLowerCase();
    final upperCase = trimmed.toUpperCase();
    final titleCase = trimmed.length > 1
        ? '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}'
        : upperCase;

    final variants = <String>{trimmed, lowerCase, upperCase, titleCase};

    final seenIds = <String>{};
    final results = <ProductModel>[];

    Future<void> runQuery(String start) async {
      if (results.length >= limit) return;
      final end = '$start\uf8ff';
      final snapshot = await _products
          .orderBy('name')
          .where('name', isGreaterThanOrEqualTo: start)
          .where('name', isLessThanOrEqualTo: end)
          .limit(limit)
          .get();
      for (final doc in snapshot.docs) {
        if (seenIds.add(doc.id)) {
          results.add(ProductModel.fromMap(doc.data(), doc.id));
        }
        if (results.length >= limit) return;
      }
    }

    for (final variant in variants) {
      await runQuery(variant);
      if (results.length >= limit) break;
    }

    results.sort((a, b) => a.name.compareTo(b.name));
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  /// Fetches a page of products for pagination. Use [startAfter] for the next page.
  Future<
    ({List<ProductModel> products, DocumentSnapshot? lastDoc, bool hasMore})
  >
  getProductsPage({required int limit, DocumentSnapshot? startAfter}) async {
    Query<Map<String, dynamic>> query = _products
        .orderBy('name')
        .limit(limit + 1);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final resultDocs = hasMore ? docs.sublist(0, limit) : docs;
    final lastDoc = resultDocs.isNotEmpty ? resultDocs.last : null;
    final products = resultDocs
        .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
        .toList();
    return (products: products, lastDoc: lastDoc, hasMore: hasMore);
  }

  Stream<List<ProductModel>> getProductsByCategory(String categoryId) {
    return _products
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('name')
        .snapshots(includeMetadataChanges: false)
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<ProductModel?> getProduct(String productId) async {
    final doc = await _products.doc(productId).get();
    if (doc.exists) {
      return ProductModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  Future<String> addProduct(ProductModel product) async {
    final docRef = await _products.add(product.toMap());
    return docRef.id;
  }

  Future<void> updateProduct(ProductModel product) async {
    await _products.doc(product.id).update(product.toMap());
  }

  Future<void> deleteProduct(String productId) async {
    final transactions = await _transactions
        .where('productId', isEqualTo: productId)
        .get();

    var batch = _firestore.batch();
    int opCount = 0;

    for (var doc in transactions.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= kFirestoreBatchLimit) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    batch.delete(_products.doc(productId));
    await batch.commit();
  }

  Future<int> bulkAddProducts(List<ProductModel> products) async {
    var batch = _firestore.batch();
    int count = 0;

    for (var product in products) {
      final docRef = _products.doc();
      batch.set(docRef, product.toMap());
      count++;

      if (count % kFirestoreBatchLimit == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }

    if (count % kFirestoreBatchLimit != 0) {
      await batch.commit();
    }
    return count;
  }

  Future<int> bulkUpdateProducts(List<ProductModel> products) async {
    _ensureCompanyId();
    var batch = _firestore.batch();
    int count = 0;

    for (var product in products) {
      if (product.id.isEmpty) continue;
      final docRef = _products.doc(product.id);
      batch.update(docRef, product.toMap());
      count++;

      if (count % kFirestoreBatchLimit == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }

    if (count % kFirestoreBatchLimit != 0) {
      await batch.commit();
    }
    return count;
  }

  // ==================== STOCK TRANSACTIONS ====================

  Future<void> addStock({
    required String productId,
    required String productName,
    required int quantity,
    required String location,
    required String userId,
    required String userName,
    String reason = '',
    String vendorId = '',
    String vendorName = '',
  }) async {
    if (quantity <= 0) throw ArgumentError('quantity must be > 0');
    location = location.trim();
    final stockTransaction = StockTransactionModel(
      id: '',
      productId: productId,
      productName: productName,
      type: TransactionType.stockIn,
      quantity: quantity,
      location: location,
      reason: reason,
      userId: userId,
      userName: userName,
      date: DateTime.now(),
      vendorId: vendorId,
      vendorName: vendorName,
    );

    await _firestore.runTransaction((txn) async {
      final productRef = _products.doc(productId);
      final snapshot = await txn.get(productRef);
      if (!snapshot.exists) throw Exception('Product not found');

      final txnRef = _transactions.doc();
      txn.set(txnRef, stockTransaction.toMap());

      final updates = <String, dynamic>{
        'quantity': FieldValue.increment(quantity),
        'locationQuantities.$location': FieldValue.increment(quantity),
        'updatedAt': Timestamp.now(),
      };
      if (vendorId.isNotEmpty) {
        updates['lastVendorId'] = vendorId;
        updates['lastVendorName'] = vendorName;
      }
      txn.update(productRef, updates);
    });
  }

  Future<void> removeStock({
    required String productId,
    required String productName,
    required int quantity,
    required String location,
    required String userId,
    required String userName,
    String reason = '',
    String vendorId = '',
    String vendorName = '',
  }) async {
    location = location.trim();
    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locQty = ((data['locationQuantities'] as Map?)?[location] as num?)?.toInt() ?? 0;
      final unit = data['unit'] ?? 'pcs';
      if (locQty < quantity) {
        throw Exception(
          'Not enough stock at $location. Available: $locQty $unit',
        );
      }

      final stockTransaction = StockTransactionModel(
        id: '',
        productId: productId,
        productName: productName,
        type: TransactionType.stockOut,
        quantity: quantity,
        location: location,
        reason: reason,
        userId: userId,
        userName: userName,
        date: DateTime.now(),
        vendorId: vendorId,
        vendorName: vendorName,
      );

      final txnRef = _transactions.doc();
      txn.set(txnRef, stockTransaction.toMap());

      final newLocQty = locQty - quantity;
      final locMap = Map<String, dynamic>.from(
        data['locationQuantities'] ?? {},
      );

      if (newLocQty <= 0) {
        locMap.remove(location);
      } else {
        locMap[location] = newLocQty;
      }

      final totalQty = locMap.values.fold<int>(
        0,
        (acc, v) => acc + ((v as num?)?.toInt() ?? 0),
      );

      final updates = <String, dynamic>{
        'quantity': totalQty,
        'locationQuantities': locMap,
        'updatedAt': Timestamp.now(),
      };

      txn.update(docRef, updates);
    });
  }

  Future<void> recordDamage({
    required String productId,
    required String productName,
    required int quantity,
    required String location,
    required String userId,
    required String userName,
    required String reason,
  }) async {
    location = location.trim();
    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locQty = ((data['locationQuantities'] as Map?)?[location] as num?)?.toInt() ?? 0;
      final unit = data['unit'] ?? 'pcs';
      if (locQty < quantity) {
        throw Exception(
          'Damage qty exceeds stock at $location. Available: $locQty $unit',
        );
      }

      final stockTransaction = StockTransactionModel(
        id: '',
        productId: productId,
        productName: productName,
        type: TransactionType.damage,
        quantity: quantity,
        location: location,
        reason: reason,
        userId: userId,
        userName: userName,
        date: DateTime.now(),
      );

      final txnRef = _transactions.doc();
      txn.set(txnRef, stockTransaction.toMap());

      final newLocQty = locQty - quantity;
      final locMap = Map<String, dynamic>.from(
        data['locationQuantities'] ?? {},
      );

      if (newLocQty <= 0) {
        locMap.remove(location);
      } else {
        locMap[location] = newLocQty;
      }

      final totalQty = locMap.values.fold<int>(
        0,
        (acc, v) => acc + ((v as num?)?.toInt() ?? 0),
      );

      final updates = <String, dynamic>{
        'quantity': totalQty,
        'locationQuantities': locMap,
        'updatedAt': Timestamp.now(),
      };

      txn.update(docRef, updates);
    });
  }

  Future<void> transferStock({
    required String productId,
    required String productName,
    required int quantity,
    required String fromLocation,
    required String toLocation,
    required String userId,
    required String userName,
    String reason = '',
  }) async {
    final from = fromLocation.trim();
    final to = toLocation.trim();

    if (from == to) {
      throw Exception('Source and destination locations must be different');
    }

    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locQty = (data['locationQuantities'] as Map?)?[from] ?? 0;
      final unit = data['unit'] ?? 'pcs';
      if (locQty < quantity) {
        throw Exception(
          'Not enough stock at $from. Available: $locQty $unit',
        );
      }

      final stockTransaction = StockTransactionModel(
        id: '',
        productId: productId,
        productName: productName,
        type: TransactionType.transfer,
        quantity: quantity,
        location: '$from → $to',
        reason: reason,
        userId: userId,
        userName: userName,
        date: DateTime.now(),
      );

      final txnRef = _transactions.doc();
      txn.set(txnRef, stockTransaction.toMap());

      final newFromQty = locQty - quantity;
      final locMap = Map<String, dynamic>.from(
        data['locationQuantities'] ?? {},
      );

      if (newFromQty <= 0) {
        locMap.remove(from);
      } else {
        locMap[from] = newFromQty;
      }
      locMap[to] = (locMap[to] ?? 0) + quantity;

      final totalQty = locMap.values.fold<int>(
        0,
        (a, v) => a + ((v is int) ? v : (v as num).toInt()),
      );
      txn.update(docRef, {
        'locationQuantities': locMap,
        'quantity': totalQty,
        'updatedAt': Timestamp.now(),
      });
    });
  }

  /// Records a stock adjustment (physical count correction).
  Future<void> recordAdjustment({
    required String productId,
    required String productName,
    required int adjustmentDelta,
    required String location,
    required String userId,
    required String userName,
    String reason = '',
  }) async {
    location = location.trim();

    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locMap = Map<String, dynamic>.from(
        data['locationQuantities'] ?? {},
      );
      final currentLocQty = (locMap[location] as num?)?.toInt() ?? 0;
      final newLocQty = currentLocQty + adjustmentDelta;

      if (newLocQty < 0) {
        throw Exception(
          'Adjustment would result in negative stock ($newLocQty) at $location',
        );
      }

      if (newLocQty <= 0) {
        locMap.remove(location);
      } else {
        locMap[location] = newLocQty;
      }

      final totalQty = locMap.values.fold<int>(
        0,
        (a, v) => a + ((v is int) ? v : (v as num).toInt()),
      );

      final stockTransaction = StockTransactionModel(
        id: '',
        productId: productId,
        productName: productName,
        type: TransactionType.adjustment,
        quantity: adjustmentDelta.abs(),
        location: location,
        reason: reason,
        userId: userId,
        userName: userName,
        date: DateTime.now(),
      );

      final txnRef = _transactions.doc();
      txn.set(txnRef, stockTransaction.toMap());

      txn.update(docRef, {
        'locationQuantities': locMap,
        'quantity': totalQty,
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Future<void> updateTransactionLocation(
    String transactionId,
    String newLocation,
  ) async {
    _ensureCompanyId();
    await _transactions.doc(transactionId).update({'location': newLocation});
  }

  Stream<List<StockTransactionModel>> getProductTransactions(String productId) {
    return _transactions
        .where('productId', isEqualTo: productId)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<StockTransactionModel>> getAllTransactions({int limit = 2000}) {
    return _transactions
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<StockTransactionModel>> getAllTransactionsOnce({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query query = _transactions.orderBy('date', descending: true);

    if (startDate != null) {
      query = query.where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'date',
        isLessThanOrEqualTo: Timestamp.fromDate(
          endDate.add(const Duration(days: 1)),
        ),
      );
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) => StockTransactionModel.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ),
        )
        .toList();
  }

  Stream<List<StockTransactionModel>> getTransactionsByType(
    TransactionType type,
  ) {
    String typeStr;
    switch (type) {
      case TransactionType.stockIn:
        typeStr = 'stock_in';
        break;
      case TransactionType.stockOut:
        typeStr = 'stock_out';
        break;
      case TransactionType.damage:
        typeStr = 'damage';
        break;
      case TransactionType.transfer:
        typeStr = 'transfer';
        break;
      case TransactionType.adjustment:
        typeStr = 'adjustment';
        break;
    }

    return _transactions
        .where('type', isEqualTo: typeStr)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ==================== DASHBOARD STATS ====================

  Future<int> getTotalProductCount() async {
    final snapshot = await _products.count().get();
    return snapshot.count ?? 0;
  }

  Future<List<ProductModel>> getAllProductsOnce() async {
    final snapshot = await _products.orderBy('name').get();
    return snapshot.docs
        .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  // ==================== VENDORS ====================

  Stream<List<VendorModel>> getVendors() {
    return _vendors
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => VendorModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<VendorModel>> getVendorsOnce() async {
    final snapshot = await _vendors.orderBy('name').get();
    return snapshot.docs
        .map((doc) => VendorModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<VendorModel?> getVendorById(String vendorId) async {
    final doc = await _vendors.doc(vendorId).get();
    if (doc.exists) {
      return VendorModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  Future<String> addVendor(VendorModel vendor) async {
    final docRef = await _vendors.add(vendor.toMap());
    return docRef.id;
  }

  Future<void> updateVendor(VendorModel vendor) async {
    await _vendors.doc(vendor.id).update(vendor.toMap());
  }

  Future<void> deleteVendor(String vendorId) async {
    await _vendors.doc(vendorId).delete();
  }

  Stream<List<StockTransactionModel>> getVendorTransactions(String vendorId) {
    return _transactions
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> bulkAssignVendor({
    required List<String> productIds,
    required String vendorId,
    required String vendorName,
  }) async {
    var batch = _firestore.batch();
    int count = 0;
    for (final pid in productIds) {
      batch.update(_products.doc(pid), {
        'preferredVendorId': vendorId,
        'preferredVendorName': vendorName,
        'updatedAt': Timestamp.now(),
      });
      count++;
      if (count % kFirestoreBatchLimit == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }
    if (count % kFirestoreBatchLimit != 0) {
      await batch.commit();
    }
  }

  /// Propagate a vendor name change across products, transactions,
  /// purchase orders, and returns.
  Future<void> propagateVendorRename({
    required String vendorId,
    required String newName,
  }) async {
    _ensureCompanyId();

    // 1. Products – preferredVendorName
    var snap = await _products
        .where('preferredVendorId', isEqualTo: vendorId)
        .limit(kFirestoreBatchLimit)
        .get();
    while (snap.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'preferredVendorName': newName});
      }
      await batch.commit();
      if (snap.docs.length < kFirestoreBatchLimit) break;
      snap = await _products
          .where('preferredVendorId', isEqualTo: vendorId)
          .limit(kFirestoreBatchLimit)
          .startAfterDocument(snap.docs.last)
          .get();
    }

    // 2. Products – lastVendorName
    snap = await _products
        .where('lastVendorId', isEqualTo: vendorId)
        .limit(kFirestoreBatchLimit)
        .get();
    while (snap.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'lastVendorName': newName});
      }
      await batch.commit();
      if (snap.docs.length < kFirestoreBatchLimit) break;
      snap = await _products
          .where('lastVendorId', isEqualTo: vendorId)
          .limit(kFirestoreBatchLimit)
          .startAfterDocument(snap.docs.last)
          .get();
    }

    // 3. Transactions – vendorName
    snap = await _transactions
        .where('vendorId', isEqualTo: vendorId)
        .limit(kFirestoreBatchLimit)
        .get();
    while (snap.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'vendorName': newName});
      }
      await batch.commit();
      if (snap.docs.length < kFirestoreBatchLimit) break;
      snap = await _transactions
          .where('vendorId', isEqualTo: vendorId)
          .limit(kFirestoreBatchLimit)
          .startAfterDocument(snap.docs.last)
          .get();
    }

    // 4. Purchase orders – vendorName
    snap = await _purchaseOrders
        .where('vendorId', isEqualTo: vendorId)
        .limit(kFirestoreBatchLimit)
        .get();
    while (snap.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'vendorName': newName});
      }
      await batch.commit();
      if (snap.docs.length < kFirestoreBatchLimit) break;
      snap = await _purchaseOrders
          .where('vendorId', isEqualTo: vendorId)
          .limit(kFirestoreBatchLimit)
          .startAfterDocument(snap.docs.last)
          .get();
    }

    // 5. Returns – vendorName (vendor returns)
    snap = await _returns
        .where('vendorId', isEqualTo: vendorId)
        .limit(kFirestoreBatchLimit)
        .get();
    while (snap.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'vendorName': newName});
      }
      await batch.commit();
      if (snap.docs.length < kFirestoreBatchLimit) break;
      snap = await _returns
          .where('vendorId', isEqualTo: vendorId)
          .limit(kFirestoreBatchLimit)
          .startAfterDocument(snap.docs.last)
          .get();
    }
  }

  // ==================== PURCHASE ORDERS ====================

  CollectionReference<Map<String, dynamic>> get _purchaseOrders {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('purchaseOrders');
  }

  Stream<List<PurchaseOrderModel>> getPurchaseOrders() {
    return _purchaseOrders.orderBy('createdAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => PurchaseOrderModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addPurchaseOrder(PurchaseOrderModel po) async {
    final ref = await _purchaseOrders.add(po.toMap());
    return ref.id;
  }

  Future<void> updatePurchaseOrder(PurchaseOrderModel po) async {
    await _purchaseOrders.doc(po.id).update(po.toMap());
  }

  Future<void> deletePurchaseOrder(String id) async {
    await _purchaseOrders.doc(id).delete();
  }

  Future<void> setPurchaseOrderInvoiceId(String orderId, String invoiceId) async {
    await _purchaseOrders.doc(orderId).update({
      'invoiceId': invoiceId,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> receivePurchaseOrder({
    required PurchaseOrderModel po,
    required String userId,
    required String userName,
    required String location,
  }) async {
    var batch = _firestore.batch();
    int opCount = 0;

    for (final item in po.items) {
      final qty = item.quantity - item.receivedQuantity;
      if (qty <= 0) continue;
      final txn = StockTransactionModel(
        id: '', productId: item.productId, productName: item.productName,
        type: TransactionType.stockIn, quantity: qty,
        location: location, reason: 'PO #${po.id.substring(0, 6)}',
        userId: userId, userName: userName, date: DateTime.now(),
      );
      batch.set(_transactions.doc(), txn.toMap());
      opCount++;
      batch.update(_products.doc(item.productId), {
        'quantity': FieldValue.increment(qty),
        'locationQuantities.$location': FieldValue.increment(qty),
        'updatedAt': Timestamp.now(),
      });
      opCount++;

      if (opCount >= kFirestoreBatchLimit - 1) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    final updatedItems = po.items.map((i) => i.copyWith(receivedQuantity: i.quantity).toMap()).toList();
    batch.update(_purchaseOrders.doc(po.id), {
      'status': 'received', 'items': updatedItems,
      'receivedDate': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
    opCount++;

    await batch.commit();

    // Update product costPrice if PO unit price differs
    for (final item in po.items) {
      if (item.unitPrice <= 0) continue;
      final productDoc = await _products.doc(item.productId).get();
      if (!productDoc.exists) continue;
      final data = productDoc.data()!;
      final currentCost = (data['costPrice'] as num?)?.toDouble() ?? 0.0;
      if ((currentCost - item.unitPrice).abs() > 0.001) {
        await _products.doc(item.productId).update({
          'costPrice': item.unitPrice,
          'updatedAt': Timestamp.now(),
        });
        await addPriceHistory(PriceHistoryModel(
          id: '',
          productId: item.productId,
          productName: item.productName,
          field: 'costPrice',
          oldValue: currentCost,
          newValue: item.unitPrice,
          changedBy: userId,
          changedByName: userName,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  // ==================== SALES ORDERS ====================

  CollectionReference<Map<String, dynamic>> get _salesOrders {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('salesOrders');
  }

  Stream<List<SalesOrderModel>> getSalesOrders() {
    return _salesOrders.orderBy('createdAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => SalesOrderModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addSalesOrder(SalesOrderModel so) async {
    final ref = await _salesOrders.add(so.toMap());
    return ref.id;
  }

  Future<void> updateSalesOrder(SalesOrderModel so) async {
    await _salesOrders.doc(so.id).update(so.toMap());
  }

  Future<void> deleteSalesOrder(String id) async {
    await _salesOrders.doc(id).delete();
  }

  Future<void> setSalesOrderInvoiceId(String orderId, String invoiceId) async {
    await _salesOrders.doc(orderId).update({
      'invoiceId': invoiceId,
      'updatedAt': Timestamp.now(),
    });
  }

  // ==================== RETURNS ====================

  CollectionReference<Map<String, dynamic>> get _returns {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('returns');
  }

  Stream<List<ReturnModel>> getReturns() {
    return _returns.orderBy('createdAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => ReturnModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addReturn(ReturnModel r) async {
    final ref = await _returns.add(r.toMap());
    return ref.id;
  }

  Future<void> updateReturn(ReturnModel r) async {
    await _returns.doc(r.id).update(r.toMap());
  }

  // ==================== CUSTOMERS ====================

  CollectionReference<Map<String, dynamic>> get _customers {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('customers');
  }

  Stream<List<CustomerModel>> getCustomers() {
    return _customers.orderBy('name').snapshots().map(
      (s) => s.docs.map((d) => CustomerModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<List<CustomerModel>> getCustomersOnce() async {
    final s = await _customers.orderBy('name').get();
    return s.docs.map((d) => CustomerModel.fromMap(d.data(), d.id)).toList();
  }

  Future<String> addCustomer(CustomerModel c) async {
    final ref = await _customers.add(c.toMap());
    return ref.id;
  }

  Future<void> updateCustomer(CustomerModel c) async {
    await _customers.doc(c.id).update(c.toMap());
  }

  Future<void> deleteCustomer(String id) async {
    await _customers.doc(id).delete();
  }

  // ==================== BATCHES ====================

  CollectionReference<Map<String, dynamic>> get _batches {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('batches');
  }

  Stream<List<BatchModel>> getBatches() {
    return _batches.orderBy('createdAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => BatchModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addBatch(BatchModel b) async {
    final ref = await _batches.add(b.toMap());
    return ref.id;
  }

  Future<void> updateBatch(BatchModel b) async {
    await _batches.doc(b.id).update(b.toMap());
  }

  Future<void> deleteBatch(String id) async {
    await _batches.doc(id).delete();
  }

  // ==================== STOCK TAKES ====================

  CollectionReference<Map<String, dynamic>> get _stockTakes {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('stockTakes');
  }

  Stream<List<StockTakeModel>> getStockTakes() {
    return _stockTakes.orderBy('startedAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => StockTakeModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addStockTake(StockTakeModel st) async {
    final ref = await _stockTakes.add(st.toMap());
    return ref.id;
  }

  Future<void> updateStockTake(StockTakeModel st) async {
    await _stockTakes.doc(st.id).update(st.toMap());
  }

  // ==================== AUDIT LOGS ====================

  CollectionReference<Map<String, dynamic>> get _auditLogs {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('auditLogs');
  }

  Stream<List<AuditLogModel>> getAuditLogs({int limit = 200}) {
    return _auditLogs.orderBy('timestamp', descending: true).limit(limit).snapshots().map(
      (s) => s.docs.map((d) => AuditLogModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<void> addAuditLog(AuditLogModel log) async {
    await _auditLogs.add(log.toMap());
  }

  // ==================== NOTIFICATIONS ====================

  CollectionReference<Map<String, dynamic>> get _notifications {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('notifications');
  }

  Stream<List<AppNotificationModel>> getNotifications({int limit = 100}) {
    return _notifications.orderBy('timestamp', descending: true).limit(limit).snapshots().map(
      (s) => s.docs.map((d) => AppNotificationModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<void> addNotification(AppNotificationModel n) async {
    await _notifications.add(n.toMap());
  }

  Future<void> markNotificationRead(String id) async {
    await _notifications.doc(id).update({'isRead': true});
  }

  Future<void> markAllNotificationsRead() async {
    final snap = await _notifications.where('isRead', isEqualTo: false).get();
    final b = _firestore.batch();
    for (final d in snap.docs) {
      b.update(d.reference, {'isRead': true});
    }
    await b.commit();
  }

  Future<void> deleteNotification(String id) async {
    await _notifications.doc(id).delete();
  }

  // ==================== PRICE HISTORY ====================

  CollectionReference<Map<String, dynamic>> get _priceHistory {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('priceHistory');
  }

  Stream<List<PriceHistoryModel>> getPriceHistory({String? productId}) {
    Query<Map<String, dynamic>> q = _priceHistory.orderBy('timestamp', descending: true);
    if (productId != null) q = q.where('productId', isEqualTo: productId);
    return q.limit(500).snapshots().map(
      (s) => s.docs.map((d) => PriceHistoryModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<void> addPriceHistory(PriceHistoryModel p) async {
    await _priceHistory.add(p.toMap());
  }

  // ==================== WAREHOUSE ZONES ====================

  CollectionReference<Map<String, dynamic>> get _warehouseZones {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('warehouseZones');
  }

  Stream<List<WarehouseZoneModel>> getWarehouseZones() {
    return _warehouseZones.orderBy('locationName').snapshots().map(
      (s) => s.docs.map((d) => WarehouseZoneModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addWarehouseZone(WarehouseZoneModel z) async {
    final ref = await _warehouseZones.add(z.toMap());
    return ref.id;
  }

  Future<void> updateWarehouseZone(WarehouseZoneModel z) async {
    await _warehouseZones.doc(z.id).update(z.toMap());
  }

  Future<void> deleteWarehouseZone(String id) async {
    await _warehouseZones.doc(id).delete();
  }

  // ==================== INVOICES ====================

  CollectionReference<Map<String, dynamic>> get _invoices {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId).collection('invoices');
  }

  DocumentReference get _companyDoc {
    _ensureCompanyId();
    return _firestore.collection('companies').doc(_companyId);
  }

  Stream<List<InvoiceModel>> getInvoices() {
    return _invoices.orderBy('createdAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => InvoiceModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Future<String> addInvoice(InvoiceModel invoice) async {
    final ref = await _invoices.add(invoice.toMap());
    return ref.id;
  }

  Future<void> setInvoiceStockDeducted(String invoiceId, bool value) async {
    await _invoices.doc(invoiceId).update({
      'stockDeducted': value,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<SalesOrderModel?> getSalesOrderById(String id) async {
    final doc = await _salesOrders.doc(id).get();
    if (!doc.exists) return null;
    return SalesOrderModel.fromMap(doc.data()!, doc.id);
  }

  Future<PurchaseOrderModel?> getPurchaseOrderById(String id) async {
    final doc = await _purchaseOrders.doc(id).get();
    if (!doc.exists) return null;
    return PurchaseOrderModel.fromMap(doc.data()!, doc.id);
  }

  Future<void> clearSalesOrderInvoiceId(String orderId) async {
    await _salesOrders.doc(orderId).update({
      'invoiceId': '',
      'updatedAt': Timestamp.now(),
    });
  }

  /// Atomically creates a sales order and sets [linkedSalesOrderId] on the invoice.
  Future<String> createSalesOrderLinkedToInvoice({
    required String invoiceId,
    required SalesOrderModel orderWithoutDocId,
  }) async {
    _ensureCompanyId();
    final batch = _firestore.batch();
    final soRef = _salesOrders.doc();
    final now = DateTime.now();
    final so = orderWithoutDocId.copyWith(
      id: soRef.id,
      invoiceId: invoiceId,
      updatedAt: now,
    );
    batch.set(soRef, so.toMap());
    batch.update(_invoices.doc(invoiceId), {
      'linkedSalesOrderId': soRef.id,
      'updatedAt': Timestamp.fromDate(now),
    });
    await batch.commit();
    return soRef.id;
  }

  Future<void> clearPurchaseOrderInvoiceId(String orderId) async {
    await _purchaseOrders.doc(orderId).update({
      'invoiceId': '',
      'updatedAt': Timestamp.now(),
    });
  }

  /// Atomically creates a purchase order and sets [linkedPurchaseOrderId] on the bill.
  Future<String> createPurchaseOrderLinkedToInvoice({
    required String invoiceId,
    required PurchaseOrderModel orderWithoutDocId,
  }) async {
    _ensureCompanyId();
    final batch = _firestore.batch();
    final poRef = _purchaseOrders.doc();
    final now = DateTime.now();
    final po = orderWithoutDocId.copyWith(
      id: poRef.id,
      invoiceId: invoiceId,
      updatedAt: now,
    );
    batch.set(poRef, po.toMap());
    batch.update(_invoices.doc(invoiceId), {
      'linkedPurchaseOrderId': poRef.id,
      'updatedAt': Timestamp.fromDate(now),
    });
    await batch.commit();
    return poRef.id;
  }

  Future<void> updateInvoice(InvoiceModel invoice) async {
    await _invoices.doc(invoice.id).update(invoice.toMap());
  }

  Future<void> deleteInvoice(String id) async {
    await _invoices.doc(id).delete();
  }

  DocumentReference<Map<String, dynamic>> get _billingSequencesDoc {
    _ensureCompanyId();
    return _companyDoc.collection('billingSequences').doc('default');
  }

  /// Atomically allocates the next sales invoice sequence. Uses
  /// [billingSequences/default] so users with [canCreateInvoices] need not
  /// update the whole company document (which requires company settings).
  Future<String> getNextInvoiceNumber(String prefix) async {
    final seqRef = _billingSequencesDoc;
    return _firestore.runTransaction((txn) async {
      final seqSnap = await txn.get(seqRef);
      int nextInv = 1;
      int nextPur = 1;
      if (seqSnap.exists && seqSnap.data() != null) {
        final d = seqSnap.data()!;
        nextInv = (d['nextInvoiceNumber'] as num?)?.toInt() ?? 1;
        nextPur = (d['nextPurchaseNumber'] as num?)?.toInt() ?? 1;
      } else {
        final companySnap = await txn.get(_companyDoc);
        if (companySnap.exists) {
          final companyData = companySnap.data() as Map<String, dynamic>?;
          final billing =
              companyData?['settings']?['billing'] as Map<String, dynamic>?;
          if (billing != null) {
            nextInv = (billing['nextInvoiceNumber'] as num?)?.toInt() ?? 1;
            nextPur = (billing['nextPurchaseNumber'] as num?)?.toInt() ?? 1;
          }
        }
      }
      final formatted = '$prefix-${nextInv.toString().padLeft(4, '0')}';
      txn.set(seqRef, {
        'nextInvoiceNumber': nextInv + 1,
        'nextPurchaseNumber': nextPur,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return formatted;
    });
  }

  Future<String> getNextPurchaseInvoiceNumber(String prefix) async {
    final seqRef = _billingSequencesDoc;
    return _firestore.runTransaction((txn) async {
      final seqSnap = await txn.get(seqRef);
      int nextInv = 1;
      int nextPur = 1;
      if (seqSnap.exists && seqSnap.data() != null) {
        final d = seqSnap.data()!;
        nextInv = (d['nextInvoiceNumber'] as num?)?.toInt() ?? 1;
        nextPur = (d['nextPurchaseNumber'] as num?)?.toInt() ?? 1;
      } else {
        final companySnap = await txn.get(_companyDoc);
        if (companySnap.exists) {
          final companyData = companySnap.data() as Map<String, dynamic>?;
          final billing =
              companyData?['settings']?['billing'] as Map<String, dynamic>?;
          if (billing != null) {
            nextInv = (billing['nextInvoiceNumber'] as num?)?.toInt() ?? 1;
            nextPur = (billing['nextPurchaseNumber'] as num?)?.toInt() ?? 1;
          }
        }
      }
      final formatted = '$prefix-${nextPur.toString().padLeft(4, '0')}';
      txn.set(seqRef, {
        'nextInvoiceNumber': nextInv,
        'nextPurchaseNumber': nextPur + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return formatted;
    });
  }

  Future<void> recordPaymentOnInvoice(
    String invoiceId,
    PaymentRecord payment,
    double newAmountPaid,
    double newAmountDue,
    InvoiceStatus newStatus,
  ) async {
    await _invoices.doc(invoiceId).update({
      'payments': FieldValue.arrayUnion([payment.toMap()]),
      'amountPaid': newAmountPaid,
      'amountDue': newAmountDue,
      'status': newStatus == InvoiceStatus.paid
          ? 'paid'
          : newStatus == InvoiceStatus.partiallyPaid
              ? 'partiallyPaid'
              : 'sent',
      'updatedAt': Timestamp.now(),
    });
  }
}
