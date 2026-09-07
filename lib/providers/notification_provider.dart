import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_notification_model.dart';
import '../models/batch_model.dart';
import '../models/invoice_model.dart';
import '../models/product_model.dart';
import '../models/purchase_order_model.dart';
import '../services/database_service.dart';
import '../services/notification_engine.dart';
import '../services/notification_prefs.dart';
import '../utils/error_helpers.dart';

class NotificationProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final NotificationEngine _engine = const NotificationEngine();

  List<AppNotificationModel> _notifications = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  NotificationPrefs _prefs = NotificationPrefs.defaults();
  bool _prefsLoaded = false;
  bool _isScanning = false;
  DateTime? _lastScanAt;

  /// Set by the caller so alerts can also reach the Android tray. Left null on
  /// platforms without a tray, which is why this is a hook rather than a direct
  /// dependency — the provider stays testable and web-safe.
  Future<void> Function(List<NotificationCandidate>)? onNewAlerts;

  List<AppNotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  NotificationPrefs get prefs => _prefs;
  bool get isScanning => _isScanning;
  DateTime? get lastScanAt => _lastScanAt;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Unread count per alert type, for the filter chips.
  Map<String, int> get unreadByType {
    final counts = <String, int>{};
    for (final n in _notifications) {
      if (n.isRead) continue;
      counts[n.type] = (counts[n.type] ?? 0) + 1;
    }
    return counts;
  }

  /// The alert types actually present in the current list, in the order they
  /// first appear (newest notification first, since the stream is sorted that
  /// way). Used to build filter chips without offering one that matches
  /// nothing.
  List<String> get presentTypes {
    final seen = <String>{};
    for (final n in _notifications) {
      if (n.type.isNotEmpty) seen.add(n.type);
    }
    return seen.toList();
  }

  List<AppNotificationModel> filtered({String? type, bool unreadOnly = false}) {
    return _notifications.where((n) {
      if (unreadOnly && n.isRead) return false;
      if (type != null && type.isNotEmpty && n.type != type) return false;
      return true;
    }).toList();
  }

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

    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefs = await NotificationPrefs.load();
    _lastScanAt = await NotificationPrefs.lastScanAt();
    _prefsLoaded = true;
    notifyListeners();
  }

  Future<void> updatePrefs(NotificationPrefs next) async {
    _prefs = next;
    _prefsLoaded = true;
    notifyListeners();
    await next.save();
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _notifications = [];
    _isLoading = false;
    _errorMessage = null;
    _isScanning = false;
    notifyListeners();
  }

  /// Derives alerts from the data already in memory and persists any that do
  /// not exist yet.
  ///
  /// Cheap by construction: candidate ids are deterministic, so an unchanged
  /// workspace produces ids that are already in the streamed list and the
  /// method returns without touching Firestore.
  ///
  /// [minInterval] throttles repeat scans across app resumes; pass
  /// [force] to bypass it for an explicit pull-to-refresh.
  Future<int> runScan({
    List<ProductModel> products = const [],
    List<BatchModel> batches = const [],
    List<InvoiceModel> invoices = const [],
    List<PurchaseOrderModel> purchaseOrders = const [],
    Duration minInterval = const Duration(hours: 6),
    bool force = false,
    DateTime? now,
  }) async {
    if (_isScanning) return 0;
    if (!_prefsLoaded) await _loadPrefs();

    final at = now ?? DateTime.now();
    if (!force && _lastScanAt != null && at.difference(_lastScanAt!) < minInterval) {
      return 0;
    }
    if (_prefs.enabledTypes.isEmpty) return 0;

    _isScanning = true;
    notifyListeners();
    try {
      final candidates = _engine.scan(
        now: at,
        products: products,
        batches: batches,
        invoices: invoices,
        purchaseOrders: purchaseOrders,
        config: _prefs.toScanConfig(),
      );

      // The live list is the cheap dedupe filter; only what survives it costs a
      // read. Normally that is nothing at all.
      final known = _notifications.map((n) => n.id).toSet();
      final missing = candidates.where((c) => !known.contains(c.id)).toList();

      _lastScanAt = at;
      await NotificationPrefs.markScanned(at);

      // The dedupe filter above only sees the newest 100 rows, so a workspace
      // sitting at the cap would start re-raising alerts that scrolled out of
      // the window. Pruning read, month-old rows keeps it under the cap.
      if (_notifications.length >= _pruneThreshold) await pruneOld();

      if (missing.isEmpty) return 0;

      final created = await _databaseService.createAlertsIfAbsent(missing);
      if (created.isNotEmpty && _prefs.systemEnabled) {
        await onNewAlerts?.call(created);
      }
      return created.length;
    } catch (e) {
      if (kDebugMode) debugPrint('Alert scan failed: $e');
      return 0;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
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

  /// Deletes one notification.
  ///
  /// Returns false when the write was rejected — rules allow deletes for admins
  /// only, and the caller needs to know so it can put the row back instead of
  /// leaving the list disagreeing with the server.
  Future<bool> delete(String id) async {
    // Optimistic: the swipe already removed the row visually, so drop it from
    // the list too and let the stream correct us if the write fails.
    final previous = _notifications;
    _notifications = _notifications.where((n) => n.id != id).toList();
    notifyListeners();
    try {
      await _databaseService.deleteNotification(id);
      return true;
    } catch (e) {
      _notifications = previous;
      _errorMessage = friendlyError(
        e,
        fallback: 'Could not delete notification.',
      );
      notifyListeners();
      return false;
    }
  }

  /// How full the streamed window has to get before pruning is worth a query.
  /// The stream asks for 100, so this triggers just short of the cap.
  static const int _pruneThreshold = 90;

  /// Removes read notifications older than 30 days. Admin-only server side, so
  /// failures are swallowed rather than surfaced.
  Future<void> pruneOld() async {
    try {
      await _databaseService.pruneNotifications();
    } catch (e) {
      if (kDebugMode) debugPrint('Notification prune skipped: $e');
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> addNotification({
    required String type,
    required String title,
    String message = '',
    String entityType = '',
    String entityId = '',
    AlertSeverity severity = AlertSeverity.info,
  }) async {
    try {
      final notification = AppNotificationModel(
        id: '',
        type: type,
        title: title,
        message: message,
        entityType: entityType,
        entityId: entityId,
        severity: severity,
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
