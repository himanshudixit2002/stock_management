import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/home_actions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/home_customization_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/app_list_row.dart';
import '../../widgets/app_screen_scaffold.dart';
import 'settings_focus.dart';
import 'settings_page_shell.dart';
import 'settings_summaries.dart';

/// Theme and home-screen preferences.
///
/// Both are stored per device rather than per workspace, which the page says
/// out loud: someone changing the theme on their phone should not expect their
/// colleague's tablet to follow.
class SettingsAppearanceScreen extends StatefulWidget {
  const SettingsAppearanceScreen({super.key, this.focusId});

  final String? focusId;

  @override
  State<SettingsAppearanceScreen> createState() =>
      _SettingsAppearanceScreenState();
}

class _SettingsAppearanceScreenState extends State<SettingsAppearanceScreen>
    with SettingsFocusMixin {
  bool _resolvedFocus = false;

  @override
  Widget build(BuildContext context) {
    if (!_resolvedFocus) {
      _resolvedFocus = true;
      focusAfterLayout(widget.focusId ?? settingsAnchorOf(context));
    }

    final home = context.watch<HomeCustomizationProvider>();
    final actionCount = home.selectedIds.length;

    return AppScreenScaffold(
      icon: Icons.palette_rounded,
      title: 'Appearance & home',
      subtitle: 'Applies to this device',
      iconColor: AppTheme.accentColor,
      body: SettingsPageBody(
        children: [
          KeyedSubtree(
            key: keyFor('appearance.theme'),
            child: SettingsGroup(
              title: 'Theme',
              children: [
                _ThemeChoice(highlighted: isFlashing('appearance.theme')),
              ],
            ),
          ),
          KeyedSubtree(
            key: keyFor('appearance.home'),
            child: SettingsGroup(
              title: 'Home screen',
              children: [
                AppListRow(
                  icon: Icons.dashboard_customize_rounded,
                  accent: AppTheme.primaryColor,
                  title: 'Home quick actions',
                  subtitle: home.isLoaded
                      ? '$actionCount of ${HomeActionsRegistry.maxActions} chosen'
                      : 'Choose the shortcuts on your home screen',
                  highlighted: isFlashing('appearance.home'),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.homeCustomization,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The three theme modes as full-width labelled options.
///
/// They used to be three unlabelled icon segments squeezed to the right of a
/// row, which on a phone gave three ~28px targets and no way to tell
/// "automatic" from "light" without tapping one.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.highlighted});

  final bool highlighted;

  static const _options = <(ThemeMode, IconData, String)>[
    (ThemeMode.system, Icons.brightness_auto_rounded, 'Match the device'),
    (ThemeMode.light, Icons.light_mode_rounded, 'Always light'),
    (ThemeMode.dark, Icons.dark_mode_rounded, 'Always dark'),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _options.length; i++)
              AppListRow(
                index: i,
                icon: _options[i].$2,
                accent: AppTheme.accentColor,
                title: themeModeLabel(_options[i].$1),
                subtitle: _options[i].$3,
                highlighted: highlighted,
                showChevron: false,
                onTap: () => theme.setThemeMode(_options[i].$1),
                trailing: Icon(
                  theme.themeMode == _options[i].$1
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: theme.themeMode == _options[i].$1
                      ? AppTheme.primary(context)
                      : AppTheme.iconMute(context),
                ),
              ),
          ],
        );
      },
    );
  }
}
