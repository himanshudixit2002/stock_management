import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../ai/rag_chat_screen.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/return_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/return_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/provider_error_banner.dart';
import '../../config/app_navigation.dart';

class ReturnsListScreen extends StatefulWidget {
  const ReturnsListScreen({super.key});

  @override
  State<ReturnsListScreen> createState() => _ReturnsListScreenState();
}

class _ReturnsListScreenState extends State<ReturnsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ReturnStatus? _statusFilter;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color _statusColor(ReturnStatus status) => switch (status) {
    ReturnStatus.pending => AppTheme.warningColor,
    ReturnStatus.approved => AppTheme.primaryColor,
    ReturnStatus.processed => AppTheme.successColor,
    ReturnStatus.rejected => AppTheme.dangerColor,
  };

  List<ReturnModel> _filteredReturns(
    List<ReturnModel> returns,
    ReturnType type,
  ) {
    var result = returns.where((r) => r.type == type).toList();
    if (_statusFilter != null) {
      result = result.where((r) => r.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where(
            (r) =>
                r.customerName.toLowerCase().contains(q) ||
                r.vendorName.toLowerCase().contains(q) ||
                r.relatedOrderId.toLowerCase().contains(q) ||
                r.relatedOrderSummary.toLowerCase().contains(q) ||
                r.id.toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewReturns,
      featureName: 'Returns',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    final allReturns = context.watch<ReturnProvider>().returns;
    final isLoading = context.watch<ReturnProvider>().isLoading;
    final errorMessage = context.watch<ReturnProvider>().errorMessage;
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.assignment_return_rounded,
          color: AppTheme.warningColor,
          title: 'Returns',
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSec(context),
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Customer Returns'),
            Tab(text: 'Vendor Returns'),
          ],
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
                if (errorMessage != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Responsive.horizontalPadding(context),
                      8,
                      Responsive.horizontalPadding(context),
                      0,
                    ),
                    child: ProviderErrorBanner(
                      message: errorMessage,
                      onDismiss: () =>
                          context.read<ReturnProvider>().clearError(),
                      onRetry: () => context.read<ReturnProvider>().initialize(
                        companyId: context
                            .read<AuthProvider>()
                            .currentUser!
                            .companyId,
                      ),
                    ),
                  ),
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
                      hintText: 'Search returns...',
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
                      _buildFilterChip('Pending', ReturnStatus.pending),
                      _buildFilterChip('Approved', ReturnStatus.approved),
                      _buildFilterChip('Processed', ReturnStatus.processed),
                      _buildFilterChip('Rejected', ReturnStatus.rejected),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildReturnList(
                        allReturns,
                        ReturnType.customerReturn,
                        isLoading,
                        dateFormat,
                      ),
                      _buildReturnList(
                        allReturns,
                        ReturnType.vendorReturn,
                        isLoading,
                        dateFormat,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton:
          (user?.hasPermission(AppPermissions.createReturns) ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.createReturn),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Return'),
            )
          : null,
    );
  }

  Widget _buildReturnList(
    List<ReturnModel> allReturns,
    ReturnType type,
    bool isLoading,
    DateFormat dateFormat,
  ) {
    final filtered = _filteredReturns(allReturns, type);
    if (isLoading && allReturns.isEmpty) {
      return const ShimmerLoading(layout: ShimmerLayout.listTile);
    }
    if (filtered.isEmpty) {
      final hasFilters = _statusFilter != null || _searchQuery.isNotEmpty;
      return EmptyStateWidget(
        icon: Icons.assignment_return_outlined,
        title:
            'No ${type == ReturnType.customerReturn ? 'Customer' : 'Vendor'} Returns',
        subtitle: hasFilters
            ? 'Try changing filters or search query.'
            : 'Returns will appear here when created.',
        buttonText:
            hasFilters ||
                !(context.read<AuthProvider>().currentUser?.hasPermission(
                      AppPermissions.createReturns,
                    ) ??
                    false)
            ? null
            : 'Create Return',
        onButtonPressed: hasFilters
            ? null
            : (context.read<AuthProvider>().currentUser?.hasPermission(
                    AppPermissions.createReturns,
                  ) ??
                  false)
            ? () => context.pushAppRoute(AppRoutes.createReturn)
            : null,
      );
    }
    return RefreshIndicator(
      color: AppTheme.primaryColor,
      onRefresh: () async {
        final companyId = context.read<AuthProvider>().currentUser!.companyId;
        context.read<ReturnProvider>().initialize(companyId: companyId);
      },
      child: Responsive.listGridColumns(context) > 1
          ? GridView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
                vertical: 4,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.listGridColumns(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 0,
                mainAxisExtent: Responsive.listGridColumns(context) >= 3
                    ? 120
                    : 110,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final ret = filtered[index];
                final statusColor = _statusColor(ret.status);
                final partyName = type == ReturnType.customerReturn
                    ? (ret.customerName.isNotEmpty
                          ? ret.customerName
                          : 'Unknown')
                    : (ret.vendorName.isNotEmpty ? ret.vendorName : 'Unknown');
                return AnimatedListItem(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: () => context.pushAppRoute(
                        AppRoutes.returnDetail,
                        extra: ret.id,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.assignment_return_rounded,
                                    color: statusColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        partyName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: AppTheme.textPri(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'RET-${ret.id.substring(0, 6).toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    ret.statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _infoChip(
                                  Icons.inventory_2_outlined,
                                  '${ret.items.length} items',
                                ),
                                const SizedBox(width: 16),
                                _infoChip(
                                  Icons.calendar_today_rounded,
                                  dateFormat.format(ret.createdAt),
                                ),
                                if (ret.relatedOrderId.isNotEmpty) ...[
                                  const SizedBox(width: 16),
                                  _infoChip(
                                    Icons.link_rounded,
                                    ret.relatedOrderSummary.isNotEmpty
                                        ? (ret.relatedOrderSummary
                                                      .split('\n')
                                                      .first
                                                      .length >
                                                  28
                                              ? '${ret.relatedOrderSummary.split('\n').first.substring(0, 28)}…'
                                              : ret.relatedOrderSummary
                                                    .split('\n')
                                                    .first)
                                        : ret.relatedOrderId
                                              .substring(0, 6)
                                              .toUpperCase(),
                                  ),
                                ],
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
                horizontal: Responsive.horizontalPadding(context),
                vertical: 4,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final ret = filtered[index];
                final statusColor = _statusColor(ret.status);
                final partyName = type == ReturnType.customerReturn
                    ? (ret.customerName.isNotEmpty
                          ? ret.customerName
                          : 'Unknown')
                    : (ret.vendorName.isNotEmpty ? ret.vendorName : 'Unknown');
                return AnimatedListItem(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: () => context.pushAppRoute(
                        AppRoutes.returnDetail,
                        extra: ret.id,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.assignment_return_rounded,
                                    color: statusColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        partyName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: AppTheme.textPri(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'RET-${ret.id.substring(0, 6).toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    ret.statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _infoChip(
                                  Icons.inventory_2_outlined,
                                  '${ret.items.length} items',
                                ),
                                const SizedBox(width: 16),
                                _infoChip(
                                  Icons.calendar_today_rounded,
                                  dateFormat.format(ret.createdAt),
                                ),
                                if (ret.relatedOrderId.isNotEmpty) ...[
                                  const SizedBox(width: 16),
                                  _infoChip(
                                    Icons.link_rounded,
                                    ret.relatedOrderSummary.isNotEmpty
                                        ? (ret.relatedOrderSummary
                                                      .split('\n')
                                                      .first
                                                      .length >
                                                  28
                                              ? '${ret.relatedOrderSummary.split('\n').first.substring(0, 28)}…'
                                              : ret.relatedOrderSummary
                                                    .split('\n')
                                                    .first)
                                        : ret.relatedOrderId
                                              .substring(0, 6)
                                              .toUpperCase(),
                                  ),
                                ],
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
    );
  }

  Widget _buildFilterChip(String label, ReturnStatus? status) {
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
