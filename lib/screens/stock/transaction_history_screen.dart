import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/invoice_search.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/animations.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/provider_error_banner.dart';

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
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final show = _scrollController.offset > 500;
      if (show != _showScrollToTop && mounted) {
        setState(() => _showScrollToTop = show);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  Future<void> _onRefreshTransactions() async {
    final cid = context.read<ProductProvider>().companyId;
    if (cid.isEmpty) return;
    context.read<StockProvider>().initialize(companyId: cid);
    await Future<void>.delayed(const Duration(milliseconds: 350));
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
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.history_rounded,
          color: AppTheme.primaryColor,
          title: 'Transaction History',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: AnimatedGradientBackground(
            colors: AppTheme.scaffoldGrad(context).colors,
            child: Column(
              children: [
                if (stockProvider.errorMessage != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Responsive.horizontalPadding(context),
                      8,
                      Responsive.horizontalPadding(context),
                      0,
                    ),
                    child: ProviderErrorBanner(
                      message: stockProvider.errorMessage!,
                      onDismiss: () => stockProvider.clearError(),
                      onRetry: () {
                        final cid = context.read<ProductProvider>().companyId;
                        if (cid.isNotEmpty) {
                          stockProvider.initialize(companyId: cid);
                        }
                      },
                    ),
                  ),
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
                              tooltip: 'Clear search',
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
                        onTap: () => setState(
                          () => _typeFilter = TransactionType.stockIn,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Stock Out',
                        isSelected: _typeFilter == TransactionType.stockOut,
                        color: AppTheme.primaryColor,
                        onTap: () => setState(
                          () => _typeFilter = TransactionType.stockOut,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Damage',
                        isSelected: _typeFilter == TransactionType.damage,
                        color: AppTheme.dangerColor,
                        onTap: () => setState(
                          () => _typeFilter = TransactionType.damage,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Transfer',
                        isSelected: _typeFilter == TransactionType.transfer,
                        color: AppTheme.indigoColor,
                        onTap: () => setState(
                          () => _typeFilter = TransactionType.transfer,
                        ),
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
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Hold',
                        isSelected: _typeFilter == TransactionType.hold,
                        color: AppTheme.warningColor,
                        onTap: () =>
                            setState(() => _typeFilter = TransactionType.hold),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Release',
                        isSelected: _typeFilter == TransactionType.holdRelease,
                        color: AppTheme.successColor,
                        onTap: () => setState(
                          () => _typeFilter = TransactionType.holdRelease,
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
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSec(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.primaryColor,
                    onRefresh: _onRefreshTransactions,
                    child: _buildTransactionListBody(
                      context,
                      stockProvider: stockProvider,
                      filtered: filtered,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _showScrollToTop
          ? AnimatedScale(
              scale: _showScrollToTop ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                heroTag: 'scrollTop',
                tooltip: 'Scroll to top',
                onPressed: () => _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                backgroundColor: AppTheme.surface(context),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: AppTheme.primaryColor,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTransactionListBody(
    BuildContext context, {
    required StockProvider stockProvider,
    required List<StockTransactionModel> filtered,
  }) {
    final hPad = Responsive.horizontalPadding(context);

    if (stockProvider.isLoading && stockProvider.allTransactions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.4,
            child: const ShimmerLoading(layout: ShimmerLayout.listTile),
          ),
        ],
      );
    }

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: hPad),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.38,
            child: const EmptyStateWidget(
              icon: Icons.receipt_long_rounded,
              title: 'No Transactions',
              subtitle: 'No transactions match the current filters.',
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: hPad),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return AnimatedListItem(
          index: index,
          child: _TransactionTile(transaction: filtered[index]),
        );
      },
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
      color: isSelected ? c.withValues(alpha: 0.15) : AppTheme.surface(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? c : AppTheme.dividerC(context),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? c : AppTheme.textPri(context),
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
      TransactionType.hold => (
        Icons.pause_circle_rounded,
        AppTheme.warningColor,
      ),
      TransactionType.holdRelease => (
        Icons.play_circle_rounded,
        AppTheme.successColor,
      ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTer(context),
                      ),
                    ),
                    if (transaction.reason.isNotEmpty)
                      Text(
                        transaction.reason,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSec(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Builder(
                      builder: (context) {
                        final invNum = invoiceNumberFromStockReason(
                          transaction.reason,
                        );
                        if (invNum == null) return const SizedBox.shrink();
                        final user = context.watch<AuthProvider>().currentUser;
                        final billingOn = context
                            .watch<BillingSettingsProvider>()
                            .billingEnabled;
                        if (!billingOn ||
                            !(user?.hasPermission(
                                  AppPermissions.viewInvoices,
                                ) ??
                                false)) {
                          return const SizedBox.shrink();
                        }
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(
                              Icons.receipt_long_rounded,
                              size: 14,
                              color: AppTheme.primaryColor,
                            ),
                            label: Text(
                              'Open invoice $invNum',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.invoiceDetail,
                                arguments: invNum,
                              );
                            },
                          ),
                        );
                      },
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTer(context),
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
                        TransactionType.transfer || TransactionType.adjustment || TransactionType.hold || TransactionType.holdRelease => '',
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
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTer(context),
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
