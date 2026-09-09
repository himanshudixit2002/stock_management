import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../providers/billing_provider.dart';
import '../../services/tax_summary_service.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';

/// Period tax position, built from the invoices already on file.
class TaxSummaryScreen extends StatefulWidget {
  const TaxSummaryScreen({super.key});

  @override
  State<TaxSummaryScreen> createState() => _TaxSummaryScreenState();
}

class _TaxSummaryScreenState extends State<TaxSummaryScreen> {
  late TaxPeriod _period = TaxPeriod.month(DateTime.now());

  void _setKind(TaxPeriodKind kind) {
    final anchor = _period.start;
    setState(() {
      _period = switch (kind) {
        TaxPeriodKind.month => TaxPeriod.month(anchor),
        TaxPeriodKind.quarter => TaxPeriod.quarter(anchor),
        TaxPeriodKind.financialYear => TaxPeriod.financialYear(anchor),
        TaxPeriodKind.custom => _period,
      };
    });
  }

  void _shift(int steps) => setState(() => _period = _period.shift(steps));

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewTaxReports,
      featureName: 'Tax Summary',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final billing = context.watch<BillingProvider>();
    final summary = TaxSummaryService.build(billing.invoices, _period);
    final symbol = Money.symbolOf(context);

    return AppScreenScaffold(
      icon: Icons.receipt_long_rounded,
      title: 'Tax Summary',
      subtitle: _period.label,
      iconColor: AppTheme.infoColor,
      isLoading: billing.isLoading && billing.invoices.isEmpty,
      header: _PeriodBar(
        period: _period,
        onKindChanged: _setKind,
        onShift: _shift,
      ),
      isEmpty: summary.isEmpty,
      emptyState: EmptyStateWidget(
        icon: Icons.receipt_long_rounded,
        title: 'Nothing to report for ${_period.label}',
        subtitle:
            'Only issued invoices count towards tax. Drafts and cancelled '
            'documents are left out.',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Totals(summary: summary, symbol: symbol),
          const SizedBox(height: 16),
          _SlabTable(
            title: 'Output tax — sales',
            subtitle: 'Tax charged to customers',
            side: summary.output,
            accent: AppTheme.successColor,
            symbol: symbol,
            index: 0,
          ),
          if (summary.credits.documentCount > 0) ...[
            const SizedBox(height: 12),
            _SlabTable(
              title: 'Credit notes',
              subtitle: 'Reduces the output tax above',
              side: summary.credits,
              accent: AppTheme.warningColor,
              symbol: symbol,
              index: 1,
            ),
          ],
          const SizedBox(height: 12),
          _SlabTable(
            title: 'Input tax — purchases',
            subtitle: 'Tax paid to suppliers, offset against output',
            side: summary.input,
            accent: AppTheme.indigoColor,
            symbol: symbol,
            index: 2,
          ),
          if (summary.excludedCount > 0) ...[
            const SizedBox(height: 12),
            _ExcludedNote(count: summary.excludedCount),
          ],
          const SizedBox(height: 12),
          const _Disclaimer(),
        ],
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.onKindChanged,
    required this.onShift,
  });

  final TaxPeriod period;
  final ValueChanged<TaxPeriodKind> onKindChanged;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => onShift(-1),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous period',
            ),
            Expanded(
              child: Text(
                period.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onShift(1),
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next period',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final kind in const [
              TaxPeriodKind.month,
              TaxPeriodKind.quarter,
              TaxPeriodKind.financialYear,
            ])
              ChoiceChip(
                label: Text(switch (kind) {
                  TaxPeriodKind.month => 'Month',
                  TaxPeriodKind.quarter => 'Quarter',
                  TaxPeriodKind.financialYear => 'Financial year',
                  TaxPeriodKind.custom => 'Custom',
                }),
                selected: period.kind == kind,
                onSelected: (_) => onKindChanged(kind),
              ),
          ],
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.summary, required this.symbol});

  final TaxSummary summary;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final payable = summary.netPayable;
    final isRefund = payable < 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Output tax',
                value: Money.withSymbol(symbol, summary.netOutputTax),
                icon: Icons.trending_up_rounded,
                color: AppTheme.successColor,
                caption: '${summary.output.documentCount} sales invoices',
                index: 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: 'Input tax',
                value: Money.withSymbol(symbol, summary.input.taxAmount),
                icon: Icons.trending_down_rounded,
                color: AppTheme.indigoColor,
                caption: '${summary.input.documentCount} purchase invoices',
                index: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MetricCard(
          label: isRefund ? 'Net refund position' : 'Net tax payable',
          value: Money.withSymbol(symbol, payable.abs()),
          icon: isRefund
              ? Icons.account_balance_wallet_rounded
              : Icons.account_balance_rounded,
          color: isRefund ? AppTheme.infoColor : AppTheme.warningColor,
          caption: 'Output less credit notes, less input tax',
          index: 2,
        ),
      ],
    );
  }
}

class _SlabTable extends StatelessWidget {
  const _SlabTable({
    required this.title,
    required this.subtitle,
    required this.side,
    required this.accent,
    required this.symbol,
    required this.index,
  });

  final String title;
  final String subtitle;
  final TaxSide side;
  final Color accent;
  final String symbol;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AnimatedListItem(
      index: index,
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.percent_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (side.slabs.isEmpty)
              Text(
                'No documents in this period.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSec(context),
                ),
              )
            else ...[
              // Horizontally scrollable so three money columns stay readable on
              // a phone instead of wrapping into an unreadable stack.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.sizeOf(context).width - 96,
                  ),
                  child: DataTable(
                    columnSpacing: 24,
                    headingRowHeight: 36,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 48,
                    columns: const [
                      DataColumn(label: Text('Rate')),
                      DataColumn(label: Text('Taxable'), numeric: true),
                      DataColumn(label: Text('Tax'), numeric: true),
                      DataColumn(label: Text('Docs'), numeric: true),
                    ],
                    rows: [
                      for (final slab in side.slabs)
                        DataRow(
                          cells: [
                            DataCell(
                              Text('${_trim(slab.rate)}%'),
                            ),
                            DataCell(
                              Text(
                                Money.withSymbol(symbol, slab.taxableValue),
                              ),
                            ),
                            DataCell(
                              Text(Money.withSymbol(symbol, slab.taxAmount)),
                            ),
                            DataCell(Text('${slab.documentCount}')),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total taxable ${Money.withSymbol(symbol, side.taxableValue)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    Money.withSymbol(symbol, side.taxAmount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "18" rather than "18.0", but "2.5" kept intact.
  static String _trim(double rate) {
    if (rate == rate.roundToDouble()) return rate.toStringAsFixed(0);
    return rate.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }
}

class _ExcludedNote extends StatelessWidget {
  const _ExcludedNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(
            Icons.filter_alt_off_rounded,
            size: 18,
            color: AppTheme.warningColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count document${count == 1 ? '' : 's'} in this period '
              '${count == 1 ? 'was' : 'were'} left out — drafts and cancelled '
              'invoices carry no tax liability.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Figures are derived from the invoices in this workspace and are a '
      'working summary, not a filed return. Check them against your books '
      'before submitting anything.',
      style: TextStyle(fontSize: 11.5, color: AppTheme.textSec(context)),
    );
  }
}
