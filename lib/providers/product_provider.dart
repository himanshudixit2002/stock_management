import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/product_model.dart';
import '../services/database_service.dart';
import '../services/stats_cache.dart';
import '../utils/error_helpers.dart';
import '../utils/product_search.dart';

class ProductProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final StatsCache _statsCache = StatsCache();

  /// Shared in-flight analytics load so [search] can await the same future as [initialize].
  Future<void>? _analyticsInFlight;

  /// Last-known counters seeded from [StatsCache] so Home can show real numbers
  /// the instant the shell paints — before the first Firestore page returns.
  /// Cleared as soon as authoritative data (even an empty result) arrives.
  int? _seedTotal;
  int? _seedLowStock;
  int? _seedOutOfStock;

  bool get _hasLiveProducts => _analyticsSource.isNotEmpty;

  /// True when Home has *something* real to show (live data or a cached seed),
  /// so stat tiles can render numbers instead of skeletons.
  bool get hasSeededStats =>
      _hasLiveProducts ||
      _seedTotal != null ||
      _seedLowStock != null ||
      _seedOutOfStock != null;

  String get companyId => _databaseService.companyId;

  List<ProductModel> _products = [];
  List<ProductModel> _filteredProducts = [];
  List<ProductModel> _lowStockProducts = [];
  // Starts true so the Home shell shows skeletons (not a "0" flash) on the
  // fast web path, before [initialize] has run. Cleared after the first page.
  bool _isLoading = true;
  String? _errorMessage;
  String? _warningMessage;
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

  DocumentSnapshot? _lastDoc;
  bool _hasMoreProducts = true;
  bool _isLoadingMore = false;

  List<ProductModel>? _searchResults;
  List<ProductModel>? _searchResultsRaw;
  bool _isSearching = false;
  int _searchGeneration = 0;

  // --- Analytics (full product set for Dashboard/Reports) ---
  List<ProductModel>? _analyticsProducts;
  bool _isLoadingAnalytics = false;
  DateTime? _analyticsFetchedAt;
  static const int _analyticsCacheMinutes = 2;

  List<ProductModel> get _analyticsSource => _analyticsProducts ?? _products;
  bool get isLoadingAnalytics => _isLoadingAnalytics;
  bool get isAnalyticsLoaded => _analyticsProducts != null;
  DateTime? get analyticsFetchedAt => _analyticsFetchedAt;

  /// Full product set for Dashboard/Reports. Use this for analytics displays.
  List<ProductModel> get analyticsProducts => _analyticsSource;

  // --- Analytics cache ---
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

  List<ProductModel> get products => _searchResults ?? _filteredProducts;
  bool get isSearching => _isSearching;
  bool get isInSearchMode => _searchResults != null;
  List<ProductModel> get allProducts => _products;
  List<ProductModel> get lowStockProducts {
    if (_analyticsProducts != null) {
      return _analyticsProducts!
          .where((p) => p.quantity <= p.lowStockThreshold)
          .toList();
    }
    return _lowStockProducts;
  }

  bool get isLoading => _isLoading;
  bool get hasMoreProducts => _hasMoreProducts;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _warningMessage;

  void setWarning(String message) {
    _warningMessage = message;
    notifyListeners();
  }

  void clearWarning() {
    _warningMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

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
    if (_cachedAvailableLocations != null) {
      return _cachedAvailableLocations!;
    }
    final source = _analyticsProducts ?? _products;
    final locations = <String>{};
    for (final p in source) {
      for (final entry in p.locationQuantities.entries) {
        if (entry.value > 0) locations.add(entry.key);
      }
    }
    _cachedAvailableLocations = locations.toList()..sort();
    return _cachedAvailableLocations!;
  }

  /// Companies from products when Settings are empty. Includes search results.
  List<String> get availableCompaniesFromProducts {
    final source = _analyticsProducts ?? _products;
    final set = <String>{};
    for (final p in source) {
      if (p.company.isNotEmpty) set.add(p.company);
    }
    if (_searchResultsRaw != null) {
      for (final p in _searchResultsRaw!) {
        if (p.company.isNotEmpty) set.add(p.company);
      }
    }
    return set.toList()..sort();
  }

  /// Sizes from products when Settings are empty. Includes search results.
  List<String> get availableSizesFromProducts {
    final source = _analyticsProducts ?? _products;
    final set = <String>{};
    for (final p in source) {
      if (p.size.isNotEmpty) set.add(p.size);
    }
    if (_searchResultsRaw != null) {
      for (final p in _searchResultsRaw!) {
        if (p.size.isNotEmpty) set.add(p.size);
      }
    }
    return set.toList()..sort();
  }

  /// Locations from products when Settings are empty. Includes search results.
  List<String> get availableLocationsFromProducts {
    final source = _analyticsProducts ?? _products;
    final locations = <String>{};
    for (final p in source) {
      for (final entry in p.locationQuantities.entries) {
        if (entry.value > 0) locations.add(entry.key);
      }
    }
    if (_searchResultsRaw != null) {
      for (final p in _searchResultsRaw!) {
        for (final entry in p.locationQuantities.entries) {
          if (entry.value > 0) locations.add(entry.key);
        }
      }
    }
    return locations.toSet().toList()..sort();
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

  void reset() {
    _products = [];
    _filteredProducts = [];
    _lowStockProducts = [];
    _isLoading = false;
    _errorMessage = null;
    _searchQuery = '';
    _selectedCategoryId = null;
    _selectedLocation = null;
    _selectedCompany = null;
    _selectedSize = null;
    _selectedStockStatus = null;
    _selectedVendorId = null;
    _sortBy = 'name';
    _filterStartDate = null;
    _filterEndDate = null;
    _lastDoc = null;
    _hasMoreProducts = true;
    _isLoadingMore = false;
    _searchResults = null;
    _searchResultsRaw = null;
    _isSearching = false;
    _searchGeneration = 0;
    _analyticsProducts = null;
    _isLoadingAnalytics = false;
    _analyticsFetchedAt = null;
    _seedTotal = null;
    _seedLowStock = null;
    _seedOutOfStock = null;
    _invalidateAnalytics();
    notifyListeners();
  }

  /// Loads the first product page quickly.
  ///
  /// [loadFullCatalog] controls whether the full-catalog analytics fetch is
  /// kicked off here. During staggered startup the shell schedules analytics in
  /// a later background phase (so Home is never blocked on the full catalog),
  /// so it passes `false`. Manual refreshes pass `true` to refresh everything.
  Future<void> initialize({
    required String companyId,
    bool loadFullCatalog = true,
  }) async {
    _databaseService.setCompanyId(companyId);

    _errorMessage = null;
    _products = [];
    _analyticsProducts = null;
    _analyticsFetchedAt = null;
    _lastDoc = null;
    _hasMoreProducts = true;
    _isLoading = true;

    // Seed last-known counters so the Home shell shows real numbers before the
    // first page returns. Reconciled (and cleared) the moment data arrives.
    final cached = await _statsCache.readProductStats(companyId);
    if (cached != null) {
      _seedTotal = cached.total;
      _seedLowStock = cached.lowStock;
      _seedOutOfStock = cached.outOfStock;
    }
    notifyListeners();

    try {
      // Load first page quickly for immediate UI rendering.
      final result = await _databaseService
          .getProductsPage(limit: DatabaseService.productsPageSize)
          .timeout(const Duration(seconds: 15));
      _products = result.products;
      _lastDoc = result.lastDoc;
      _hasMoreProducts = result.hasMore;
      _lowStockProducts = _products
          .where((p) => p.quantity <= p.lowStockThreshold)
          .toList();
      // Authoritative page data is in — stop using the seed fallback.
      _seedTotal = null;
      _seedLowStock = null;
      _seedOutOfStock = null;
      _invalidateAnalytics();
      _applyFilters();
    } catch (error) {
      _errorMessage = friendlyError(
        error,
        fallback: 'Could not load products.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Full product set for accurate analytics. Non-blocking — dashboard/reports
    // use _analyticsSource which falls back to the first page until it arrives.
    if (loadFullCatalog) loadAnalytics();
  }

  Future<void> loadMoreProducts() async {
    // Skip if full dataset already loaded via loadAnalytics().
    if (_analyticsProducts != null) return;
    if (!_hasMoreProducts || _isLoadingMore || _lastDoc == null) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _databaseService.getProductsPage(
        limit: DatabaseService.productsPageSize,
        startAfter: _lastDoc,
      );
      // If analytics loaded while we were fetching, skip merging to avoid dupes.
      if (_analyticsProducts != null) return;
      _products = [..._products, ...result.products];
      _lowStockProducts = _products
          .where((p) => p.quantity <= p.lowStockThreshold)
          .toList();
      _lastDoc = result.lastDoc;
      _hasMoreProducts = result.hasMore;
      _invalidateAnalytics();
      _applyFilters();
    } catch (error) {
      _errorMessage = friendlyError(
        error,
        fallback: 'Could not load more products.',
      );
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refreshProducts() async {
    _searchQuery = '';
    _searchResults = null;
    _searchResultsRaw = null;
    _lastDoc = null;
    _hasMoreProducts = true;
    _analyticsProducts = null;
    _analyticsFetchedAt = null;
    await initialize(companyId: _databaseService.companyId);
  }

  /// Re-fetches only the given products and patches them in place so stock/hold
  /// changes reflect immediately — without resetting the whole list (which
  /// flickers, loses pagination/scroll, and can briefly drop a held product
  /// that lives beyond the first page). Call this after hold / unhold /
  /// dispatch operations so the products page updates instantly.
  Future<void> refreshProductsByIds(Iterable<String> ids) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet();
    if (unique.isEmpty) return;

    final fetched = <ProductModel>[];
    for (final id in unique) {
      try {
        final product = await _databaseService.getProduct(id);
        if (product != null) fetched.add(product);
      } catch (_) {
        // Ignore individual fetch failures; patch whatever we could refresh.
      }
    }
    if (fetched.isEmpty) return;

    final byId = {for (final p in fetched) p.id: p};
    List<ProductModel> patch(List<ProductModel> list) =>
        list.map((p) => byId[p.id] ?? p).toList();

    _products = patch(_products);
    if (_analyticsProducts != null) {
      _analyticsProducts = patch(_analyticsProducts!);
    }
    if (_searchResultsRaw != null) {
      _searchResultsRaw = patch(_searchResultsRaw!);
    }
    if (_searchResults != null) {
      _searchResults = patch(_searchResults!);
    }
    _lowStockProducts =
        _products.where((p) => p.quantity <= p.lowStockThreshold).toList();
    _invalidateAnalytics();
    _applyFilters();
    notifyListeners();
  }

  /// Clears analytics cache so next loadAnalytics fetches fresh data.
  /// Call after stock operations (in/out/transfer/damage) to keep counts accurate.
  void invalidateAnalytics() {
    _analyticsProducts = null;
    _analyticsFetchedAt = null;
    _invalidateAnalytics();
    notifyListeners();
  }

  /// Fetches the full product set for accurate analytics/reports.
  /// Cached for 2 minutes to avoid redundant fetches.
  /// Called automatically by initialize() and manually after stock operations.
  Future<void> loadAnalytics() async {
    // On the fast startup path the Home shell can mount (and request analytics)
    // before this provider has been scoped to a company. Bail out quietly —
    // the staggered init's background phase calls this again once bound.
    if (_databaseService.companyId.isEmpty) return;
    final now = DateTime.now();
    if (_analyticsProducts != null &&
        _analyticsFetchedAt != null &&
        now.difference(_analyticsFetchedAt!).inMinutes <
            _analyticsCacheMinutes) {
      return;
    }

    _analyticsInFlight ??= _loadAnalyticsBody().whenComplete(() {
      _analyticsInFlight = null;
    });
    await _analyticsInFlight!;
  }

  Future<void> _loadAnalyticsBody() async {
    final loadForCompany = _databaseService.companyId;
    _isLoadingAnalytics = true;
    notifyListeners();
    try {
      final products = await _databaseService.getAllProductsOnce().timeout(
        const Duration(seconds: 15),
      );
      if (_databaseService.companyId != loadForCompany) return;
      _products = products;
      _analyticsProducts = products;
      _analyticsFetchedAt = DateTime.now();
      _lowStockProducts = products
          .where((p) => p.quantity <= p.lowStockThreshold)
          .toList();
      _lastDoc = null;
      _hasMoreProducts = false;
      _seedTotal = null;
      _seedLowStock = null;
      _seedOutOfStock = null;
      _invalidateAnalytics();
      // Persist authoritative counters so the next cold start can paint them
      // before Firestore returns. Fire-and-forget; never blocks the UI.
      unawaited(
        _statsCache.saveProductStats(
          loadForCompany,
          total: products.length,
          lowStock: products.where((p) => p.isLowStock).length,
          outOfStock: products.where((p) => p.isOutOfStock).length,
        ),
      );
    } catch (e) {
      if (_databaseService.companyId != loadForCompany) return;
      // Fall back to whatever is already loaded so dashboard isn't empty.
      // Always set _analyticsProducts so isAnalyticsLoaded becomes true and
      // the UI stops showing loading spinners.
      _analyticsProducts = List.from(_products);
      _invalidateAnalytics();
    } finally {
      _isLoadingAnalytics = false;
      if (_databaseService.companyId == loadForCompany) {
        _applyFilters();
      }
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _searchResults = null;
    _searchResultsRaw = null;
    _searchGeneration++;
    final generation = _searchGeneration;
    _applyFilters();
    if (_searchQuery.length >= 2) {
      _isSearching = true;
      notifyListeners();
      try {
        _errorMessage = null;
        await loadAnalytics();
        if (_searchGeneration != generation) return;

        final catalog = analyticsProducts;
        final ranked = searchProductsRanked(catalog, _searchQuery, limit: 150);
        if (_searchGeneration != generation) return;

        final results = ranked.map((r) => r.product).toList();
        _searchResultsRaw = results;
        _searchResults = _applyNonSearchFilters(results);
        _applySortToSearchResultsIfNeeded();
      } catch (e) {
        if (_searchGeneration != generation) return;
        _searchResultsRaw = [];
        _searchResults = [];
        _errorMessage = friendlyError(e, fallback: 'Search failed.');
      } finally {
        if (_searchGeneration == generation) {
          _isSearching = false;
          notifyListeners();
        }
      }
    } else {
      notifyListeners();
    }
  }

  List<ProductModel> _applyNonSearchFilters(List<ProductModel> input) {
    Iterable<ProductModel> result = input;
    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId);
    }
    if (_selectedCompany != null) {
      final companyLower = _selectedCompany!.toLowerCase();
      result = result.where((p) => p.company.toLowerCase() == companyLower);
    }
    if (_selectedSize != null) {
      final sizeLower = _selectedSize!.toLowerCase();
      result = result.where((p) => p.size.toLowerCase() == sizeLower);
    }
    if (_selectedLocation != null) {
      final locLower = _selectedLocation!.toLowerCase();
      result = result.where(
        (p) => p.locationQuantities.entries.any(
          (e) => e.key.toLowerCase() == locLower && e.value > 0,
        ),
      );
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
      result = result.where(
        (p) =>
            p.preferredVendorId == _selectedVendorId ||
            p.lastVendorId == _selectedVendorId,
      );
    }
    if (_filterStartDate != null) {
      final start = DateTime(
        _filterStartDate!.year,
        _filterStartDate!.month,
        _filterStartDate!.day,
      );
      result = result.where((p) => !p.createdAt.isBefore(start));
    }
    if (_filterEndDate != null) {
      final endExclusive = DateTime(
        _filterEndDate!.year,
        _filterEndDate!.month,
        _filterEndDate!.day + 1,
      );
      result = result.where((p) => p.createdAt.isBefore(endExclusive));
    }
    return result.toList();
  }

  void _sortProductList(List<ProductModel> list) {
    switch (_sortBy) {
      case 'name':
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'quantity':
        list.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case 'quantity_desc':
        list.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
    }
  }

  /// Search results are ranked by relevance when sort is [name]; other sorts reorder hits.
  void _applySortToSearchResultsIfNeeded() {
    if (_searchResults == null || _searchResults!.isEmpty) return;
    if (_sortBy != 'name') {
      _sortProductList(_searchResults!);
    }
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
    for (final p in _analyticsSource) {
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
    _searchResults = null;
    _searchResultsRaw = null;
    _selectedCategoryId = null;
    _selectedCompany = null;
    _selectedSize = null;
    _selectedLocation = null;
    _selectedStockStatus = null;
    _selectedVendorId = null;
    _sortBy = 'name';
    _filterStartDate = null;
    _filterEndDate = null;
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    Iterable<ProductModel> result = _analyticsSource;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where(
        (p) =>
            p.name.toLowerCase().contains(query) ||
            p.categoryName.toLowerCase().contains(query) ||
            p.company.toLowerCase().contains(query) ||
            p.size.toLowerCase().contains(query) ||
            p.locations.any((l) => l.toLowerCase().contains(query)) ||
            p.description.toLowerCase().contains(query),
      );
    }

    if (_selectedCategoryId != null) {
      result = result.where((p) => p.categoryId == _selectedCategoryId);
    }

    if (_selectedCompany != null) {
      final companyLower = _selectedCompany!.toLowerCase();
      result = result.where((p) => p.company.toLowerCase() == companyLower);
    }

    if (_selectedSize != null) {
      final sizeLower = _selectedSize!.toLowerCase();
      result = result.where((p) => p.size.toLowerCase() == sizeLower);
    }

    if (_selectedLocation != null) {
      final locLower = _selectedLocation!.toLowerCase();
      result = result.where(
        (p) => p.locationQuantities.entries.any(
          (e) => e.key.toLowerCase() == locLower && e.value > 0,
        ),
      );
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
      result = result.where(
        (p) =>
            p.preferredVendorId == _selectedVendorId ||
            p.lastVendorId == _selectedVendorId,
      );
    }

    if (_filterStartDate != null) {
      final start = DateTime(
        _filterStartDate!.year,
        _filterStartDate!.month,
        _filterStartDate!.day,
      );
      result = result.where((p) => !p.createdAt.isBefore(start));
    }
    if (_filterEndDate != null) {
      final endExclusive = DateTime(
        _filterEndDate!.year,
        _filterEndDate!.month,
        _filterEndDate!.day + 1,
      );
      result = result.where((p) => p.createdAt.isBefore(endExclusive));
    }

    final filtered = result.toList();

    // When server search results exist, apply non-search filters to them
    // instead of replacing with local data.
    if (_searchResultsRaw != null && _searchQuery.length >= 2) {
      _searchResults = _applyNonSearchFilters(_searchResultsRaw!);
      _applySortToSearchResultsIfNeeded();
    }

    _sortProductList(filtered);
    _filteredProducts = filtered;
  }

  Future<bool> addProduct(ProductModel product) async {
    try {
      _errorMessage = null;
      await _databaseService.addProduct(product);
      await refreshProducts();
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
      await refreshProducts();
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
      await refreshProducts();
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
    _errorMessage = null;
    try {
      final productsWithAudit = products
          .map((p) => p.copyWith(createdBy: userId, createdByName: userName))
          .toList();
      final count = await _databaseService.bulkAddProducts(productsWithAudit);
      // Reload so newly imported products (and updated counts) appear without a
      // manual refresh — matching the add/edit/delete and bulkUpdate paths.
      await refreshProducts();
      return count;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to import products.');
      notifyListeners();
      rethrow;
    }
  }

  Future<int> bulkUpdateProducts(
    List<ProductModel> products, {
    required String userId,
    required String userName,
  }) async {
    _errorMessage = null;
    try {
      final now = DateTime.now();
      final productsWithAudit = products
          .map(
            (p) => p.copyWith(
              updatedBy: userId,
              updatedByName: userName,
              updatedAt: now,
            ),
          )
          .toList();
      final count = await _databaseService.bulkUpdateProducts(
        productsWithAudit,
      );
      await refreshProducts();
      return count;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update products.');
      notifyListeners();
      rethrow;
    }
  }

  // --- Dashboard stats (use _analyticsSource for correct totals) ---
  // While no live products are loaded yet, fall back to the cached seed so the
  // Home shell shows real numbers immediately, then reconciles when data lands.
  int get totalProducts =>
      _hasLiveProducts ? _analyticsSource.length : (_seedTotal ?? 0);

  int get lowStockCount => _hasLiveProducts
      ? _analyticsSource.where((p) => p.isLowStock).length
      : (_seedLowStock ?? 0);

  int get outOfStockCount {
    if (!_hasLiveProducts) return _seedOutOfStock ?? 0;
    if (_cachedOutOfStockCount != null) {
      return _cachedOutOfStockCount!;
    }
    _cachedOutOfStockCount = _analyticsSource
        .where((p) => p.isOutOfStock)
        .length;
    return _cachedOutOfStockCount!;
  }

  // --- Category analytics (cached) ---

  Map<String, List<ProductModel>> get productsByCategory {
    if (_cachedProductsByCategory != null) {
      return _cachedProductsByCategory!;
    }
    final map = <String, List<ProductModel>>{};
    for (final p in _analyticsSource) {
      final cat = p.categoryName.isNotEmpty ? p.categoryName : 'Uncategorized';
      map.putIfAbsent(cat, () => []).add(p);
    }
    _cachedProductsByCategory = map;
    return map;
  }

  Map<String, int> get productCountByCategory {
    if (_cachedProductCountByCategory != null) {
      return _cachedProductCountByCategory!;
    }
    _cachedProductCountByCategory = productsByCategory.map(
      (key, value) => MapEntry(key, value.length),
    );
    return _cachedProductCountByCategory!;
  }

  Map<String, int> get lowStockByCategory {
    if (_cachedLowStockByCategory != null) {
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
    if (_cachedOutOfStockByCategory != null) {
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
    if (_cachedTopProductsByQuantity != null) {
      return _cachedTopProductsByQuantity!;
    }
    final sorted = List<ProductModel>.from(_analyticsSource)
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    _cachedTopProductsByQuantity = sorted.take(10).toList();
    return _cachedTopProductsByQuantity!;
  }

  Map<String, int> get locationBreakdown {
    if (_cachedLocationBreakdown != null) {
      return _cachedLocationBreakdown!;
    }
    final map = <String, int>{};
    for (final p in _analyticsSource) {
      for (final entry in p.locationQuantities.entries) {
        if (entry.value > 0) map[entry.key] = (map[entry.key] ?? 0) + 1;
      }
    }
    _cachedLocationBreakdown = map;
    return map;
  }

  Map<String, int> get quantityByLocation {
    if (_cachedQuantityByLocation != null) {
      return _cachedQuantityByLocation!;
    }
    final map = <String, int>{};
    for (final p in _analyticsSource) {
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
    if (_cachedInventoryHealthScore != null) {
      return _cachedInventoryHealthScore!;
    }
    if (_analyticsSource.isEmpty) {
      _cachedInventoryHealthScore = 100.0;
      return 100.0;
    }
    final oos = outOfStockCount;
    final ls = _analyticsSource.where((p) => p.isLowStock).length;
    final penalty = (oos * 10.0 + ls * 3.0) / _analyticsSource.length;
    _cachedInventoryHealthScore = (100.0 - penalty * 10).clamp(0.0, 100.0);
    return _cachedInventoryHealthScore!;
  }

  String get healthLabel {
    final score = inventoryHealthScore;
    if (score >= 80) return 'Good';
    if (score >= 50) return 'Warning';
    return 'Critical';
  }
}
