import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/notification_provider.dart';
import '../../services/local_notification_service.dart';
import '../../services/notification_engine.dart';
import '../../services/notification_prefs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/form_section.dart';
import '../settings/settings_focus.dart';

/// Per-device notification preferences.
///
/// Device-local by design: whether this phone buzzes is a personal choice, so
/// two staff sharing a workspace do not overwrite each other.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.focusId});

  /// Group to scroll to and flash, when arrived at from settings search.
  final String? focusId;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen>
    with SettingsFocusMixin {
  bool _systemPermitted = true;
  bool _checkedPermission = false;
  bool _resolvedFocus = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final service = LocalNotificationService.instance;
    if (!service.isSupported) {
      setState(() => _checkedPermission = true);
      return;
    }
    // Reflects the OS switch, which is separate from the in-app one and can be
    // turned off in Android settings behind the app's back.
    final granted = await service.ensurePermission();
    if (!mounted) return;
    setState(() {
      _systemPermitted = granted;
      _checkedPermission = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolvedFocus) {
      _resolvedFocus = true;
      focusAfterLayout(widget.focusId ?? settingsAnchorOf(context));
    }
    final provider = context.watch<NotificationProvider>();
    final prefs = provider.prefs;
    final trayAvailable = LocalNotificationService.instance.isSupported;

    return AppScreenScaffold(
      icon: Icons.tune_rounded,
      title: 'Notification settings',
      subtitle: 'Applies to this device',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (trayAvailable) ...[
            KeyedSubtree(
              key: keyFor('notifications.delivery'),
              child: FormSection(
                title: 'Delivery',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: prefs.systemEnabled,
                    onChanged: (v) => provider.updatePrefs(
                      prefs.copyWith(systemEnabled: v),
                    ),
                    title: const Text('Show alerts in the notification tray'),
                    subtitle: const Text(
                      'Important alerts also appear on your phone outside the '
                      'app. Alerts always appear in this list either way.',
                    ),
                  ),
                  if (_checkedPermission &&
                      prefs.systemEnabled &&
                      !_systemPermitted)
                    _PermissionNotice(onRetry: _checkPermission),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          KeyedSubtree(
            key: keyFor('notifications.types'),
            child: FormSection(
              title: 'Alert me about',
              children: [
                for (final type in AlertType.all)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: prefs.isEnabled(type),
                    onChanged: (v) {
                      final next = Set<String>.from(prefs.enabledTypes);
                      if (v) {
                        next.add(type);
                      } else {
                        next.remove(type);
                      }
                      provider.updatePrefs(prefs.copyWith(enabledTypes: next));
                    },
                    title: Text(AlertType.label(type)),
                    subtitle: Text(AlertType.description(type)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: keyFor('notifications.expiry'),
            child: FormSection(
              title: 'Expiry warning window',
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Warn me this far ahead of a batch expiry date.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final days in NotificationPrefs.expiryDayOptions)
                      ChoiceChip(
                        label: Text('$days days'),
                        selected: prefs.expiryWarningDays == days,
                        onSelected: (_) => provider.updatePrefs(
                          prefs.copyWith(expiryWarningDays: days),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (prefs.enabledTypes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Every alert type is off, so nothing new will appear.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.warningColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.warningColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_off_rounded,
            size: 18,
            color: AppTheme.warningColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Android is blocking notifications',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPri(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Turn them on for SmartShelfKart in your phone\'s Settings '
                  '> Apps > Notifications. Alerts still appear inside the app.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSec(context),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Check again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
