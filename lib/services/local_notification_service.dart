import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_engine.dart';

/// Posts alerts to the Android notification tray.
///
/// Local notifications only — there is no push server. Alerts are raised by the
/// on-device scan in [NotificationProvider], so they appear when the app is
/// running or resumed rather than at arbitrary times. Everything here is a
/// no-op off Android, which keeps web and desktop builds free of dead calls.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  static const String _channelId = 'stock_alerts';
  static const String _channelName = 'Stock alerts';
  static const String _channelDescription =
      'Low stock, expiring batches, overdue invoices and late orders.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionRequested = false;

  /// Called when the user taps a tray notification. The payload is the alert's
  /// `entityType|entityId`, which the app maps to a route.
  void Function(String payload)? onSelect;

  /// True only where a tray exists and the plugin is usable.
  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize({void Function(String payload)? onSelect}) async {
    this.onSelect = onSelect;
    if (!isSupported || _initialized) return;

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notification'),
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            this.onSelect?.call(payload);
          }
        },
      );

      // Creating the channel up front means the user can tune or silence stock
      // alerts in Android settings before the first one ever fires.
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.defaultImportance,
        ),
      );

      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('Local notifications unavailable: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Asks for POST_NOTIFICATIONS once per process.
  ///
  /// Android 13+ only; older versions grant it at install time and the call
  /// returns true. A denial is remembered by the OS, so re-asking every scan
  /// would be pointless as well as rude.
  Future<bool> ensurePermission() async {
    if (!isSupported) return false;
    if (!_initialized) await initialize(onSelect: onSelect);
    if (!_initialized) return false;

    try {
      final android = _android;
      if (android == null) return false;
      if (await android.areNotificationsEnabled() ?? false) return true;
      if (_permissionRequested) return false;
      _permissionRequested = true;
      return await android.requestNotificationsPermission() ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('Notification permission check failed: $e');
      return false;
    }
  }

  /// Shows [candidates] in the tray.
  ///
  /// A single alert is posted on its own so tapping it deep-links straight to
  /// the item. Several at once are collapsed into one summary — a scan that
  /// found eight problems should not produce eight buzzes.
  Future<void> showAlerts(List<NotificationCandidate> candidates) async {
    if (!isSupported || candidates.isEmpty) return;
    if (!await ensurePermission()) return;

    // Info-level alerts are real but not worth interrupting anyone for.
    final worth = candidates
        .where((c) => c.severity != AlertSeverity.info)
        .toList();
    if (worth.isEmpty) return;

    try {
      if (worth.length == 1) {
        final c = worth.single;
        await _show(
          id: c.id.hashCode,
          title: c.title,
          body: c.message,
          payload: '${c.entityType}|${c.entityId}',
          critical: c.severity == AlertSeverity.critical,
        );
        return;
      }

      final critical = worth.any((c) => c.severity == AlertSeverity.critical);
      await _show(
        // A fixed id so consecutive summaries replace each other instead of
        // stacking up in the tray.
        id: _summaryId,
        title: '${worth.length} new stock alerts',
        body: worth.take(3).map((c) => c.title).join(' · '),
        payload: 'notification_list|',
        critical: critical,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Could not post notification: $e');
    }
  }

  static const int _summaryId = 424242;

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String payload,
    required bool critical,
  }) async {
    final details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: critical ? Importance.high : Importance.defaultImportance,
      priority: critical ? Priority.high : Priority.defaultPriority,
      color: const Color(0xFF0D9488),
      // Long titles are the norm here ("Blue Widget 500ml is running low"), so
      // let the tray expand rather than truncate.
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: _channelName,
      ),
      category: AndroidNotificationCategory.status,
    );

    await _plugin.show(
      // Notification ids are 32-bit signed on Android; hashCode can exceed it.
      id: id.abs() % 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
      payload: payload,
    );
  }

  /// Clears everything this app has posted. Used on sign-out so one user's
  /// alerts do not linger for the next person on a shared device.
  Future<void> cancelAll() async {
    if (!isSupported || !_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Nothing to do — a stale tray entry is harmless.
    }
  }
}
