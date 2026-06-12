import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../providers/batch_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';

class ExpiryAlertsScreen extends StatelessWidget {
  const ExpiryAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewExpiryAlerts,
      featureName: 'Expiry Alerts',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const AppBarTitleRow(
              icon: Icons.warning_amber_rounded,
              color: AppTheme.warningColor,
              title: 'Expiry Alerts',
            ),
            bottom: TabBar(
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: AppTheme.textSec(context),
              indicatorColor: AppTheme.primaryColor,
              tabs: const [
                Tab(text: '7 Days'),
                Tab(text: '30 Days'),
                Tab(text: '90 Days'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _ExpiryTab(days: 7),
              _ExpiryTab(days: 30),
              _ExpiryTab(days: 90),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpiryTab extends StatelessWidget {
  final int days;

  const _ExpiryTab({required this.days});

  Color _urgencyColor(int daysLeft) {
    if (daysLeft <= 0) return AppTheme.dangerColor;
    if (daysLeft < 7) return const Color(0xFFFB8C00); // orange
    if (daysLeft < 30) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  String _expiryCountdownLabel(int daysLeft) {
    if (daysLeft < 0) return 'Expired ${-daysLeft} days ago';
    if (daysLeft == 0) return 'Expires today';
    if (daysLeft == 1) return 'Expires in 1 day';
    return 'Expires in $daysLeft days';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BatchProvider>();
    final expiring = provider.getExpiringBatches(days);
    final expired = provider.expiredBatches;
    final combined = [...expired, ...expiring];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Responsive.contentMaxWidth(context),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
                vertical: 16,
              ),
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _SummaryItem(
                      label: 'Expired',
                      count: expired.length,
                      color: AppTheme.dangerColor,
                    ),
                    const SizedBox(width: 16),
                    _SummaryItem(
                      label: 'Expiring ≤${days}d',
                      count: expiring.length,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 16),
                    _SummaryItem(
                      label: 'Total',
                      count: combined.length,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: combined.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'All Clear',
                      subtitle: 'No batches expiring in this time frame.',
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        Responsive.horizontalPadding(context),
                        0,
                        Responsive.horizontalPadding(context),
                        16,
                      ),
                      itemCount: combined.length,
                      itemBuilder: (context, index) {
                        final batch = combined[index];
                        final now = DateTime.now();
                        final daysLeft = batch.expiryDate
                            .difference(now)
                            .inDays;
                        final color = _urgencyColor(daysLeft);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: color, width: 4),
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        daysLeft < 0
                                            ? Icons.error_rounded
                                            : Icons.schedule_rounded,
                                        color: color,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          batch.batchNumber,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: AppTheme.textPri(context),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          _expiryCountdownLabel(daysLeft),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    batch.productName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSec(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        'Qty: ${batch.quantity}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                      if (batch.location.isNotEmpty) ...[
                                        Text(
                                          ' • ',
                                          style: TextStyle(
                                            color: AppTheme.textSec(context),
                                          ),
                                        ),
                                        Text(
                                          batch.location,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSec(context),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        DateFormat.yMMMd().format(
                                          batch.expiryDate,
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: color,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
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

class _SummaryItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryItem({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
