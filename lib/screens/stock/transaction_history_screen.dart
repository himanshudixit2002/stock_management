import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/stock_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  TransactionType? _typeFilter;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final transactions = stockProvider.recentTransactions;

    var filtered = transactions.where((t) {
      if (_typeFilter != null && t.type != _typeFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return t.productName.toLowerCase().contains(q) ||
            t.location.toLowerCase().contains(q) ||
            t.userName.toLowerCase().contains(q) ||
            t.reason.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.history_rounded,
          color: AppTheme.primaryColor,
          title: 'Transaction History',
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
                vertical: 8,
              ),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by product, location, user...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _debounce?.cancel();
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: _onSearchChanged,
              ),
            ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
              ),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    isSelected: _typeFilter == null,
                    onTap: () => setState(() => _typeFilter = null),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Stock In',
                    isSelected: _typeFilter == TransactionType.stockIn,
                    color: AppTheme.successColor,
                    onTap: () =>
                        setState(() => _typeFilter = TransactionType.stockIn),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Stock Out',
                    isSelected: _typeFilter == TransactionType.stockOut,
                    color: AppTheme.primaryColor,
                    onTap: () =>
                        setState(() => _typeFilter = TransactionType.stockOut),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Damage',
                    isSelected: _typeFilter == TransactionType.damage,
                    color: AppTheme.dangerColor,
                    onTap: () =>
                        setState(() => _typeFilter = TransactionType.damage),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Transfer',
                    isSelected: _typeFilter == TransactionType.transfer,
                    color: AppTheme.indigoColor,
                    onTap: () =>
                        setState(() => _typeFilter = TransactionType.transfer),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Adjustment',
                    isSelected: _typeFilter == TransactionType.adjustment,
                    color: AppTheme.warningColor,
                    onTap: () => setState(
                      () => _typeFilter = TransactionType.adjustment,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
              ),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} transactions',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: stockProvider.isLoading
                  ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                  : filtered.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.receipt_long_rounded,
                      title: 'No Transactions',
                      subtitle: 'No transactions match the current filters.',
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: Responsive.horizontalPadding(context),
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return AnimatedListItem(
                          index: index,
                          child: _TransactionTile(transaction: filtered[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryColor;
    return Material(
      color: isSelected ? c.withValues(alpha: 0.15) : AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? c : AppTheme.dividerColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? c : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final StockTransactionModel transaction;
  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (transaction.type) {
      TransactionType.stockIn => (
        Icons.add_circle_rounded,
        AppTheme.successColor,
      ),
      TransactionType.stockOut => (
        Icons.remove_circle_rounded,
        AppTheme.primaryColor,
      ),
      TransactionType.damage => (
        Icons.broken_image_rounded,
        AppTheme.dangerColor,
      ),
      TransactionType.transfer => (
        Icons.swap_horiz_rounded,
        AppTheme.indigoColor,
      ),
      TransactionType.adjustment => (Icons.tune_rounded, AppTheme.warningColor),
    };

    final dateStr = DateFormat(
      'MMM d, y \u2022 h:mm a',
    ).format(transaction.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 16,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.productName.isNotEmpty
                          ? transaction.productName
                          : transaction.productId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transaction.typeLabel} \u2022 ${transaction.location}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    if (transaction.reason.isNotEmpty)
                      Text(
                        transaction.reason,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${switch (transaction.type) {
                        TransactionType.stockIn => '+',
                        TransactionType.stockOut || TransactionType.damage => '-',
                        TransactionType.transfer || TransactionType.adjustment => '',
                      }}${transaction.quantity}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (transaction.userName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      transaction.userName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
