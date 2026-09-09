import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/budget_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Period budgets, and how each is tracking.
class BudgetListScreen extends StatefulWidget {
  const BudgetListScreen({super.key});

  @override
  State<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends State<BudgetListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isEmpty) return;
      context.read<BudgetProvider>().initialize(companyId: companyId);
      // Actuals come from expenses as well as invoices and orders, and the
      // expense stream is not started anywhere else on this route.
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
    final invoices = context.watch<BillingProvider>().invoices;
    final orders = context.watch<PurchaseOrderProvider>().orders;
    final expenses = context.watch<ExpenseProvider>().expenses;
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) => a.currentUser?.hasPermission(AppPermissions.manageBudgets) ?? false,
    );

    return AppScreenScaffold(
      icon: Icons.donut_small_rounded,
      title: 'Budgets',
      subtitle: '${provider.current.length} covering today',
      iconColor: AppTheme.successColor,
      isLoading: provider.isLoading && provider.budgets.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.budgetEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New budget'),
            )
          : null,
      isEmpty: provider.budgets.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.donut_small_rounded,
        title: 'No budgets set',
        subtitle:
            'Every other report looks backwards. A budget is the one that '
            'compares what happened to what was supposed to happen — measured '
            'against invoices, purchase orders and expenses you already have.',
        buttonText: canManage ? 'Set a budget' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.budgetEditor)
            : null,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: provider.budgets.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return provider.errorMessage == null
                ? const SizedBox.shrink()
                : ProviderErrorBanner(
                    message: provider.errorMessage!,
                    onDismiss: provider.clearError,
                  );
          }
          final budget = provider.budgets[index - 1];
          final report = provider.varianceFor(
            budget: budget,
            invoices: invoices,
            purchaseOrders: orders,
            expenses: expenses,
          );
          final usage = report.spendUsage;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AnimatedListItem(
              index: index - 1,
              child: GlassCard(
                onTap: () => context.pushAppRoute(
                  AppRoutes.budgetDetail,
                  extra: budget.id,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              budget.name.isEmpty
                                  ? budget.periodLabel
                                  : budget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (budget.isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Current',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.successColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${budget.periodLabel} · '
                        '${BudgetModel.periodLabelOf(budget.period)} · '
                        '${budget.lines.length} lines',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Spend '
                              '${Money.compactWithSymbol(symbol, report.spendActual)}'
                              ' of '
                              '${Money.compactWithSymbol(symbol, report.spendBudget)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (report.overBudget.isNotEmpty)
                            Text(
                              '${report.overBudget.length} over',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.dangerColor,
                              ),
                            )
                          else if (report.aheadOfPace.isNotEmpty)
                            Text(
                              '${report.aheadOfPace.length} ahead of pace',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.warningColor,
                              ),
                            ),
                        ],
                      ),
                      if (usage != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: usage > 1 ? 1 : usage,
                            minHeight: 5,
                            backgroundColor: AppTheme.successColor.withValues(
                              alpha: 0.15,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              usage > 1
                                  ? AppTheme.dangerColor
                                  : (usage > report.elapsedShare
                                        ? AppTheme.warningColor
                                        : AppTheme.successColor),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
