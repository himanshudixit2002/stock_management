import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/price_list_model.dart';
import '../models/product_model.dart';
import '../services/database_service.dart';
import '../services/price_list_resolver.dart';
import '../utils/error_helpers.dart';

/// Customer price lists, and the one resolver everything prices through.
class PriceListProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<PriceListModel> _lists = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<PriceListModel> get lists => _lists;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Lists that would actually apply today.
  List<PriceListModel> get active =>
      _lists.where((l) => l.isApplicable).toList(growable: false);

  /// The resolver over the current lists.
  ///
  /// Rebuilt per read rather than cached: it is a thin wrapper over the list
  /// the stream already holds, and a cached one would keep quoting yesterday's
  /// prices after an edit.
  PriceListResolver get resolver => PriceListResolver(_lists);

  PriceListModel? byId(String id) {
    final idx = _lists.indexWhere((l) => l.id == id);
    return idx == -1 ? null : _lists[idx];
  }

  /// The list [customerId] is on, if any.
  PriceListModel? listForCustomer(String customerId) =>
      resolver.listFor(customerId);

  /// What [customerId] pays for [product] at [quantity].
  ResolvedPrice priceFor({
    required ProductModel product,
    required String customerId,
    int quantity = 1,
  }) => resolver.resolve(
    product: product,
    customerId: customerId,
    quantity: quantity,
  );

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _lists = [];
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _databaseService.getPriceLists().listen(
      (lists) {
        _lists = lists;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load price lists.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> add(PriceListModel list) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.addPriceList(list);
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to save the price list.',
      );
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> update(PriceListModel list) => _guard(
    () => _databaseService.updatePriceList(list),
    'Failed to update the price list.',
  );

  Future<bool> remove(String id) => _guard(
    () => _databaseService.deletePriceList(id),
    'Failed to delete the price list.',
  );

  Future<bool> _guard(Future<void> Function() action, String fallback) async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
