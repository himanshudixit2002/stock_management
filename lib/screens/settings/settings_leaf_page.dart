import 'package:flutter/material.dart';

import '../../config/settings_catalog.dart';
import '../../config/theme.dart';
import '../../widgets/app_list_row.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import 'settings_context.dart';
import 'settings_focus.dart';
import 'settings_page_shell.dart';
import 'settings_search_field.dart';

/// A named run of catalogued settings on a [SettingsLeafPage].
class SettingsLeafGroup {
  const SettingsLeafGroup({
    required this.title,
    required this.leafIds,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<String> leafIds;
}

/// A settings page that is nothing but navigation rows.
///
/// Team, Data and Help are all the same page with different contents: a few
/// named groups of catalogued destinations, each row shown exactly when the
/// catalog says the user may see it. Writing that once means those three pages
/// cannot drift apart, and — more to the point — cannot drift from what search
/// will find, since both ask the same question of the same catalog.
class SettingsLeafPage extends StatefulWidget {
  const SettingsLeafPage({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.groups,
    this.subtitle,
    this.focusId,
    this.emptyMessage = 'Nothing here is available to you.',
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final List<SettingsLeafGroup> groups;
  final String? focusId;
  final String emptyMessage;

  @override
  State<SettingsLeafPage> createState() => _SettingsLeafPageState();
}

class _SettingsLeafPageState extends State<SettingsLeafPage>
    with SettingsFocusMixin {
  bool _resolved = false;

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      _resolved = true;
      focusAfterLayout(widget.focusId ?? settingsAnchorOf(context));
    }

    final ctx = settingsVisibilityContext(context);
    final sections = <Widget>[];
    var rowIndex = 0;

    for (final group in widget.groups) {
      final rows = <Widget>[];
      for (final id in group.leafIds) {
        final leaf = SettingsCatalog.leafById(id);
        if (leaf == null || !isSettingVisible(leaf, ctx)) continue;
        rows.add(
          KeyedSubtree(
            key: keyFor(leaf.id),
            child: AppListRow(
              index: rowIndex++,
              icon: leaf.icon,
              accent: leaf.accent,
              title: leaf.title,
              subtitle: leaf.subtitle,
              highlighted: isFlashing(leaf.id),
              onTap: () => openSetting(context, leaf),
            ),
          ),
        );
      }
      if (rows.isEmpty) continue;
      sections.add(
        SettingsGroup(
          title: group.title,
          subtitle: group.subtitle,
          children: rows,
        ),
      );
    }

    return AppScreenScaffold(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      iconColor: widget.accent,
      isEmpty: sections.isEmpty,
      emptyState: EmptyStateWidget(
        icon: Icons.lock_outline_rounded,
        title: 'Nothing to configure',
        subtitle: widget.emptyMessage,
      ),
      body: SettingsPageBody(children: sections),
    );
  }
}

/// Team, roles and the partner directories.
class SettingsTeamScreen extends StatelessWidget {
  const SettingsTeamScreen({super.key, this.focusId});

  final String? focusId;

  @override
  Widget build(BuildContext context) => SettingsLeafPage(
    focusId: focusId,
    icon: Icons.groups_rounded,
    title: 'Team & partners',
    subtitle: 'Who has access, and who you trade with',
    accent: AppTheme.primaryColor,
    emptyMessage: 'Ask an admin for permission to manage people.',
    groups: const [
      SettingsLeafGroup(
        title: 'People',
        subtitle: 'Roles set the baseline; overrides handle the exceptions',
        leafIds: ['team.users', 'team.roles', 'team.overrides'],
      ),
      SettingsLeafGroup(
        title: 'Partners',
        leafIds: ['team.vendors', 'team.customers'],
      ),
    ],
  );
}

/// Spreadsheets, maintenance and the bulk tools.
class SettingsDataScreen extends StatelessWidget {
  const SettingsDataScreen({super.key, this.focusId});

  final String? focusId;

  @override
  Widget build(BuildContext context) => SettingsLeafPage(
    focusId: focusId,
    icon: Icons.dataset_rounded,
    title: 'Data & tools',
    subtitle: 'Move data in and out, and fix it in bulk',
    accent: AppTheme.violetColor,
    emptyMessage: 'Ask an admin for import or export permission.',
    groups: const [
      SettingsLeafGroup(
        title: 'Spreadsheets',
        leafIds: ['data.import', 'data.update', 'data.export'],
      ),
      SettingsLeafGroup(title: 'Maintenance', leafIds: ['data.health']),
      SettingsLeafGroup(
        title: 'Bulk actions',
        leafIds: ['data.bulkStockIn', 'data.bulkEdit'],
      ),
      SettingsLeafGroup(
        title: 'Workspace',
        leafIds: ['data.companySwitcher', 'data.onboarding'],
      ),
    ],
  );
}

/// Help, the activity trail, and the legal pages.
class SettingsHelpScreen extends StatelessWidget {
  const SettingsHelpScreen({super.key, this.focusId});

  final String? focusId;

  @override
  Widget build(BuildContext context) => SettingsLeafPage(
    focusId: focusId,
    icon: Icons.help_outline_rounded,
    title: 'Help, legal & about',
    subtitle: 'Guides, policies and app info',
    accent: AppTheme.cyanColor,
    groups: const [
      SettingsLeafGroup(
        title: 'Help',
        leafIds: ['help.guides', 'help.activity'],
      ),
      SettingsLeafGroup(title: 'About', leafIds: ['help.about']),
      SettingsLeafGroup(
        title: 'Legal',
        leafIds: [
          'help.privacy',
          'help.terms',
          'help.support',
          'help.dataDeletion',
        ],
      ),
    ],
  );
}
