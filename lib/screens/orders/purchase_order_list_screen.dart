import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/purchase_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../config/routes.dart';

class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  State<PurchaseOrderListScreen> createState() =>
      _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  POStatus? _statusFilter;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _statusColor(BuildContext context, POStatus status) => switch (status) {
    POStatus.draft => Theme.of(context).colorScheme.outline,
    POStatus.sent => AppTheme.infoColor,
    POStatus.partial => AppTheme.warningColor,
    POStatus.received => AppTheme.successColor,
    POStatus.cancelled => AppTheme.dangerColor,
  };

  List<PurchaseOrderModel> _filteredOrders(List<PurchaseOrderModel> orders) {
    var result = orders;
    if (_statusFilter != null) {
      result = result.where((o) => o.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where(
            (o) =>
                o.vendorName.toLowerCase().contains(q) ||
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
      permission: AppPermissions.viewPurchaseOrders,
      featureName: 'Purchase Orders',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    final allOrders = context.watch<PurchaseOrderProvider>().orders;
    final isLoading = context.watch<PurchaseOrderProvider>().isLoading;
    final filtered = _filteredOrders(allOrders);
    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(
      symbol: AppTheme.currencySymbol,
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.shopping_cart_rounded,
          color: AppTheme.primaryColor,
          title: 'Purchase Orders',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Column(
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
                      _buildFilterChip('Draft', POStatus.draft),
                      _buildFilterChip('Sent', POStatus.sent),
                      _buildFilterChip('Partial', POStatus.partial),
                      _buildFilterChip('Received', POStatus.received),
                      _buildFilterChip('Cancelled', POStatus.cancelled),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: isLoading && allOrders.isEmpty
                      ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                      : filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.shopping_cart_outlined,
                          title: 'No Purchase Orders',
                          subtitle:
                              _statusFilter != null || _searchQuery.isNotEmpty
                              ? 'Try changing filters or search query.'
                              : 'Create your first purchase order to get started.',
                          buttonText:
                              allOrders.isEmpty &&
                                  (user?.hasPermission(
                                        AppPermissions.createPurchaseOrders,
                                      ) ??
                                      false)
                              ? 'Create Order'
                              : null,
                          onButtonPressed:
                              allOrders.isEmpty &&
                                  (user?.hasPermission(
                                        AppPermissions.createPurchaseOrders,
                                      ) ??
                                      false)
                              ? () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.createPurchaseOrder,
                                )
                              : null,
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            final companyId = context
                                .read<AuthProvider>()
                                .currentUser!
                                .companyId;
                            context.read<PurchaseOrderProvider>().initialize(
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
                                    return AnimatedListItem(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: GlassCard(
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.purchaseOrderDetail,
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
                                                            .shopping_cart_rounded,
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
                                                                    .vendorName
                                                                    .isNotEmpty
                                                                ? order
                                                                      .vendorName
                                                                : 'Unknown Vendor',
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
                                                            'PO-${order.id.substring(0, 6).toUpperCase()}',
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
                                                        order.expectedDate,
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
                                    return AnimatedListItem(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: GlassCard(
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.purchaseOrderDetail,
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
                                                            .shopping_cart_rounded,
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
                                                                    .vendorName
                                                                    .isNotEmpty
                                                                ? order
                                                                      .vendorName
                                                                : 'Unknown Vendor',
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
                                                            'PO-${order.id.substring(0, 6).toUpperCase()}',
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
                                                        order.expectedDate,
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
          ),
        ),
      ),
      floatingActionButton:
          (user?.hasPermission(AppPermissions.createPurchaseOrders) ?? false)
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.createPurchaseOrder),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New PO'),
            )
          : null,
    );
  }

  Widget _buildFilterChip(String label, POStatus? status) {
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
