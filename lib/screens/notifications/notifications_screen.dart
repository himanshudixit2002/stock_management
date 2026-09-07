import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_engine.dart';
import '../../utils/notification_routing.dart';
import '../../utils/responsive.dart';
import '../../providers/notification_provider.dart';
import '../../models/app_notification_model.dart';
import '../../models/batch_model.dart';
import '../../models/invoice_model.dart';
import '../../models/product_model.dart';
import '../../models/purchase_order_model.dart';
import '../../providers/batch_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/animations.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _typeFilter;
  bool _unreadOnly = false;

  /// Id of the row whose target is being resolved. A product alert has to look
  /// the product up before it can open the detail screen, and that can reach
  /// Firestore, so the row shows a spinner instead of appearing to ignore the
  /// tap.
  String? _openingId;

  static IconData typeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('low_stock') || t.contains('warning')) {
      return Icons.warning_amber_rounded;
    }
    if (t.contains('out_of_stock') || t.contains('alert')) {
      return Icons.error_rounded;
    }
    if (t.contains('expir')) return Icons.event_busy_rounded;
    if (t.contains('invoice')) return Icons.receipt_long_rounded;
    if (t.contains('order') || t.contains('purchase') || t.contains('po_')) {
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

  /// Severity drives the colour where it is known, so a critical alert reads as
  /// critical regardless of which subsystem raised it. Older rows have no
  /// severity, so type is the fallback.
  static Color typeColor(AppNotificationModel n) {
    switch (n.severity) {
      case AlertSeverity.critical:
        return AppTheme.dangerColor;
      case AlertSeverity.warning:
        return AppTheme.warningColor;
      case AlertSeverity.info:
        break;
    }
    final t = n.type.toLowerCase();
    if (t.contains('low_stock')) return AppTheme.warningColor;
    if (t.contains('out_of_stock') || t.contains('damage')) {
      return AppTheme.dangerColor;
    }
    if (t.contains('order') || t.contains('purchase')) {
      return AppTheme.indigoColor;
    }
    if (t.contains('stock_in') || t.contains('receive')) {
      return AppTheme.successColor;
    }
    if (t.contains('transfer')) return AppTheme.infoColor;
    return AppTheme.primaryColor;
  }

  static String relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM').format(dt);
  }

  /// Section header for a notification's day, so a long list stays scannable.
  static String _dayBucket(DateTime dt) {
    final now = DateTime.now();
    final day = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final delta = today.difference(day).inDays;
    if (delta <= 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta < 7) return 'This week';
    if (delta < 30) return 'This month';
    return 'Earlier';
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    final companyId = auth.currentUser?.companyId ?? '';
    if (companyId.isEmpty) return;
    final provider = context.read<NotificationProvider>();
    provider.initialize(companyId: companyId);
    await _rescan();
  }

  /// Runs an immediate scan, bypassing the resume throttle — an explicit pull
  /// means "check now".
  Future<void> _rescan() async {
    final provider = context.read<NotificationProvider>();
    final found = await provider.runScan(
      products: _products(),
      batches: _batches(),
      invoices: _invoices(),
      purchaseOrders: _orders(),
      force: true,
    );
    if (!mounted) return;
    if (found == 0 && provider.unreadCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All clear — nothing needs attention.')),
      );
    }
  }

  /// Reads one provider's list, tolerating a provider that is missing or has
  /// not initialised — a scan on partial data is better than no scan.
  List<T> _read<T>(List<T> Function() get) {
    try {
      return get();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final all = provider.notifications;
    final visible = provider.filtered(
      type: _typeFilter,
      unreadOnly: _unreadOnly,
    );
    final isAdmin = context.read<AuthProvider>().currentUser?.isAdmin ?? false;

    // Surface a write failure once, then clear it so it does not stick.
    final error = provider.errorMessage;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppTheme.dangerColor,
          ),
        );
        provider.clearError();
      });
    }

    return AppScreenScaffold(
      icon: Icons.notifications_rounded,
      title: 'Notifications',
      subtitle: provider.unreadCount > 0
          ? '${provider.unreadCount} unread'
          : null,
      isLoading: provider.isLoading,
      shimmerLayout: ShimmerLayout.listTile,
      isEmpty: all.isEmpty,
      emptyState: EmptyStateWidget(
        icon: Icons.notifications_off_rounded,
        title: 'Nothing needs your attention',
        buttonText: 'Check now',
        onButtonPressed: _rescan,
        subtitle:
            'Alerts appear here when stock runs low or runs out, batches near '
            'expiry, invoices fall overdue, or a purchase order is late. '
            'Choose which of those you want in Settings.',
      ),
      actions: [
        IconButton(
          tooltip: 'Notification settings',
          icon: const Icon(Icons.tune_rounded, size: 20),
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.notificationSettings),
        ),
        if (provider.unreadCount > 0)
          TextButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              provider.markAllRead();
            },
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Mark all read', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
            ),
          ),
      ],
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: _refresh,
        child: Column(
          children: [
            _Filters(
              types: provider.presentTypes,
              selectedType: _typeFilter,
              unreadOnly: _unreadOnly,
              unreadByType: provider.unreadByType,
              onTypeChanged: (t) => setState(() => _typeFilter = t),
              onUnreadChanged: (v) => setState(() => _unreadOnly = v),
            ),
            Expanded(
              child: visible.isEmpty
                  ? _FilteredEmpty(
                      onClear: () => setState(() {
                        _typeFilter = null;
                        _unreadOnly = false;
                      }),
                    )
                  : _buildList(visible, provider, isAdmin),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<AppNotificationModel> visible,
    NotificationProvider provider,
    bool isAdmin,
  ) {
    // Flatten to rows so headers and cards share one scrollable, keeping the
    // list lazy rather than building every group up front.
    final rows = <Widget>[];
    String? lastBucket;
    for (var i = 0; i < visible.length; i++) {
      final n = visible[i];
      final bucket = _dayBucket(n.timestamp);
      if (bucket != lastBucket) {
        rows.add(_SectionHeader(label: bucket));
        lastBucket = bucket;
      }
      rows.add(
        _NotificationCard(
          notification: n,
          icon: typeIcon(n.type),
          color: typeColor(n),
          relativeTime: relativeTime(n.timestamp),
          canDelete: isAdmin,
          isOpening: _openingId == n.id,
          onTap: () => _handleTap(n, provider),
          onDelete: () async {
            HapticFeedback.mediumImpact();
            return provider.delete(n.id);
          },
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 8,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        // Cap entrance animations to the first items for long lists.
        return index < 15 ? AnimatedListItem(index: index, child: row) : row;
      },
    );
  }

  Future<void> _handleTap(
    AppNotificationModel n,
    NotificationProvider provider,
  ) async {
    HapticFeedback.selectionClick();
    if (!n.isRead) provider.markRead(n.id);
    if (!NotificationRouting.isActionable(n.entityType) &&
        n.entityId.isEmpty) {
      return;
    }
    setState(() => _openingId = n.id);
    try {
      await NotificationRouting.open(
        context,
        entityType: n.entityType,
        entityId: n.entityId,
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  // The scan derives alerts from data other providers already hold, so it
  // costs no extra reads.
  List<ProductModel> _products() =>
      _read(() => context.read<ProductProvider>().analyticsProducts);

  List<BatchModel> _batches() =>
      _read(() => context.read<BatchProvider>().batches);

  List<InvoiceModel> _invoices() =>
      _read(() => context.read<BillingProvider>().invoices);

  List<PurchaseOrderModel> _orders() =>
      _read(() => context.read<PurchaseOrderProvider>().orders);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTheme.textMute(context),
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.types,
    required this.selectedType,
    required this.unreadOnly,
    required this.unreadByType,
    required this.onTypeChanged,
    required this.onUnreadChanged,
  });

  final List<String> types;
  final String? selectedType;
  final bool unreadOnly;
  final Map<String, int> unreadByType;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<bool> onUnreadChanged;

  @override
  Widget build(BuildContext context) {
    // One type of alert is not worth a filter bar.
    if (types.length < 2 && !unreadOnly) {
      return _UnreadToggleRow(
        unreadOnly: unreadOnly,
        onChanged: onUnreadChanged,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UnreadToggleRow(unreadOnly: unreadOnly, onChanged: onUnreadChanged),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
            ),
            children: [
              _Chip(
                label: 'All',
                selected: selectedType == null,
                onTap: () => onTypeChanged(null),
              ),
              for (final type in types)
                _Chip(
                  label: AlertType.label(type),
                  count: unreadByType[type] ?? 0,
                  selected: selectedType == type,
                  onTap: () =>
                      onTypeChanged(selectedType == type ? null : type),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnreadToggleRow extends StatelessWidget {
  const _UnreadToggleRow({required this.unreadOnly, required this.onChanged});

  final bool unreadOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        4,
        Responsive.horizontalPadding(context),
        0,
      ),
      child: Row(
        children: [
          const Spacer(),
          Text(
            'Unread only',
            style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
          ),
          Switch(
            value: unreadOnly,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        label: Text(
          count > 0 ? '$label ($count)' : label,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // Must stay scrollable so pull-to-refresh still works with no rows.
    return ListView(
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.filter_alt_off_rounded,
          size: 40,
          color: AppTheme.textMute(context),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Nothing matches this filter',
            style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(onPressed: onClear, child: const Text('Clear')),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotificationModel notification;
  final IconData icon;
  final Color color;
  final String relativeTime;
  final bool canDelete;
  final bool isOpening;
  final VoidCallback onTap;
  final Future<bool> Function() onDelete;

  const _NotificationCard({
    required this.notification,
    required this.icon,
    required this.color,
    required this.relativeTime,
    required this.canDelete,
    required this.isOpening,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    // Rules restrict deletes to admins. Offering the swipe to everyone made the
    // row vanish and then reappear when the write bounced, so staff get a
    // non-dismissible card instead.
    if (!canDelete) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: card,
      );
    }

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
        // confirmDismiss, not onDismissed: the row only leaves the tree once
        // the server has actually accepted the delete.
        confirmDismiss: (_) => onDelete(),
        child: card,
      ),
    );
  }

  Widget _card(BuildContext context) {
    final isUnread = !notification.isRead;
    final actionable =
        NotificationRouting.isActionable(notification.entityType) ||
        notification.entityId.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: isUnread ? AppTheme.surface(context) : AppTheme.bg(context),
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
                                  fontSize: 12,
                                  color: AppTheme.textMute(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isOpening)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: color,
                              ),
                            ),
                          )
                        else if (isUnread)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: PulsingDot(color: color, size: 8),
                          )
                        else if (actionable)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppTheme.textMute(context),
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
    );
  }
}
