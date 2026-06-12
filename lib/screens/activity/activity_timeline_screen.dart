import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../providers/stock_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/stock_transaction_model.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/animated_list_item.dart';

class ActivityTimelineScreen extends StatefulWidget {
  const ActivityTimelineScreen({super.key});

  @override
  State<ActivityTimelineScreen> createState() => _ActivityTimelineScreenState();
}

class _ActivityTimelineScreenState extends State<ActivityTimelineScreen> {
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 30;
  int _visibleCount = _pageSize;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    final total = context.read<StockProvider>().allTransactions.length;
    if (_visibleCount >= total) return;
    setState(() => _loadingMore = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _visibleCount = (_visibleCount + _pageSize).clamp(0, total);
          _loadingMore = false;
        });
      }
    });
  }

  // --- Helpers ---

  Map<String, List<StockTransactionModel>> _groupByDay(
    List<StockTransactionModel> transactions,
  ) {
    final grouped = <String, List<StockTransactionModel>>{};
    for (final tx in transactions) {
      final key = DateFormat('yyyy-MM-dd').format(tx.date);
      grouped.putIfAbsent(key, () => []).add(tx);
    }
    return grouped;
  }

  String _dayLabel(String dateKey) {
    final date = DateFormat('yyyy-MM-dd').parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  IconData _iconForType(TransactionType type) {
    return switch (type) {
      TransactionType.stockIn => Icons.arrow_downward_rounded,
      TransactionType.stockOut => Icons.arrow_upward_rounded,
      TransactionType.damage => Icons.warning_amber_rounded,
      TransactionType.transfer => Icons.swap_horiz_rounded,
      TransactionType.adjustment => Icons.tune_rounded,
      TransactionType.hold => Icons.pause_circle_rounded,
      TransactionType.holdRelease => Icons.play_circle_rounded,
    };
  }

  Color _colorForType(TransactionType type) {
    return switch (type) {
      TransactionType.stockIn => AppTheme.successColor,
      TransactionType.stockOut => AppTheme.infoColor,
      TransactionType.damage => AppTheme.dangerColor,
      TransactionType.transfer => AppTheme.indigoColor,
      TransactionType.adjustment => AppTheme.warningColor,
      TransactionType.hold => AppTheme.warningColor,
      TransactionType.holdRelease => AppTheme.successColor,
    };
  }

  String _qtyPrefix(TransactionType type) {
    return switch (type) {
      TransactionType.stockIn => '+',
      TransactionType.stockOut => '-',
      TransactionType.damage => '-',
      TransactionType.transfer => '',
      TransactionType.adjustment => '',
      TransactionType.hold => '',
      TransactionType.holdRelease => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewActivityTimeline,
      featureName: 'Activity Timeline',
      child: Builder(builder: _buildContent),
    );
  }

  Future<void> _onRefresh() async {
    final cid = context.read<ProductProvider>().companyId;
    if (cid.isEmpty) return;
    context.read<StockProvider>().initialize(companyId: cid);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Widget _buildContent(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();
    final allTx = stockProvider.allTransactions;
    final isLoading = stockProvider.isLoading;
    final hPad = Responsive.horizontalPadding(context);

    return AppScreenScaffold(
      icon: Icons.timeline_rounded,
      title: 'Activity Timeline',
      isLoading: isLoading && allTx.isEmpty,
      shimmerLayout: ShimmerLayout.listTile,
      isEmpty: !isLoading && allTx.isEmpty,
      emptyState: const EmptyStateWidget(
        icon: Icons.timeline_rounded,
        title: 'No Activity Yet',
        subtitle: 'Stock transactions will appear here as a timeline.',
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: _onRefresh,
        child: _buildTimeline(allTx, hPad),
      ),
    );
  }

  Widget _buildTimeline(List<StockTransactionModel> allTx, double hPad) {
    final sorted = List<StockTransactionModel>.from(allTx)
      ..sort((a, b) => b.date.compareTo(a.date));
    final visible = sorted.take(_visibleCount).toList();
    final grouped = _groupByDay(visible);
    final dayKeys = grouped.keys.toList();

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: dayKeys.length + (_visibleCount < allTx.length ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == dayKeys.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final dayKey = dayKeys[index];
        final transactions = grouped[dayKey]!;
        return AnimatedListItem(
          index: index,
          child: _DaySection(
            label: _dayLabel(dayKey),
            isFirst: index == 0,
            children: transactions
              .map(
                (tx) => _TransactionTile(
                  transaction: tx,
                  icon: _iconForType(tx.type),
                  color: _colorForType(tx.type),
                  timeAgo: _timeAgo(tx.date),
                  qtyPrefix: _qtyPrefix(tx.type),
                ),
              )
              .toList(),
          ),
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  final String label;
  final bool isFirst;
  final List<Widget> children;

  const _DaySection({
    required this.label,
    required this.isFirst,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isFirst) const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Divider(color: AppTheme.dividerC(context))),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class _TransactionTile extends StatefulWidget {
  final StockTransactionModel transaction;
  final IconData icon;
  final Color color;
  final String timeAgo;
  final String qtyPrefix;

  const _TransactionTile({
    required this.transaction,
    required this.icon,
    required this.color,
    required this.timeAgo,
    required this.qtyPrefix,
  });

  @override
  State<_TransactionTile> createState() => _TransactionTileState();
}

class _TransactionTileState extends State<_TransactionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.productName.isNotEmpty
                              ? tx.productName
                              : 'Unknown Product',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPri(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              tx.typeLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textTer(context),
                              ),
                            ),
                            if (tx.userName.isNotEmpty) ...[
                              Text(
                                ' · ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textTer(context),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  tx.userName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textTer(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${widget.qtyPrefix}${tx.quantity}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: widget.color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textTer(context),
                        ),
                      ),
                    ],
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: AppTheme.textTer(context),
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildDetails(context, tx),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, StockTransactionModel tx) {
    final details = <_DetailRow>[];

    if (tx.location.isNotEmpty) {
      details.add(
        _DetailRow('Location', tx.location, Icons.location_on_outlined),
      );
    }
    if (tx.reason.isNotEmpty) {
      details.add(_DetailRow('Reason', tx.reason, Icons.info_outline_rounded));
    }
    if (tx.vendorName.isNotEmpty) {
      details.add(_DetailRow('Vendor', tx.vendorName, Icons.store_outlined));
    }
    details.add(
      _DetailRow(
        'Date & Time',
        DateFormat('MMM d, yyyy · h:mm a').format(tx.date),
        Icons.schedule_rounded,
      ),
    );

    if (details.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.inputFill(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: details
              .map(
                (d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(d.icon, size: 16, color: AppTheme.textTer(context)),
                      const SizedBox(width: 8),
                      Text(
                        '${d.label}:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          d.value,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textPri(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _DetailRow {
  final String label;
  final String value;
  final IconData icon;
  const _DetailRow(this.label, this.value, this.icon);
}
