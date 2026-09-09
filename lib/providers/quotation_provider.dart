import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/quotation_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Priced offers, and where each one has got to.
class QuotationProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<QuotationModel> _quotations = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<QuotationModel> get quotations => _quotations;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  /// Quotes still waiting on an answer.
  List<QuotationModel> get open =>
      _quotations.where((q) => q.isOpen).toList(growable: false);

  List<QuotationModel> get accepted => _quotations
      .where((q) => q.status == QuotationStatus.accepted)
      .toList(growable: false);

  /// Sent, past their validity date, and still unanswered.
  List<QuotationModel> get lapsed =>
      _quotations.where((q) => q.hasLapsed).toList(growable: false);

  /// Sent, still valid, and lapsing within a week — the chase list.
  List<QuotationModel> get expiringSoon => _quotations
      .where(
        (q) =>
            q.status == QuotationStatus.sent &&
            !q.hasLapsed &&
            (q.daysToExpiry ?? 999) <= 7,
      )
      .toList(growable: false);

  /// Value of everything still in play.
  double get pipelineValue =>
      open.fold(0.0, (acc, q) => acc + q.grandTotal) +
      accepted.fold(0.0, (acc, q) => acc + q.grandTotal);

  /// Accepted or converted, as a share of everything that got an answer.
  double get winRate {
    final decided = _quotations
        .where(
          (q) =>
              q.status == QuotationStatus.accepted ||
              q.status == QuotationStatus.converted ||
              q.status == QuotationStatus.declined,
        )
        .toList();
    if (decided.isEmpty) return 0;
    final won = decided
        .where((q) => q.status != QuotationStatus.declined)
        .length;
    return won / decided.length;
  }

  QuotationModel? byId(String id) {
    final idx = _quotations.indexWhere((q) => q.id == id);
    return idx == -1 ? null : _quotations[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _quotations = [];
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

    _subscription = _databaseService.getQuotations().listen(
      (quotations) {
        _quotations = quotations;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load quotations.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addQuotation(QuotationModel quotation) async {
    final result = await _run(
      () => _databaseService.addQuotation(quotation),
      'Failed to save the quotation.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateQuotation(QuotationModel quotation) async {
    final result = await _run(
      () => _databaseService.updateQuotation(quotation),
      'Failed to update the quotation.',
    );
    return result != null;
  }

  Future<bool> deleteQuotation(String id) async {
    final result = await _run(
      () => _databaseService.deleteQuotation(id),
      'Failed to delete the quotation.',
    );
    return result != null;
  }

  Future<bool> markSent(QuotationModel quotation) async {
    final result = await _run(
      () => _databaseService.markQuotationSent(quotation.id),
      'Could not mark this quotation as sent.',
    );
    return result != null;
  }

  Future<bool> decide({
    required QuotationModel quotation,
    required bool accepted,
    required String note,
    required String userId,
    required String userName,
  }) async {
    final result = await _run(
      () => _databaseService.decideQuotation(
        quotation: quotation,
        accepted: accepted,
        note: note,
        userId: userId,
        userName: userName,
      ),
      'Could not record the decision.',
    );
    return result != null;
  }

  /// Returns the new sales order's id, or null on failure.
  Future<String?> convertToSalesOrder({
    required QuotationModel quotation,
    required String userId,
    required String userName,
  }) async {
    final result = await _run(
      () => _databaseService.convertQuotationToSalesOrder(
        quotation: quotation,
        userId: userId,
        userName: userName,
      ),
      'Could not convert this quotation.',
    );
    return result is String ? result : null;
  }

  Future<Object?> _run(
    Future<Object?> Function() action,
    String fallback,
  ) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action() ?? true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      return null;
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
