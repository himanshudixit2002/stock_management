import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../services/stock_calculations.dart';
import '../../utils/date_formats.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/product_picker.dart';

/// Per-product movement history with a running balance, so a discrepancy can
/// be traced to the movement that caused it. The transaction history screen
/// lists movements but never shows a balance, which makes reconciling
/// impossible.
class StockLedgerScreen extends StatefulWidget {
  const StockLedgerScreen({super.key, this.initialProduct});

  final ProductModel? initialProduct;

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  ProductModel? _product;

  @override
  void initState() {
    super.initState();
    _product = widget.initialProduct;
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.receipt_long_rounded,
          color: AppTheme.infoColor,
          title: 'Stock Ledger',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: _ProductSelector(
                product: product,
                onPick: (p) => setState(() => _product = p),
              ),
            ),
            Expanded(
              child: product == null
                  ? const EmptyStateWidget(
                      icon: Icons.inventory_2_rounded,
                      title: 'Pick a product',
                      subtitle:
                          'Choose a product to see every movement and the '
                          'running balance after each one.',
                    )
                  : _Ledger(product: product),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSelector extends StatelessWidget {
  const _ProductSelector({required this.product, required this.onPick});

  final ProductModel? product;
  final ValueChanged<ProductModel> onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showProductPicker(
          context: context,
          products: context.read<ProductProvider>().analyticsProducts,
          selectedProductId: product?.id,
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Product',
          prefixIcon: Icon(Icons.inventory_2_rounded),
        ),
        child: Text(
          product?.name ?? 'Tap to select',
          style: TextStyle(
            color: product != null ? null : AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    // The catalogue copy can be stale relative to the stream; prefer the live
    // one so the closing balance matches what the rest of the app shows.
    final live = context
        .watch<ProductProvider>()
        .analyticsProducts
        .where((p) => p.id == product.id);
    final current = live.isNotEmpty ? live.first : product;

    return StreamBuilder<List<StockTransactionModel>>(
      stream: context.read<StockProvider>().getProductTransactions(product.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyStateWidget(
            icon: Icons.error_outline_rounded,
            title: 'Could not load movements',
            subtitle: '${snapshot.error}',
          );
        }
        final transactions = snapshot.data ?? const <StockTransactionModel>[];
        if (transactions.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.history_rounded,
            title: 'No movements yet',
            subtitle: 'This product has no recorded stock movements.',
          );
        }

        final rows = StockCalculations.buildLedger(
          transactions,
          closingBalance: current.quantity,
        );
        final incomplete = StockCalculations.hasUnknownDirection(transactions);
        final opening = rows.isEmpty
            ? current.quantity
            : rows.first.balanceAfter - (rows.first.effect ?? 0);

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          // header + rows + footer
          itemCount: rows.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _BalanceCard(
                label: 'Opening balance',
                value: opening,
                unit: current.baseUnit,
                incomplete: incomplete,
              );
            }
            if (index == rows.length + 1) {
              return _BalanceCard(
                label: 'Closing balance',
                value: current.quantity,
                unit: current.baseUnit,
                emphasise: true,
              );
            }
            // Newest first reads better, so walk the list backwards.
            return _LedgerRowTile(row: rows[rows.length - index]);
          },
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.label,
    required this.value,
    required this.unit,
    this.emphasise = false,
    this.incomplete = false,
  });

  final String label;
  final int value;
  final String unit;
  final bool emphasise;
  final bool incomplete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$value $unit',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: emphasise ? AppTheme.primaryColor : null,
                    ),
                  ),
                ],
              ),
              if (incomplete) ...[
                const SizedBox(height: 6),
                Text(
                  'Some older adjustments were saved without a direction, so '
                  'the opening balance is approximate.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.warningColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerRowTile extends StatelessWidget {
  const _LedgerRowTile({required this.row});

  final LedgerRow row;

  @override
  Widget build(BuildContext context) {
    final effect = row.effect;
    final color = effect == null
        ? AppTheme.warningColor
        : (effect > 0
              ? AppTheme.successColor
              : (effect < 0 ? AppTheme.dangerColor : AppTheme.textSec(context)));
    final effectLabel = effect == null
        ? '?'
        : (effect > 0 ? '+$effect' : '$effect');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.transaction.typeIcon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.transaction.typeLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    AppDates.dayTime.format(row.transaction.date),
                    if (row.transaction.location.isNotEmpty)
                      row.transaction.location,
                    if (row.transaction.userName.isNotEmpty)
                      row.transaction.userName,
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (row.transaction.reason.isNotEmpty)
                  Text(
                    row.transaction.reason,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                effectLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                '${row.balanceAfter}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
