import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/serial_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Serialised units — the register, and the lookups against it.
class SerialProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<SerialModel> _serials = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;

  /// Numbers refused by the last registration because they already existed.
  /// Held so the intake sheet can list them rather than just saying "some
  /// failed".
  List<String> _lastRejected = const [];

  StreamSubscription? _subscription;

  List<SerialModel> get serials => _serials;
  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  List<String> get lastRejected => _lastRejected;

  /// How many loaded units sit in each status, for the register's filter chips.
  Map<SerialStatus, int> get statusCounts {
    final counts = <SerialStatus, int>{};
    for (final serial in _serials) {
      counts[serial.status] = (counts[serial.status] ?? 0) + 1;
    }
    return counts;
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _serials = [];
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    _lastRejected = const [];
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _databaseService.getSerials().listen(
      (serials) {
        _serials = serials;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load serial numbers.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// The unit carrying [serialNumber].
  ///
  /// Checks the loaded page first and only then queries: a scan at the counter
  /// is almost always a unit the register is already showing, and paying a
  /// round trip for it would make the scanner feel broken.
  Future<SerialModel?> lookup(String serialNumber) async {
    final key = SerialModel.normalizeSerial(serialNumber);
    if (key.isEmpty) return null;
    final idx = _serials.indexWhere((s) => s.serialKey == key);
    if (idx != -1) return _serials[idx];
    try {
      return await _databaseService.findSerial(key);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not look that up.');
      notifyListeners();
      return null;
    }
  }

  /// Registers [serials]. Returns how many were accepted; the duplicates it
  /// refused are in [lastRejected].
  Future<int> register(List<SerialModel> serials) async {
    if (_isBusy || serials.isEmpty) return 0;
    _isBusy = true;
    _errorMessage = null;
    _lastRejected = const [];
    notifyListeners();
    try {
      final rejected = await _databaseService.addSerials(serials);
      _lastRejected = rejected;
      return serials.length - rejected.length;
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Failed to register those serial numbers.',
      );
      return 0;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Moves [serial] to [status], appending the reason to its history.
  Future<bool> changeStatus({
    required SerialModel serial,
    required SerialStatus status,
    required String userId,
    required String userName,
    String note = '',
    String referenceType = '',
    String referenceId = '',
    String referenceLabel = '',
  }) async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = serial
          .withEvent(
            SerialEvent(
              action: SerialModel.statusLabelOf(status),
              note: note,
              referenceType: referenceType,
              referenceId: referenceId,
              userId: userId,
              userName: userName,
              at: DateTime.now(),
            ),
            status: status,
          )
          .copyWith(
            referenceType: referenceType,
            referenceId: referenceId,
            referenceLabel: referenceLabel,
          );
      await _databaseService.updateSerial(updated);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not update that unit.');
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> updateSerial(SerialModel serial) async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateSerial(serial);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not save that unit.');
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deleteSerial(String id) async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.deleteSerial(id);
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not delete that unit.');
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
