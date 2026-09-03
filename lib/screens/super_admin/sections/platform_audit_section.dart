import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../providers/super_admin_provider.dart';
import '../../../utils/responsive.dart';
import '../../../utils/date_formats.dart';
import '../../../widgets/admin_search_bar.dart';
import '../console_widgets.dart';

/// What platform admins did, across every tenant.
///
/// The per-company `auditLogs` records what a tenant did to its own data;
/// nothing recorded what someone with cross-tenant powers did to a tenant.
/// This is that record, and the rules make it append-only so it cannot be
/// tidied away by the person it describes.
class PlatformAuditSection extends StatefulWidget {
  const PlatformAuditSection({super.key});

  @override
  State<PlatformAuditSection> createState() => _PlatformAuditSectionState();
}

class _PlatformAuditSectionState extends State<PlatformAuditSection> {
  String _query = '';
  String? _actionFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SuperAdminProvider>().startWatchingPlatformAudit();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final all = provider.platformAuditLogs;

    final actions =
        all
            .map((l) => l['action'] as String? ?? '')
            .where((a) => a.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final q = _query.toLowerCase();
    final visible = all.where((l) {
      if (_actionFilter != null && l['action'] != _actionFilter) return false;
      if (q.isEmpty) return true;
      return [
        l['actorEmail'],
        l['actorUid'],
        l['targetName'],
        l['targetId'],
        l['action'],
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
            hintText: 'Search by admin, workspace, or action',
            onChanged: (v) => setState(() => _query = v),
            selectedFilter: _actionFilter,
            onFilterChanged: (v) =>
                setState(() => _actionFilter = v == _actionFilter ? null : v),
            filters: [
              AdminFilter(value: null, label: 'All', count: all.length),
              for (final action in actions)
                AdminFilter(
                  value: action,
                  label: action,
                  count: all.where((l) => l['action'] == action).length,
                ),
            ],
          ),
        ),
        Expanded(
          child: ConsoleListState(
            // An explicit flag: "no rows" is a legitimate state for this log,
            // and inferring loading from an empty list meant a platform with
            // nothing recorded yet spun forever.
            isLoading: provider.platformAuditLoading,
            error: provider.platformAuditError,
            isEmpty: visible.isEmpty,
            emptyIcon: Icons.history_rounded,
            emptyTitle: all.isEmpty ? 'Nothing recorded yet' : 'Nothing matches',
            emptySubtitle: all.isEmpty
                ? 'Plan changes, suspensions, purges and workspace inspections '
                      'are recorded here as they happen.'
                : 'Try a different search or action.',
            onRetry: provider.retryPlatformAudit,
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                12,
                Responsive.horizontalPadding(context),
                32,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final log = visible[i];
                final action = log['action'] as String? ?? 'unknown';
                final target =
                    log['targetName'] as String? ??
                    log['targetId'] as String? ??
                    '';
                final actor = log['actorEmail'] as String? ??
                    log['actorUid'] as String? ??
                    'unknown admin';
                final ts = log['timestamp'];
                final when = ts is Timestamp
                    ? AppDates.dayTime.format(ts.toDate())
                    : 'unknown time';

                return ConsoleDocTile(
                  index: i,
                  data: log,
                  icon: _iconFor(action),
                  iconColor: _colorFor(action),
                  title: '$action · $target',
                  subtitle: '$actor\n$when',
                  sheetTitle: action,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(String action) {
    if (action.startsWith('plan')) return Icons.workspace_premium_rounded;
    if (action.startsWith('inspect')) return Icons.visibility_rounded;
    if (action.contains('purge')) return Icons.delete_forever_rounded;
    if (action.contains('suspended')) return Icons.pause_circle_rounded;
    if (action.contains('deleted')) return Icons.delete_rounded;
    if (action.contains('active')) return Icons.play_circle_rounded;
    return Icons.bolt_rounded;
  }

  static Color _colorFor(String action) {
    if (action.contains('purge') || action.contains('deleted')) {
      return AppTheme.dangerColor;
    }
    if (action.contains('suspended')) return AppTheme.warningColor;
    if (action.startsWith('inspect')) return AppTheme.indigoColor;
    if (action.startsWith('plan')) return AppTheme.violetColor;
    return AppTheme.infoColor;
  }
}
