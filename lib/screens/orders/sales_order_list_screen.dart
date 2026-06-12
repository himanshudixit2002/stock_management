import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/sales_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/stock_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../config/routes.dart';

class SalesOrderListScreen extends StatefulWidget {
  const SalesOrderListScreen({super.key});

  @override
  State<SalesOrderListScreen> createState() => _SalesOrderListScreenState();
}

class _SalesOrderListScreenState extends State<SalesOrderListScreen> {
  SOStatus? _statusFilter;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _statusColor(BuildContext context, SOStatus status) => switch (status) {
    SOStatus.draft => Theme.of(context).colorScheme.outline,
    SOStatus.confirmed => AppTheme.primaryColor,
    SOStatus.dispatched => AppTheme.indigoColor,
    SOStatus.delivered => AppTheme.successColor,
    SOStatus.cancelled => AppTheme.dangerColor,
  };

  List<SalesOrderModel> _filteredOrders(List<SalesOrderModel> orders) {
    var result = orders;
    if (_statusFilter != null) {
      result = result.where((o) => o.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where(
            (o) =>
                o.customerName.toLowerCase().contains(q) ||
                o.id.toLowerCase().contains(q) ||
                o.notes.toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewSalesOrders,
      featureName: 'Sales Orders',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    final allOrders = context.watch<SalesOrderProvider>().orders;
    final activeHolds = context.watch<StockProvider>().activeHolds;
    final isLoading = context.watch<SalesOrderProvider>().isLoading;
    final holdCountByOrder = <String, int>{};
    for (final hold in activeHolds) {
      if (hold.sourceId.isEmpty) continue;
      holdCountByOrder[hold.sourceId] =
          (holdCountByOrder[hold.sourceId] ?? 0) + hold.remainingQuantity;
    }
    final filtered = _filteredOrders(allOrders);
    final currencyFormat = NumberFormat.currency(
      symbol: AppTheme.currencySymbol,
      decimalDigits: 2,
    );
    final dateFormat = DateFormat('dd MMM yyyy');

    return AppScreenScaffold(
      icon: Icons.receipt_long_rounded,
      iconColor: AppTheme.indigoColor,
      title: 'Sales Orders',
      body: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    12,
                    Responsive.horizontalPadding(context),
                    0,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search orders...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.horizontalPadding(context),
                    ),
                    children: [
                      _buildFilterChip('All', null),
                      _buildFilterChip('Draft', SOStatus.draft),
                      _buildFilterChip('Confirmed', SOStatus.confirmed),
                      _buildFilterChip('Dispatched', SOStatus.dispatched),
                      _buildFilterChip('Delivered', SOStatus.delivered),
                      _buildFilterChip('Cancelled', SOStatus.cancelled),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: isLoading && allOrders.isEmpty
                      ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                      : filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.receipt_long_outlined,
                          title: 'No Sales Orders',
                          subtitle:
                              _statusFilter != null || _searchQuery.isNotEmpty
                              ? 'Try changing filters or search query.'
                              : 'Create your first sales order to get started.',
                          buttonText:
                              allOrders.isEmpty &&
                                  (user?.hasPermission(
                                        AppPermissions.createSalesOrders,
                                      ) ??
                                      false)
                              ? 'Create Order'
                              : null,
                          onButtonPressed:
                              allOrders.isEmpty &&
                                  (user?.hasPermission(
                                        AppPermissions.createSalesOrders,
                                      ) ??
                                      false)
                              ? () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.createSalesOrder,
                                )
                              : null,
                        )
                      : RefreshIndicator(
                          color: AppTheme.primaryColor,
                          onRefresh: () async {
                            final companyId = context
                                .read<AuthProvider>()
                                .currentUser!
                                .companyId;
                            context.read<SalesOrderProvider>().initialize(
                              companyId: companyId,
                            );
                          },
                          child: Responsive.listGridColumns(context) > 1
                              ? GridView.builder(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: Responsive.horizontalPadding(
                                      context,
                                    ),
                                    vertical: 4,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            Responsive.listGridColumns(context),
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 0,
                                        mainAxisExtent: 120,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final order = filtered[index];
                                    final statusColor = _statusColor(
                                      context,
                                      order.status,
                                    );
                                    final heldQty =
                                        holdCountByOrder[order.id] ?? 0;
                                    return AnimatedListItem(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: GlassCard(
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.salesOrderDetail,
                                            arguments: order.id,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .receipt_long_rounded,
                                                        color: statusColor,
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            order
                                                                    .customerName
                                                                    .isNotEmpty
                                                                ? order
                                                                      .customerName
                                                                : 'Walk-in Customer',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize: 15,
                                                              color:
                                                                  AppTheme.textPri(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            'SO-${order.id.substring(0, 6).toUpperCase()}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  AppTheme.textSec(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        order.statusLabel,
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    if (heldQty > 0) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: AppTheme
                                                              .warningColor
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'Hold $heldQty',
                                                          style: const TextStyle(
                                                            color: AppTheme
                                                                .warningColor,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    _infoChip(
                                                      Icons
                                                          .inventory_2_outlined,
                                                      '${order.items.length} items',
                                                    ),
                                                    const SizedBox(width: 16),
                                                    _infoChip(
                                                      Icons
                                                          .calendar_today_rounded,
                                                      dateFormat.format(
                                                        order.createdAt,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      currencyFormat.format(
                                                        order.totalAmount,
                                                      ),
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 15,
                                                        color: AppTheme.textPri(
                                                          context,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: Responsive.horizontalPadding(
                                      context,
                                    ),
                                    vertical: 4,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final order = filtered[index];
                                    final statusColor = _statusColor(
                                      context,
                                      order.status,
                                    );
                                    final heldQty =
                                        holdCountByOrder[order.id] ?? 0;
                                    return AnimatedListItem(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: GlassCard(
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.salesOrderDetail,
                                            arguments: order.id,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .receipt_long_rounded,
                                                        color: statusColor,
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            order
                                                                    .customerName
                                                                    .isNotEmpty
                                                                ? order
                                                                      .customerName
                                                                : 'Walk-in Customer',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize: 15,
                                                              color:
                                                                  AppTheme.textPri(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            'SO-${order.id.substring(0, 6).toUpperCase()}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  AppTheme.textSec(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        order.statusLabel,
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    if (heldQty > 0) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: AppTheme
                                                              .warningColor
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'Hold $heldQty',
                                                          style: const TextStyle(
                                                            color: AppTheme
                                                                .warningColor,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    _infoChip(
                                                      Icons
                                                          .inventory_2_outlined,
                                                      '${order.items.length} items',
                                                    ),
                                                    const SizedBox(width: 16),
                                                    _infoChip(
                                                      Icons
                                                          .calendar_today_rounded,
                                                      dateFormat.format(
                                                        order.createdAt,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      currencyFormat.format(
                                                        order.totalAmount,
                                                      ),
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 15,
                                                        color: AppTheme.textPri(
                                                          context,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
      floatingActionButton:
          (user?.hasPermission(AppPermissions.createSalesOrders) ?? false)
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.createSalesOrder),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New SO'),
            )
          : null,
    );
  }

  Widget _buildFilterChip(String label, SOStatus? status) {
    final isSelected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _statusFilter = status),
        selectedColor: AppTheme.primaryColor,
        backgroundColor: AppTheme.card(context),
        side: BorderSide(
          color: isSelected ? Colors.transparent : AppTheme.dividerC(context),
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textPri(context),
          fontWeight: FontWeight.w500,
        ),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textTer(context)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}
