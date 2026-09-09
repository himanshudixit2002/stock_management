import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/landed_cost_model.dart';
import '../services/database_service.dart';
import '../services/landed_cost_allocator.dart';
import '../utils/error_helpers.dart';

/// Landed-cost sheets and the cost updates they apply.
class LandedCostProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<LandedCostModel> _sheets = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<LandedCostModel> get sheets => _sheets;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  List<LandedCostModel> get drafts => _sheets
      .where((s) => s.status == LandedCostStatus.draft)
      .toList(growable: false);

  /// Total charges captured by applied sheets — how much it has cost to land
  /// stock, which nothing else in the app could answer.
  double get appliedCharges => _sheets
      .where((s) => s.status == LandedCostStatus.applied)
      .fold(0.0, (acc, s) => acc + s.totalCharges);

  LandedCostModel? byId(String id) {
    final idx = _sheets.indexWhere((s) => s.id == id);
    return idx == -1 ? null : _sheets[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _sheets = [];
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

    _subscription = _databaseService.getLandedCosts().listen(
      (sheets) {
        _sheets = sheets;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load landed cost sheets.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Saves [sheet] with its charges allocated across its lines.
  ///
  /// Allocation happens here rather than at apply time so what the user
  /// approved on screen is exactly what is stored, and so a sheet reopened
  /// later shows the same split it was saved with.
  Future<String?> add(LandedCostModel sheet) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.addLandedCost(_allocated(sheet));
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to save the sheet.');
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> update(LandedCostModel sheet) => _guard(
    () => _databaseService.updateLandedCost(_allocated(sheet)),
    'Failed to update the sheet.',
  );

  Future<bool> remove(String id) => _guard(
    () => _databaseService.deleteLandedCost(id),
    'Failed to delete the sheet.',
  );

  Future<bool> apply({
    required LandedCostModel sheet,
    required String userId,
    required String userName,
  }) => _guard(
    () => _databaseService.applyLandedCost(
      sheet: sheet,
      userId: userId,
      userName: userName,
    ),
    'Could not apply the landed costs.',
  );

  Future<bool> reverse({
    required LandedCostModel sheet,
    required String userId,
    required String userName,
  }) => _guard(
    () => _databaseService.applyLandedCost(
      sheet: sheet,
      userId: userId,
      userName: userName,
      reverse: true,
    ),
    'Could not reverse the landed costs.',
  );

  static LandedCostModel _allocated(LandedCostModel sheet) => sheet.copyWith(
    lines: LandedCostAllocator.allocate(
      lines: sheet.lines,
      charges: sheet.charges,
    ),
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
