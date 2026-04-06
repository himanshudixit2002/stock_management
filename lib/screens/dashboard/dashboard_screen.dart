import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/stock_transaction_model.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/charts/transaction_line_chart.dart';
import '../../widgets/charts/category_pie_chart.dart';
import '../../widgets/charts/top_products_chart.dart';
import '../../widgets/charts/stock_bar_chart.dart';
import '../../utils/responsive.dart';
import '../../widgets/empty_state_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _chartDays = 7;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.viewDashboard)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final today = DateFormat('EEEE, d MMM').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Selector<ProductProvider, int>(
            selector: (_, p) => p.lowStockCount,
            builder: (context, lowStockCount, _) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {
                    _StatsRow._showLowStockSheet(context);
                  },
                  tooltip: 'Low Stock Alerts',
                ),
                if (lowStockCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.dangerColor,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        '$lowStockCount',
                        style: TextStyle(
                          color: AppTheme.surface(context),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: RefreshIndicator(
          onRefresh: () async {
            final companyId = context.read<ProductProvider>().companyId;
            context.read<ProductProvider>().initialize(companyId: companyId);
            context.read<CategoryProvider>().initialize(companyId: companyId);
            context.read<StockProvider>().initialize(companyId: companyId);
          },
          child: Selector<ProductProvider, bool>(
            selector: (_, p) => p.isLoading,
            builder: (context, isLoading, child) {
              if (isLoading &&
                  context.read<ProductProvider>().totalProducts == 0) {
                return const ShimmerLoading(layout: ShimmerLayout.stat);
              }
              return child!;
            },
            child: SingleChildScrollView(
              physics: Responsive.scrollPhysics(context),
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              8,
              Responsive.horizontalPadding(context),
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.contentMaxWidth(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    Selector<AuthProvider, String>(
                      selector: (_, auth) => auth.currentUser?.name ?? 'User',
                      builder: (context, name, _) => Text(
                        'Hi, $name',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(today, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),

                    Consumer<SettingsProvider>(
                      builder: (context, settings, _) {
                        if (!settings.vendorsEnabled) {
                          return const SizedBox.shrink();
                        }
                        final vendorProvider = context.watch<VendorProvider>();
                        final stockProvider = context.watch<StockProvider>();
                        final productProvider = context
                            .watch<ProductProvider>();
                        if (vendorProvider.isLoading) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              height: 36,
                              child: Row(
                                children: List.generate(
                                  3,
                                  (i) => Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Container(
                                      width: 80,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppTheme.inputFill(context),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        final activeVendors = vendorProvider.activeVendors;
                        if (activeVendors.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _VendorToggleChip(
                                  label: 'All Vendors',
                                  isSelected:
                                      stockProvider.filterVendorId.isEmpty &&
                                      productProvider.selectedVendorId == null,
                                  onTap: () {
                                    stockProvider.setVendorFilter(null);
                                    productProvider.filterByVendor(null);
                                  },
                                ),
                                ...activeVendors.map(
                                  (v) => _VendorToggleChip(
                                    label: v.name,
                                    isSelected:
                                        stockProvider.filterVendorId == v.id,
                                    onTap: () {
                                      final isActive =
                                          stockProvider.filterVendorId == v.id;
                                      stockProvider.setVendorFilter(
                                        isActive ? null : v.id,
                                      );
                                      productProvider.filterByVendor(
                                        isActive ? null : v.id,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Today summary
                    Selector<StockProvider, bool>(
                      selector: (_, s) => s.hasTodayActivity,
                      builder: (context, hasActivity, _) {
                        if (!hasActivity) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _TodaySummary(),
                        );
                      },
                    ),

                    // Stats Cards
                    const _StatsRow(),

                    const SizedBox(height: 20),

                    // Quick Actions
                    Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Selector<AuthProvider, bool>(
                      selector: (_, auth) => auth.isAdmin,
                      builder: (context, isAdmin, _) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final actions = <Widget>[
                              _QuickActionCard(
                                icon: Icons.add_box_rounded,
                                label: 'Stock In',
                                subtitle: 'Add items',
                                color: AppTheme.successColor,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.stockIn,
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.outbox_rounded,
                                label: 'Stock Out',
                                subtitle: 'Remove',
                                color: AppTheme.primaryColor,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.stockOut,
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.swap_horiz_rounded,
                                label: 'Transfer',
                                subtitle: 'Move',
                                color: AppTheme.indigoColor,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.stockTransfer,
                                ),
                              ),
                              _QuickActionCard(
                                icon: Icons.report_problem_rounded,
                                label: 'Damage',
                                subtitle: 'Report',
                                color: AppTheme.dangerColor,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.damageReport,
                                ),
                              ),
                              if (isAdmin) ...[
                                _QuickActionCard(
                                  icon: Icons.add_circle_rounded,
                                  label: 'Add Item',
                                  subtitle: 'New product',
                                  color: AppTheme.primaryDark,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.addProduct,
                                  ),
                                ),
                                _QuickActionCard(
                                  icon: Icons.upload_file_rounded,
                                  label: 'Import',
                                  subtitle: 'From Excel',
                                  color: AppTheme.accentColor,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.excelImport,
                                  ),
                                ),
                                _QuickActionCard(
                                  icon: Icons.download_rounded,
                                  label: 'Export',
                                  subtitle: 'To Excel',
                                  color: AppTheme.indigoColor,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.excelExport,
                                  ),
                                ),
                              ],
                            ];

                            final crossAxisCount =
                                Responsive.isDesktop(context)
                                    ? 6
                                    : (Responsive.isMobile(context) ? 2 : 4);
                            const spacing = 10.0;
                            final itemWidth = (constraints.maxWidth -
                                    spacing * (crossAxisCount - 1)) /
                                crossAxisCount;

                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: actions
                                  .map(
                                    (a) =>
                                        SizedBox(width: itemWidth, child: a),
                                  )
                                  .toList(),
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // Charts & Insights
                    _ChartsSection(
                      chartDays: _chartDays,
                      onDaysChanged: (d) => setState(() => _chartDays = d),
                    ),

                    const SizedBox(height: 28),

                    // Recent Activity
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Activity',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pushNamed(context, AppRoutes.reports),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    const _RecentActivitySection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return Selector<ProductProvider, ({int total, int low, int oos})>(
      selector: (_, p) => (
        total: p.totalProducts,
        low: p.lowStockCount,
        oos: p.outOfStockCount,
      ),
      builder: (context, stats, _) => Row(
        children: [
          Expanded(
            child: _StatCard(
              title: 'Products',
              value: '${stats.total}',
              icon: Icons.inventory_2_rounded,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              title: 'Low Stock',
              value: '${stats.low}',
              icon: Icons.warning_amber_rounded,
              color: AppTheme.warningColor,
              onTap: () => _showLowStockSheet(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              title: 'Out of Stock',
              value: '${stats.oos}',
              icon: Icons.error_rounded,
              color: AppTheme.dangerColor,
            ),
          ),
        ],
      ),
    );
  }

  static void _showLowStockSheet(BuildContext context) {
    final provider = context.read<ProductProvider>();
    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final lowStock = provider.lowStockProducts;
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx2, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.emptyIcon(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: AppTheme.warningColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Low Stock (${lowStock.length})',
                          style: Theme.of(ctx2).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: lowStock.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.check_circle_outline_rounded,
                            title: 'All Stocked Up',
                            subtitle: 'All products are well stocked!',
                          )
                        : GridView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  Responsive.isDesktop(context) ? 3 : 1,
                              mainAxisExtent: 80,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: lowStock.length,
                            itemBuilder: (ctx3, index) {
                              final product = lowStock[index];
                              final stockColor = AppTheme.getStockColor(
                                product.quantity,
                                threshold: product.lowStockThreshold,
                              );
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: stockColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    product.isOutOfStock
                                        ? Icons.error_rounded
                                        : Icons.warning_amber_rounded,
                                    color: stockColor,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${product.categoryName}${product.locations.isNotEmpty ? ' \u2022 ${product.locations.join(", ")}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Text(
                                  '${product.quantity} ${product.unit}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: stockColor,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// Extracted: only rebuilds when today's transactions change
class _TodaySummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<StockProvider, Map<TransactionType, int>>(
      selector: (_, s) => s.todayTransactions,
      builder: (context, today, _) {
        final inQty = today[TransactionType.stockIn] ?? 0;
        final outQty = today[TransactionType.stockOut] ?? 0;
        final dmgQty = today[TransactionType.damage] ?? 0;
        final xfrQty = today[TransactionType.transfer] ?? 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.today_rounded,
                  color: AppTheme.primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Today',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (inQty > 0)
                      _TodayChip(label: '+$inQty in', color: AppTheme.successColor),
                    if (outQty > 0)
                      _TodayChip(label: '-$outQty out', color: AppTheme.primaryColor),
                    if (xfrQty > 0)
                      _TodayChip(label: '$xfrQty xfr', color: AppTheme.indigoColor),
                    if (dmgQty > 0)
                      _TodayChip(label: '$dmgQty dmg', color: AppTheme.dangerColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Extracted: only rebuilds when recent transactions change
class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context) {
    return Selector<StockProvider, List<StockTransactionModel>>(
      selector: (_, s) => s.recentTransactions,
      builder: (context, transactions, _) {
        if (transactions.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.dividerC(context)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: AppTheme.iconMute(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'No recent activity',
                  style: TextStyle(color: AppTheme.textTer(context), fontSize: 15),
                ),
              ],
            ),
          );
        }
        return Column(
          children: transactions
              .take(10)
              .toList()
              .asMap()
              .entries
              .map(
                (e) => AnimatedListItem(
                  index: e.key,
                  child: _ActivityTile(transaction: e.value),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                color.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  if (onTap != null) ...[
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: color.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: color.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.dividerC(context)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textPri(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.textSec(context),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final StockTransactionModel transaction;

  const _ActivityTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM, hh:mm a');
    Color typeColor;
    IconData typeIcon;

    switch (transaction.type) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
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
                  transaction.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    transaction.typeLabel,
                    if (transaction.location.isNotEmpty) transaction.location,
                    if (transaction.userName.isNotEmpty)
                      'By ${transaction.userName}',
                    dateFormat.format(transaction.date),
                  ].join(' \u2022 '),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            transaction.type == TransactionType.stockIn
                ? '+${transaction.quantity}'
                : transaction.type == TransactionType.transfer
                ? '${transaction.quantity}'
                : '-${transaction.quantity}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: typeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TodayChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ChartsSection extends StatelessWidget {
  final int chartDays;
  final ValueChanged<int> onDaysChanged;

  const _ChartsSection({
    required this.chartDays,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final productProvider = context.watch<ProductProvider>();

    final countByCategory = productProvider.productCountByCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.insights_rounded,
                size: 20, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Charts & Insights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [7, 30, 90].map((d) {
            final selected = chartDays == d;
            return ChoiceChip(
              label: Text('${d}d'),
              selected: selected,
              onSelected: (_) => onDaysChanged(d),
              selectedColor: AppTheme.primaryColor,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppTheme.textSec(context),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        if (Responsive.isDesktop(context)) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RepaintBoundary(
                  child: GlassSectionCard(
                    title: 'Stock Trend',
                    icon: Icons.show_chart_rounded,
                    child: TransactionLineChart(
                      dataByDay: stockProvider.transactionsByDay,
                      days: chartDays,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: RepaintBoundary(
                  child: GlassSectionCard(
                    title: 'Category Distribution',
                    icon: Icons.pie_chart_rounded,
                    child: CategoryPieChart(
                      data: countByCategory.map(
                        (k, v) => MapEntry(k, v.toDouble()),
                      ),
                      valueLabel: 'products',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RepaintBoundary(
                  child: GlassSectionCard(
                    title: 'Top Movers',
                    icon: Icons.trending_up_rounded,
                    child: TopProductsChart(
                      data: stockProvider.topProductsByQuantityMoved,
                      barColor: AppTheme.successColor,
                      valueLabel: 'units',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: RepaintBoundary(
                  child: GlassSectionCard(
                    title: 'Stock by Location',
                    icon: Icons.bar_chart_rounded,
                    child: StockBarChart(
                      data: productProvider.quantityByLocation.map(
                        (k, v) => MapEntry(k, v.toDouble()),
                      ),
                      barColor: AppTheme.primaryColor,
                      emptyMessage: 'No location data available',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          RepaintBoundary(
            child: GlassSectionCard(
              title: 'Stock Trend',
              icon: Icons.show_chart_rounded,
              child: TransactionLineChart(
                dataByDay: stockProvider.transactionsByDay,
                days: chartDays,
              ),
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: GlassSectionCard(
              title: 'Category Distribution',
              icon: Icons.pie_chart_rounded,
              child: CategoryPieChart(
                data: countByCategory.map(
                  (k, v) => MapEntry(k, v.toDouble()),
                ),
                valueLabel: 'products',
              ),
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: GlassSectionCard(
              title: 'Top Movers',
              icon: Icons.trending_up_rounded,
              child: TopProductsChart(
                data: stockProvider.topProductsByQuantityMoved,
                barColor: AppTheme.successColor,
                valueLabel: 'units',
              ),
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: GlassSectionCard(
              title: 'Stock by Location',
              icon: Icons.bar_chart_rounded,
              child: StockBarChart(
                data: productProvider.quantityByLocation.map(
                  (k, v) => MapEntry(k, v.toDouble()),
                ),
                barColor: AppTheme.primaryColor,
                emptyMessage: 'No location data available',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VendorToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _VendorToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.indigoColor
                : AppTheme.indigoColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppTheme.indigoColor
                  : AppTheme.indigoColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_shipping_rounded,
                size: 14,
                color: isSelected
                    ? AppTheme.surface(context)
                    : AppTheme.indigoColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppTheme.surface(context)
                      : AppTheme.indigoColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
