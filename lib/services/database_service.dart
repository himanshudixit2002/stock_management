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

  CollectionReference<Map<String, dynamic>> get _products {
    assert(_companyId.isNotEmpty, 'companyId must be set before accessing products');
    return _firestore.collection('companies').doc(_companyId).collection('products');
  }

  CollectionReference<Map<String, dynamic>> get _categories {
    assert(_companyId.isNotEmpty, 'companyId must be set before accessing categories');
    return _firestore.collection('companies').doc(_companyId).collection('categories');
  }

  CollectionReference<Map<String, dynamic>> get _transactions {
    assert(_companyId.isNotEmpty, 'companyId must be set before accessing transactions');
    return _firestore.collection('companies').doc(_companyId).collection('transactions');
  }

  CollectionReference<Map<String, dynamic>> get _vendors {
    assert(_companyId.isNotEmpty, 'companyId must be set before accessing vendors');
    return _firestore.collection('companies').doc(_companyId).collection('vendors');
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
        .map((snapshot) => snapshot.docs
            .map((doc) => CategoryModel.fromMap(doc.data(), doc.id))
            .toList());
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
          'Cannot delete category. It is being used by existing products.');
    }

    await _categories.doc(categoryId).delete();
  }

  // ==================== PRODUCTS ====================

  Stream<List<ProductModel>> getProducts() {
    return _products
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<ProductModel>> getProductsByCategory(String categoryId) {
    return _products
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<ProductModel>> getLowStockProducts() {
    return _products
        .orderBy('quantity')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
            .where((p) => p.quantity <= p.lowStockThreshold)
            .toList());
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

    final batch = _firestore.batch();
    for (var doc in transactions.docs) {
      batch.delete(doc.reference);
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
      final txnRef = _transactions.doc();
      txn.set(txnRef, stockTransaction.toMap());

      final productRef = _products.doc(productId);
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
            'Not enough stock at $location. Available: $locQty $unit');
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
      final totalQty = (data['quantity'] ?? 0) - quantity;

      final updates = <String, dynamic>{
        'quantity': totalQty,
        'updatedAt': Timestamp.now(),
      };

      if (newLocQty <= 0) {
        final locMap =
            Map<String, dynamic>.from(data['locationQuantities'] ?? {});
        locMap.remove(location);
        updates['locationQuantities'] = locMap;
      } else {
        updates['locationQuantities.$location'] = newLocQty;
      }

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
            'Damage qty exceeds stock at $location. Available: $locQty $unit');
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
      final totalQty = (data['quantity'] ?? 0) - quantity;

      final updates = <String, dynamic>{
        'quantity': totalQty,
        'updatedAt': Timestamp.now(),
      };

      if (newLocQty <= 0) {
        final locMap =
            Map<String, dynamic>.from(data['locationQuantities'] ?? {});
        locMap.remove(location);
        updates['locationQuantities'] = locMap;
      } else {
        updates['locationQuantities.$location'] = newLocQty;
      }

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
            'Not enough stock at $fromLocation. Available: $locQty $unit');
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
      final locMap =
          Map<String, dynamic>.from(data['locationQuantities'] ?? {});

      if (newFromQty <= 0) {
        locMap.remove(fromLocation);
      } else {
        locMap[fromLocation] = newFromQty;
      }
      locMap[toLocation] = (locMap[toLocation] ?? 0) + quantity;

      txn.update(docRef, {
        'locationQuantities': locMap,
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Stream<List<StockTransactionModel>> getProductTransactions(String productId) {
    return _transactions
        .where('productId', isEqualTo: productId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<List<StockTransactionModel>> getAllTransactions({int limit = 500}) {
    return _transactions
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<List<StockTransactionModel>> getAllTransactionsOnce({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query query = _transactions.orderBy('date', descending: true);

    if (startDate != null) {
      query = query.where('date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('date',
          isLessThanOrEqualTo: Timestamp.fromDate(
              endDate.add(const Duration(days: 1))));
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => StockTransactionModel.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Stream<List<StockTransactionModel>> getTransactionsByType(
      TransactionType type) {
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
    }

    return _transactions
        .where('type', isEqualTo: typeStr)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
            .toList());
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
        .map((snapshot) => snapshot.docs
            .map((doc) => VendorModel.fromMap(doc.data(), doc.id))
            .toList());
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
        .map((snapshot) => snapshot.docs
            .map((doc) => StockTransactionModel.fromMap(doc.data(), doc.id))
            .toList());
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
