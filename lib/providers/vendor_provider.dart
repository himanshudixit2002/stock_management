import 'dart:async';
import 'package:flutter/material.dart';
import '../models/vendor_model.dart';
import '../models/product_model.dart';
import '../models/stock_transaction_model.dart';
import '../utils/error_helpers.dart';
import '../services/database_service.dart';

class VendorProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<VendorModel> _vendors = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _vendorsSubscription;

  List<VendorModel> get vendors => _vendors;
  List<VendorModel> get activeVendors =>
      _vendors.where((v) => v.isActive).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  VendorModel? getVendorById(String id) {
    for (final v in _vendors) {
      if (v.id == id) return v;
    }
    return null;
  }

  Map<String, VendorModel> getVendorIdMap() {
    final map = <String, VendorModel>{};
    for (var vendor in _vendors) {
      map[vendor.id] = vendor;
    }
    return map;
  }

  Map<String, VendorModel> getVendorNameMap() {
    final map = <String, VendorModel>{};
    for (var vendor in _vendors) {
      map[vendor.name.toLowerCase()] = vendor;
    }
    return map;
  }

  Future<Map<String, VendorModel>> fetchVendorNameMap() async {
    try {
      final vendors = await _databaseService.getVendorsOnce();
      _vendors = vendors;
      notifyListeners();
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not fetch vendors.');
      notifyListeners();
    }
    return getVendorNameMap();
  }

  void reset() {
    _vendorsSubscription?.cancel();
    _vendorsSubscription = null;
    _vendors = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _vendorsSubscription?.cancel();
    _isLoading = true;
    _vendorsSubscription = _databaseService.getVendors().listen(
      (vendors) {
        _vendors = vendors;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load vendors.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<VendorModel?> addVendor(VendorModel vendor) async {
    if (_isLoading) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final newId = await _databaseService.addVendor(vendor);
      _isLoading = false;
      notifyListeners();
      return vendor.copyWith(id: newId);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Vendor operation failed.');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateVendor(VendorModel vendor) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateVendor(vendor);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Vendor operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteVendor(String vendorId) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.deleteVendor(vendorId);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Vendor operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> bulkAssignVendor({
    required List<String> productIds,
    required String vendorId,
    required String vendorName,
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.bulkAssignVendor(
        productIds: productIds,
        vendorId: vendorId,
        vendorName: vendorName,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Vendor operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Stream<List<StockTransactionModel>> getVendorTransactions(String vendorId) {
    return _databaseService.getVendorTransactions(vendorId);
  }

  Map<String, dynamic> vendorScorecard(
    String vendorId,
    List<StockTransactionModel> allTransactions,
  ) {
    final vendorTxns = allTransactions
        .where((t) => t.vendorId == vendorId)
        .toList();
    final stockInTxns = vendorTxns
        .where((t) => t.type == TransactionType.stockIn)
        .toList();
    final totalQty = stockInTxns.fold<int>(0, (s, t) => s + t.quantity);

    DateTime? lastDate;
    if (vendorTxns.isNotEmpty) {
      lastDate = vendorTxns
          .reduce((a, b) => a.date.isAfter(b.date) ? a : b)
          .date;
    }

    final productCounts = <String, int>{};
    for (final t in vendorTxns) {
      final name = t.productName.isNotEmpty ? t.productName : t.productId;
      productCounts[name] = (productCounts[name] ?? 0) + t.quantity;
    }
    final topProducts =
        (productCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .toList();

    return {
      'totalTransactions': vendorTxns.length,
      'totalQuantity': totalQty,
      'lastTransactionDate': lastDate,
      'topProducts': topProducts,
    };
  }

  List<MapEntry<String, int>> vendorsByTransactionVolume(
    List<StockTransactionModel> allTransactions,
  ) {
    final map = <String, int>{};
    for (final t in allTransactions) {
      if (t.vendorId.isNotEmpty) {
        final name = t.vendorName.isNotEmpty ? t.vendorName : t.vendorId;
        map[name] = (map[name] ?? 0) + 1;
      }
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  List<Map<String, dynamic>> generatePurchaseOrderDraft(
    String vendorId,
    List<ProductModel> allProducts,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final p in allProducts) {
      if (p.preferredVendorId == vendorId &&
          p.quantity <= p.lowStockThreshold) {
        final suggestedQty = (p.lowStockThreshold * 2) - p.quantity;
        items.add({
          'productId': p.id,
          'productName': p.name,
          'currentQty': p.quantity,
          'threshold': p.lowStockThreshold,
          'suggestedOrderQty': suggestedQty > 0
              ? suggestedQty
              : p.lowStockThreshold,
          'unit': p.unit,
        });
      }
    }
    return items;
  }

  Map<String, List<ProductModel>> lowStockByVendor(
    List<ProductModel> allProducts,
  ) {
    final map = <String, List<ProductModel>>{};
    for (final p in allProducts) {
      if (p.preferredVendorId.isNotEmpty && p.quantity <= p.lowStockThreshold) {
        final key = p.preferredVendorName.isNotEmpty
            ? p.preferredVendorName
            : p.preferredVendorId;
        map.putIfAbsent(key, () => []).add(p);
      }
    }
    return map;
  }

  double weightedAverageCost(
    String productId,
    List<StockTransactionModel> allTransactions,
    Map<String, double> vendorPrices,
  ) {
    final stockIns = allTransactions
        .where(
          (t) =>
              t.productId == productId &&
              t.type == TransactionType.stockIn &&
              t.vendorId.isNotEmpty,
        )
        .toList();

    if (stockIns.isEmpty || vendorPrices.isEmpty) return 0;

    double totalCost = 0;
    int totalQty = 0;
    for (final t in stockIns) {
      final price = vendorPrices[t.vendorId] ?? 0;
      if (price > 0) {
        totalCost += price * t.quantity;
        totalQty += t.quantity;
      }
    }
    return totalQty > 0 ? totalCost / totalQty : 0;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _vendorsSubscription?.cancel();
    super.dispose();
  }
}
