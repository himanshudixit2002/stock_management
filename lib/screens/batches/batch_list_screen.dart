import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/batch_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/batch_provider.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../config/routes.dart';
import '../../utils/responsive.dart';

enum _BatchFilter { all, active, expiringSoon, expired, recalled }

class BatchListScreen extends StatefulWidget {
  const BatchListScreen({super.key});

  @override
  State<BatchListScreen> createState() => _BatchListScreenState();
}

class _BatchListScreenState extends State<BatchListScreen> {
  _BatchFilter _filter = _BatchFilter.all;

  List<BatchModel> _filtered(List<BatchModel> batches) {
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 30));
    switch (_filter) {
      case _BatchFilter.all:
        return batches;
      case _BatchFilter.active:
        return batches
            .where(
              (b) =>
                  b.status == BatchStatus.active && b.expiryDate.isAfter(now),
            )
            .toList();
      case _BatchFilter.expiringSoon:
        return batches
            .where(
              (b) =>
                  b.status == BatchStatus.active &&
                  b.expiryDate.isAfter(now) &&
                  b.expiryDate.isBefore(soon),
            )
            .toList();
      case _BatchFilter.expired:
        return batches
            .where(
              (b) =>
                  b.status == BatchStatus.active && b.expiryDate.isBefore(now),
            )
            .toList();
      case _BatchFilter.recalled:
        return batches.where((b) => b.status == BatchStatus.recalled).toList();
    }
  }

  Color _expiryColor(DateTime expiryDate) {
    final now = DateTime.now();
    final diff = expiryDate.difference(now).inDays;
    if (diff <= 0) return AppTheme.dangerColor;
    if (diff < 7) return const Color(0xFFFB8C00); // orange
    if (diff < 30) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  String _expiryLabel(DateTime expiryDate) {
    final now = DateTime.now();
    final diff = expiryDate.difference(now).inDays;
    if (diff < 0) return 'Expired ${-diff} days ago';
    if (diff == 0) return 'Expires today';
    if (diff == 1) return 'Expires in 1 day';
    return 'Expires in $diff days';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.manageBatches)) {
      return Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const AppBarTitleRow(
              icon: Icons.layers_rounded,
              color: AppTheme.primaryColor,
              title: 'Batch Tracking',
            ),
          ),
          body: const Center(
            child: Text('You do not have permission to access this feature.'),
          ),
        ),
      );
    }

    final provider = context.watch<BatchProvider>();
    final batches = _filtered(provider.batches);

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.layers_rounded,
            color: AppTheme.primaryColor,
            title: 'Batch Tracking',
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.addBatch),
          child: const Icon(Icons.add_rounded),
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: _BatchFilter.values.map((f) {
                  final label = switch (f) {
                    _BatchFilter.all => 'All',
                    _BatchFilter.active => 'Active',
                    _BatchFilter.expiringSoon => 'Expiring Soon',
                    _BatchFilter.expired => 'Expired',
                    _BatchFilter.recalled => 'Recalled',
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                      selectedColor: AppTheme.primaryColor,
                      labelStyle: TextStyle(
                        color: _filter == f
                            ? Colors.white
                            : AppTheme.textPri(context),
                        fontWeight: FontWeight.w500,
                      ),
                      checkmarkColor: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: provider.isLoading
                  ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                  : batches.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.layers_clear_rounded,
                      title: 'No Batches',
                      subtitle: 'Add a batch to start tracking.',
                      buttonText: 'Add Batch',
                      onButtonPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.addBatch),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: Responsive.contentMaxWidth(context),
                        ),
                        child: RefreshIndicator(
                          onRefresh: () async {
                            final companyId = context
                                .read<AuthProvider>()
                                .currentUser!
                                .companyId;
                            context.read<BatchProvider>().initialize(
                              companyId: companyId,
                            );
                          },
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              Responsive.horizontalPadding(context),
                              0,
                              Responsive.horizontalPadding(context),
                              80,
                            ),
                            itemCount: batches.length,
                            itemBuilder: (context, index) {
                              final batch = batches[index];
                              final color = _expiryColor(batch.expiryDate);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
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
                                                color: color.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.layers_rounded,
                                                color: color,
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
                                                    batch.batchNumber,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15,
                                                      color: AppTheme.textPri(
                                                        context,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    batch.productName,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                batch.statusLabel,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: color,
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
                                              Icons.inventory_2_outlined,
                                              'Qty: ${batch.quantity}',
                                            ),
                                            const SizedBox(width: 12),
                                            if (batch.location.isNotEmpty)
                                              _infoChip(
                                                Icons.location_on_outlined,
                                                batch.location,
                                              ),
                                            const Spacer(),
                                            Text(
                                              _expiryLabel(batch.expiryDate),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: color,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Expiry: ${DateFormat.yMMMd().format(batch.expiryDate)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSec(context),
                                          ),
                                        ),
                                      ],
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
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
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
