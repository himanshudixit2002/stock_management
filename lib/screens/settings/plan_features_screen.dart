import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/currency.dart';
import '../../config/feature_access.dart';
import '../../config/feature_map.dart';
import '../../config/theme.dart';
import '../../models/company_plan_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/plan_catalog_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/date_formats.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';

/// Formats a plan price.
///
/// Deliberately the platform's own currency rather than the tenant's configured
/// one — these are what SmartShelfKart charges, not amounts in the customer's
/// books. Routed through Money so it gets thousands grouping, which raw string
/// interpolation did not.
String _platformPrice(num value) =>
    Money.withSymbol(AppTheme.currencySymbol, value, decimals: 0);

/// What this workspace is on, and exactly which features this user can reach.
///
/// The feature list is derived from [FeatureMap] rather than written out by
/// hand, so it cannot drift from what the app actually offers. Anything the
/// user cannot reach says *why* — whether to ask an admin for permission or to
/// switch a company feature on — because a greyed row with no explanation just
/// prompts a support message.
class PlanFeaturesScreen extends StatelessWidget {
  const PlanFeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final settings = context.watch<SettingsProvider>();
    final billingOn = context.select<BillingSettingsProvider, bool>(
      (b) => b.billingEnabled,
    );

    final permissions = user?.effectivePermissions ?? const <String, bool>{};
    // Watched so a tier the platform admin re-prices or re-caps is reflected
    // here without the tenant restarting the app.
    context.watch<PlanCatalogProvider>();
    final plan = settings.plan;
    final productCount = context.select<ProductProvider, int>(
      (p) => p.totalProducts,
    );

    final gates = FeatureGateState(
      billing: billingOn,
      barcode: settings.barcodeEnabled,
      vendors: settings.vendorsEnabled,
      pricing: settings.pricingEnabled,
    );

    // Every catalogued feature, grouped by category in the app's own order.
    final grouped = <FeatureCategory, List<FeatureEntry>>{};
    for (final entry in FeatureMap.all) {
      grouped.putIfAbsent(entry.category, () => []).add(entry);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.label.compareTo(b.label));
    }

    final available = FeatureMap.all
        .where((e) => resolveFeatureAccess(e, permissions, gates, plan: plan) == FeatureAccess.available)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.workspace_premium_rounded,
          color: AppTheme.infoColor,
          title: 'Plan & Features',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PlanCard(
              plan: plan,
              productCount: productCount,
              available: available,
              total: FeatureMap.all.length,
            ),
            const SizedBox(height: 16),
            Text(
              'Features',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Everything this app offers, and what you can reach today.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final category in FeatureCategory.values)
              if (grouped[category] != null)
                _CategoryBlock(
                  category: category,
                  entries: grouped[category]!,
                  permissions: permissions,
                  gates: gates,
                  plan: plan,
                ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.available,
    required this.total,
    required this.productCount,
  });

  final CompanyPlan plan;
  final int available;
  final int total;

  /// Products currently in this workspace, or null if not loaded yet. Shown
  /// against the cap so a limit is visible before it bites.
  final int? productCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDeco(context).copyWith(
        gradient: AppTheme.heroGrad(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onGradient,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.definition.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onGradient.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (plan.definition.nominalPrice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, right: 8),
                    child: Text(
                      '${_platformPrice(plan.definition.nominalPrice!)}/mo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.onGradient.withValues(alpha: 0.6),
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppTheme.onGradient.withValues(alpha: 0.6),
                        decorationThickness: 2.0,
                      ),
                    ),
                  ),
                if (plan.definition.promotionalPrice == 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppTheme.coloredShadow(Colors.black.withValues(alpha: 0.1)),
                    ),
                    child: const Text(
                      'FREE FOREVER',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                else if (plan.definition.promotionalPrice != null)
                   Text(
                      '${_platformPrice(plan.definition.promotionalPrice!)}/mo',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.onGradient,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Features unlocked',
                    value: '$available of $total',
                    color: AppTheme.onGradient,
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Active since',
                    value: plan.startedAt != null
                        ? AppDates.day.format(plan.startedAt!)
                        : '—',
                    color: AppTheme.onGradient,
                  ),
                ),
              ],
            ),
            if (plan.effectiveLimits.isEmpty) ...[
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.all_inclusive_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No limits on products, orders, invoices, users, or AI capabilities.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.onGradient,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              // effectiveLimits, not the tier's own: a per-workspace override
              // is the number that actually applies, and showing the tier value
              // would tell someone with extra headroom the wrong figure.
              ...plan.effectiveLimits.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          PlanLimitKeys.labelOf(e.key),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.onGradient.withValues(alpha: 0.9)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        e.key == PlanLimitKeys.products && productCount != null
                            ? '$productCount / ${e.value}'
                            : '${e.value}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onGradient,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (plan.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(plan.note, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.onGradient.withValues(alpha: 0.8))),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color?.withValues(alpha: 0.8))),
      ],
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.category,
    required this.entries,
    required this.permissions,
    required this.gates,
    required this.plan,
  });

  final FeatureCategory category;
  final List<FeatureEntry> entries;
  final Map<String, bool> permissions;
  final FeatureGateState gates;
  final CompanyPlan plan;

  @override
  Widget build(BuildContext context) {
    final meta = FeatureMap.categoryMeta[category];
    final color = FeatureMap.categoryColor(category);
    final usable = entries
        .where((e) => resolveFeatureAccess(e, permissions, gates, plan: plan) == FeatureAccess.available)
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        child: Theme(
          // The default divider on an expansion tile fights the panel border.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            leading: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                meta?.icon ?? Icons.widgets_rounded,
                color: color,
                size: 18,
              ),
            ),
            title: Text(
              meta?.title ?? category.name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              '$usable of ${entries.length} available',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: entries
                .map(
                  (e) => _FeatureRow(
                    entry: e,
                    access: resolveFeatureAccess(e, permissions, gates, plan: plan),
                    gates: gates,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.entry,
    required this.access,
    required this.gates,
  });

  final FeatureEntry entry;
  final FeatureAccess access;
  final FeatureGateState gates;

  @override
  Widget build(BuildContext context) {
    final available = access == FeatureAccess.available;

    // Name the specific switch that is off, so the fix is obvious.
    final offGate = gates
        .blockedGatesFor(entry)
        .map(FeatureGateState.labelOf)
        .join(', ');

    final reason = switch (access) {
      FeatureAccess.available => null,
      FeatureAccess.needsPermission => 'Ask an admin for access',
      FeatureAccess.featureOff => '$offGate is switched off for this workspace',
      FeatureAccess.needsPlan =>
        'Not included in your plan — ask your platform administrator to '
            'upgrade this workspace',
    };

    final muted = Theme.of(context).textTheme.bodySmall?.color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            available
                ? Icons.check_circle_rounded
                : switch (access) {
                    FeatureAccess.featureOff => Icons.toggle_off_rounded,
                    FeatureAccess.needsPlan =>
                      Icons.workspace_premium_outlined,
                    _ => Icons.lock_outline_rounded,
                  },
            size: 18,
            color: available ? AppTheme.successColor : muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: available ? null : muted,
                  ),
                ),
                Text(
                  reason ?? entry.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: available ? null : FontStyle.italic,
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
