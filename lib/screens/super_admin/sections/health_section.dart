import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../models/company_model.dart';
import '../../../providers/super_admin_provider.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/glass_panel.dart';
import '../console_widgets.dart';

/// Data-integrity checks across the estate.
///
/// Everything here is computed from the company list and the global user list
/// already in memory — no extra reads — so it is cheap enough to leave running.
class HealthSection extends StatefulWidget {
  const HealthSection({super.key});

  @override
  State<HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<HealthSection> {
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
    final companies = provider.companies;
    final users = provider.globalUsers;
    final companyIds = companies.map((c) => c.id).toSet();
    final loading = provider.isLoading || provider.globalUsersLoading;
    // Two checks are only sound against the *whole* user list. Past the cap,
    // "this owner has no user document" really means "their document is on a
    // page we never read", so the check is withheld rather than guessed at.
    final usersComplete = !provider.globalUsersTruncated;

    // A user whose companyId names a workspace that no longer exists. They
    // reach a shell bound to nothing, which reads as an app that will not load.
    final orphaned = users.where((u) {
      final companyId = (u['companyId'] as String? ?? '').trim();
      return companyId.isNotEmpty && !companyIds.contains(companyId);
    }).toList();

    // Users with no companyId at all — a registration that never completed.
    final unbound = users
        .where((u) => (u['companyId'] as String? ?? '').trim().isEmpty)
        .toList();

    // Two workspaces advertising the same join code: whoever redeems it lands
    // in whichever one joinCodeIndex happens to point at.
    final byCode = <String, List<CompanyModel>>{};
    for (final c in companies) {
      final code = c.permanentJoinCode.trim();
      if (code.isEmpty) continue;
      byCode.putIfAbsent(code, () => []).add(c);
    }
    final duplicateCodes = byCode.entries
        .where((e) => e.value.length > 1)
        .toList();

    final softDeleted = companies.where((c) => c.isDeleted).toList();

    // A workspace whose owner has no user document at all.
    final userIds = users.map((u) => u['id'] as String? ?? '').toSet();
    final ownerless = (users.isEmpty || !usersComplete)
        ? <CompanyModel>[]
        : companies
              .where(
                (c) =>
                    c.adminUid.isNotEmpty && !userIds.contains(c.adminUid),
              )
              .toList();

    // Everything below reads as a clean bill of health when the lists are
    // simply empty, so say "still checking" until they have arrived.
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        16,
        Responsive.horizontalPadding(context),
        32,
      ),
      children: [
        if (provider.globalUsersError != null)
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.warningColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'User checks are unavailable: ${provider.globalUsersError}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const ConsoleSectionTitle(
          title: 'Integrity checks',
          icon: Icons.rule_rounded,
          color: AppTheme.warningColor,
        ),
        _Check(
          title: 'Orphaned users',
          detail:
              'Their companyId points at a workspace that no longer exists, so '
              'the app loads into nothing.',
          items: [
            for (final u in orphaned)
              '${u['email'] ?? u['id']} → ${u['companyId']}',
          ],
        ),
        _Check(
          title: 'Users with no workspace',
          detail: 'Registration never bound them to a company.',
          items: [for (final u in unbound) '${u['email'] ?? u['id']}'],
        ),
        _Check(
          title: 'Duplicate join codes',
          detail:
              'Two workspaces share a code. Whoever redeems it lands in only '
              'one of them.',
          items: [
            for (final entry in duplicateCodes)
              '${entry.key}: ${entry.value.map((c) => c.displayName).join(', ')}',
          ],
        ),
        _Check(
          title: 'Owner has no user document',
          detail:
              'The workspace names an adminUid with no matching user, so no '
              'one can administer it.',
          items: [for (final c in ownerless) '${c.displayName} (${c.adminUid})'],
          unavailable: !usersComplete,
          unavailableReason:
              'Unavailable: the user list is capped at '
              '${SuperAdminProvider.globalUsersLimit}, so an owner outside that '
              'page would be reported here in error.',
        ),
        _Check(
          title: 'Soft-deleted, still holding data',
          detail:
              'Marked deleted but not purged. Restore them or purge them for '
              'good from the workspace danger zone.',
          items: [for (final c in softDeleted) c.displayName],
        ),
        const ConsoleSectionTitle(
          title: 'Coverage',
          icon: Icons.query_stats_rounded,
          color: AppTheme.infoColor,
        ),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Counts loaded for ${provider.statsLoadedCount} of '
                '${companies.length} workspaces. '
                '${users.length} user documents visible.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                // reloadAllStats, not loadAllStats: the latter skips anything
                // already cached, which made this button inert.
                onPressed: provider.reloadAllStats,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh all counts'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.title,
    required this.detail,
    required this.items,
    this.unavailable = false,
    this.unavailableReason,
  });

  final String title;
  final String detail;
  final List<String> items;

  /// True when the check could not be run soundly — reported as unknown rather
  /// than as a pass, which would be a false all-clear.
  final bool unavailable;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final clean = items.isEmpty;
    final color = unavailable
        ? AppTheme.textSec(context)
        : (clean ? AppTheme.successColor : AppTheme.warningColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              enabled: !clean && !unavailable,
              leading: Icon(
                unavailable
                    ? Icons.help_outline_rounded
                    : (clean
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded),
                color: color,
              ),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                unavailable
                    ? (unavailableReason ?? 'Check unavailable.')
                    : (clean ? 'Nothing found.' : detail),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // Badge *and* chevron: passing the badge alone as `trailing`
              // replaced the expand arrow, so nothing indicated the row opened.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConsoleBadge(
                    label: unavailable ? '—' : '${items.length}',
                    color: color,
                  ),
                  if (!clean && !unavailable)
                    const Icon(Icons.expand_more_rounded, size: 20),
                ],
              ),
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    title: SelectableText(
                      item,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
