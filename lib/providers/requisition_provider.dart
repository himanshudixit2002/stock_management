import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/requisition_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Purchase requisitions and the approval queue over them.
class RequisitionProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<RequisitionModel> _requisitions = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<RequisitionModel> get requisitions => _requisitions;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Everything waiting on a decision, most urgent (then oldest) first — the
  /// order an approver should work through.
  List<RequisitionModel> get pendingApproval {
    final list = _requisitions
        .where((r) => r.status == RequisitionStatus.submitted)
        .toList();
    list.sort((a, b) {
      final byUrgency = b.urgency.index.compareTo(a.urgency.index);
      if (byUrgency != 0) return byUrgency;
      final aWhen = a.submittedAt ?? a.createdAt;
      final bWhen = b.submittedAt ?? b.createdAt;
      return aWhen.compareTo(bWhen);
    });
    return list;
  }

  /// Submitted requests that have gone unanswered long enough to chase.
  int get staleCount => pendingApproval.where((r) => r.isStale()).length;

  RequisitionModel? byId(String id) {
    final idx = _requisitions.indexWhere((r) => r.id == id);
    return idx == -1 ? null : _requisitions[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _requisitions = [];
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

    _subscription = _databaseService.getRequisitions().listen(
      (requisitions) {
        _requisitions = requisitions;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load requisitions.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> add(RequisitionModel requisition) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.addRequisition(requisition);
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to save the requisition.',
      );
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> update(RequisitionModel requisition) => _guard(
    () => _databaseService.updateRequisition(requisition),
    'Failed to update the requisition.',
  );

  Future<bool> remove(String id) => _guard(
    () => _databaseService.deleteRequisition(id),
    'Failed to delete the requisition.',
  );

  /// Moves a draft into the approval queue.
  Future<bool> submit(RequisitionModel requisition) {
    final now = DateTime.now();
    return update(
      requisition.copyWith(
        status: RequisitionStatus.submitted,
        submittedAt: now,
        updatedAt: now,
        // A resubmitted rejection starts clean, or the requester sees the old
        // rejection note sitting under their new request.
        decisionNote: '',
        decidedBy: '',
        decidedByName: '',
      ),
    );
  }

  Future<bool> cancel(RequisitionModel requisition) => update(
    requisition.copyWith(
      status: RequisitionStatus.cancelled,
      updatedAt: DateTime.now(),
    ),
  );

  Future<bool> decide({
    required RequisitionModel requisition,
    required bool approved,
    required String note,
    required String userId,
    required String userName,
  }) => _guard(
    () => _databaseService.decideRequisition(
      requisition: requisition,
      approved: approved,
      note: note,
      userId: userId,
      userName: userName,
    ),
    'Could not record that decision.',
  );

  /// Converts an approved requisition into a draft purchase order, returning
  /// the new order's id.
  Future<String?> convertToPurchaseOrder({
    required RequisitionModel requisition,
    required DateTime expectedDate,
    required String userId,
    required String userName,
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.convertRequisitionToPurchaseOrder(
        requisition: requisition,
        expectedDate: expectedDate,
        userId: userId,
        userName: userName,
      );
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not raise a purchase order from this requisition.',
      );
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

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
