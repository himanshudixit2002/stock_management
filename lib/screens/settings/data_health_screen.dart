import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';

import '../../providers/billing_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/stock_provider.dart';
import '../../services/data_health_service.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';

/// Admin diagnostic: scans loaded workspace data for the inconsistencies that
/// stock and billing bugs can leave behind, and says what to do about each.
class DataHealthScreen extends StatelessWidget {
  const DataHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductProvider>().analyticsProducts;
    final holds = context.watch<StockProvider>().stockHolds;
    final invoices = context.watch<BillingProvider>().invoices;
    final orders = context.watch<SalesOrderProvider>().orders;

    final checks = const DataHealthService().scan(
      products: products,
      holds: holds,
      invoices: invoices,
      salesOrders: orders,
    );

    final findings = [
      for (final c in checks) ...c.findings,
    ]..sort((a, b) => a.severity.index.compareTo(b.severity.index));

    final critical = findings
        .where((f) => f.severity == DataHealthSeverity.critical)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.health_and_safety_rounded,
          color: AppTheme.infoColor,
          title: 'Data Health',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Summary(
              total: findings.length,
              critical: critical,
              scanned: products.length,
            ),
            const SizedBox(height: 16),
            if (findings.isNotEmpty) ...[
              ...findings.map((f) => _FindingCard(finding: f)),
              const SizedBox(height: 24),
            ],
            Text(
              'Checks run',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...checks.map((c) => _CheckRow(check: c)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.critical,
    required this.scanned,
  });

  final int total;
  final int critical;
  final int scanned;

  @override
  Widget build(BuildContext context) {
    final clean = total == 0;
    final color = clean
        ? AppTheme.successColor
        : (critical > 0 ? AppTheme.dangerColor : AppTheme.warningColor);

    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              clean ? Icons.verified_rounded : Icons.report_problem_rounded,
              color: color,
              size: 36,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clean
                        ? 'No problems found'
                        : '$total problem${total == 1 ? '' : 's'} found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    clean
                        ? 'Scanned $scanned product(s). Stock totals, '
                              'reservations and invoice links all reconcile.'
                        : '$critical critical. Scanned $scanned product(s).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding});

  final DataHealthFinding finding;

  @override
  Widget build(BuildContext context) {
    final color = switch (finding.severity) {
      DataHealthSeverity.critical => AppTheme.dangerColor,
      DataHealthSeverity.warning => AppTheme.warningColor,
      DataHealthSeverity.info => AppTheme.infoColor,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      finding.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                finding.detail,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.build_rounded,
                    size: 14,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      finding.remedy,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final DataHealthCheck check;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: check.passed ? AppTheme.successColor : AppTheme.dangerColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  check.passed
                      ? check.description
                      : '${check.findings.length} issue(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
