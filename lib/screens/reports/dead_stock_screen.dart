import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/app_navigation.dart';
import '../../config/theme.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../services/dead_stock_service.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/truncated_data_banner.dart';

/// Which stock has stopped selling, and what it is costing to hold.
class DeadStockScreen extends StatefulWidget {
  const DeadStockScreen({super.key});

  @override
  State<DeadStockScreen> createState() => _DeadStockScreenState();
}

class _DeadStockScreenState extends State<DeadStockScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  int _staleAfterDays = DeadStockService.defaultStaleAfterDays;
  MovementBand? _bandFilter;

  int get _deadAfterDays => _staleAfterDays * 2;

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewDeadStock,
      featureName: 'Dead Stock',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final products = context.watch<ProductProvider>();
    final stock = context.watch<StockProvider>();
    final symbol = Money.symbolOf(context);

    final report = DeadStockService.analyse(
      products: products.analyticsProducts,
      transactions: stock.allTransactions,
      staleAfterDays: _staleAfterDays,
      deadAfterDays: _deadAfterDays,
      windowDays: _deadAfterDays,
    );

    final rows = _bandFilter == null
        ? report.entries
        : report.entries.where((e) => e.band == _bandFilter).toList();

    return AppScreenScaffold(
      icon: Icons.hourglass_disabled_rounded,
      title: 'Dead Stock',
      subtitle: 'Capital sitting still',
      iconColor: AppTheme.warningColor,
      isLoading: products.isLoading && products.analyticsProducts.isEmpty,
      header: _Thresholds(
        staleAfterDays: _staleAfterDays,
        onChanged: (days) => setState(() => _staleAfterDays = days),
      ),
      isEmpty: report.entries.isEmpty,
      emptyState: const EmptyStateWidget(
        icon: Icons.inventory_2_rounded,
        title: 'Nothing in stock to analyse',
        subtitle:
            'Products with no units on hand are left out — there is no capital '
            'at rest in an empty shelf.',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Totals(report: report, symbol: symbol),
          const SizedBox(height: 12),
          _BandFilters(
            report: report,
            selected: _bandFilter,
            onSelected: (band) => setState(() => _bandFilter = band),
          ),
          // Self-hiding: it only appears when the transaction stream actually
          // hit its cap, which is exactly when "never sold" may mean "sold
          // before the window we can see".
          const TruncatedDataBanner(padding: EdgeInsets.only(top: 12)),
          if (report.transactionsCovered == 0)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: _NoMovementNote(),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeadStockRow(
                entry: rows[i],
                symbol: symbol,
                index: i,
                dateFormat: _dateFormat,
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No products in this band.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSec(context)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thresholds extends StatelessWidget {
  const _Thresholds({required this.staleAfterDays, required this.onChanged});

  final int staleAfterDays;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stale after $staleAfterDays days · dead after ${staleAfterDays * 2}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final days in const [30, 60, 90, 180])
              ChoiceChip(
                label: Text('$days d'),
                selected: staleAfterDays == days,
                onSelected: (_) => onChanged(days),
              ),
          ],
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.report, required this.symbol});

  final DeadStockReport report;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final atRisk = report.deadValue + report.staleValue;
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: 'Capital at rest',
            value: Money.withSymbol(symbol, atRisk),
            icon: Icons.savings_rounded,
            color: AppTheme.dangerColor,
            caption: '${(report.problemShare * 100).toStringAsFixed(0)}% '
                'of ${Money.compactWithSymbol(symbol, report.totalValueAtRest)}',
            index: 0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: 'Products affected',
            value:
                '${report.countOf(MovementBand.dead) + report.countOf(MovementBand.stale) + report.countOf(MovementBand.neverSold)}',
            icon: Icons.inventory_2_rounded,
            color: AppTheme.warningColor,
            caption: 'Stale, dead or never sold',
            index: 1,
          ),
        ),
      ],
    );
  }
}

class _BandFilters extends StatelessWidget {
  const _BandFilters({
    required this.report,
    required this.selected,
    required this.onSelected,
  });

  final DeadStockReport report;
  final MovementBand? selected;
  final ValueChanged<MovementBand?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('All (${report.entries.length})'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final band in MovementBand.values)
            if (report.countOf(band) > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    '${DeadStockService.bandLabel(band)} (${report.countOf(band)})',
                  ),
                  selected: selected == band,
                  onSelected: (_) => onSelected(selected == band ? null : band),
                ),
              ),
        ],
      ),
    );
  }
}

class _DeadStockRow extends StatelessWidget {
  const _DeadStockRow({
    required this.entry,
    required this.symbol,
    required this.index,
    required this.dateFormat,
  });

  final DeadStockEntry entry;
  final String symbol;
  final int index;
  final DateFormat dateFormat;

  Color get _bandColor => switch (entry.band) {
    MovementBand.fresh => AppTheme.successColor,
    MovementBand.slowing => AppTheme.infoColor,
    MovementBand.stale => AppTheme.warningColor,
    MovementBand.dead => AppTheme.dangerColor,
    MovementBand.neverSold => AppTheme.violetColor,
  };

  @override
  Widget build(BuildContext context) {
    final product = entry.product;
    final lastSale = entry.lastSaleDate;
    return AnimatedListItem(
      index: index,
      child: GlassCard(
        onTap: () => context.pushAppRoute(
          AppRoutes.productDetail,
          extra: product,
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
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _bandColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      DeadStockService.bandLabel(entry.band),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _bandColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                lastSale == null
                    ? 'No outbound movement on record'
                    : 'Last sold ${dateFormat.format(lastSale)} · '
                          '${entry.daysSinceLastSale} days ago',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Stat(
                    label: 'On hand',
                    value: '${product.quantity} ${product.unit}',
                  ),
                  _Stat(
                    label: 'At rest',
                    value: Money.withSymbol(symbol, entry.valueAtRest),
                  ),
                  _Stat(
                    label: 'Sold in window',
                    value: '${entry.unitsSoldInWindow}',
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Shown when there is no outbound history at all, so the report's verdict of
/// "never sold" for everything is a data gap rather than a finding.
class _NoMovementNote extends StatelessWidget {
  const _NoMovementNote();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.infoColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No outbound movements were found, so every product reads as '
              'never sold. Record some stock-outs, or wait for history to '
              'finish loading.',
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
