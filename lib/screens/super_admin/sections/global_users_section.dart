import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../providers/super_admin_provider.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/glass_panel.dart';
import '../../../widgets/admin_search_bar.dart';
import '../console_widgets.dart';

/// Every user on the platform, across every workspace.
///
/// This list is the one the console could never show. Users live in the root
/// `/users` collection, which the `companies/{id}/{document=**}` grant cannot
/// reach, so the query was denied and — with no error path — rendered as a
/// permanent spinner. It needs the platform-admin branch on `/users` in
/// firestore.rules to return anything at all.
class GlobalUsersSection extends StatefulWidget {
  const GlobalUsersSection({super.key});

  @override
  State<GlobalUsersSection> createState() => _GlobalUsersSectionState();
}

class _GlobalUsersSectionState extends State<GlobalUsersSection> {
  String _query = '';
  String? _roleFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SuperAdminProvider>().startWatchingGlobalUsers();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final all = provider.globalUsers;

    final roles =
        all
            .map((u) => (u['role'] as String? ?? '').trim())
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final q = _query.toLowerCase();
    final visible = all.where((u) {
      if (_roleFilter != null && u['role'] != _roleFilter) return false;
      if (q.isEmpty) return true;
      return [
        u['name'],
        u['email'],
        u['id'],
        u['uid'],
        u['companyName'],
        u['companyId'],
      ].any((v) => (v as String? ?? '').toLowerCase().contains(q));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context),
            12,
            Responsive.horizontalPadding(context),
            0,
          ),
          child: AdminSearchBar<String?, void>(
            hintText: 'Search by name, email, uid, or workspace',
            onChanged: (v) => setState(() => _query = v),
            selectedFilter: _roleFilter,
            onFilterChanged: (v) =>
                setState(() => _roleFilter = v == _roleFilter ? null : v),
            filters: [
              AdminFilter(value: null, label: 'All', count: all.length),
              for (final role in roles)
                AdminFilter(
                  value: role,
                  label: role.toUpperCase(),
                  count: all.where((u) => u['role'] == role).length,
                ),
            ],
            trailing: [
              IconButton(
                tooltip: 'Copy visible rows',
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: () => copyRowsAsTsv(
                  context,
                  headers: const [
                    'Name',
                    'Email',
                    'Uid',
                    'Role',
                    'Workspace',
                    'Workspace id',
                  ],
                  rows: [
                    for (final u in visible)
                      [
                        u['name']?.toString() ?? '',
                        u['email']?.toString() ?? '',
                        u['id']?.toString() ?? '',
                        u['role']?.toString() ?? '',
                        u['companyName']?.toString() ?? '',
                        u['companyId']?.toString() ?? '',
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // The list is capped, so say so rather than letting it read as the
        // whole platform — several health checks depend on knowing this.
        if (provider.globalUsersTruncated)
          Padding(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              10,
              Responsive.horizontalPadding(context),
              0,
            ),
            child: GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppTheme.infoColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Showing the ${SuperAdminProvider.globalUsersLimit} most '
                      'recent users. Older accounts are not listed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ConsoleListState(
            isLoading: provider.globalUsersLoading,
            error: provider.globalUsersError,
            isEmpty: visible.isEmpty,
            emptyIcon: Icons.people_outline_rounded,
            emptyTitle: all.isEmpty ? 'No users found' : 'Nothing matches',
            emptySubtitle: all.isEmpty
                ? 'No user documents were returned. If workspaces exist, check '
                      'that the platform-admin read rule on /users is deployed.'
                : 'Try a different search or role.',
            onRetry: provider.retryGlobalUsers,
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                12,
                Responsive.horizontalPadding(context),
                32,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final u = visible[i];
                final name = (u['name'] as String? ?? '').trim();
                final display = name.isEmpty ? 'Unnamed user' : name;
                final email = u['email'] as String? ?? '';
                final workspace = u['companyName'] as String? ?? '—';
                final role = (u['role'] as String? ?? '').toUpperCase();
                final memberships = u['companyMemberships'];
                final extra = memberships is List && memberships.length > 1
                    ? ' · ${memberships.length} workspaces'
                    : '';

                return ConsoleDocTile(
                  index: i,
                  data: u,
                  icon: Icons.person_rounded,
                  iconColor: AppTheme.indigoColor,
                  title: display,
                  subtitle: '$email\n$workspace$extra',
                  sheetTitle: display,
                  trailing: role.isEmpty
                      ? null
                      : ConsoleBadge(
                          label: role,
                          color: AppTheme.accentColor,
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
