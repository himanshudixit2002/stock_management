import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/billing_provider.dart';
import '../../services/aging_service.dart';
import '../../utils/currency.dart';
import '../../utils/date_formats.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';

/// Receivables and payables split into ageing buckets, per party.
///
/// Kept on separate tabs on purpose: money owed to you and money you owe are
/// different obligations and must never be shown as one net figure.
class AgingScreen extends StatelessWidget {
  const AgingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.hourglass_bottom_rounded,
            color: AppTheme.infoColor,
            title: 'Ageing',
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Receivable'),
              Tab(text: 'Payable'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              _AgingTab(sales: true),
              _AgingTab(sales: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgingTab extends StatelessWidget {
  const _AgingTab({required this.sales});

  final bool sales;

  @override
  Widget build(BuildContext context) {
    final invoices = context.watch<BillingProvider>().invoices;
    const service = AgingService();
    final rows = service.build(
      invoices,
      sales: sales,
      asOf: DateTime.now(),
    );

    if (rows.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.check_circle_outline_rounded,
        title: sales ? 'Nothing outstanding' : 'Nothing owed',
        subtitle: sales
            ? 'Every customer invoice has been settled.'
            : 'Every supplier bill has been settled.',
      );
    }

    final totals = service.totals(rows);
    final grand = totals.values.fold<double>(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        GlassPanel(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sales ? 'Total receivable' : 'Total payable',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  Money.of(context, grand),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: sales
                        ? AppTheme.successColor
                        : AppTheme.warningColor,
                  ),
                ),
                const SizedBox(height: 12),
                ...AgingBucket.values.map((b) {
                  final value = totals[b] ?? 0;
                  if (value <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Both sides were unbounded: a long amount on a narrow
                        // phone pushed the label off the row.
                        Expanded(
                          child: Text(
                            b.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Money.of(context, value),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: b == AgingBucket.days90Plus
                                    ? AppTheme.dangerColor
                                    : null,
                              ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...rows.map((row) => _PartyTile(row: row, sales: sales)),
      ],
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.row, required this.sales});

  final PartyAging row;
  final bool sales;

  @override
  Widget build(BuildContext context) {
    final worst = AgingBucket.values.lastWhere(
      (b) => row.amountIn(b) > 0,
      orElse: () => AgingBucket.current,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          // A long customer name against an unbounded trailing amount wrapped
          // to several lines on a phone. Cap it and let the amount win.
          title: Text(
            row.partyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${row.invoices.length} open • oldest ${worst.label.toLowerCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Text(
            Money.of(context, row.total),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: worst == AgingBucket.days90Plus
                  ? AppTheme.dangerColor
                  : null,
            ),
          ),
          children: row.invoices.map((inv) {
            final days = DateTime.now().difference(inv.dueDate).inDays;
            return ListTile(
              dense: true,
              title: Text(inv.invoiceNumber),
              subtitle: Text(
                days > 0
                    ? 'Due ${AppDates.day.format(inv.dueDate)} • $days day(s) overdue'
                    : 'Due ${AppDates.day.format(inv.dueDate)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Text(
                Money.of(context, inv.amountDue),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: days > 90 ? AppTheme.dangerColor : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
