import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/budget_variance_service.dart';
import '../../utils/currency.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';

/// One budget against what actually happened.
class BudgetDetailScreen extends StatefulWidget {
  const BudgetDetailScreen({super.key, required this.budgetId});

  final String budgetId;

  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isEmpty) return;
      context.read<BudgetProvider>().initialize(companyId: companyId);
      context.read<ExpenseProvider>().initialize(companyId: companyId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewBudgets,
      featureName: 'Budgets',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<BudgetProvider>();
    final budget = provider.byId(widget.budgetId);
    final symbol = Money.symbolOf(context);

    if (budget == null) {
      return AppScreenScaffold(
        icon: Icons.donut_small_rounded,
        title: 'Budget',
        iconColor: AppTheme.successColor,
        isLoading: provider.isLoading,
        body: const NotFoundState(
          icon: Icons.donut_small_rounded,
          title: 'Budget not found',
          message: 'It may have been deleted since this link was opened.',
        ),
      );
    }

    final report = provider.varianceFor(
      budget: budget,
      invoices: context.watch<BillingProvider>().invoices,
      purchaseOrders: context.watch<PurchaseOrderProvider>().orders,
      expenses: context.watch<ExpenseProvider>().expenses,
    );
    final canManage = context.select<AuthProvider, bool>(
      (a) => a.currentUser?.hasPermission(AppPermissions.manageBudgets) ?? false,
    );

    return AppScreenScaffold(
      icon: Icons.donut_small_rounded,
      title: budget.name.isEmpty ? budget.periodLabel : budget.name,
      subtitle:
          '${budget.periodLabel} · ${(report.elapsedShare * 100).round()}% elapsed',
      iconColor: AppTheme.successColor,
      actions: [
        if (canManage)
          IconButton(
            tooltip: 'Edit',
            onPressed: () =>
                context.pushAppRoute(AppRoutes.budgetEditor, extra: budget),
            icon: const Icon(Icons.edit_rounded),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Net planned',
                  value: Money.compactWithSymbol(symbol, report.plannedNet),
                  icon: Icons.flag_rounded,
                  color: AppTheme.infoColor,
                  dense: true,
                  index: 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Net actual',
                  value: Money.compactWithSymbol(symbol, report.actualNet),
                  icon: report.netVariance >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: report.netVariance >= 0
                      ? AppTheme.successColor
                      : AppTheme.dangerColor,
                  caption:
                      '${report.netVariance >= 0 ? '+' : ''}'
                      '${Money.compactWithSymbol(symbol, report.netVariance)} vs plan',
                  dense: true,
                  index: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (report.hasProblems)
            GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: report.overBudget.isNotEmpty
                        ? AppTheme.dangerColor
                        : AppTheme.warningColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        if (report.overBudget.isNotEmpty)
                          '${report.overBudget.length} line(s) over budget',
                        if (report.aheadOfPace.isNotEmpty)
                          '${report.aheadOfPace.length} spending faster than the period is passing',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          for (final line in report.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LineCard(
                line: line,
                symbol: symbol,
                elapsed: report.elapsedShare,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Pace matters as much as the total: a line 60% spent is fine in '
            'month eight of a year and a problem in month two, so the bar '
            'shows where the period has got to as well as where the money has.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSec(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.symbol,
    required this.elapsed,
  });

  final BudgetLineVariance line;
  final String symbol;
  final double elapsed;

  @override
  Widget build(BuildContext context) {
    final usage = line.usage;
    final color = line.isOverBudget
        ? AppTheme.dangerColor
        : (line.isAheadOfPace || line.isBehindTarget
              ? AppTheme.warningColor
              : AppTheme.successColor);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.line.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${line.variance >= 0 ? '+' : ''}'
                  '${Money.withSymbol(symbol, line.variance)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: line.variance >= 0
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${Money.withSymbol(symbol, line.actual)} of '
              '${Money.withSymbol(symbol, line.budget)}'
              '${usage == null ? '' : ' · ${(usage * 100).round()}%'}',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
              ),
            ),
            const SizedBox(height: 8),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: usage == null ? 0 : (usage > 1 ? 1 : usage),
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                // The pace marker: where an evenly spread budget would be today.
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: elapsed.clamp(0.0, 1.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 2,
                        height: 10,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (line.isOverBudget || line.isAheadOfPace || line.isBehindTarget)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  line.isOverBudget
                      ? 'Over budget'
                      : (line.isAheadOfPace
                            ? 'Ahead of pace by '
                                  '${(line.paceGap * 100).round()}% of the budget'
                            : 'Behind target by '
                                  '${(line.paceGap * 100).round()}% of the budget'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
