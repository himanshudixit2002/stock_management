import 'dart:async';
import 'package:flutter/material.dart';
import '../models/stock_transaction_model.dart';
import '../models/stock_hold_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';
import 'package:intl/intl.dart';

class StockProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  /// Hard cap on the transactions stream. When the result reaches this many
  /// rows the data is (likely) truncated and totals/charts only reflect the
  /// most recent window — the UI surfaces a warning so figures aren't silently
  /// undercounted.
  static const int transactionFetchLimit = 2000;

  List<StockTransactionModel> _recentTransactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  /// True when the transactions stream hit [transactionFetchLimit], meaning
  /// older transactions are not loaded and reports show a partial window.
  bool get transactionsTruncated =>
      _recentTransactions.length >= transactionFetchLimit;

  StreamSubscription? _transactionsSubscription;
  StreamSubscription? _holdsSubscription;
  List<StockHoldModel> _stockHolds = [];

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
  List<StockHoldModel> get stockHolds => _stockHolds;
  List<StockHoldModel> get activeHolds => _stockHolds
      .where(
        (h) =>
            h.status == StockHoldStatus.active ||
            h.status == StockHoldStatus.partiallyConsumed,
      )
      .toList();

  /// Active holds grouped by challan number, preserving creation order.
  /// Holds without a challan are grouped under an empty-string key.
  Map<String, List<StockHoldModel>> get activeHoldsByChallan {
    final map = <String, List<StockHoldModel>>{};
    for (final hold in activeHolds) {
      if (hold.remainingQuantity <= 0) continue;
      map.putIfAbsent(hold.challanNumber.trim(), () => []).add(hold);
    }
    return map;
  }

  /// Distinct challan numbers that still have active held stock.
  List<String> get activeChallans => activeHoldsByChallan.keys
      .where((c) => c.isNotEmpty)
      .toList()
    ..sort();

  /// Active holds (with remaining qty) for a given product.
  List<StockHoldModel> activeHoldsForProduct(String productId) => activeHolds
      .where((h) => h.productId == productId && h.remainingQuantity > 0)
      .toList();

  /// Active holds belonging to a specific challan number.
  List<StockHoldModel> activeHoldsForChallan(String challanNumber) {
    final key = challanNumber.trim();
    return activeHolds
        .where((h) => h.challanNumber.trim() == key && h.remainingQuantity > 0)
        .toList();
  }

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
  Map<String, int>? _cachedPreviousPeriodTotals;
  Map<String, double>? _cachedPeriodChangePercentages;

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
    _cachedPreviousPeriodTotals = null;
    _cachedPeriodChangePercentages = null;
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
          TransactionType.hold: 0,
          TransactionType.holdRelease: 0,
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
      TransactionType.hold: 0,
      TransactionType.holdRelease: 0,
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
      TransactionType.hold: 0,
      TransactionType.holdRelease: 0,
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
          TransactionType.hold: 0,
          TransactionType.holdRelease: 0,
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
          TransactionType.hold: 0,
          TransactionType.holdRelease: 0,
        },
      );
      map[monthKey]![t.type] = (map[monthKey]![t.type] ?? 0) + t.quantity;
    }
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    _cachedTransactionsByMonth = Map.fromEntries(sorted);
    return _cachedTransactionsByMonth!;
  }

  /// Computes totals for the period immediately before the current filter window.
  /// Keys: 'stockIn', 'stockOut', 'damage', 'transfer', 'count'.
  Map<String, int> get previousPeriodTotals {
    if (_cachedPreviousPeriodTotals != null && !_filtersDirty) {
      return _cachedPreviousPeriodTotals!;
    }
    final now = DateTime.now();
    final currentEnd = _filterEndDate ?? now;
    final currentStart =
        _filterStartDate ?? currentEnd.subtract(const Duration(days: 30));
    final duration = currentEnd.difference(currentStart);
    final prevEnd = currentStart.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(duration);

    final prevStartDay = DateTime(
      prevStart.year,
      prevStart.month,
      prevStart.day,
    );
    final prevEndExcl = DateTime(prevEnd.year, prevEnd.month, prevEnd.day + 1);

    int stockIn = 0, stockOut = 0, damage = 0, transfer = 0, count = 0;
    for (final t in _recentTransactions) {
      if (t.date.isBefore(prevStartDay) || !t.date.isBefore(prevEndExcl))
        continue;
      if (_filterUserId.isNotEmpty && t.userId != _filterUserId) continue;
      if (_filterVendorId.isNotEmpty && t.vendorId != _filterVendorId) continue;
      if (_filterProductId.isNotEmpty) {
        final lc = _filterProductId.toLowerCase();
        if (t.productId != _filterProductId &&
            !t.productName.toLowerCase().contains(lc)) {
          continue;
        }
      }
      count++;
      switch (t.type) {
        case TransactionType.stockIn:
          stockIn += t.quantity;
        case TransactionType.stockOut:
          stockOut += t.quantity;
        case TransactionType.damage:
          damage += t.quantity;
        case TransactionType.transfer:
          transfer += t.quantity;
        case TransactionType.adjustment:
        case TransactionType.hold:
        case TransactionType.holdRelease:
          break;
      }
    }
    _cachedPreviousPeriodTotals = {
      'stockIn': stockIn,
      'stockOut': stockOut,
      'damage': damage,
      'transfer': transfer,
      'count': count,
    };
    return _cachedPreviousPeriodTotals!;
  }

  /// % change for each metric vs the previous period.
  /// Returns values like 25.0 for +25%, -10.0 for -10%. null-safe: 0 if no prior data.
  Map<String, double> get periodChangePercentages {
    if (_cachedPeriodChangePercentages != null && !_filtersDirty) {
      return _cachedPeriodChangePercentages!;
    }
    final prev = previousPeriodTotals;
    double pct(int current, int previous) {
      if (previous == 0) return current > 0 ? 100.0 : 0.0;
      return ((current - previous) / previous) * 100;
    }

    _cachedPeriodChangePercentages = {
      'stockIn': pct(stockInTotal, prev['stockIn']!),
      'stockOut': pct(stockOutTotal, prev['stockOut']!),
      'damage': pct(damageTotal, prev['damage']!),
      'transfer': pct(transferTotal, prev['transfer']!),
      'count': pct(recentTransactions.length, prev['count']!),
      'netFlow': pct(
        netStockChange,
        prev['stockIn']! - prev['stockOut']! - prev['damage']!,
      ),
    };
    return _cachedPeriodChangePercentages!;
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
      TransactionType.hold: 0,
      TransactionType.holdRelease: 0,
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

  void reset() {
    _transactionsSubscription?.cancel();
    _holdsSubscription?.cancel();
    _transactionsSubscription = null;
    _holdsSubscription = null;
    _loadingTimeout?.cancel();
    _loadingTimeout = null;
    _recentTransactions = [];
    _stockHolds = [];
    _isLoading = false;
    _errorMessage = null;
    _filterStartDate = null;
    _filterEndDate = null;
    _filterUserId = '';
    _filterProductId = '';
    _filterVendorId = '';
    _sortBy = 'date_desc';
    _invalidateAnalytics();
    notifyListeners();
  }

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
        .getAllTransactions(limit: transactionFetchLimit)
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
    _holdsSubscription = _databaseService
        .getStockHolds(limit: 1000)
        .listen(
          (holds) {
            _stockHolds = holds;
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = friendlyError(
              error,
              fallback: 'Could not load stock hold data.',
            );
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
      _errorMessage = friendlyError(e, fallback: 'Could not update location.');
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

  Future<bool> createStockHold({
    required String productId,
    required String productName,
    required int quantity,
    String location = '',
    required String userId,
    required String userName,
    StockHoldSourceType sourceType = StockHoldSourceType.manual,
    String sourceId = '',
    String challanNumber = '',
    String reason = '',
    String notes = '',
    DateTime? expiresAt,
  }) async {
    if (_isLoading) return false;
    if (quantity <= 0) {
      _errorMessage = 'Quantity must be greater than zero.';
      notifyListeners();
      return false;
    }
    // Location-bound holds (sales orders, invoices) must specify a location;
    // manual holds reserve at the product level and pick a location at despatch.
    if (sourceType != StockHoldSourceType.manual && location.trim().isEmpty) {
      _errorMessage = 'Location is required.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.createStockHold(
        productId: productId,
        productName: productName,
        quantity: quantity,
        location: location,
        userId: userId,
        userName: userName,
        sourceType: sourceType,
        sourceId: sourceId,
        challanNumber: challanNumber,
        reason: reason,
        notes: notes,
        expiresAt: expiresAt,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to create stock hold.',
      );
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Creates several location-less manual holds under one challan in a single
  /// transaction. Returns true only if every item was reserved.
  Future<bool> createStockHoldsBatch({
    required List<StockHoldBatchItem> items,
    required String userId,
    required String userName,
    String challanNumber = '',
    String reason = '',
    String notes = '',
    DateTime? expiresAt,
  }) async {
    if (_isLoading) return false;
    if (items.where((e) => e.quantity > 0).isEmpty) {
      _errorMessage = 'Add at least one item with a quantity.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.createStockHoldsBatch(
        items: items,
        userId: userId,
        userName: userName,
        challanNumber: challanNumber,
        reason: reason,
        notes: notes,
        expiresAt: expiresAt,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to create stock holds.',
      );
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> releaseStockHold({
    required String holdId,
    required String userId,
    required String userName,
    String reason = '',
  }) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.releaseStockHold(
        holdId: holdId,
        userId: userId,
        userName: userName,
        reason: reason,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to release hold.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> releaseStockHoldQuantity({
    required String holdId,
    required int quantity,
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
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.releaseStockHoldQuantity(
        holdId: holdId,
        quantity: quantity,
        userId: userId,
        userName: userName,
        reason: reason,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to unhold stock.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> dispatchHoldQuantity({
    required String holdId,
    required int quantity,
    required String userId,
    required String userName,
    String location = '',
    String reason = '',
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
      await _databaseService.dispatchHoldQuantity(
        holdId: holdId,
        quantity: quantity,
        userId: userId,
        userName: userName,
        location: location,
        reason: reason,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to despatch hold.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
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
    _holdsSubscription?.cancel();
    super.dispose();
  }
}
