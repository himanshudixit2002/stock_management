import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/purchase_order_model.dart';
import '../../models/sales_order_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';

/// A compact, tappable "Today" snapshot for Home: how many stock transactions
/// happened today, how many products are low on stock, and how many orders are
/// still awaiting action. Each segment deep-links to the relevant screen using
/// the existing routes. Reads live from providers (which already seed cached
/// values for an instant first paint) and reconciles silently.
///
/// Kept to a single compact row so it never pushes the daily actions off-screen.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final perms = context.select<AuthProvider, Map<String, bool>>(
      (a) =>
          a.currentUser?.effectivePermissions ?? UserModel.defaultPermissions,
    );

    final todayTxns = context.select<StockProvider, int>((s) {
      final now = DateTime.now();
      return s.allTransactions
          .where(
            (t) =>
                t.date.year == now.year &&
                t.date.month == now.month &&
                t.date.day == now.day,
          )
          .length;
    });

    final lowStock = context.select<ProductProvider, int>(
      (p) => p.lowStockCount,
    );

    final canViewSO = perms['canViewSalesOrders'] == true;
    final canViewPO = perms['canViewPurchaseOrders'] == true;

    final pendingSales = canViewSO
        ? context.select<SalesOrderProvider, int>(
            (p) => p.orders
                .where(
                  (o) =>
                      o.status == SOStatus.draft ||
                      o.status == SOStatus.confirmed,
                )
                .length,
          )
        : 0;
    final pendingPurchase = canViewPO
        ? context.select<PurchaseOrderProvider, int>(
            (p) => p.orders
                .where(
                  (o) =>
                      o.status == POStatus.draft ||
                      o.status == POStatus.sent ||
                      o.status == POStatus.partial,
                )
                .length,
          )
        : 0;
    final pendingOrders = pendingSales + pendingPurchase;
    final showPendingOrders = canViewSO || canViewPO;

    final segments = <_TodaySegment>[
      _TodaySegment(
        label: 'Today',
        value: todayTxns,
        icon: Icons.receipt_long_rounded,
        color: AppTheme.infoColor,
        onTap: () =>
            Navigator.pushNamed(context, AppRoutes.transactionHistory),
      ),
      _TodaySegment(
        label: 'Low stock',
        value: lowStock,
        icon: Icons.warning_amber_rounded,
        color: lowStock > 0 ? AppTheme.warningColor : AppTheme.successColor,
        onTap: () => Navigator.pushNamed(context, AppRoutes.lowStock),
      ),
      if (showPendingOrders)
        _TodaySegment(
          label: 'Pending',
          value: pendingOrders,
          icon: Icons.pending_actions_rounded,
          color: AppTheme.indigoColor,
          onTap: () => Navigator.pushNamed(
            context,
            canViewSO ? AppRoutes.salesOrders : AppRoutes.purchaseOrders,
          ),
        ),
    ];

    return FadeSlideIn(
      child: GlassPanel(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 36,
                  color: AppTheme.dividerC(context),
                ),
              Expanded(child: _SegmentTile(segment: segments[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodaySegment {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TodaySegment({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _SegmentTile extends StatelessWidget {
  final _TodaySegment segment;
  const _SegmentTile({required this.segment});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${segment.value} ${segment.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: segment.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(segment.icon, size: 18, color: segment.color),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CountUpText(
                        segment.value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: segment.color,
                        ),
                      ),
                      Text(
                        segment.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
