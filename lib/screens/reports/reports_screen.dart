import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/stock_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../services/excel_service.dart';
import '../../widgets/charts/transaction_line_chart.dart';
import '../../widgets/charts/category_pie_chart.dart';
import '../../widgets/charts/stock_bar_chart.dart';
import '../../widgets/charts/top_products_chart.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'all';
  int _chartDays = 7;
  String _chartGranularity = 'daily'; // daily | weekly | monthly
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDateRange(StockProvider stockProvider) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: stockProvider.filterStartDate != null
          ? DateTimeRange(
              start: stockProvider.filterStartDate!,
              end: stockProvider.filterEndDate ?? now,
            )
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: AppTheme.primaryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      stockProvider.setDateRangeFilter(picked.start, picked.end);
    }
  }

  void _showDateRangeSheet(StockProvider stockProvider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Date Range', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('Last 7 days'),
                onTap: () {
                  stockProvider.setDateRangeFilter(
                    DateTime.now().subtract(const Duration(days: 7)),
                    DateTime.now(),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('Last 30 days'),
                onTap: () {
                  stockProvider.setDateRangeFilter(
                    DateTime.now().subtract(const Duration(days: 30)),
                    DateTime.now(),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range_outlined),
                title: const Text('Last 90 days'),
                onTap: () {
                  stockProvider.setDateRangeFilter(
                    DateTime.now().subtract(const Duration(days: 90)),
                    DateTime.now(),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Custom range...'),
                onTap: () {
                  Navigator.pop(context);
                  _pickCustomDateRange(stockProvider);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('Clear date filter'),
                onTap: () {
                  stockProvider.setDateRangeFilter(null, null);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdvancedFiltersSheet(StockProvider stockProvider) {
    final vendorProvider = context.read<VendorProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    String tempUserId = stockProvider.filterUserId;
    String tempVendorId = stockProvider.filterVendorId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final users = stockProvider.uniqueUsers;
          final vendors = vendorProvider.vendors;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Advanced Filters',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  if (users.isNotEmpty) ...[
                    const Text('User', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    )),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.dividerColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempUserId.isEmpty ? null : tempUserId,
                          hint: const Text('All users', style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('All users', style: TextStyle(fontSize: 13)),
                            ),
                            ...users.map((u) => DropdownMenuItem(
                              value: u.key,
                              child: Text(u.value, style: const TextStyle(fontSize: 13)),
                            )),
                          ],
                          onChanged: (v) => setSheetState(() => tempUserId = v ?? ''),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (settingsProvider.vendorsEnabled && vendors.isNotEmpty) ...[
                    const Text('Vendor', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    )),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.dividerColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempVendorId.isEmpty ? null : tempVendorId,
                          hint: const Text('All vendors', style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('All vendors', style: TextStyle(fontSize: 13)),
                            ),
                            ...vendors.map((v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.name, style: const TextStyle(fontSize: 13)),
                            )),
                          ],
                          onChanged: (v) => setSheetState(() => tempVendorId = v ?? ''),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            stockProvider.setUserFilter('');
                            stockProvider.setVendorFilter('');
                            Navigator.pop(ctx);
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            stockProvider.setUserFilter(tempUserId);
                            stockProvider.setVendorFilter(tempVendorId);
                            Navigator.pop(ctx);
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportTransactions(
    List<StockTransactionModel> transactions,
  ) async {
    if (_isExporting) return;
    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No transactions to export'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final excelService = ExcelService();
      final result = await excelService.exportTransactionsToCsv(transactions);
      if (!mounted) return;
      await excelService.saveAndShare(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorSize: TabBarIndicatorSize.label,
          indicator: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.primaryColor, width: 3),
            ),
          ),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.history_rounded, size: 18),
              text: 'Transactions',
            ),
            Tab(
              icon: Icon(Icons.category_rounded, size: 18),
              text: 'Categories',
            ),
            Tab(icon: Icon(Icons.show_chart_rounded, size: 18), text: 'Charts'),
            Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Summary'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTransactionTab(),
          _buildCategoryAnalyticsTab(),
          _buildChartsTab(),
          _buildSummaryTab(),
        ],
      ),
    );
  }

  // ==================== TAB 1: TRANSACTIONS ====================

  Widget _buildTransactionTab() {
    final stockProvider = context.watch<StockProvider>();
    final dateFormat = DateFormat('dd MMM, hh:mm a');
    final hPad = Responsive.horizontalPadding(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Responsive.contentMaxWidth(context),
        ),
        child: Column(
          children: [
            // Row 1: Search + Date + Sort + Export
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search product...',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppTheme.dividerColor,
                            ),
                          ),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) => stockProvider.setProductFilter(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _showDateRangeSheet(stockProvider),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Icon(
                        Icons.calendar_today,
                        size: 20,
                        color: stockProvider.filterStartDate != null
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.sort, size: 20),
                    tooltip: 'Sort',
                    onSelected: (v) => stockProvider.setSortBy(v),
                    itemBuilder: (context) => [
                      _sortMenuItem(
                        'date_desc',
                        'Date (newest)',
                        stockProvider.sortBy,
                      ),
                      _sortMenuItem(
                        'date_asc',
                        'Date (oldest)',
                        stockProvider.sortBy,
                      ),
                      _sortMenuItem(
                        'qty_desc',
                        'Qty (high-low)',
                        stockProvider.sortBy,
                      ),
                      _sortMenuItem(
                        'qty_asc',
                        'Qty (low-high)',
                        stockProvider.sortBy,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined, size: 20),
                    tooltip: 'Export CSV',
                    onPressed: _isExporting
                        ? null
                        : () => _exportTransactions(
                            _getFilteredTransactions(stockProvider),
                          ),
                  ),
                  _AdvancedFilterButton(
                    hasActive: stockProvider.filterUserId.isNotEmpty ||
                        stockProvider.filterVendorId.isNotEmpty,
                    onTap: () => _showAdvancedFiltersSheet(stockProvider),
                  ),
                  if (stockProvider.filterStartDate != null ||
                      stockProvider.filterUserId.isNotEmpty ||
                      stockProvider.filterVendorId.isNotEmpty ||
                      stockProvider.filterProductId.isNotEmpty ||
                      _selectedFilter != 'all')
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        stockProvider.clearFilters();
                        setState(() => _selectedFilter = 'all');
                      },
                      tooltip: 'Clear filters',
                    ),
                ],
              ),
            ),
            // Row 2: Type chips
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 6),
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'All',
                      isSelected: _selectedFilter == 'all',
                      onTap: () => setState(() => _selectedFilter = 'all'),
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: 'Stock In',
                      isSelected: _selectedFilter == 'stock_in',
                      onTap: () => setState(() => _selectedFilter = 'stock_in'),
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: 'Stock Out',
                      isSelected: _selectedFilter == 'stock_out',
                      onTap: () =>
                          setState(() => _selectedFilter = 'stock_out'),
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: 'Damage',
                      isSelected: _selectedFilter == 'damage',
                      onTap: () => setState(() => _selectedFilter = 'damage'),
                      color: AppTheme.dangerColor,
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: 'Transfer',
                      isSelected: _selectedFilter == 'transfer',
                      onTap: () =>
                          setState(() => _selectedFilter = 'transfer'),
                      color: AppTheme.indigoColor,
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.transactionHistory,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Full History',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // KPI cards
            _KpiRow(
              padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 8),
              cards: [
                _KpiCard(
                  label: 'Transactions',
                  value: '${stockProvider.recentTransactions.length}',
                  icon: Icons.receipt_long_rounded,
                  color: AppTheme.primaryColor,
                  changePercent: stockProvider.periodChangePercentages['count'],
                ),
                _KpiCard(
                  label: 'Stock In',
                  value: '${stockProvider.stockInTotal}',
                  icon: Icons.add_circle_rounded,
                  color: AppTheme.successColor,
                  changePercent: stockProvider.periodChangePercentages['stockIn'],
                ),
                _KpiCard(
                  label: 'Stock Out',
                  value: '${stockProvider.stockOutTotal}',
                  icon: Icons.remove_circle_rounded,
                  color: AppTheme.primaryColor,
                  changePercent: stockProvider.periodChangePercentages['stockOut'],
                ),
                _KpiCard(
                  label: 'Net Flow',
                  value: '${stockProvider.netStockChange >= 0 ? '+' : ''}${stockProvider.netStockChange}',
                  icon: Icons.swap_vert_rounded,
                  color: stockProvider.netStockChange >= 0
                      ? AppTheme.successColor
                      : AppTheme.dangerColor,
                  changePercent: stockProvider.periodChangePercentages['netFlow'],
                ),
              ],
            ),
            // Transaction list
            Expanded(
              child: Builder(
                builder: (context) {
                  final transactions = _getFilteredTransactions(stockProvider);

                  if (transactions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 56,
                            color: AppTheme.iconMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No transactions found',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    addAutomaticKeepAlives: false,
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final t = transactions[index];
                      return _TransactionTile(
                        transaction: t,
                        dateFormat: dateFormat,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<StockTransactionModel> _getFilteredTransactions(
    StockProvider stockProvider,
  ) {
    var transactions = stockProvider.recentTransactions;
    if (_selectedFilter != 'all') {
      TransactionType filterType;
      switch (_selectedFilter) {
        case 'stock_in':
          filterType = TransactionType.stockIn;
          break;
        case 'stock_out':
          filterType = TransactionType.stockOut;
          break;
        case 'damage':
          filterType = TransactionType.damage;
          break;
        case 'transfer':
          filterType = TransactionType.transfer;
          break;
        default:
          filterType = TransactionType.stockIn;
      }
      transactions = transactions.where((t) => t.type == filterType).toList();
    }
    return transactions;
  }

  PopupMenuItem<String> _sortMenuItem(
    String value,
    String label,
    String current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (current == value)
            const Icon(Icons.check, size: 16, color: AppTheme.primaryColor)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ==================== TAB 2: CATEGORY ANALYTICS ====================

  Widget _buildCategoryAnalyticsTab() {
    final productProvider = context.watch<ProductProvider>();

    final hasNoData = productProvider.analyticsProducts.isEmpty;
    final isStillLoading = productProvider.isLoading ||
        (productProvider.isLoadingAnalytics && hasNoData);

    if (isStillLoading && hasNoData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 16),
              Text(
                'Loading analytics...',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    final countByCategory = productProvider.productCountByCategory;
    final lowByCategory = productProvider.lowStockByCategory;
    final outByCategory = productProvider.outOfStockByCategory;

    final isRefining = productProvider.isLoadingAnalytics;

    return RefreshIndicator(
      onRefresh: () => productProvider.loadAnalytics(),
      child: SingleChildScrollView(
        physics: Responsive.scrollPhysics(context),
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isRefining)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppTheme.primaryColor,
                      backgroundColor: Color(0x1A007AFF),
                    ),
                  ),
                _KpiRow(
                  padding: const EdgeInsets.only(bottom: 12),
                  cards: [
                    _KpiCard(
                      label: 'Categories',
                      value: '${countByCategory.length}',
                      icon: Icons.category_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    _KpiCard(
                      label: 'Total Products',
                      value: '${productProvider.totalProducts}',
                      icon: Icons.inventory_2_rounded,
                      color: AppTheme.successColor,
                    ),
                    _KpiCard(
                      label: 'Health Score',
                      value: '${productProvider.inventoryHealthScore.toInt()}',
                      icon: Icons.favorite_rounded,
                      color: productProvider.inventoryHealthScore >= 80
                          ? AppTheme.successColor
                          : productProvider.inventoryHealthScore >= 50
                              ? AppTheme.warningColor
                              : AppTheme.dangerColor,
                    ),
                  ],
                ),
                _SectionCard(
                  title: 'Products by Category',
                  child: CategoryPieChart(
                    data: countByCategory.map(
                      (k, v) => MapEntry(k, v.toDouble()),
                    ),
                    valueLabel: 'products',
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Category Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                ...countByCategory.entries.map((entry) {
                  final name = entry.key;
                  final count = entry.value;
                  final low = lowByCategory[name] ?? 0;
                  final out = outByCategory[name] ?? 0;

                  final categoryProducts =
                      productProvider.productsByCategory[name];
                  final categoryId =
                      categoryProducts != null && categoryProducts.isNotEmpty
                      ? categoryProducts.first.categoryId
                      : null;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: categoryId != null
                          ? () {
                              productProvider.filterByCategory(categoryId);
                              Navigator.pushNamed(
                                context,
                                AppRoutes.productList,
                              );
                            }
                          : null,
                      child: GlassCard(
                        borderRadius: 14,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(
                                      Icons.category,
                                      color: AppTheme.primaryColor,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$count products',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _MiniStat(
                                    icon: Icons.inventory_2,
                                    label: 'Products',
                                    value: '$count',
                                    color: AppTheme.primaryColor,
                                  ),
                                  const SizedBox(width: 16),
                                  _MiniStat(
                                    icon: Icons.warning_amber,
                                    label: 'Low Stock',
                                    value: '$low',
                                    color: AppTheme.warningColor,
                                  ),
                                  const SizedBox(width: 16),
                                  _MiniStat(
                                    icon: Icons.error_outline,
                                    label: 'Out',
                                    value: '$out',
                                    color: AppTheme.dangerColor,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== TAB 3: CHARTS & TRENDS ====================

  Widget _buildChartsTab() {
    final stockProvider = context.watch<StockProvider>();
    final authProvider = context.watch<AuthProvider>();
    final wide = Responsive.isWide(context);

    final pctChange = stockProvider.periodChangePercentages;

    final kpiRow = _KpiRow(
      padding: const EdgeInsets.only(bottom: 12),
      cards: [
        _KpiCard(
          label: 'Stock In',
          value: '${stockProvider.stockInTotal}',
          icon: Icons.add_circle_rounded,
          color: AppTheme.successColor,
          changePercent: pctChange['stockIn'],
        ),
        _KpiCard(
          label: 'Stock Out',
          value: '${stockProvider.stockOutTotal}',
          icon: Icons.remove_circle_rounded,
          color: AppTheme.primaryColor,
          changePercent: pctChange['stockOut'],
        ),
        _KpiCard(
          label: 'Damage',
          value: '${stockProvider.damageTotal}',
          icon: Icons.report_problem_rounded,
          color: AppTheme.dangerColor,
          changePercent: pctChange['damage'],
        ),
        _KpiCard(
          label: 'Transfers',
          value: '${stockProvider.transferTotal}',
          icon: Icons.swap_horiz_rounded,
          color: AppTheme.indigoColor,
          changePercent: pctChange['transfer'],
        ),
      ],
    );

    final Map<String, Map<TransactionType, int>> trendData;
    final String granularityLabel;
    int? daysParam;
    switch (_chartGranularity) {
      case 'weekly':
        trendData = stockProvider.transactionsByWeek;
        granularityLabel = 'weekly';
      case 'monthly':
        trendData = stockProvider.transactionsByMonth;
        granularityLabel = 'monthly';
      default:
        trendData = stockProvider.transactionsByDay;
        granularityLabel = 'daily';
        daysParam = stockProvider.filterStartDate != null &&
                stockProvider.filterEndDate != null
            ? stockProvider.filterEndDate!
                  .difference(stockProvider.filterStartDate!)
                  .inDays
                  .clamp(1, 365)
            : _chartDays;
    }

    final trendChart = _SectionCard(
      title: 'Transaction Trends',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleChip(
            label: 'D',
            isSelected: _chartGranularity == 'daily',
            onTap: () => setState(() => _chartGranularity = 'daily'),
          ),
          const SizedBox(width: 4),
          _ToggleChip(
            label: 'W',
            isSelected: _chartGranularity == 'weekly',
            onTap: () => setState(() => _chartGranularity = 'weekly'),
          ),
          const SizedBox(width: 4),
          _ToggleChip(
            label: 'M',
            isSelected: _chartGranularity == 'monthly',
            onTap: () => setState(() => _chartGranularity = 'monthly'),
          ),
          if (_chartGranularity == 'daily') ...[
            const SizedBox(width: 8),
            _ToggleChip(
              label: '7D',
              isSelected: _chartDays == 7,
              onTap: () => setState(() => _chartDays = 7),
            ),
            const SizedBox(width: 4),
            _ToggleChip(
              label: '30D',
              isSelected: _chartDays == 30,
              onTap: () => setState(() => _chartDays = 30),
            ),
            const SizedBox(width: 4),
            _ToggleChip(
              label: '90D',
              isSelected: _chartDays == 90,
              onTap: () => setState(() => _chartDays = 90),
            ),
          ],
        ],
      ),
      child: TransactionLineChart(
        dataByDay: trendData,
        days: daysParam ?? trendData.length,
        granularity: granularityLabel,
      ),
    );

    final movementChart = _SectionCard(
      title: 'Stock Movement Breakdown',
      child: CategoryPieChart(
        data: {
          'Stock In': stockProvider.stockInTotal.toDouble(),
          'Stock Out': stockProvider.stockOutTotal.toDouble(),
          'Transfer': stockProvider.transferTotal.toDouble(),
          'Damage': stockProvider.damageTotal.toDouble(),
        },
        valueLabel: 'units',
        onSliceTap: (category, _) {
          final typeMap = {
            'Stock In': 'stock_in',
            'Stock Out': 'stock_out',
            'Transfer': 'transfer',
            'Damage': 'damage',
          };
          if (typeMap.containsKey(category)) {
            setState(() => _selectedFilter = typeMap[category]!);
            _tabController.animateTo(0);
          }
        },
      ),
    );

    void drillDownProduct(String name, int _) {
      stockProvider.setProductFilter(name);
      _tabController.animateTo(0);
    }

    final activityChart = _SectionCard(
      title: 'Top Products by Activity',
      child: TopProductsChart(
        data: stockProvider.topProductsByTransactions,
        barColor: AppTheme.primaryColor,
        valueLabel: 'transactions',
        onItemTap: drillDownProduct,
      ),
    );

    final unitsChart = _SectionCard(
      title: 'Top Products by Units Moved',
      child: TopProductsChart(
        data: stockProvider.topProductsByQuantityMoved,
        barColor: AppTheme.successColor,
        valueLabel: 'units',
        onItemTap: drillDownProduct,
      ),
    );

    final salesChart = _SectionCard(
      title: 'Top Items by Sales',
      child: TopProductsChart(
        data: stockProvider.topProductsBySales,
        barColor: AppTheme.primaryColor,
        valueLabel: 'boxes sold',
        onItemTap: drillDownProduct,
      ),
    );

    final breakageChart = _SectionCard(
      title: 'Top Items by Breakage',
      child: TopProductsChart(
        data: stockProvider.topProductsByBreakage,
        barColor: AppTheme.dangerColor,
        valueLabel: 'boxes damaged',
        onItemTap: drillDownProduct,
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kpiRow,
              if (wide) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: trendChart),
                    const SizedBox(width: 16),
                    Expanded(child: movementChart),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: activityChart),
                    const SizedBox(width: 16),
                    Expanded(child: unitsChart),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: salesChart),
                    const SizedBox(width: 16),
                    Expanded(child: breakageChart),
                  ],
                ),
              ] else ...[
                trendChart,
                const SizedBox(height: 16),
                movementChart,
                const SizedBox(height: 16),
                activityChart,
                const SizedBox(height: 16),
                unitsChart,
                const SizedBox(height: 16),
                salesChart,
                const SizedBox(height: 16),
                breakageChart,
              ],
              const SizedBox(height: 16),
              if (authProvider.isAdmin) ...[
                _SectionCard(
                  title: 'Activity by User',
                  child: StockBarChart(
                    data: stockProvider.transactionsByUser.map(
                      (k, v) => MapEntry(k, v.toDouble()),
                    ),
                    barColor: AppTheme.infoColor,
                    emptyMessage: 'No user activity data',
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== TAB 4: SUMMARY ====================

  Widget _buildSummaryTab() {
    final productProvider = context.watch<ProductProvider>();
    final stockProvider = context.watch<StockProvider>();

    final hasNoData = productProvider.analyticsProducts.isEmpty;
    final isStillLoading = productProvider.isLoading ||
        (productProvider.isLoadingAnalytics && hasNoData);

    if (isStillLoading && hasNoData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 16),
              Text(
                'Loading analytics...',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    final healthScore = productProvider.inventoryHealthScore;
    final healthLabel = productProvider.healthLabel;
    Color healthColor;
    if (healthScore >= 80) {
      healthColor = AppTheme.successColor;
    } else if (healthScore >= 50) {
      healthColor = AppTheme.warningColor;
    } else {
      healthColor = AppTheme.dangerColor;
    }

    final lowStockItems = productProvider.analyticsProducts
        .where((p) => p.isLowStock)
        .toList();
    final outOfStockItems = productProvider.analyticsProducts
        .where((p) => p.isOutOfStock)
        .toList();

    return RefreshIndicator(
      onRefresh: () => productProvider.loadAnalytics(),
      child: SingleChildScrollView(
        physics: Responsive.scrollPhysics(context),
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inventory health score
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        healthColor.withValues(alpha: 0.15),
                        healthColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: healthColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Inventory Health',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 90,
                            height: 90,
                            child: CircularProgressIndicator(
                              value: healthScore / 100,
                              strokeWidth: 8,
                              backgroundColor: healthColor.withValues(
                                alpha: 0.15,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                healthColor,
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              Text(
                                '${healthScore.toInt()}',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: healthColor,
                                ),
                              ),
                              Text(
                                healthLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: healthColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _SectionCard(
                  title: 'Inventory Overview',
                  child: Column(
                    children: [
                      _SummaryRow(
                        label: 'Total Products',
                        value: '${productProvider.totalProducts}',
                        icon: Icons.inventory_2_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      const _DividerRow(),
                      GestureDetector(
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.lowStock),
                        child: _SummaryRow(
                          label: 'Low Stock Items',
                          value: '${productProvider.lowStockCount}',
                          icon: Icons.warning_amber_rounded,
                          color: AppTheme.warningColor,
                        ),
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Out of Stock',
                        value: '${productProvider.outOfStockCount}',
                        icon: Icons.error_rounded,
                        color: AppTheme.dangerColor,
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Locations',
                        value:
                            '${context.watch<SettingsProvider>().locations.length}',
                        icon: Icons.location_on_rounded,
                        color: AppTheme.infoColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Consumer<SettingsProvider>(
                  builder: (context, settings, _) {
                    if (!settings.pricingEnabled) {
                      return const SizedBox.shrink();
                    }
                    final allProducts = productProvider.analyticsProducts;
                    double totalCostValue = 0;
                    double totalSellingValue = 0;
                    for (final p in allProducts) {
                      totalCostValue += p.totalCostValue;
                      totalSellingValue += p.totalStockValue;
                    }
                    final totalProfit = totalSellingValue - totalCostValue;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _SectionCard(
                        title: 'Inventory Valuation',
                        child: Column(
                          children: [
                            _SummaryRow(
                              label: 'Total Cost Value',
                              value:
                                  '${AppTheme.currencySymbol}${totalCostValue.toStringAsFixed(2)}',
                              icon: Icons.money_rounded,
                              color: AppTheme.primaryColor,
                            ),
                            const _DividerRow(),
                            _SummaryRow(
                              label: 'Total Selling Value',
                              value:
                                  '${AppTheme.currencySymbol}${totalSellingValue.toStringAsFixed(2)}',
                              icon: Icons.sell_rounded,
                              color: AppTheme.infoColor,
                            ),
                            const _DividerRow(),
                            _SummaryRow(
                              label: 'Total Profit',
                              value:
                                  '${AppTheme.currencySymbol}${totalProfit.toStringAsFixed(2)}',
                              icon: Icons.trending_up_rounded,
                              color: totalProfit >= 0
                                  ? AppTheme.successColor
                                  : AppTheme.dangerColor,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                _SectionCard(
                  title: 'Transaction Summary',
                  child: Column(
                    children: [
                      _SummaryRow(
                        label: 'Stock In',
                        value:
                            '${stockProvider.transactionsByType[TransactionType.stockIn] ?? 0} entries (+${stockProvider.stockInTotal} units)',
                        icon: Icons.add_circle_rounded,
                        color: AppTheme.successColor,
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Stock Out',
                        value:
                            '${stockProvider.transactionsByType[TransactionType.stockOut] ?? 0} entries (-${stockProvider.stockOutTotal} units)',
                        icon: Icons.remove_circle_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Damage',
                        value:
                            '${stockProvider.transactionsByType[TransactionType.damage] ?? 0} entries (-${stockProvider.damageTotal} units)',
                        icon: Icons.report_problem_rounded,
                        color: AppTheme.dangerColor,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.damageHistory,
                        ),
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Transfer',
                        value:
                            '${stockProvider.transactionsByType[TransactionType.transfer] ?? 0} entries (${stockProvider.transferTotal} units)',
                        icon: Icons.swap_horiz_rounded,
                        color: AppTheme.indigoColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Stock Turnover & Net Flow
                _SectionCard(
                  title: 'Stock Turnover & Flow',
                  child: Column(
                    children: [
                      _SummaryRow(
                        label: 'Net Stock Flow',
                        value:
                            '${stockProvider.netStockChange >= 0 ? '+' : ''}${stockProvider.netStockChange} units',
                        icon: Icons.swap_vert_rounded,
                        color: stockProvider.netStockChange >= 0
                            ? AppTheme.successColor
                            : AppTheme.dangerColor,
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Avg Transaction Size',
                        value:
                            '${stockProvider.averageTransactionSize.toStringAsFixed(1)} units',
                        icon: Icons.analytics_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      const _DividerRow(),
                      _SummaryRow(
                        label: 'Peak Activity Day',
                        value: stockProvider.peakActivityDay,
                        icon: Icons.calendar_today_rounded,
                        color: AppTheme.infoColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Location breakdown
                _SectionCard(
                  title: 'Location Breakdown',
                  child: Column(
                    children: productProvider.locationBreakdown.entries.map((
                      entry,
                    ) {
                      final locQty =
                          productProvider.quantityByLocation[entry.key] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: AppTheme.infoColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${entry.value} products',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$locQty units',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Low stock items (expandable)
                if (lowStockItems.isNotEmpty)
                  _ExpandableSection(
                    title: 'Low Stock Items (${lowStockItems.length})',
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppTheme.warningColor,
                    children: lowStockItems
                        .map(
                          (p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.circle,
                              size: 8,
                              color: AppTheme.warningColor,
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              '${p.quantity} ${p.unit}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.warningColor,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 8),

                // Out of stock items (expandable)
                if (outOfStockItems.isNotEmpty)
                  _ExpandableSection(
                    title: 'Out of Stock Items (${outOfStockItems.length})',
                    icon: Icons.error_rounded,
                    iconColor: AppTheme.dangerColor,
                    children: outOfStockItems
                        .map(
                          (p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.circle,
                              size: 8,
                              color: AppTheme.dangerColor,
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              '0 ${p.unit}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.dangerColor,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 16),

                // Export full report button
                Consumer<SettingsProvider>(
                  builder: (context, settings, _) {
                    if (!settings.vendorsEnabled) {
                      return const SizedBox.shrink();
                    }
                    final vendorProvider = context.watch<VendorProvider>();
                    final vendorVolume = vendorProvider
                        .vendorsByTransactionVolume(
                          stockProvider.allTransactions,
                        );
                    if (vendorVolume.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(
                              Icons.local_shipping_rounded,
                              color: AppTheme.indigoColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Vendor Analytics',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: AppTheme.cardDecoration,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Top Vendors by Transaction Volume',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...vendorVolume.take(5).map((entry) {
                                final maxVal = vendorVolume.first.value;
                                final fraction = maxVal > 0
                                    ? entry.value / maxVal
                                    : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              entry.key,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${entry.value}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.indigoColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: fraction,
                                          backgroundColor: AppTheme.indigoColor
                                              .withValues(alpha: 0.1),
                                          color: AppTheme.indigoColor,
                                          minHeight: 6,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.excelExport),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Export Full Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== HELPER WIDGETS ====================

class _TransactionTile extends StatelessWidget {
  final StockTransactionModel transaction;
  final DateFormat dateFormat;

  const _TransactionTile({required this.transaction, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    Color typeColor;
    IconData typeIcon;

    switch (t.type) {
      case TransactionType.stockIn:
        typeColor = AppTheme.successColor;
        typeIcon = Icons.add_circle_rounded;
        break;
      case TransactionType.stockOut:
        typeColor = AppTheme.primaryColor;
        typeIcon = Icons.remove_circle_rounded;
        break;
      case TransactionType.damage:
        typeColor = AppTheme.dangerColor;
        typeIcon = Icons.report_problem_rounded;
        break;
      case TransactionType.transfer:
        typeColor = AppTheme.indigoColor;
        typeIcon = Icons.swap_horiz_rounded;
        break;
      case TransactionType.adjustment:
        typeColor = AppTheme.warningColor;
        typeIcon = Icons.tune_rounded;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GlassCard(
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, color: typeColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        t.typeLabel,
                        if (t.location.isNotEmpty) t.location,
                        if (t.userName.isNotEmpty) t.userName,
                        dateFormat.format(t.date),
                      ].join(' \u2022 '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (t.vendorName.isNotEmpty)
                      Text(
                        'Vendor: ${t.vendorName}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.indigoColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (t.reason.isNotEmpty)
                      Text(
                        t.reason,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                t.type == TransactionType.stockIn
                    ? '+${t.quantity}'
                    : t.type == TransactionType.transfer
                    ? '${t.quantity}'
                    : '-${t.quantity}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: typeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.primaryColor;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? chipColor : chipColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? null
                : Border.all(color: chipColor.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : chipColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.primaryColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 12,
            color: color.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: row,
        ),
      );
    }
    return row;
  }
}

class _DividerRow extends StatelessWidget {
  const _DividerRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return GlassSectionCard(title: title, trailing: trailing, child: child);
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _ExpandableSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: widget.iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Column(children: widget.children),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AdvancedFilterButton extends StatelessWidget {
  final bool hasActive;
  final VoidCallback onTap;

  const _AdvancedFilterButton({required this.hasActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.tune_rounded, size: 20),
          tooltip: 'User & Vendor filters',
          onPressed: onTap,
        ),
        if (hasActive)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double? changePercent;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.changePercent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: color.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (changePercent != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  changePercent! >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 12,
                  color: changePercent! >= 0
                      ? AppTheme.successColor
                      : AppTheme.dangerColor,
                ),
                const SizedBox(width: 2),
                Text(
                  '${changePercent! >= 0 ? '+' : ''}${changePercent!.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: changePercent! >= 0
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final List<_KpiCard> cards;
  final EdgeInsetsGeometry? padding;

  const _KpiRow({required this.cards, this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        height: 82,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: Responsive.scrollPhysics(context),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => cards[i],
        ),
      ),
    );
  }
}
