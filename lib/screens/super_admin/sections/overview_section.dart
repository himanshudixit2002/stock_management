import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/plan_limits.dart';
import '../../../config/theme.dart';
import '../../../models/company_model.dart';
import '../../../models/company_plan_model.dart';
import '../../../providers/super_admin_provider.dart';
import '../../../utils/date_formats.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/animations.dart';
import '../../../widgets/glass_panel.dart';
import '../console_widgets.dart';

/// The platform at a glance: how big the estate is, how it is distributed, and
/// what needs attention.
class OverviewSection extends StatelessWidget {
  const OverviewSection({super.key, required this.onOpenWorkspaces});

  final VoidCallback onOpenWorkspaces;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final companies = provider.companies;
    final totals = provider.totalsAcrossCompanies;
    final active = companies.where((c) => c.isActive).length;

    if (provider.isLoading && companies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final alerts = _buildAlerts(provider);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        16,
        Responsive.horizontalPadding(context),
        32,
      ),
      children: [
        FadeSlideIn(
          child: _PlatformHero(
            total: companies.length,
            totals: totals,
            loadedOf: provider.statsLoadedCount,
          ),
        ),
        if (provider.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppTheme.dangerColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      provider.clearError();
                      provider.startWatching();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        const ConsoleSectionTitle(
          title: 'Workspace status',
          icon: Icons.donut_small_rounded,
          color: AppTheme.successColor,
        ),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: _DistributionBar(
            segments: [
              _Segment('Active', active, AppTheme.successColor),
              _Segment(
                'Suspended',
                provider.suspendedCount,
                AppTheme.warningColor,
              ),
              _Segment('Deleted', provider.deletedCount, AppTheme.dangerColor),
            ],
          ),
        ),
        const ConsoleSectionTitle(
          title: 'Plan mix',
          icon: Icons.workspace_premium_rounded,
          color: AppTheme.violetColor,
        ),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: _DistributionBar(
            segments: [
              for (var i = 0; i < PlanCatalog.all.length; i++)
                _Segment(
                  PlanCatalog.all[i].label,
                  companies
                      .where((c) => c.plan.planId == PlanCatalog.all[i].id)
                      .length,
                  _planColors[i % _planColors.length],
                ),
            ],
          ),
        ),
        ConsoleSectionTitle(
          title: 'Needs attention',
          icon: Icons.notification_important_rounded,
          color: AppTheme.warningColor,
          trailing: TextButton(
            onPressed: onOpenWorkspaces,
            child: const Text('All workspaces'),
          ),
        ),
        if (alerts.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.successColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nothing to look at. Every workspace is active, inside its '
                    'plan, and has had activity recently.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < alerts.length; i++)
            FadeSlideIn(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassPanel(
                  border: Border.all(
                    color: alerts[i].color.withValues(alpha: 0.35),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: alerts[i].color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            alerts[i].icon,
                            size: 19,
                            color: alerts[i].color,
                          ),
                        ),
                        title: Text(
                          alerts[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          alerts[i].detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConsoleBadge(
                              label: '${alerts[i].count}',
                              color: alerts[i].color,
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.iconMute(context),
                            ),
                          ],
                        ),
                        onTap: onOpenWorkspaces,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        const ConsoleSectionTitle(
          title: 'Newest workspaces',
          icon: Icons.fiber_new_rounded,
          color: AppTheme.primaryColor,
        ),
        if (companies.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No workspaces yet. They appear here as soon as someone signs up.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ..._newest(companies).map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassPanel(
              child: ListTile(
                title: Text(
                  c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  c.createdAt == null
                      ? 'Created date unknown'
                      : 'Created ${AppDates.day.format(c.createdAt!)}',
                ),
                trailing: ConsoleBadge(
                  label: c.plan.label,
                  color: AppTheme.infoColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const List<Color> _planColors = [
    AppTheme.infoColor,
    AppTheme.indigoColor,
    AppTheme.violetColor,
    AppTheme.primaryColor,
  ];

  static List<CompanyModel> _newest(List<CompanyModel> companies) {
    // watchCompanies already orders by createdAt desc, so the head is newest.
    return companies.take(5).toList();
  }

  /// Alerts computed entirely from data already in memory — no extra queries.
  static List<_Alert> _buildAlerts(SuperAdminProvider provider) {
    final alerts = <_Alert>[];
    final companies = provider.companies;

    if (provider.suspendedCount > 0) {
      alerts.add(
        _Alert(
          icon: Icons.pause_circle_rounded,
          color: AppTheme.warningColor,
          title: 'Suspended workspaces',
          detail: 'These cannot write new data until reactivated.',
          count: provider.suspendedCount,
        ),
      );
    }

    final awaitingPurge = companies.where((c) => c.isDeleted).length;
    if (awaitingPurge > 0) {
      alerts.add(
        _Alert(
          icon: Icons.delete_sweep_rounded,
          color: AppTheme.dangerColor,
          title: 'Soft-deleted, awaiting purge',
          detail: 'Still holding data. Purge or restore them.',
          count: awaitingPurge,
        ),
      );
    }

    final pastDue = companies
        .where((c) => c.plan.status == PlanStatus.pastDue)
        .length;
    if (pastDue > 0) {
      alerts.add(
        _Alert(
          icon: Icons.credit_card_off_rounded,
          color: AppTheme.dangerColor,
          title: 'Plans past due',
          detail: 'Billing has lapsed on these workspaces.',
          count: pastDue,
        ),
      );
    }

    final trialsExpired = companies.where((c) => c.plan.trialExpired).length;
    if (trialsExpired > 0) {
      alerts.add(
        _Alert(
          icon: Icons.hourglass_bottom_rounded,
          color: AppTheme.warningColor,
          title: 'Trials expired',
          detail: 'The trial end date has passed with no plan change.',
          count: trialsExpired,
        ),
      );
    }

    // Over-limit needs counts, so it only reports on workspaces whose stats
    // have loaded. Reporting "0 over limit" while half the estate is unmeasured
    // would be worse than saying nothing.
    var overLimit = 0;
    for (final company in companies) {
      final stats = provider.statsFor(company.id);
      if (stats == null) continue;
      final results = PlanLimits.checkAll(company.plan, planUsageOf(stats));
      if (results.any((r) => r.isBlocked)) overLimit++;
    }
    if (overLimit > 0) {
      alerts.add(
        _Alert(
          icon: Icons.speed_rounded,
          color: AppTheme.dangerColor,
          title: 'Over their plan limit',
          detail: 'At least one cap is exhausted. Writes are being refused.',
          count: overLimit,
        ),
      );
    }

    final empty = companies.where((c) {
      final stats = provider.statsFor(c.id);
      return stats != null && stats.products == 0 && stats.invoices == 0;
    }).length;
    if (empty > 0) {
      alerts.add(
        _Alert(
          icon: Icons.inbox_rounded,
          color: AppTheme.infoColor,
          title: 'Never used',
          detail: 'Signed up but has no products and no invoices.',
          count: empty,
        ),
      );
    }

    return alerts;
  }
}

class _Alert {
  const _Alert({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final int count;
}

class _PlatformHero extends StatelessWidget {
  const _PlatformHero({
    required this.total,
    required this.totals,
    required this.loadedOf,
  });

  final int total;
  final CompanyStats totals;
  final int loadedOf;

  @override
  Widget build(BuildContext context) {
    final partial = loadedOf < total;
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.heroGrad(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.public_rounded,
                color: AppTheme.onGradient,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'Platform Estate',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.onGradient,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 26,
            runSpacing: 18,
            children: [
              _HeroStat(
                label: 'Workspaces',
                value: total,
                icon: Icons.business_rounded,
              ),
              _HeroStat(
                label: 'Users',
                value: totals.users,
                icon: Icons.people_alt_rounded,
              ),
              _HeroStat(
                label: 'Products',
                value: totals.products,
                icon: Icons.inventory_2_rounded,
              ),
              _HeroStat(
                label: 'Invoices',
                value: totals.invoices,
                icon: Icons.receipt_long_rounded,
              ),
              _HeroStat(
                label: 'Orders',
                value: totals.salesOrders + totals.purchaseOrders,
                icon: Icons.local_shipping_rounded,
              ),
            ],
          ),
          if (partial) ...[
            const SizedBox(height: 16),
            Text(
              'Counts cover $loadedOf of $total workspaces so far.',
              style: TextStyle(
                color: AppTheme.onGradient.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CountUpText(
          value.toDouble(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.onGradient,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: AppTheme.onGradient.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.onGradient.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Segment {
  const _Segment(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.segments});

  final List<_Segment> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, s) => sum + s.count);
    if (total == 0) {
      return Text(
        'Nothing to show yet.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textSec(context)),
      );
    }

    return Column(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final s in segments)
              if (s.count > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Bounded: a long tier label inside a Wrap's Row overflowed
                    // horizontally rather than wrapping.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        '${s.label} (${s.count})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final s in segments)
                  if (s.count > 0)
                    Expanded(
                      flex: s.count,
                      child: Container(color: s.color),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
