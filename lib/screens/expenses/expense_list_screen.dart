import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/expense_summary_service.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Operating spend, month by month.
class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _headFilter;

  static final DateFormat _monthFormat = DateFormat('MMMM yyyy');
  static final DateFormat _dayFormat = DateFormat('dd MMM');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<ExpenseProvider>().initialize(companyId: companyId);
      }
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewExpenses,
      featureName: 'Expenses',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) => a.currentUser?.hasPermission(AppPermissions.manageExpenses) ?? false,
    );

    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final summary = provider.summaryFor(from: from, to: to);
    final scoped = ExpenseSummaryService.inPeriod(
      provider.expenses,
      from: from,
      to: to,
    );
    final expenses = _headFilter == null
        ? scoped
        : scoped.where((e) => e.categoryKey == _headFilter).toList();

    return AppScreenScaffold(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Expenses',
      subtitle: _monthFormat.format(_month),
      iconColor: AppTheme.warningColor,
      isLoading: provider.isLoading && provider.expenses.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.expenseEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record spend'),
            )
          : null,
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Previous month',
                ),
                Expanded(
                  child: Text(
                    _monthFormat.format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Next month',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Spent',
                    value: Money.withSymbol(symbol, summary.total),
                    icon: Icons.payments_rounded,
                    color: AppTheme.warningColor,
                    caption: '${summary.count} entries',
                    dense: true,
                    index: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Unpaid',
                    value: Money.withSymbol(symbol, summary.unpaidTotal),
                    icon: Icons.schedule_rounded,
                    color: summary.unpaidTotal > 0
                        ? AppTheme.dangerColor
                        : AppTheme.successColor,
                    caption: summary.largestHead == null
                        ? null
                        : 'Top head: ${summary.largestHead!.label}',
                    dense: true,
                    index: 1,
                  ),
                ),
              ],
            ),
          ),
          if (summary.heads.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All heads'),
                      selected: _headFilter == null,
                      onSelected: (_) => setState(() => _headFilter = null),
                    ),
                  ),
                  for (final head in summary.heads)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          '${head.label} · '
                          '${Money.compactWithSymbol(symbol, head.total)}',
                        ),
                        selected: _headFilter == head.key,
                        onSelected: (_) => setState(
                          () => _headFilter =
                              _headFilter == head.key ? null : head.key,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: expenses.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Nothing recorded for this month',
                    subtitle:
                        'Rent, wages, freight out and the rest. Without them '
                        'the Profit & Loss report is a gross margin wearing '
                        'the word profit.',
                    buttonText: canManage ? 'Record spend' : null,
                    onButtonPressed: canManage
                        ? () => context.pushAppRoute(AppRoutes.expenseEditor)
                        : null,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: expenses.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AnimatedListItem(
                        index: i,
                        child: GlassCard(
                          onTap: canManage
                              ? () => context.pushAppRoute(
                                  AppRoutes.expenseEditor,
                                  extra: expenses[i],
                                )
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        expenses[i].categoryLabel,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        [
                                          _dayFormat.format(
                                            expenses[i].expenseDate,
                                          ),
                                          if (expenses[i].vendorName.isNotEmpty)
                                            expenses[i].vendorName,
                                          if (expenses[i].reference.isNotEmpty)
                                            expenses[i].reference,
                                        ].join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      Money.withSymbol(
                                        symbol,
                                        expenses[i].total,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      expenses[i].isPaid ? 'Paid' : 'Unpaid',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: expenses[i].isPaid
                                            ? AppTheme.successColor
                                            : AppTheme.dangerColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
