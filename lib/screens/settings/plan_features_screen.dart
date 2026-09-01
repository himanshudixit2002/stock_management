import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/feature_access.dart';
import '../../config/feature_map.dart';
import '../../config/theme.dart';
import '../../models/company_plan_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/date_formats.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';

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
    final plan = settings.plan;

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
        .where((e) => resolveFeatureAccess(e, permissions, gates) == FeatureAccess.available)
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
  });

  final CompanyPlan plan;
  final int available;
  final int total;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.infoColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppTheme.infoColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan.label} plan',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        plan.definition.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!plan.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Attention',
                      style: TextStyle(
                        color: AppTheme.warningColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Features you can use',
                    value: '$available of $total',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Since',
                    value: plan.startedAt != null
                        ? AppDates.day.format(plan.startedAt!)
                        : '—',
                  ),
                ),
              ],
            ),
            // The free plan applies no caps, so say so plainly rather than
            // leaving people to wonder what they are up against.
            if (plan.definition.limits.isEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.all_inclusive_rounded,
                    size: 16,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No limits on products, orders, invoices or users.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ] else
              ...plan.definition.limits.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        e.key,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${e.value}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (plan.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(plan.note, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
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
  });

  final FeatureCategory category;
  final List<FeatureEntry> entries;
  final Map<String, bool> permissions;
  final FeatureGateState gates;

  @override
  Widget build(BuildContext context) {
    final meta = FeatureMap.categoryMeta[category];
    final color = FeatureMap.categoryColor(category);
    final usable = entries
        .where((e) => resolveFeatureAccess(e, permissions, gates) == FeatureAccess.available)
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
                    access: resolveFeatureAccess(e, permissions, gates),
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
                : (access == FeatureAccess.featureOff
                      ? Icons.toggle_off_rounded
                      : Icons.lock_outline_rounded),
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
