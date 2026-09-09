import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bom_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Bills of materials, and the assembly runs made from them.
class BomProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<BomModel> _boms = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<BomModel> get boms => _boms;

  /// Recipes that can actually be built from right now.
  List<BomModel> get buildable =>
      _boms.where((b) => b.isBuildable).toList(growable: false);

  bool get isLoading => _isLoading;

  /// True while a build/unbuild is in flight. Separate from [isLoading] so the
  /// list does not flash a shimmer every time somebody builds one kit.
  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  BomModel? byId(String id) {
    final idx = _boms.indexWhere((b) => b.id == id);
    return idx == -1 ? null : _boms[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _boms = [];
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

    _subscription = _databaseService.getBoms().listen(
      (boms) {
        _boms = boms;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load bills of materials.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addBom(BomModel bom) async {
    final result = await _run(
      () => _databaseService.addBom(bom),
      'Failed to save the BOM.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateBom(BomModel bom) async {
    final result = await _run(
      () => _databaseService.updateBom(bom),
      'Failed to update the BOM.',
    );
    return result != null;
  }

  Future<bool> deleteBom(String id) async {
    final result = await _run(
      () => _databaseService.deleteBom(id),
      'Failed to delete the BOM.',
    );
    return result != null;
  }

  /// Runs [bom] [runs] times, or unbuilds when [reverse] is true.
  ///
  /// Returns the number of output units moved, or null on failure — the caller
  /// needs the count to report "Built 24 units", which a bool cannot carry.
  Future<int?> runAssembly({
    required BomModel bom,
    required int runs,
    required String location,
    required String userId,
    required String userName,
    bool reverse = false,
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final units = await _databaseService.runAssembly(
        bom: bom,
        runs: runs,
        location: location,
        userId: userId,
        userName: userName,
        reverse: reverse,
      );
      return units;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: reverse ? 'Unbuild failed.' : 'Build failed.',
      );
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Shared write wrapper. Returns a sentinel on success so callers can null-
  /// check without every method needing its own try/catch ladder.
  Future<Object?> _run(Future<Object?> Function() action, String fallback) async {
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
