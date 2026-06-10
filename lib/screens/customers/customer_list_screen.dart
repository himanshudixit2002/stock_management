import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../config/app_navigation.dart';

enum _CustomerSort {
  nameAsc,
  nameDesc,
  ordersHigh,
  ordersLow,
  spentHigh,
  spentLow,
}

enum _StatusFilter { all, activeOnly, inactiveOnly }

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  _CustomerSort _sort = _CustomerSort.nameAsc;
  _StatusFilter _statusFilter = _StatusFilter.all;
  bool _hasOrdersOnly = false;
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

  bool get _hasActiveFilters =>
      _statusFilter != _StatusFilter.all || _hasOrdersOnly;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<CustomerModel> _applyFiltersAndSort(List<CustomerModel> customers) {
    var result = customers.where((c) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!c.name.toLowerCase().contains(q) &&
            !c.company.toLowerCase().contains(q) &&
            !c.email.toLowerCase().contains(q) &&
            !c.phone.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_statusFilter == _StatusFilter.activeOnly && !c.isActive)
        return false;
      if (_statusFilter == _StatusFilter.inactiveOnly && c.isActive)
        return false;
      if (_hasOrdersOnly && c.totalOrders <= 0) return false;
      return true;
    }).toList();

    result.sort(
      (a, b) => switch (_sort) {
        _CustomerSort.nameAsc => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _CustomerSort.nameDesc => b.name.toLowerCase().compareTo(
          a.name.toLowerCase(),
        ),
        _CustomerSort.ordersHigh => b.totalOrders.compareTo(a.totalOrders),
        _CustomerSort.ordersLow => a.totalOrders.compareTo(b.totalOrders),
        _CustomerSort.spentHigh => b.totalSpent.compareTo(a.totalSpent),
        _CustomerSort.spentLow => a.totalSpent.compareTo(b.totalSpent),
      },
    );

    return result;
  }

  void _showFilterSheet() {
    var tempStatus = _statusFilter;
    var tempHasOrders = _hasOrdersOnly;

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.dividerC(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Filter Customers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const Spacer(),
                        if (tempStatus != _StatusFilter.all || tempHasOrders)
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                tempStatus = _StatusFilter.all;
                                tempHasOrders = false;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _FilterToggle(
                          label: 'All',
                          selected: tempStatus == _StatusFilter.all,
                          onTap: () => setSheetState(
                            () => tempStatus = _StatusFilter.all,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterToggle(
                          label: 'Active',
                          selected: tempStatus == _StatusFilter.activeOnly,
                          onTap: () => setSheetState(
                            () => tempStatus = _StatusFilter.activeOnly,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterToggle(
                          label: 'Inactive',
                          selected: tempStatus == _StatusFilter.inactiveOnly,
                          onTap: () => setSheetState(
                            () => tempStatus = _StatusFilter.inactiveOnly,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Has orders',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: tempHasOrders,
                          activeTrackColor: AppTheme.primaryColor,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            setSheetState(() => tempHasOrders = v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _statusFilter = tempStatus;
                            _hasOrdersOnly = tempHasOrders;
                          });
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.viewCustomers)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customers')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final customerProvider = context.watch<CustomerProvider>();
    final allCustomers = customerProvider.customers;
    final filtered = _applyFiltersAndSort(allCustomers);
    final currencyFormat = NumberFormat.currency(
      symbol: AppTheme.currencySymbol,
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.people_rounded,
          color: AppTheme.primaryColor,
          title: 'Customers (${allCustomers.length})',
        ),
        actions: [
          PopupMenuButton<_CustomerSort>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              _sortMenuItem(_CustomerSort.nameAsc, 'Name A–Z'),
              _sortMenuItem(_CustomerSort.nameDesc, 'Name Z–A'),
              const PopupMenuDivider(),
              _sortMenuItem(_CustomerSort.ordersHigh, 'Orders: High to Low'),
              _sortMenuItem(_CustomerSort.ordersLow, 'Orders: Low to High'),
              const PopupMenuDivider(),
              _sortMenuItem(_CustomerSort.spentHigh, 'Spent: High to Low'),
              _sortMenuItem(_CustomerSort.spentLow, 'Spent: Low to High'),
            ],
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _hasActiveFilters,
              smallSize: 8,
              child: const Icon(Icons.filter_list_rounded),
            ),
            tooltip: 'Filter',
            onPressed: _showFilterSheet,
          ),
        ],
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
                    8,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search customers...',
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
                      filled: true,
                      fillColor: AppTheme.inputFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                if (_hasActiveFilters || _sort != _CustomerSort.nameAsc)
                  _ActiveFilterChips(
                    statusFilter: _statusFilter,
                    hasOrdersOnly: _hasOrdersOnly,
                    sort: _sort,
                    onClearStatus: () =>
                        setState(() => _statusFilter = _StatusFilter.all),
                    onClearHasOrders: () =>
                        setState(() => _hasOrdersOnly = false),
                    onClearSort: () =>
                        setState(() => _sort = _CustomerSort.nameAsc),
                    onClearAll: () => setState(() {
                      _statusFilter = _StatusFilter.all;
                      _hasOrdersOnly = false;
                      _sort = _CustomerSort.nameAsc;
                    }),
                  ),
                Expanded(
                  child: customerProvider.isLoading && allCustomers.isEmpty
                      ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                      : filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.people_outline_rounded,
                          title: _searchQuery.isEmpty && !_hasActiveFilters
                              ? 'No Customers'
                              : 'No matching customers',
                          subtitle: _searchQuery.isEmpty && !_hasActiveFilters
                              ? 'Add your first customer to get started.'
                              : 'Try different search terms or filters',
                          buttonText:
                              _searchQuery.isEmpty &&
                                  !_hasActiveFilters &&
                                  (user?.hasPermission(
                                        AppPermissions.addCustomers,
                                      ) ??
                                      false)
                              ? 'Add Customer'
                              : null,
                          onButtonPressed:
                              _searchQuery.isEmpty &&
                                  !_hasActiveFilters &&
                                  (user?.hasPermission(
                                        AppPermissions.addCustomers,
                                      ) ??
                                      false)
                              ? () =>
                                    context.pushAppRoute(AppRoutes.addCustomer)
                              : null,
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            context.read<CustomerProvider>().initialize(
                              companyId: context
                                  .read<AuthProvider>()
                                  .currentUser!
                                  .companyId,
                            );
                          },
                          child: Responsive.listGridColumns(context) > 1
                              ? GridView.builder(
                                  controller: _scrollController,
                                  padding: EdgeInsets.all(
                                    Responsive.horizontalPadding(context),
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            Responsive.listGridColumns(context),
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 0,
                                        mainAxisExtent:
                                            Responsive.listGridColumns(
                                                  context,
                                                ) >=
                                                3
                                            ? 110
                                            : 100,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final customer = filtered[index];
                                    return AnimatedListItem(
                                      index: index,
                                      child: _buildCustomerCard(
                                        context,
                                        customer,
                                        currencyFormat,
                                      ),
                                    );
                                  },
                                )
                              : ListView.separated(
                                  controller: _scrollController,
                                  padding: EdgeInsets.all(
                                    Responsive.horizontalPadding(context),
                                  ),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final customer = filtered[index];
                                    return AnimatedListItem(
                                      index: index,
                                      child: _buildCustomerCard(
                                        context,
                                        customer,
                                        currencyFormat,
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _showScrollToTop ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: FloatingActionButton.small(
              heroTag: 'scrollTop',
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
          ),
          const SizedBox(height: 8),
          if (user?.hasPermission(AppPermissions.addCustomers) ?? false)
            FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.addCustomer),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add Customer'),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(
    BuildContext context,
    CustomerModel customer,
    NumberFormat currencyFormat,
  ) {
    return GlassCard(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushAppRoute(AppRoutes.customerDetail, extra: customer.id);
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  if (customer.company.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      customer.company,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (customer.phone.isNotEmpty) ...[
                        Icon(
                          Icons.phone_rounded,
                          size: 13,
                          color: AppTheme.textTer(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          customer.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Icon(
                        Icons.receipt_rounded,
                        size: 13,
                        color: AppTheme.textTer(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${customer.totalOrders} orders',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  currencyFormat.format(customer.totalSpent),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: customer.isActive
                        ? AppTheme.successColor.withValues(alpha: 0.12)
                        : AppTheme.dangerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    customer.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: customer.isActive
                          ? AppTheme.successColor
                          : AppTheme.dangerColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuEntry<_CustomerSort> _sortMenuItem(
    _CustomerSort value,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_sort == value)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.check_rounded,
                size: 18,
                color: AppTheme.primaryColor,
              ),
            ),
          Text(label),
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final _StatusFilter statusFilter;
  final bool hasOrdersOnly;
  final _CustomerSort sort;
  final VoidCallback onClearStatus;
  final VoidCallback onClearHasOrders;
  final VoidCallback onClearSort;
  final VoidCallback onClearAll;

  const _ActiveFilterChips({
    required this.statusFilter,
    required this.hasOrdersOnly,
    required this.sort,
    required this.onClearStatus,
    required this.onClearHasOrders,
    required this.onClearSort,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (statusFilter == _StatusFilter.activeOnly) {
      chips.add(_chip(context, 'Active only', onClearStatus));
    } else if (statusFilter == _StatusFilter.inactiveOnly) {
      chips.add(_chip(context, 'Inactive only', onClearStatus));
    }

    if (hasOrdersOnly) {
      chips.add(_chip(context, 'Has orders', onClearHasOrders));
    }

    if (sort != _CustomerSort.nameAsc) {
      final label = switch (sort) {
        _CustomerSort.nameDesc => 'Name Z–A',
        _CustomerSort.ordersHigh => 'Orders ↑',
        _CustomerSort.ordersLow => 'Orders ↓',
        _CustomerSort.spentHigh => 'Spent ↑',
        _CustomerSort.spentLow => 'Spent ↓',
        _ => '',
      };
      chips.add(_chip(context, label, onClearSort));
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
      ),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
            if (chips.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: GestureDetector(
                  onTap: onClearAll,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      labelStyle: TextStyle(color: AppTheme.primaryColor),
      deleteIconColor: AppTheme.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : AppTheme.inputFill(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primaryColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? AppTheme.primaryColor
                  : AppTheme.textSec(context),
            ),
          ),
        ),
      ),
    );
  }
}
