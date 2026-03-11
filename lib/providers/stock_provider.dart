import 'dart:async';
import 'package:flutter/material.dart';
import '../models/stock_transaction_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';
import 'package:intl/intl.dart';

class StockProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<StockTransactionModel> _recentTransactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription? _transactionsSubscription;

  // Filter state
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _filterUserId = '';
  String _filterProductId = '';
  String _filterVendorId = '';
  String _sortBy = 'date_desc';

  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  String get filterUserId => _filterUserId;
  String get filterProductId => _filterProductId;
  String get filterVendorId => _filterVendorId;
  String get sortBy => _sortBy;

  List<StockTransactionModel> get allTransactions => _recentTransactions;

  // --- Analytics cache ---
  bool _filtersDirty = true;
  List<StockTransactionModel>? _cachedRecentTransactions;
  int? _cachedStockInTotal;
  int? _cachedStockOutTotal;
  int? _cachedDamageTotal;
  int? _cachedTransferTotal;
  Map<String, Map<TransactionType, int>>? _cachedTransactionsByDay;
  Map<TransactionType, int>? _cachedTransactionsByType;
  Map<TransactionType, int>? _cachedTransactionQuantityByType;
  List<MapEntry<String, int>>? _cachedTopProductsByTransactions;
  Map<String, int>? _cachedTransactionsByUser;
  double? _cachedAverageTransactionSize;
  List<MapEntry<String, int>>? _cachedTopProductsByQuantityMoved;
  String? _cachedPeakActivityDay;
  Map<String, Map<TransactionType, int>>? _cachedTransactionsByWeek;
  Map<String, Map<TransactionType, int>>? _cachedTransactionsByMonth;

  void _invalidateAnalytics() {
    _filtersDirty = true;
    _cachedRecentTransactions = null;
    _cachedStockInTotal = null;
    _cachedStockOutTotal = null;
    _cachedDamageTotal = null;
    _cachedTransferTotal = null;
    _cachedTransactionsByDay = null;
    _cachedTransactionsByType = null;
    _cachedTransactionQuantityByType = null;
    _cachedTopProductsByTransactions = null;
    _cachedTransactionsByUser = null;
    _cachedAverageTransactionSize = null;
    _cachedTopProductsByQuantityMoved = null;
    _cachedPeakActivityDay = null;
    _cachedTransactionsByWeek = null;
    _cachedTransactionsByMonth = null;
  }

  List<StockTransactionModel> get recentTransactions {
    if (_cachedRecentTransactions != null && !_filtersDirty) {
      return _cachedRecentTransactions!;
    }

    Iterable<StockTransactionModel> result = _recentTransactions;

    if (_filterStartDate != null) {
      final start = DateTime(
        _filterStartDate!.year,
        _filterStartDate!.month,
        _filterStartDate!.day,
      );
      result = result.where((t) => !t.date.isBefore(start));
    }
    if (_filterEndDate != null) {
      final endExclusive = DateTime(
        _filterEndDate!.year,
        _filterEndDate!.month,
        _filterEndDate!.day + 1,
      );
      result = result.where((t) => t.date.isBefore(endExclusive));
    }
    if (_filterUserId.isNotEmpty) {
      result = result.where((t) => t.userId == _filterUserId);
    }
    if (_filterProductId.isNotEmpty) {
      final lc = _filterProductId.toLowerCase();
      result = result.where(
        (t) =>
            t.productId == _filterProductId ||
            t.productName.toLowerCase().contains(lc),
      );
    }
    if (_filterVendorId.isNotEmpty) {
      result = result.where((t) => t.vendorId == _filterVendorId);
    }

    final filtered = result.toList();

    switch (_sortBy) {
      case 'date_asc':
        filtered.sort((a, b) => a.date.compareTo(b.date));
        break;
      case 'qty_desc':
        filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case 'qty_asc':
        filtered.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case 'date_desc':
      default:
        filtered.sort((a, b) => b.date.compareTo(a.date));
        break;
    }

    _cachedRecentTransactions = filtered;
    _filtersDirty = false;
    return filtered;
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // --- Analytics getters (cached) ---

  int get stockInTotal {
    if (_cachedStockInTotal != null && !_filtersDirty) {
      return _cachedStockInTotal!;
    }
    _cachedStockInTotal = recentTransactions
        .where((t) => t.type == TransactionType.stockIn)
        .fold<int>(0, (sum, t) => sum + t.quantity);
    return _cachedStockInTotal!;
  }

  int get stockOutTotal {
    if (_cachedStockOutTotal != null && !_filtersDirty) {
      return _cachedStockOutTotal!;
    }
    _cachedStockOutTotal = recentTransactions
        .where((t) => t.type == TransactionType.stockOut)
        .fold<int>(0, (sum, t) => sum + t.quantity);
    return _cachedStockOutTotal!;
  }

  int get damageTotal {
    if (_cachedDamageTotal != null && !_filtersDirty) {
      return _cachedDamageTotal!;
    }
    _cachedDamageTotal = recentTransactions
        .where((t) => t.type == TransactionType.damage)
        .fold<int>(0, (sum, t) => sum + t.quantity);
    return _cachedDamageTotal!;
  }

  int get transferTotal {
    if (_cachedTransferTotal != null && !_filtersDirty) {
      return _cachedTransferTotal!;
    }
    _cachedTransferTotal = recentTransactions
        .where((t) => t.type == TransactionType.transfer)
        .fold<int>(0, (sum, t) => sum + t.quantity);
    return _cachedTransferTotal!;
  }

  Map<String, Map<TransactionType, int>> get transactionsByDay {
    if (_cachedTransactionsByDay != null && !_filtersDirty) {
      return _cachedTransactionsByDay!;
    }
    final map = <String, Map<TransactionType, int>>{};
    final dateFormat = DateFormat('yyyy-MM-dd');
    for (final t in recentTransactions) {
      final dayKey = dateFormat.format(t.date);
      map.putIfAbsent(
        dayKey,
        () => {
          TransactionType.stockIn: 0,
          TransactionType.stockOut: 0,
          TransactionType.damage: 0,
          TransactionType.transfer: 0,
          TransactionType.adjustment: 0,
        },
      );
      map[dayKey]![t.type] = (map[dayKey]![t.type] ?? 0) + t.quantity;
    }
    final sortedEntries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    _cachedTransactionsByDay = Map.fromEntries(sortedEntries);
    return _cachedTransactionsByDay!;
  }

  Map<TransactionType, int> get transactionsByType {
    if (_cachedTransactionsByType != null && !_filtersDirty) {
      return _cachedTransactionsByType!;
    }
    final map = <TransactionType, int>{
      TransactionType.stockIn: 0,
      TransactionType.stockOut: 0,
      TransactionType.damage: 0,
      TransactionType.transfer: 0,
      TransactionType.adjustment: 0,
    };
    for (final t in recentTransactions) {
      map[t.type] = (map[t.type] ?? 0) + 1;
    }
    _cachedTransactionsByType = map;
    return map;
  }

  Map<TransactionType, int> get transactionQuantityByType {
    if (_cachedTransactionQuantityByType != null && !_filtersDirty) {
      return _cachedTransactionQuantityByType!;
    }
    final map = <TransactionType, int>{
      TransactionType.stockIn: 0,
      TransactionType.stockOut: 0,
      TransactionType.damage: 0,
      TransactionType.transfer: 0,
      TransactionType.adjustment: 0,
    };
    for (final t in recentTransactions) {
      map[t.type] = (map[t.type] ?? 0) + t.quantity;
    }
    _cachedTransactionQuantityByType = map;
    return map;
  }

  List<MapEntry<String, int>> get topProductsByTransactions {
    if (_cachedTopProductsByTransactions != null && !_filtersDirty) {
      return _cachedTopProductsByTransactions!;
    }
    final map = <String, int>{};
    for (final t in recentTransactions) {
      final name = t.productName.isNotEmpty ? t.productName : t.productId;
      map[name] = (map[name] ?? 0) + 1;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _cachedTopProductsByTransactions = sorted.take(10).toList();
    return _cachedTopProductsByTransactions!;
  }

  Map<String, int> get transactionsByUser {
    if (_cachedTransactionsByUser != null && !_filtersDirty) {
      return _cachedTransactionsByUser!;
    }
    final map = <String, int>{};
    for (final t in recentTransactions) {
      final name = t.userName.isNotEmpty ? t.userName : t.userId;
      if (name.isNotEmpty) {
        map[name] = (map[name] ?? 0) + 1;
      }
    }
    _cachedTransactionsByUser = map;
    return map;
  }

  List<MapEntry<String, String>> get uniqueUsers {
    final map = <String, String>{};
    for (final t in _recentTransactions) {
      if (t.userId.isNotEmpty) {
        map[t.userId] = t.userName.isNotEmpty ? t.userName : t.userId;
      }
    }
    return map.entries.toList();
  }

  double get averageTransactionSize {
    if (_cachedAverageTransactionSize != null && !_filtersDirty) {
      return _cachedAverageTransactionSize!;
    }
    final txns = recentTransactions;
    if (txns.isEmpty) {
      _cachedAverageTransactionSize = 0;
      return 0;
    }
    final total = txns.fold(0, (sum, t) => sum + t.quantity);
    _cachedAverageTransactionSize = total / txns.length;
    return _cachedAverageTransactionSize!;
  }

  int get netStockChange => stockInTotal - stockOutTotal - damageTotal;

  List<MapEntry<String, int>> get topProductsByQuantityMoved {
    if (_cachedTopProductsByQuantityMoved != null && !_filtersDirty) {
      return _cachedTopProductsByQuantityMoved!;
    }
    final map = <String, int>{};
    for (final t in recentTransactions) {
      final name = t.productName.isNotEmpty ? t.productName : t.productId;
      map[name] = (map[name] ?? 0) + t.quantity;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _cachedTopProductsByQuantityMoved = sorted.take(10).toList();
    return _cachedTopProductsByQuantityMoved!;
  }

  List<MapEntry<String, int>> get topProductsBySales {
    final map = <String, int>{};
    for (final t in recentTransactions) {
      if (t.type != TransactionType.stockOut) continue;
      final name = t.productName.isNotEmpty ? t.productName : t.productId;
      map[name] = (map[name] ?? 0) + t.quantity;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).toList();
  }

  List<MapEntry<String, int>> get topProductsByBreakage {
    final map = <String, int>{};
    for (final t in recentTransactions) {
      if (t.type != TransactionType.damage) continue;
      final name = t.productName.isNotEmpty ? t.productName : t.productId;
      map[name] = (map[name] ?? 0) + t.quantity;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).toList();
  }

  String get peakActivityDay {
    if (_cachedPeakActivityDay != null && !_filtersDirty) {
      return _cachedPeakActivityDay!;
    }
    final map = <int, int>{};
    for (final t in recentTransactions) {
      final weekday = t.date.weekday;
      map[weekday] = (map[weekday] ?? 0) + 1;
    }
    if (map.isEmpty) {
      _cachedPeakActivityDay = 'N/A';
      return 'N/A';
    }
    final peakDay = map.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    const dayNames = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    _cachedPeakActivityDay = dayNames[peakDay] ?? 'N/A';
    return _cachedPeakActivityDay!;
  }

  Map<String, Map<TransactionType, int>> get transactionsByWeek {
    if (_cachedTransactionsByWeek != null && !_filtersDirty) {
      return _cachedTransactionsByWeek!;
    }
    final map = <String, Map<TransactionType, int>>{};
    for (final t in recentTransactions) {
      final weekNum = _isoWeekNumber(t.date);
      final weekKey = '${t.date.year}-W${weekNum.toString().padLeft(2, '0')}';
      map.putIfAbsent(
        weekKey,
        () => {
          TransactionType.stockIn: 0,
          TransactionType.stockOut: 0,
          TransactionType.damage: 0,
          TransactionType.transfer: 0,
          TransactionType.adjustment: 0,
        },
      );
      map[weekKey]![t.type] = (map[weekKey]![t.type] ?? 0) + t.quantity;
    }
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    _cachedTransactionsByWeek = Map.fromEntries(sorted);
    return _cachedTransactionsByWeek!;
  }

  Map<String, Map<TransactionType, int>> get transactionsByMonth {
    if (_cachedTransactionsByMonth != null && !_filtersDirty) {
      return _cachedTransactionsByMonth!;
    }
    final map = <String, Map<TransactionType, int>>{};
    for (final t in recentTransactions) {
      final monthKey = DateFormat('yyyy-MM').format(t.date);
      map.putIfAbsent(
        monthKey,
        () => {
          TransactionType.stockIn: 0,
          TransactionType.stockOut: 0,
          TransactionType.damage: 0,
          TransactionType.transfer: 0,
          TransactionType.adjustment: 0,
        },
      );
      map[monthKey]![t.type] = (map[monthKey]![t.type] ?? 0) + t.quantity;
    }
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    _cachedTransactionsByMonth = Map.fromEntries(sorted);
    return _cachedTransactionsByMonth!;
  }

  Map<TransactionType, int> get todayTransactions {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final map = <TransactionType, int>{
      TransactionType.stockIn: 0,
      TransactionType.stockOut: 0,
      TransactionType.damage: 0,
      TransactionType.transfer: 0,
      TransactionType.adjustment: 0,
    };
    for (final t in _recentTransactions) {
      if (!t.date.isBefore(today)) {
        map[t.type] = (map[t.type] ?? 0) + t.quantity;
      }
    }
    return map;
  }

  bool get hasTodayActivity {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _recentTransactions.any((t) => !t.date.isBefore(today));
  }

  int _isoWeekNumber(DateTime date) {
    // ISO 8601 week: the week containing the year's first Thursday.
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(jan1).inDays) / 7).floor() + 1;
  }

  // --- Initialization ---

  Timer? _loadingTimeout;

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _transactionsSubscription?.cancel();
    _loadingTimeout?.cancel();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Safety timeout: if the stream hasn't emitted after 15 seconds, stop
    // the loading spinner so the UI is usable with empty data.
    _loadingTimeout = Timer(const Duration(seconds: 15), () {
      if (_isLoading) {
        _isLoading = false;
        _errorMessage ??= 'Transactions are still loading. Pull to refresh.';
        notifyListeners();
      }
    });

    _transactionsSubscription = _databaseService
        .getAllTransactions(limit: 2000)
        .listen(
          (transactions) {
            _loadingTimeout?.cancel();
            _recentTransactions = transactions;
            _invalidateAnalytics();
            _isLoading = false;
            _errorMessage = null;
            notifyListeners();
          },
          onError: (error) {
            _loadingTimeout?.cancel();
            _errorMessage = friendlyError(
              error,
              fallback: 'Could not load transactions.',
            );
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  // --- Transaction updates ---

  Future<bool> updateTransactionLocation(
    String transactionId,
    String newLocation,
  ) async {
    _errorMessage = null;
    try {
      await _databaseService.updateTransactionLocation(
        transactionId,
        newLocation,
      );
      final idx = _recentTransactions.indexWhere((t) => t.id == transactionId);
      if (idx >= 0) {
        final old = _recentTransactions[idx];
        _recentTransactions[idx] = StockTransactionModel(
          id: old.id,
          productId: old.productId,
          productName: old.productName,
          type: old.type,
          quantity: old.quantity,
          location: newLocation,
          reason: old.reason,
          userId: old.userId,
          userName: old.userName,
          date: old.date,
          vendorId: old.vendorId,
          vendorName: old.vendorName,
        );
        _invalidateAnalytics();
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not update location.',
      );
      notifyListeners();
      return false;
    }
  }

  // --- Stock operations ---

  Future<bool> addStock({
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
    if (_isLoading) return false;
    if (quantity <= 0) {
      _errorMessage = 'Quantity must be greater than zero.';
      notifyListeners();
      return false;
    }
    if (location.trim().isEmpty) {
      _errorMessage = 'Location is required.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _databaseService.addStock(
        productId: productId,
        productName: productName,
        quantity: quantity,
        location: location,
        userId: userId,
        userName: userName,
        reason: reason,
        vendorId: vendorId,
        vendorName: vendorName,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Stock operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeStock({
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
    if (_isLoading) return false;
    if (quantity <= 0) {
      _errorMessage = 'Quantity must be greater than zero.';
      notifyListeners();
      return false;
    }
    if (location.trim().isEmpty) {
      _errorMessage = 'Location is required.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _databaseService.removeStock(
        productId: productId,
        productName: productName,
        quantity: quantity,
        location: location,
        userId: userId,
        userName: userName,
        reason: reason,
        vendorId: vendorId,
        vendorName: vendorName,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Stock operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> recordDamage({
    required String productId,
    required String productName,
    required int quantity,
    required String location,
    required String userId,
    required String userName,
    required String reason,
  }) async {
    if (_isLoading) return false;
    if (quantity <= 0) {
      _errorMessage = 'Quantity must be greater than zero.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _databaseService.recordDamage(
        productId: productId,
        productName: productName,
        quantity: quantity,
        location: location,
        userId: userId,
        userName: userName,
        reason: reason,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Stock operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> transferStock({
    required String productId,
    required String productName,
    required int quantity,
    required String fromLocation,
    required String toLocation,
    required String userId,
    required String userName,
    String reason = '',
  }) async {
    if (_isLoading) return false;
    if (quantity <= 0) {
      _errorMessage = 'Quantity must be greater than zero.';
      notifyListeners();
      return false;
    }
    if (fromLocation.trim() == toLocation.trim()) {
      _errorMessage = 'Source and destination locations must differ.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _databaseService.transferStock(
        productId: productId,
        productName: productName,
        quantity: quantity,
        fromLocation: fromLocation,
        toLocation: toLocation,
        userId: userId,
        userName: userName,
        reason: reason,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Stock operation failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> recordAdjustment({
    required String productId,
    required String productName,
    required int adjustmentDelta,
    required String location,
    required String userId,
    required String userName,
    String reason = '',
  }) async {
    if (_isLoading) return false;
    if (adjustmentDelta == 0) {
      _errorMessage = 'No adjustment needed — count matches current stock.';
      notifyListeners();
      return false;
    }
    if (location.trim().isEmpty) {
      _errorMessage = 'Location is required.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _databaseService.recordAdjustment(
        productId: productId,
        productName: productName,
        adjustmentDelta: adjustmentDelta,
        location: location,
        userId: userId,
        userName: userName,
        reason: reason,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Adjustment failed.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Stream<List<StockTransactionModel>> getProductTransactions(String productId) {
    return _databaseService.getProductTransactions(productId);
  }

  Stream<List<StockTransactionModel>> getTransactionsByType(
    TransactionType type,
  ) {
    return _databaseService.getTransactionsByType(type);
  }

  // --- Filter operations ---

  void setDateRangeFilter(DateTime? start, DateTime? end) {
    _filterStartDate = start;
    _filterEndDate = end;
    _invalidateAnalytics();
    notifyListeners();
  }

  void setUserFilter(String? userId) {
    _filterUserId = userId ?? '';
    _invalidateAnalytics();
    notifyListeners();
  }

  void setProductFilter(String? productIdOrName) {
    _filterProductId = productIdOrName ?? '';
    _invalidateAnalytics();
    notifyListeners();
  }

  void setSortBy(String sort) {
    _sortBy = sort;
    _invalidateAnalytics();
    notifyListeners();
  }

  void setVendorFilter(String? vendorId) {
    _filterVendorId = vendorId ?? '';
    _invalidateAnalytics();
    notifyListeners();
  }

  Map<String, int> get transactionsByVendor {
    final map = <String, int>{};
    for (final t in recentTransactions) {
      if (t.vendorId.isNotEmpty) {
        final name = t.vendorName.isNotEmpty ? t.vendorName : t.vendorId;
        map[name] = (map[name] ?? 0) + 1;
      }
    }
    return map;
  }

  void clearFilters() {
    _filterStartDate = null;
    _filterEndDate = null;
    _filterUserId = '';
    _filterProductId = '';
    _filterVendorId = '';
    _sortBy = 'date_desc';
    _invalidateAnalytics();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    _transactionsSubscription?.cancel();
    super.dispose();
  }
}
