import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/vendor_model.dart';

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

  static String normalizeLocation(String raw) {
    return raw
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
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

    const batchLimit = 450;
    var batch = _firestore.batch();
    int opCount = 0;

    for (var doc in transactions.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= batchLimit) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    batch.delete(_products.doc(productId));
    await batch.commit();
  }

  /// Bulk adds products in batches of 450 (Firestore limit 500 per transaction).
  /// Note: Batches commit independently. If a later batch fails, earlier batches
  /// remain committed, leading to partial data. For very large imports, consider
  /// smaller runs or retry logic.
  Future<int> bulkAddProducts(List<ProductModel> products) async {
    var batch = _firestore.batch();
    int count = 0;

    for (var product in products) {
      final docRef = _products.doc();
      batch.set(docRef, product.toMap());
      count++;

      if (count % 450 == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }

    if (count % 450 != 0) {
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

      if (count % 450 == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }

    if (count % 450 != 0) {
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
    location = normalizeLocation(location);
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
    location = normalizeLocation(location);
    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locQty = (data['locationQuantities'] as Map?)?[location] ?? 0;
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
    location = normalizeLocation(location);
    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locQty = (data['locationQuantities'] as Map?)?[location] ?? 0;
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
    fromLocation = normalizeLocation(fromLocation);
    toLocation = normalizeLocation(toLocation);

    if (fromLocation == toLocation) {
      throw Exception('Source and destination locations must be different');
    }

    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locQty = (data['locationQuantities'] as Map?)?[fromLocation] ?? 0;
      final unit = data['unit'] ?? 'pcs';
      if (locQty < quantity) {
        throw Exception(
          'Not enough stock at $fromLocation. Available: $locQty $unit',
        );
      }

      final stockTransaction = StockTransactionModel(
        id: '',
        productId: productId,
        productName: productName,
        type: TransactionType.transfer,
        quantity: quantity,
        location: '$fromLocation → $toLocation',
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
        locMap.remove(fromLocation);
      } else {
        locMap[fromLocation] = newFromQty;
      }
      locMap[toLocation] = (locMap[toLocation] ?? 0) + quantity;

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
    final normalizedLoc = normalizeLocation(location);

    await _firestore.runTransaction((txn) async {
      final docRef = _products.doc(productId);
      final snapshot = await txn.get(docRef);

      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final locMap = Map<String, dynamic>.from(
        data['locationQuantities'] ?? {},
      );
      final currentLocQty = (locMap[normalizedLoc] ?? 0) as int;
      final newLocQty = currentLocQty + adjustmentDelta;

      if (newLocQty < 0) {
        throw Exception(
          'Adjustment would result in negative stock ($newLocQty) at $normalizedLoc',
        );
      }

      if (newLocQty <= 0) {
        locMap.remove(normalizedLoc);
      } else {
        locMap[normalizedLoc] = newLocQty;
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
        location: normalizedLoc,
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
      if (count % 450 == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }
    if (count % 450 != 0) {
      await batch.commit();
    }
  }
}
