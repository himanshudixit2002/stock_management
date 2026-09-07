import 'package:shared_preferences/shared_preferences.dart';

import 'notification_engine.dart';

/// User-facing notification settings, persisted per device.
///
/// Device-local rather than in the company doc on purpose: whether *this*
/// phone buzzes is a personal choice, and two staff sharing a workspace should
/// not overwrite each other's preferences.
class NotificationPrefs {
  static const String _kEnabledPrefix = 'notif.type.';
  static const String _kExpiryDays = 'notif.expiryWarningDays';
  static const String _kSystemEnabled = 'notif.systemEnabled';
  static const String _kLastScanMs = 'notif.lastScanMs';

  /// Expiry windows offered in the settings screen.
  static const List<int> expiryDayOptions = [7, 14, 30, 60, 90];

  const NotificationPrefs({
    required this.enabledTypes,
    required this.expiryWarningDays,
    required this.systemEnabled,
  });

  /// Everything on, 30-day expiry window — what a workspace gets before anyone
  /// visits the settings screen.
  factory NotificationPrefs.defaults() => NotificationPrefs(
    enabledTypes: AlertType.all.toSet(),
    expiryWarningDays: 30,
    systemEnabled: true,
  );

  final Set<String> enabledTypes;
  final int expiryWarningDays;

  /// Whether alerts may also surface in the Android notification tray. The OS
  /// permission is separate; this is the in-app master switch.
  final bool systemEnabled;

  bool isEnabled(String type) => enabledTypes.contains(type);

  AlertScanConfig toScanConfig() => AlertScanConfig(
    enabledTypes: enabledTypes,
    expiryWarningDays: expiryWarningDays,
  );

  NotificationPrefs copyWith({
    Set<String>? enabledTypes,
    int? expiryWarningDays,
    bool? systemEnabled,
  }) {
    return NotificationPrefs(
      enabledTypes: enabledTypes ?? this.enabledTypes,
      expiryWarningDays: expiryWarningDays ?? this.expiryWarningDays,
      systemEnabled: systemEnabled ?? this.systemEnabled,
    );
  }

  static Future<NotificationPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = <String>{};
      for (final type in AlertType.all) {
        // Absent means "not configured yet", which should behave as on.
        if (prefs.getBool('$_kEnabledPrefix$type') ?? true) enabled.add(type);
      }
      final days = prefs.getInt(_kExpiryDays) ?? 30;
      return NotificationPrefs(
        enabledTypes: enabled,
        expiryWarningDays: expiryDayOptions.contains(days) ? days : 30,
        systemEnabled: prefs.getBool(_kSystemEnabled) ?? true,
      );
    } catch (_) {
      // A broken prefs store must not stop alerts from working.
      return NotificationPrefs.defaults();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final type in AlertType.all) {
        await prefs.setBool(
          '$_kEnabledPrefix$type',
          enabledTypes.contains(type),
        );
      }
      await prefs.setInt(_kExpiryDays, expiryWarningDays);
      await prefs.setBool(_kSystemEnabled, systemEnabled);
    } catch (_) {
      // Best effort — the in-memory value already took effect.
    }
  }

  /// When the last scan ran, used to keep app-resume scans from firing on every
  /// tab switch. Null when no scan has ever run on this device.
  static Future<DateTime?> lastScanAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kLastScanMs);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> markScanned(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastScanMs, at.millisecondsSinceEpoch);
    } catch (_) {
      // Losing the marker only costs one redundant scan.
    }
  }
}
