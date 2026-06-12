import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/stock_take_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_take_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../utils/responsive.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../config/routes.dart';
import '../../config/app_navigation.dart';

class StockTakeListScreen extends StatelessWidget {
  const StockTakeListScreen({super.key});

  Color _statusColor(BuildContext context, StockTakeStatus status) {
    return switch (status) {
      StockTakeStatus.draft => AppTheme.textSec(context),
      StockTakeStatus.inProgress => AppTheme.warningColor,
      StockTakeStatus.completed => AppTheme.successColor,
    };
  }

  IconData _statusIcon(StockTakeStatus status) {
    return switch (status) {
      StockTakeStatus.draft => Icons.edit_note_rounded,
      StockTakeStatus.inProgress => Icons.hourglass_top_rounded,
      StockTakeStatus.completed => Icons.check_circle_rounded,
    };
  }

  String _varianceSummary(StockTakeModel st) {
    if (st.items.isEmpty) return 'No items';
    final withVariance = st.items.where((i) => i.variance != 0).length;
    if (withVariance == 0) return 'No variance';
    return '$withVariance item${withVariance == 1 ? '' : 's'} with variance';
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageStockTakes,
      featureName: 'Stock Takes',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final provider = context.watch<StockTakeProvider>();
    final stockTakes = provider.stockTakes;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.assignment_rounded,
            color: AppTheme.indigoColor,
            title: 'Stock Takes',
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.pushAppRoute(AppRoutes.createStockTake),
          child: const Icon(Icons.add_rounded),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: provider.isLoading
                ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                : stockTakes.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.assignment_outlined,
                    title: 'No Stock Takes',
                    subtitle: 'Create a stock take to verify inventory counts.',
                    buttonText: 'New Stock Take',
                    onButtonPressed: () =>
                        context.pushAppRoute(AppRoutes.createStockTake),
                  )
                : RefreshIndicator(
                    color: AppTheme.primaryColor,
                    onRefresh: () async {
                      final companyId = context
                          .read<AuthProvider>()
                          .currentUser!
                          .companyId;
                      context.read<StockTakeProvider>().initialize(
                        companyId: companyId,
                      );
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        Responsive.horizontalPadding(context),
                        8,
                        Responsive.horizontalPadding(context),
                        80,
                      ),
                      itemCount: stockTakes.length,
                      itemBuilder: (context, index) {
                        final st = stockTakes[index];
                        final statusColor = _statusColor(context, st.status);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AnimatedListItem(
                            index: index,
                            child: GlassCard(
                            onTap: st.status != StockTakeStatus.completed
                                ? () => context.pushAppRoute(
                                    AppRoutes.stockTakeCount,
                                    extra: st,
                                  )
                                : null,
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
                                          color: statusColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          _statusIcon(st.status),
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
                                              st.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                                color: AppTheme.textPri(
                                                  context,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              DateFormat.yMMMd().format(
                                                st.startedAt,
                                              ),
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.textSec(
                                                  context,
                                                ),
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
                                          color: statusColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          st.statusLabel,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _infoChip(
                                        context,
                                        Icons.inventory_2_outlined,
                                        '${st.items.length} items',
                                      ),
                                      const SizedBox(width: 16),
                                      _infoChip(
                                        context,
                                        Icons.compare_arrows_rounded,
                                        _varianceSummary(st),
                                      ),
                                    ],
                                  ),
                                  if (st.locationFilter.isNotEmpty ||
                                      st.categoryFilter.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        if (st.locationFilter.isNotEmpty)
                                          _infoChip(
                                            context,
                                            Icons.location_on_outlined,
                                            st.locationFilter,
                                          ),
                                        if (st.locationFilter.isNotEmpty &&
                                            st.categoryFilter.isNotEmpty)
                                          const SizedBox(width: 12),
                                        if (st.categoryFilter.isNotEmpty)
                                          _infoChip(
                                            context,
                                            Icons.category_outlined,
                                            st.categoryFilter,
                                          ),
                                      ],
                                    ),
                                  ],
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
        ),
      ),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSec(context)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}
