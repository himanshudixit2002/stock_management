import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class ProductProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  String get companyId => _databaseService.companyId;

  List<ProductModel> _products = [];
  List<ProductModel> _filteredProducts = [];
  List<ProductModel> _lowStockProducts = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedCategoryId;
  String? _selectedLocation;
  String? _selectedCompany;
  String? _selectedSize;
  String? _selectedStockStatus;
  String? _selectedVendorId;
  String _sortBy = 'name';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  StreamSubscription? _productsSubscription;
  StreamSubscription? _lowStockSubscription;

  // --- Analytics cache ---
  bool _analyticsDirty = true;
  List<String>? _cachedAvailableLocations;
  Map<String, List<ProductModel>>? _cachedProductsByCategory;
  Map<String, int>? _cachedProductCountByCategory;
  Map<String, int>? _cachedLowStockByCategory;
  Map<String, int>? _cachedOutOfStockByCategory;
  List<ProductModel>? _cachedTopProductsByQuantity;
  Map<String, int>? _cachedLocationBreakdown;
  Map<String, int>? _cachedQuantityByLocation;
  double? _cachedInventoryHealthScore;
  int? _cachedOutOfStockCount;

  void _invalidateAnalytics() {
    _analyticsDirty = true;
    _cachedAvailableLocations = null;
    _cachedProductsByCategory = null;
    _cachedProductCountByCategory = null;
    _cachedLowStockByCategory = null;
    _cachedOutOfStockByCategory = null;
    _cachedTopProductsByQuantity = null;
    _cachedLocationBreakdown = null;
    _cachedQuantityByLocation = null;
    _cachedInventoryHealthScore = null;
    _cachedOutOfStockCount = null;
  }

  bool _filtersActive = false;

  List<ProductModel> get products => _filtersActive ? _filteredProducts : _products;
  List<ProductModel> get allProducts => _products;
  List<ProductModel> get lowStockProducts => _lowStockProducts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedLocation => _selectedLocation;
  String? get selectedCompany => _selectedCompany;
  String? get selectedSize => _selectedSize;
  String? get selectedStockStatus => _selectedStockStatus;
  String? get selectedVendorId => _selectedVendorId;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;

  List<String> get availableLocations {
    if (_cachedAvailableLocations != null && !_analyticsDirty) {
      return _cachedAvailableLocations!;
    }
    final locations = <String>{};
    for (final p in _products) {
      for (final entry in p.locationQuantities.entries) {
        if (entry.value > 0) locations.add(entry.key);
      }
    }
    _cachedAvailableLocations = locations.toList()..sort();
    return _cachedAvailableLocations!;
  }

  int get activeFilterCount {
    int count = 0;
    if (_selectedCategoryId != null) count++;
    if (_selectedCompany != null) count++;
    if (_selectedSize != null) count++;
    if (_selectedLocation != null) count++;
    if (_selectedStockStatus != null) count++;
    if (_selectedVendorId != null) count++;
    if (_filterStartDate != null || _filterEndDate != null) count++;
    return count;
  }

  bool get hasActiveFilters => activeFilterCount > 0 || _searchQuery.isNotEmpty;

  void filterByDateRange(DateTime? start, DateTime? end) {
    _filterStartDate = start;
    _filterEndDate = end;
    _applyFilters();
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _productsSubscription?.cancel();
    _lowStockSubscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _productsSubscription = _databaseService.getProducts().listen(
      (products) {
        _products = products;
        _invalidateAnalytics();
        _applyFilters();
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(error, fallback: 'Could not load products.');
        _isLoading = false;
        notifyListeners();
      },
    );

    _lowStockSubscription = _databaseService.getLowStockProducts().listen(
      (products) {
        _lowStockProducts = products;
        notifyListeners();
      },
    );
  }

  void search(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void filterByCategory(String? categoryId) {
    if (_selectedCategoryId == categoryId) return;
    _selectedCategoryId = categoryId;
    _applyFilters();
    notifyListeners();
  }

  void filterByCompany(String? company) {
    if (_selectedCompany == company) return;
    _selectedCompany = company;
    _applyFilters();
    notifyListeners();
  }

  void filterBySize(String? size) {
    if (_selectedSize == size) return;
    _selectedSize = size;
    _applyFilters();
    notifyListeners();
  }

  void filterByLocation(String? location) {
    if (_selectedLocation == location) return;
    _selectedLocation = location;
    _applyFilters();
    notifyListeners();
  }

  void filterByStockStatus(String? status) {
    if (_selectedStockStatus == status) return;
    _selectedStockStatus = status;
    _applyFilters();
    notifyListeners();
  }

  void filterByVendor(String? vendorId) {
    if (_selectedVendorId == vendorId) return;
    _selectedVendorId = vendorId;
    _applyFilters();
    notifyListeners();
  }

  Map<String, List<ProductModel>> get productsByVendor {
    final map = <String, List<ProductModel>>{};
    for (final p in _products) {
      if (p.preferredVendorId.isNotEmpty) {
        final key = p.preferredVendorName.isNotEmpty
            ? p.preferredVendorName
            : p.preferredVendorId;
        map.putIfAbsent(key, () => []).add(p);
      }
    }
    return map;
  }

  void sortProducts(String sortBy) {
    if (_sortBy == sortBy) return;
    _sortBy = sortBy;
    _applyFilters();
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedCategoryId = null;
    _selectedCompany = null;
    _selectedSize = null;
    _selectedLocation = null;
    _selectedStockStatus = null;
    _selectedVendorId = null;
    _sortBy = 'name';
    _filterStartDate = null;
    _filterEndDate = null;
    _filteredProducts = [];
    _filtersActive = false;
    notifyListeners();
  }

  void _applyFilters() {
    _filtersActive = _searchQuery.isNotEmpty ||
        _selectedCategoryId != null ||
        _selectedCompany != null ||
        _selectedSize != null ||
        _selectedLocation != null ||
        _selectedStockStatus != null ||
        _selectedVendorId != null ||
        _filterStartDate != null ||
        _filterEndDate != null;

    Iterable<ProductModel> result = _products;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((p) =>
          p.name.toLowerCase().contains(query) ||
          p.categoryName.toLowerCase().contains(query) ||
          p.company.toLowerCase().contains(query) ||
          p.size.toLowerCase().contains(query) ||
          p.locations.any((l) => l.toLowerCase().contains(query)) ||
          p.description.toLowerCase().contains(query));
    }

    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId);
    }

    if (_selectedCompany != null) {
      result = result.where((p) => p.company == _selectedCompany);
    }

    if (_selectedSize != null) {
      result = result.where((p) => p.size == _selectedSize);
    }

    if (_selectedLocation != null) {
      result = result.where((p) => (p.locationQuantities[_selectedLocation] ?? 0) > 0);
    }

    if (_selectedStockStatus != null) {
      switch (_selectedStockStatus) {
        case 'in_stock':
          result = result.where((p) => p.isInStock);
          break;
        case 'low_stock':
          result = result.where((p) => p.isLowStock);
          break;
        case 'out_of_stock':
          result = result.where((p) => p.isOutOfStock);
          break;
      }
    }

    if (_selectedVendorId != null) {
      result = result.where((p) =>
          p.preferredVendorId == _selectedVendorId ||
          p.lastVendorId == _selectedVendorId);
    }

    if (_filterStartDate != null) {
      final start = DateTime(_filterStartDate!.year, _filterStartDate!.month, _filterStartDate!.day);
      result = result.where((p) => !p.createdAt.isBefore(start));
    }
    if (_filterEndDate != null) {
      final endExclusive = DateTime(_filterEndDate!.year, _filterEndDate!.month, _filterEndDate!.day + 1);
      result = result.where((p) => p.createdAt.isBefore(endExclusive));
    }

    final filtered = result.toList();

    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'quantity':
        filtered.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case 'quantity_desc':
        filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
    }

    _filteredProducts = filtered;
  }

  Future<bool> addProduct(ProductModel product) async {
    try {
      _errorMessage = null;
      await _databaseService.addProduct(product);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to add product.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProduct(ProductModel product) async {
    try {
      _errorMessage = null;
      await _databaseService.updateProduct(product);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update product.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    try {
      _errorMessage = null;
      await _databaseService.deleteProduct(productId);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete product.');
      notifyListeners();
      return false;
    }
  }

  Future<int> bulkAddProducts(
    List<ProductModel> products, {
    required String userId,
    required String userName,
  }) async {
    try {
      _errorMessage = null;
      final productsWithAudit = products
          .map((p) => p.copyWith(createdBy: userId, createdByName: userName))
          .toList();
      return await _databaseService.bulkAddProducts(productsWithAudit);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to import products.');
      notifyListeners();
      return 0;
    }
  }

  // --- Dashboard stats ---
  int get totalProducts => _products.length;
  int get lowStockCount => _lowStockProducts.length;

  int get outOfStockCount {
    if (_cachedOutOfStockCount != null && !_analyticsDirty) {
      return _cachedOutOfStockCount!;
    }
    _cachedOutOfStockCount = _products.where((p) => p.isOutOfStock).length;
    return _cachedOutOfStockCount!;
  }

  // --- Category analytics (cached) ---

  Map<String, List<ProductModel>> get productsByCategory {
    if (_cachedProductsByCategory != null && !_analyticsDirty) {
      return _cachedProductsByCategory!;
    }
    final map = <String, List<ProductModel>>{};
    for (final p in _products) {
      final cat = p.categoryName.isNotEmpty ? p.categoryName : 'Uncategorized';
      map.putIfAbsent(cat, () => []).add(p);
    }
    _cachedProductsByCategory = map;
    return map;
  }

  Map<String, int> get productCountByCategory {
    if (_cachedProductCountByCategory != null && !_analyticsDirty) {
      return _cachedProductCountByCategory!;
    }
    _cachedProductCountByCategory = productsByCategory
        .map((key, value) => MapEntry(key, value.length));
    return _cachedProductCountByCategory!;
  }

  Map<String, int> get lowStockByCategory {
    if (_cachedLowStockByCategory != null && !_analyticsDirty) {
      return _cachedLowStockByCategory!;
    }
    final map = <String, int>{};
    for (final entry in productsByCategory.entries) {
      map[entry.key] = entry.value.where((p) => p.isLowStock).length;
    }
    _cachedLowStockByCategory = map;
    return map;
  }

  Map<String, int> get outOfStockByCategory {
    if (_cachedOutOfStockByCategory != null && !_analyticsDirty) {
      return _cachedOutOfStockByCategory!;
    }
    final map = <String, int>{};
    for (final entry in productsByCategory.entries) {
      map[entry.key] = entry.value.where((p) => p.isOutOfStock).length;
    }
    _cachedOutOfStockByCategory = map;
    return map;
  }

  List<ProductModel> get topProductsByQuantity {
    if (_cachedTopProductsByQuantity != null && !_analyticsDirty) {
      return _cachedTopProductsByQuantity!;
    }
    final sorted = List<ProductModel>.from(_products)
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    _cachedTopProductsByQuantity = sorted.take(10).toList();
    return _cachedTopProductsByQuantity!;
  }

  Map<String, int> get locationBreakdown {
    if (_cachedLocationBreakdown != null && !_analyticsDirty) {
      return _cachedLocationBreakdown!;
    }
    final map = <String, int>{};
    for (final p in _products) {
      for (final entry in p.locationQuantities.entries) {
        if (entry.value > 0) map[entry.key] = (map[entry.key] ?? 0) + 1;
      }
    }
    _cachedLocationBreakdown = map;
    return map;
  }

  Map<String, int> get quantityByLocation {
    if (_cachedQuantityByLocation != null && !_analyticsDirty) {
      return _cachedQuantityByLocation!;
    }
    final map = <String, int>{};
    for (final p in _products) {
      for (final entry in p.locationQuantities.entries) {
        if (entry.value > 0) {
          map[entry.key] = (map[entry.key] ?? 0) + entry.value;
        }
      }
    }
    _cachedQuantityByLocation = map;
    return map;
  }

  double get inventoryHealthScore {
    if (_cachedInventoryHealthScore != null && !_analyticsDirty) {
      return _cachedInventoryHealthScore!;
    }
    if (_products.isEmpty) {
      _cachedInventoryHealthScore = 100.0;
      return 100.0;
    }
    final oos = outOfStockCount;
    final ls = _products.where((p) => p.isLowStock).length;
    final penalty = (oos * 10.0 + ls * 3.0) / _products.length;
    _cachedInventoryHealthScore = (100.0 - penalty * 10).clamp(0.0, 100.0);
    return _cachedInventoryHealthScore!;
  }

  String get healthLabel {
    final score = inventoryHealthScore;
    if (score >= 80) return 'Good';
    if (score >= 50) return 'Warning';
    return 'Critical';
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    _lowStockSubscription?.cancel();
    super.dispose();
  }
}
