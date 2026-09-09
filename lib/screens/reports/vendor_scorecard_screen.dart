import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../services/vendor_scorecard_service.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';

/// Which suppliers deliver on time, in full, at the price they quoted.
class VendorScorecardScreen extends StatefulWidget {
  const VendorScorecardScreen({super.key});

  @override
  State<VendorScorecardScreen> createState() => _VendorScorecardScreenState();
}

class _VendorScorecardScreenState extends State<VendorScorecardScreen> {
  int _windowDays = VendorScorecardService.defaultWindowDays;

  static const Map<int, String> _windows = {
    90: '90 days',
    180: '6 months',
    365: '1 year',
    730: '2 years',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isEmpty) return;
      context.read<VendorProvider>().initialize(companyId: companyId);
      context.read<PurchaseOrderProvider>().initialize(companyId: companyId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewVendorScorecard,
      featureName: 'Vendor Scorecard',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final vendors = context.watch<VendorProvider>().vendors;
    final orders = context.watch<PurchaseOrderProvider>().orders;
    final symbol = Money.symbolOf(context);

    final card = VendorScorecardService.analyse(
      vendors: vendors,
      orders: orders,
      windowDays: _windowDays,
    );
    final best = card.best;

    return AppScreenScaffold(
      icon: Icons.grading_rounded,
      title: 'Vendor Scorecard',
      subtitle: '${card.ordersConsidered} orders in the window',
      iconColor: AppTheme.warningColor,
      isEmpty: card.scores.isEmpty,
      emptyState: const EmptyStateWidget(
        icon: Icons.grading_rounded,
        title: 'No purchase history yet',
        subtitle:
            'Every fact needed to grade a supplier is recorded when an order '
            'is raised and received. Once a few orders have landed, they are '
            'ranked here.',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Spend',
                  value: Money.compactWithSymbol(symbol, card.totalSpend),
                  icon: Icons.payments_rounded,
                  color: AppTheme.warningColor,
                  caption: '${card.scores.length} suppliers',
                  dense: true,
                  index: 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Best rated',
                  value: best == null ? '—' : best.grade,
                  icon: Icons.emoji_events_rounded,
                  color: AppTheme.successColor,
                  caption: best?.vendorName,
                  dense: true,
                  index: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _windows.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _windowDays == entry.key,
                      onSelected: (_) =>
                          setState(() => _windowDays = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A supplier is graded once ${VendorScorecardService.minimumOrdersToRate} '
            'of their orders have been received. On-time delivery is worth the '
            'most, then fill rate, then price stability.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSec(context),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < card.scores.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedListItem(
                index: i,
                child: _ScoreCard(score: card.scores[i], symbol: symbol),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score, required this.symbol});

  final VendorScore score;
  final String symbol;

  Color get _color {
    final value = score.score;
    if (value == null) return AppTheme.textMuted;
    if (value >= 85) return AppTheme.successColor;
    if (value >= 70) return AppTheme.infoColor;
    if (value >= 55) return AppTheme.warningColor;
    return AppTheme.dangerColor;
  }

  @override
  Widget build(BuildContext context) {
    final variance = score.leadTimeVariance;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    score.grade,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        score.vendorName.isEmpty
                            ? 'Unnamed vendor'
                            : score.vendorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        score.isRated
                            ? '${score.score!.round()} / 100 · '
                                  '${score.completedCount} received'
                            : 'Not enough received orders to grade',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  Money.compactWithSymbol(symbol, score.totalSpend),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'On time',
                    value: score.onTimeCount + score.lateCount == 0
                        ? '—'
                        : '${(score.onTimeRate * 100).round()}%',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Fill rate',
                    value: score.orderedUnits == 0
                        ? '—'
                        : '${(score.fillRate * 100).round()}%',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Lead time',
                    value: score.averageLeadTimeDays == null
                        ? '—'
                        : '${score.averageLeadTimeDays!.round()}d',
                    caption: variance == null
                        ? null
                        : (variance > 0
                              ? '+${variance.round()}d vs promise'
                              : '${variance.round()}d vs promise'),
                    warn: variance != null && variance > 1,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Prices',
                    value: score.priceTrendPercent == 0
                        ? 'flat'
                        : '${score.priceTrendPercent > 0 ? '+' : ''}'
                              '${score.priceTrendPercent.toStringAsFixed(1)}%',
                    warn: score.priceTrendPercent > 5,
                  ),
                ),
              ],
            ),
            if (score.openCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${score.openCount} order(s) still open with this supplier',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.caption,
    this.warn = false,
  });

  final String label;
  final String value;
  final String? caption;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: warn ? AppTheme.warningColor : null,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
        ),
        if (caption != null)
          Text(
            caption!,
            style: TextStyle(
              fontSize: 10,
              color: warn ? AppTheme.warningColor : AppTheme.textSec(context),
            ),
          ),
      ],
    );
  }
}
