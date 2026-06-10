import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_notification_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class NotificationProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<AppNotificationModel> _notifications = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<AppNotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _subscription = _databaseService
        .getNotifications(limit: 100)
        .listen(
          (list) {
            _notifications = list;
            _isLoading = false;
            _errorMessage = null;
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = friendlyError(
              error,
              fallback: 'Could not load notifications.',
            );
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _notifications = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    try {
      await _databaseService.markNotificationRead(id);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not mark as read.');
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    try {
      await _databaseService.markAllNotificationsRead();
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Could not mark all as read.');
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    try {
      await _databaseService.deleteNotification(id);
    } catch (e) {
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not delete notification.',
      );
      notifyListeners();
    }
  }

  Future<void> addNotification({
    required String type,
    required String title,
    String message = '',
    String entityType = '',
    String entityId = '',
  }) async {
    try {
      final notification = AppNotificationModel(
        id: '',
        type: type,
        title: title,
        message: message,
        entityType: entityType,
        entityId: entityId,
        timestamp: DateTime.now(),
      );
      await _databaseService.addNotification(notification);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to add notification: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
