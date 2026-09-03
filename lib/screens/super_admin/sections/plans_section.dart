import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/plan_limits.dart';
import '../../../config/theme.dart';
import '../../../models/company_model.dart';
import '../../../models/company_plan_model.dart';
import '../../../models/promo_config_model.dart';
import '../../../providers/plan_catalog_provider.dart';
import '../../../providers/promo_provider.dart';
import '../../../providers/super_admin_provider.dart';
import '../../../utils/currency.dart';
import '../../../utils/date_formats.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/animations.dart';
import '../../../widgets/glass_panel.dart';
import '../console_widgets.dart';
import '../plan_editor_dialog.dart';
import '../promo_editor_dialog.dart';
import '../tier_editor_dialog.dart';

/// Formats a platform price.
///
/// Deliberately not [Money.of], which resolves the *tenant's* configured
/// currency symbol: these are the platform's own prices, and rendering them in
/// whichever currency the admin's own workspace happens to use would be wrong
/// as well as coupling the console to a tenant provider.
String _platformPrice(num value) =>
    Money.withSymbol(AppTheme.currencySymbol, value, decimals: 0);

/// The tier catalog, the signup offer, and who is on what.
///
/// The catalog is editable here: tiers live in `plans/{id}` rather than in the
/// Dart source, so a price or a limit changes without a redeploy.
class PlansSection extends StatefulWidget {
  const PlansSection({super.key});

  @override
  State<PlansSection> createState() => _PlansSectionState();
}

class _PlansSectionState extends State<PlansSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PromoProvider>().load();
      // Idempotent — the app shell already started it, but a hot restart or a
      // late Firebase init can leave the console as the first subscriber.
      context.read<PlanCatalogProvider>().start();
    });
  }

  /// Writes the compiled tiers into Firestore the first time.
  ///
  /// Idempotent and non-destructive — [PlanCatalogService.seedIfEmpty] refuses
  /// to touch a catalog that already has documents.
  Future<void> _seed() async {
    final wrote = await context.read<PlanCatalogProvider>().seedIfEmpty();
    if (!mounted) return;
    if (wrote == null) {
      showErrorSnackBar(context, 'Could not publish the built-in tiers.');
    } else {
      showSuccessSnackBar(
        context,
        wrote
            ? 'Published the built-in tiers. They are editable now.'
            : 'The catalog already has tiers — nothing was overwritten.',
      );
    }
  }

  int _workspacesOn(String planId) => context
      .read<SuperAdminProvider>()
      .companies
      .where((c) => c.plan.planId == planId)
      .length;

  Future<void> _editTier(PlanDefinition? plan) async {
    final saved = await showTierEditor(
      context,
      plan: plan,
      workspacesOnPlan: plan == null ? 0 : _workspacesOn(plan.id),
    );
    // The catalog stream repaints the list on its own; this is only the
    // confirmation that the write landed.
    if (saved && mounted) {
      showSuccessSnackBar(context, plan == null ? 'Tier created' : 'Tier saved');
    }
  }

  Future<void> _deleteTier(PlanDefinition plan) async {
    final onPlan = _workspacesOn(plan.id);
    // Captured before the confirmation dialog: reading it afterwards is a
    // context lookup across an async gap.
    final catalog = context.read<PlanCatalogProvider>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${plan.label}?',
      message: onPlan == 0
          ? 'No workspace is on this tier. It will disappear from the catalog.'
          : '$onPlan workspace${onPlan == 1 ? '' : 's'} still reference this '
                'tier. Deleting it silently promotes them to '
                '${PlanCatalog.maxTier.label}, because an unknown plan id falls '
                'back to the default. Archive it instead unless you mean that.',
      confirmLabel: 'Delete tier',
    );
    if (!confirmed) return;
    final ok = await catalog.deletePlan(plan.id);
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Tier deleted');
    } else {
      showErrorSnackBar(context, 'Could not delete the tier.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final companies = provider.companies;
    final promo = context.watch<PromoProvider>().config ?? const PromoConfig();
    // Watched, not read: this is what makes a tier edit repaint the catalog.
    final catalog = context.watch<PlanCatalogProvider>();
    final pad = Responsive.horizontalPadding(context);

    final needsAttention = companies
        .where(
          (c) =>
              c.plan.status != PlanStatus.active ||
              c.plan.trialExpired ||
              _isOverLimit(provider, c),
        )
        .toList();

    // Slivers rather than a ListView of eagerly-built children: the previous
    // version laid out a row per company (twice, counting the attention list)
    // on every rebuild.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const ConsoleSectionTitle(
                title: 'Signup offer',
                icon: Icons.campaign_rounded,
                color: AppTheme.primaryColor,
              ),
              _PromoCard(promo: promo),
              ConsoleSectionTitle(
                title: 'Tier catalog',
                icon: Icons.sell_rounded,
                color: AppTheme.violetColor,
                // Icon-only on a phone: the two labelled buttons needed ~180px
                // more than the header row has at 360dp.
                trailing: Responsive.isMobile(context)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Publish the built-in tiers',
                            onPressed: catalog.busy ? null : _seed,
                            icon: const Icon(
                              Icons.cloud_upload_rounded,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: 'New tier',
                            onPressed: () => _editTier(null),
                            icon: const Icon(Icons.add_rounded, size: 20),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: catalog.busy ? null : _seed,
                            icon: const Icon(
                              Icons.cloud_upload_rounded,
                              size: 18,
                            ),
                            label: const Text('Publish built-ins'),
                          ),
                          const SizedBox(width: 4),
                          FilledButton.icon(
                            onPressed: () => _editTier(null),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('New tier'),
                          ),
                        ],
                      ),
              ),
              if (catalog.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassPanel(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: AppTheme.warningColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${catalog.error!} Showing the tiers built into '
                            'this build — edits will not stick.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (var i = 0; i < catalog.plans.length; i++)
                _TierCard(
                  index: i,
                  plan: catalog.plans[i],
                  workspaces: companies
                      .where((c) => c.plan.planId == catalog.plans[i].id)
                      .length,
                  onEdit: () => _editTier(catalog.plans[i]),
                  onDelete: () => _deleteTier(catalog.plans[i]),
                ),
              ConsoleSectionTitle(
                title: 'Needs a billing decision',
                icon: Icons.report_problem_rounded,
                color: AppTheme.warningColor,
                trailing: Text(
                  '${needsAttention.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Says "still loading" rather than "all clear" while the company
              // list is empty — a green all-clear on no data is worse than
              // silence.
              if (provider.isLoading && companies.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.errorMessage != null && companies.isEmpty)
                GlassPanel(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    provider.errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else if (needsAttention.isEmpty)
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
                          'Every workspace is on an active plan and inside its '
                          'limits.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
        if (needsAttention.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverList.builder(
              itemCount: needsAttention.length,
              itemBuilder: (context, i) =>
                  _PlanRow(company: needsAttention[i], provider: provider),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverToBoxAdapter(
            child: ConsoleSectionTitle(
              title: 'All workspaces',
              icon: Icons.list_alt_rounded,
              trailing: Text(
                '${companies.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
          sliver: SliverList.builder(
            itemCount: companies.length,
            itemBuilder: (context, i) =>
                _PlanRow(company: companies[i], provider: provider),
          ),
        ),
      ],
    );
  }

  static bool _isOverLimit(SuperAdminProvider provider, CompanyModel company) {
    if (provider.statsFailedFor(company.id)) return false;
    final stats = provider.statsFor(company.id);
    if (stats == null) return false;
    return PlanLimits.checkAll(
      company.plan,
      planUsageOf(stats),
    ).any((r) => r.isBlocked);
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo});

  final PromoConfig promo;

  @override
  Widget build(BuildContext context) {
    final progress = promo.progress;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        border: Border.all(
          color: promo.enabled
              ? AppTheme.primaryColor.withValues(alpha: 0.35)
              : AppTheme.dividerC(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: promo.enabled ? AppTheme.primaryGradient : null,
                    color: promo.enabled
                        ? null
                        : AppTheme.dividerC(context).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: promo.enabled
                        ? AppTheme.onGradient
                        : AppTheme.iconMute(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    promo.activeHeadline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ConsoleBadge(
                  label: promo.enabled ? 'LIVE' : 'OFF',
                  color: promo.enabled
                      ? AppTheme.successColor
                      : AppTheme.textSec(context),
                ),
                IconButton(
                  tooltip: 'Edit the offer',
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () => showPromoEditor(context, promo),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              promo.activeSubtext,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              ConsoleMeter(
                label: 'Cohort claimed',
                valueText: '${promo.claimedCount} / ${promo.capCount}',
                fraction: progress,
                color: promo.isFull
                    ? AppTheme.warningColor
                    : AppTheme.primaryColor,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Advisory count — synced from the workspace total, not enforced '
              'at signup.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textTer(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tier, rendered as a pricing card.
///
/// Each tier gets a stable accent colour derived from its position, so the
/// catalog reads as a ladder rather than a list of identical grey panels.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.plan,
    required this.workspaces,
    required this.onEdit,
    required this.onDelete,
    required this.index,
  });

  final PlanDefinition plan;
  final int workspaces;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int index;

  static const List<Color> _accents = [
    AppTheme.infoColor,
    AppTheme.indigoColor,
    AppTheme.violetColor,
    AppTheme.primaryColor,
  ];

  @override
  Widget build(BuildContext context) {
    final isDefault = plan.id == PlanCatalog.defaultId;
    final accent = _accents[index % _accents.length];
    final muted = plan.archived;

    return FadeSlideIn(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Opacity(
          // Archived tiers stay visible — workspaces may still be on them —
          // but recede so the live ladder reads first.
          opacity: muted ? 0.6 : 1,
          child: GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Accent header carrying the name and the price together, so
                // the two things someone compares sit on one line.
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.20),
                        accent.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (plan.nominalPrice != null)
                              Text(
                                plan.promotionalPrice == 0
                                    ? '${_platformPrice(plan.nominalPrice!)} / mo · free now'
                                    : '${_platformPrice(plan.nominalPrice!)} / mo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit tier',
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        onPressed: onEdit,
                      ),
                      IconButton(
                        tooltip: isDefault
                            ? 'The default tier cannot be deleted'
                            : 'Delete tier',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        // The fallback for every plan-less company doc —
                        // deleting it would leave byId pointing at nothing.
                        onPressed: isDefault ? null : onDelete,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isDefault)
                            const ConsoleBadge(
                              label: 'DEFAULT',
                              color: AppTheme.successColor,
                            ),
                          if (plan.archived)
                            ConsoleBadge(
                              label: 'ARCHIVED',
                              color: AppTheme.textSec(context),
                            ),
                          ConsoleBadge(
                            label:
                                '$workspaces workspace${workspaces == 1 ? '' : 's'}',
                            color: accent,
                          ),
                        ],
                      ),
                      if (plan.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          plan.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (plan.limits.isEmpty)
                        Row(
                          children: [
                            const Icon(
                              Icons.all_inclusive_rounded,
                              size: 16,
                              color: AppTheme.successColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'No limits',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.successColor,
                                  ),
                            ),
                          ],
                        )
                      else
                        // A grid of caps rather than a badge soup: these are
                        // the numbers someone actually compares between tiers.
                        Wrap(
                          spacing: 18,
                          runSpacing: 10,
                          children: [
                            for (final entry in plan.limits.entries)
                              _LimitStat(
                                label: PlanLimitKeys.labelOf(entry.key),
                                value: entry.value,
                              ),
                          ],
                        ),
                      if (plan.lockedFeatures.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final feature in plan.lockedFeatures)
                              ConsoleBadge(
                                label: 'No $feature',
                                color: AppTheme.dangerColor,
                              ),
                          ],
                        ),
                      ],
                    ],
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

class _LimitStat extends StatelessWidget {
  const _LimitStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.company, required this.provider});

  final CompanyModel company;
  final SuperAdminProvider provider;

  @override
  Widget build(BuildContext context) {
    final plan = company.plan;
    final failed = provider.statsFailedFor(company.id);
    final stats = failed ? null : provider.statsFor(company.id);
    final results = stats == null
        ? const <PlanLimitResult>[]
        : PlanLimits.checkAll(plan, planUsageOf(stats));
    final capped = results.where((r) => r.isCapped).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    company.displayName,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ConsoleBadge(label: plan.label, color: AppTheme.infoColor),
                const SizedBox(width: 6),
                if (plan.status != PlanStatus.active)
                  ConsoleBadge(
                    label: CompanyPlan.statusLabel(plan.status),
                    color: AppTheme.dangerColor,
                  ),
                IconButton(
                  tooltip: 'Change plan',
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () => showPlanEditor(context, company),
                ),
              ],
            ),
            if (plan.trialEndsAt != null)
              Text(
                plan.trialExpired
                    ? 'Trial ended ${AppDates.day.format(plan.trialEndsAt!)}'
                    : 'Trial ends ${AppDates.day.format(plan.trialEndsAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: plan.trialExpired
                      ? AppTheme.warningColor
                      : AppTheme.textSec(context),
                ),
              ),
            if (plan.note.isNotEmpty)
              Text(
                plan.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSec(context),
                ),
              ),
            if (capped.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  stats == null
                      ? (failed
                            ? 'Counts could not be read.'
                            : 'Counts still loading.')
                      : 'No caps on this tier.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSec(context),
                  ),
                ),
              )
            else
              for (final result in capped)
                ConsoleMeter(
                  label: result.label,
                  valueText: result.usageText,
                  fraction: result.fraction,
                  color: switch (result.state) {
                    PlanLimitState.blocked => AppTheme.dangerColor,
                    PlanLimitState.warning => AppTheme.warningColor,
                    PlanLimitState.ok => AppTheme.successColor,
                  },
                ),
          ],
        ),
      ),
    );
  }
}
