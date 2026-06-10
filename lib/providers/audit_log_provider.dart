import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/audit_log_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class AuditLogProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<AuditLogModel> _logs = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _logsSubscription;

  List<AuditLogModel> get logs => _logs;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _logsSubscription?.cancel();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _logsSubscription = _databaseService
        .getAuditLogs(limit: 500)
        .listen(
          (logs) {
            _logs = logs;
            _isLoading = false;
            _errorMessage = null;
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = friendlyError(
              error,
              fallback: 'Could not load audit logs.',
            );
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  void reset() {
    _logsSubscription?.cancel();
    _logsSubscription = null;
    _logs = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logAction({
    required String action,
    required String entityType,
    String entityId = '',
    String entityName = '',
    String userId = '',
    String userName = '',
    Map<String, dynamic> changes = const {},
  }) async {
    try {
      final log = AuditLogModel(
        id: '',
        action: action,
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        userId: userId,
        userName: userName,
        changes: changes,
        timestamp: DateTime.now(),
      );
      await _databaseService.addAuditLog(log);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to write audit log: $e');
    }
  }

  @override
  void dispose() {
    _logsSubscription?.cancel();
    super.dispose();
  }
}
