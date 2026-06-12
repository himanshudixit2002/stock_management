import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive.dart';
import '../../providers/notification_provider.dart';
import '../../models/app_notification_model.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/animations.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _typeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('low_stock') || t.contains('warning')) {
      return Icons.warning_amber_rounded;
    }
    if (t.contains('out_of_stock') || t.contains('alert')) {
      return Icons.error_rounded;
    }
    if (t.contains('order') || t.contains('purchase')) {
      return Icons.shopping_cart_rounded;
    }
    if (t.contains('stock_in') || t.contains('receive')) {
      return Icons.archive_rounded;
    }
    if (t.contains('stock_out') || t.contains('dispatch')) {
      return Icons.unarchive_rounded;
    }
    if (t.contains('transfer')) return Icons.swap_horiz_rounded;
    if (t.contains('damage')) return Icons.report_problem_rounded;
    if (t.contains('user') || t.contains('auth')) return Icons.person_rounded;
    return Icons.notifications_rounded;
  }

  Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('low_stock') || t.contains('warning')) {
      return AppTheme.warningColor;
    }
    if (t.contains('out_of_stock') ||
        t.contains('alert') ||
        t.contains('damage')) {
      return AppTheme.dangerColor;
    }
    if (t.contains('order') || t.contains('purchase')) {
      return AppTheme.indigoColor;
    }
    if (t.contains('stock_in') || t.contains('receive')) {
      return AppTheme.successColor;
    }
    if (t.contains('stock_out') || t.contains('dispatch')) {
      return AppTheme.primaryColor;
    }
    if (t.contains('transfer')) return AppTheme.infoColor;
    return AppTheme.primaryColor;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final notifications = provider.notifications;

    return AppScreenScaffold(
      icon: Icons.notifications_rounded,
      title: 'Notifications',
      isLoading: provider.isLoading,
      shimmerLayout: ShimmerLayout.listTile,
      isEmpty: notifications.isEmpty,
      emptyState: const EmptyStateWidget(
        icon: Icons.notifications_off_rounded,
        title: 'No Notifications Yet',
        subtitle:
            'Notifications appear when stock runs low, orders change status, '
            'returns are filed, or batch items near expiry. '
            'Start adding products and stock to receive alerts.',
      ),
      actions: [
        if (provider.unreadCount > 0)
          TextButton.icon(
            onPressed: () => provider.markAllRead(),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text(
              'Mark all read',
              style: TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
            ),
          ),
      ],
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () async {
          final companyId = context.read<AuthProvider>().currentUser!.companyId;
          context.read<NotificationProvider>().initialize(
            companyId: companyId,
          );
        },
        child: ListView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.horizontalPadding(context),
            vertical: 8,
          ),
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final n = notifications[index];
            return AnimatedListItem(
              index: index,
              child: _NotificationCard(
                notification: n,
                icon: _typeIcon(n.type),
                color: _typeColor(n.type),
                relativeTime: _relativeTime(n.timestamp),
                onTap: () {
                  if (!n.isRead) {
                    provider.markRead(n.id);
                  }
                },
                onDismissed: () => provider.delete(n.id),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotificationModel notification;
  final IconData icon;
  final Color color;
  final String relativeTime;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _NotificationCard({
    required this.notification,
    required this.icon,
    required this.color,
    required this.relativeTime,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
        key: Key(notification.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppTheme.dangerColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.delete_rounded, color: AppTheme.dangerColor),
        ),
        onDismissed: (_) => onDismissed(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: isUnread
                    ? AppTheme.surface(context)
                    : AppTheme.bg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isUnread
                      ? AppTheme.dividerC(context)
                      : AppTheme.dividerC(context).withValues(alpha: 0.5),
                ),
                boxShadow: isUnread ? AppTheme.cardShadow : null,
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    if (isUnread)
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(14),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isUnread ? 12 : 16,
                          12,
                          16,
                          12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUnread
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: AppTheme.textPri(context),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (notification.message.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      notification.message,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSec(context),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    relativeTime,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMute(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isUnread)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: PulsingDot(color: color, size: 8),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
