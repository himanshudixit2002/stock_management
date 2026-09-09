import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/invoice_model.dart';
import '../models/register_session_model.dart';
import '../services/database_service.dart';
import '../services/register_tally_service.dart';
import '../utils/error_helpers.dart';

/// Till shifts: opening float, cash movements, and the close.
class RegisterSessionProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<RegisterSessionModel> _sessions = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<RegisterSessionModel> get sessions => _sessions;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  List<RegisterSessionModel> get openSessions =>
      _sessions.where((s) => s.isOpen).toList(growable: false);

  /// The open shift on a register, if there is one.
  RegisterSessionModel? openSessionFor(String registerName) {
    final key = RegisterSessionModel.keyFor(registerName);
    for (final session in _sessions) {
      if (session.isOpen && session.registerKey == key) return session;
    }
    return null;
  }

  /// The open shift this user started, whichever register it is on. What Fast
  /// POS actually needs: an operator cares about their own drawer, not about
  /// every till in the building.
  RegisterSessionModel? openSessionForUser(String userId) {
    if (userId.isEmpty) return null;
    for (final session in _sessions) {
      if (session.isOpen && session.openedBy == userId) return session;
    }
    return null;
  }

  RegisterSessionModel? byId(String id) {
    final idx = _sessions.indexWhere((s) => s.id == id);
    return idx == -1 ? null : _sessions[idx];
  }

  /// The live tally for a shift, from the invoices stamped with it.
  RegisterTally tallyFor(
    RegisterSessionModel session,
    List<InvoiceModel> invoices,
  ) => RegisterTallyService.tally(session: session, invoices: invoices);

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _sessions = [];
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

    _subscription = _databaseService.getRegisterSessions().listen(
      (sessions) {
        _sessions = sessions;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load register shifts.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Opens a shift, or returns null with [errorMessage] set when the register
  /// already has one open.
  Future<RegisterSessionModel?> openSession({
    required String registerName,
    required double openingFloat,
    required String userId,
    required String userName,
    String notes = '',
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _databaseService.openRegisterSession(
        registerName: registerName,
        openingFloat: openingFloat,
        userId: userId,
        userName: userName,
        notes: notes,
      );
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not open the shift.');
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> recordCashMovement({
    required RegisterSessionModel session,
    required double amount,
    required String reason,
    required String userId,
    required String userName,
  }) async {
    final result = await _run(
      () => _databaseService.addCashMovement(
        sessionId: session.id,
        movement: CashMovement(
          id: 'mv-${DateTime.now().microsecondsSinceEpoch}',
          amount: amount,
          reason: reason,
          userId: userId,
          userName: userName,
          at: DateTime.now(),
        ),
      ),
      'Could not record the cash movement.',
    );
    return result != null;
  }

  /// Closes a shift against [countedCash], stamping the tally it was measured
  /// against.
  Future<bool> closeSession({
    required RegisterSessionModel session,
    required double countedCash,
    required RegisterTally tally,
    required String userId,
    required String userName,
    String notes = '',
  }) async {
    final result = await _run(
      () => _databaseService.closeRegisterSession(
        session: session,
        countedCash: countedCash,
        expectedCash: tally.expectedCash,
        takingsByMethod: tally.takingsByMethod,
        invoiceCount: tally.invoiceCount,
        salesTotal: tally.salesTotal,
        userId: userId,
        userName: userName,
        notes: notes,
      ),
      'Could not close the shift.',
    );
    return result != null;
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
