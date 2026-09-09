import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/commission_plan_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/commission_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/commission_calculator.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';

/// What each salesperson earned over a period.
class CommissionStatementScreen extends StatefulWidget {
  const CommissionStatementScreen({super.key});

  @override
  State<CommissionStatementScreen> createState() =>
      _CommissionStatementScreenState();
}

class _CommissionStatementScreenState extends State<CommissionStatementScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _expandedUserId;

  static final DateFormat _monthFormat = DateFormat('MMMM yyyy');
  static final DateFormat _dayFormat = DateFormat('dd MMM');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<CommissionProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewCommissions,
      featureName: 'Commissions',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<CommissionProvider>();
    final invoices = context.watch<BillingProvider>().invoices;
    final products = context.watch<ProductProvider>().analyticsProducts;
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageCommissions) ??
          false,
    );

    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final run = provider.runFor(
      invoices: invoices,
      products: products,
      from: from,
      to: to,
    );

    return AppScreenScaffold(
      icon: Icons.workspace_premium_rounded,
      title: 'Commissions',
      subtitle: _monthFormat.format(_month),
      iconColor: AppTheme.violetColor,
      isLoading: provider.isLoading && provider.plans.isEmpty,
      actions: [
        if (canManage)
          IconButton(
            tooltip: 'Commission plans',
            onPressed: () => context.pushAppRoute(AppRoutes.commissionPlans),
            icon: const Icon(Icons.tune_rounded),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
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
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Commission',
                  value: Money.withSymbol(symbol, run.totalCommission),
                  icon: Icons.workspace_premium_rounded,
                  color: AppTheme.violetColor,
                  caption: '${run.statements.length} people',
                  dense: true,
                  index: 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Qualifying base',
                  value: Money.compactWithSymbol(symbol, run.totalBase),
                  icon: Icons.calculate_rounded,
                  color: AppTheme.infoColor,
                  caption: '${run.invoicesConsidered} invoices seen',
                  dense: true,
                  index: 1,
                ),
              ),
            ],
          ),
          if (run.invoicesWithoutPlan > 0) ...[
            const SizedBox(height: 10),
            GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppTheme.warningColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${run.invoicesWithoutPlan} invoice(s) were raised by '
                      'somebody no active plan covers. Usually a plan that has '
                      'not been told about a new starter.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (provider.plans.isEmpty)
            EmptyStateWidget(
              icon: Icons.workspace_premium_rounded,
              title: 'No commission plans yet',
              subtitle:
                  'A plan names a basis — revenue or margin — a rate, and who '
                  'it applies to. Statements are then computed straight from '
                  'the invoices, so nobody has to keep a spreadsheet.',
              buttonText: canManage ? 'Create a plan' : null,
              onButtonPressed: canManage
                  ? () => context.pushAppRoute(AppRoutes.commissionPlanEditor)
                  : null,
            )
          else if (run.statements.isEmpty)
            const EmptyStateWidget(
              icon: Icons.receipt_long_rounded,
              title: 'Nothing earned this period',
              subtitle:
                  'No invoices in this month qualify under an active plan.',
            )
          else
            for (var i = 0; i < run.statements.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AnimatedListItem(
                  index: i,
                  child: _StatementCard(
                    statement: run.statements[i],
                    symbol: symbol,
                    expanded: _expandedUserId == run.statements[i].userId,
                    dayFormat: _dayFormat,
                    onToggle: () => setState(() {
                      _expandedUserId =
                          _expandedUserId == run.statements[i].userId
                          ? null
                          : run.statements[i].userId;
                    }),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.statement,
    required this.symbol,
    required this.expanded,
    required this.dayFormat,
    required this.onToggle,
  });

  final CommissionStatement statement;
  final String symbol;
  final bool expanded;
  final DateFormat dayFormat;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statement.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${statement.planName} · '
                        '${CommissionPlanModel.basisLabelOf(statement.basis)} · '
                        '${statement.invoiceCount} invoices',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
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
                      Money.withSymbol(symbol, statement.commissionTotal),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${statement.effectiveRate.toStringAsFixed(1)}% of sales',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (expanded) ...[
              const Divider(height: 20),
              for (final line in statement.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.invoiceNumber.isEmpty
                                  ? line.customerName
                                  : '${line.invoiceNumber} · ${line.customerName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            Text(
                              '${dayFormat.format(line.date)} · base '
                              '${Money.withSymbol(symbol, line.base)}'
                              '${line.collectedShare < 1 ? ' · ${(line.collectedShare * 100).round()}% collected' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Money.withSymbol(symbol, line.commission),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
