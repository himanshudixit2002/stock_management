import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/stock_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/stock_transaction_model.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../config/routes.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../config/app_navigation.dart';

class DamageHistoryScreen extends StatefulWidget {
  const DamageHistoryScreen({super.key});

  @override
  State<DamageHistoryScreen> createState() => _DamageHistoryScreenState();
}

class _DamageHistoryScreenState extends State<DamageHistoryScreen> {
  DateTime? _startDate;
  DateTime? _endDate;

  List<StockTransactionModel> _filterByDate(
    List<StockTransactionModel> transactions,
  ) {
    Iterable<StockTransactionModel> result = transactions;
    if (_startDate != null) {
      final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      result = result.where((t) => !t.date.isBefore(start));
    }
    if (_endDate != null) {
      final end = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day + 1,
      );
      result = result.where((t) => t.date.isBefore(end));
    }
    return result.toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _startDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate ?? now)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockProvider = context.watch<StockProvider>();

    final allDamage = stockProvider.allTransactions
        .where((t) => t.type == TransactionType.damage)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final damage = _filterByDate(allDamage);

    final totalEvents = damage.length;
    final totalUnits = damage.fold<int>(0, (s, t) => s + t.quantity);

    final breakdownMap = <String, int>{};
    for (final t in damage) {
      final name = t.productName.isNotEmpty ? t.productName : t.productId;
      breakdownMap[name] = (breakdownMap[name] ?? 0) + t.quantity;
    }
    final topDamaged = breakdownMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topProduct = topDamaged.isNotEmpty ? topDamaged.first.key : 'N/A';

    final dateFormat = DateFormat('d MMM yyyy, h:mm a');
    final hasDateFilter = _startDate != null;

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const Text('Damage Report'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.date_range_rounded,
              color: hasDateFilter ? AppTheme.primaryColor : null,
            ),
            tooltip: 'Filter by date',
            onPressed: _pickDateRange,
          ),
          if (hasDateFilter)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Clear date filter',
              onPressed: () => setState(() {
                _startDate = null;
                _endDate = null;
              }),
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
            child: damage.isEmpty
                ? _buildEmptyState()
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            Responsive.horizontalPadding(context),
                            12,
                            Responsive.horizontalPadding(context),
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasDateFilter) _buildDateChip(),
                              const SizedBox(height: 8),
                              _buildSummaryCards(
                                totalEvents,
                                totalUnits,
                                topProduct,
                              ),
                              if (topDamaged.length > 1) ...[
                                const SizedBox(height: 20),
                                _buildTopDamagedSection(topDamaged),
                              ],
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: AppTheme.dangerColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'All Damage Entries ($totalEvents)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPri(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context),
                          0,
                          Responsive.horizontalPadding(context),
                          32,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _DamageTile(
                                txn: damage[index],
                                dateFormat: dateFormat,
                              ),
                            ),
                            childCount: damage.length,
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

  Widget _buildDateChip() {
    final fmt = DateFormat('d MMM');
    final label = _endDate != null
        ? '${fmt.format(_startDate!)} - ${fmt.format(_endDate!)}'
        : 'From ${fmt.format(_startDate!)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.date_range_rounded,
                  size: 14,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() {
                    _startDate = null;
                    _endDate = null;
                  }),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppTheme.primaryColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 64,
            color: AppTheme.successColor.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            'No Damage Reported',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPri(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _startDate != null
                ? 'No damage entries in the selected date range'
                : 'No damage entries found',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSec(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(int events, int units, String topProduct) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Events',
            value: '$events',
            icon: Icons.report_problem_rounded,
            color: AppTheme.dangerColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Units Lost',
            value: '$units',
            icon: Icons.broken_image_rounded,
            color: AppTheme.warningColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Most Damaged',
            value: topProduct,
            icon: Icons.trending_down_rounded,
            color: AppTheme.infoColor,
            isText: true,
          ),
        ),
      ],
    );
  }

  Widget _buildTopDamagedSection(List<MapEntry<String, int>> topDamaged) {
    final maxQty = topDamaged.first.value;
    final items = topDamaged.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppTheme.warningColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Top Damaged Products',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPri(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GlassPanel(
          padding: const EdgeInsets.all(14),
          borderRadius: 16,
          useContentVariant: true,
          child: Column(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final fraction = maxQty > 0 ? item.value / maxQty : 0.0;
              return Padding(
                padding: EdgeInsets.only(bottom: idx < items.length - 1 ? 10 : 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: idx < 3
                              ? AppTheme.dangerColor
                              : AppTheme.textTer(context),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        item.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 8,
                          backgroundColor: AppTheme.dangerColor
                              .withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(
                            idx < 3
                                ? AppTheme.dangerColor
                                : AppTheme.warningColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${item.value}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: idx < 3
                              ? AppTheme.dangerColor
                              : AppTheme.textSec(context),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------
class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isText;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isText = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            isText
                ? Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  )
                : Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSec(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual damage transaction tile
// ---------------------------------------------------------------------------
class _DamageTile extends StatelessWidget {
  final StockTransactionModel txn;
  final DateFormat dateFormat;

  const _DamageTile({required this.txn, required this.dateFormat});

  void _showChangeLocationSheet(BuildContext context) {
    final stockProvider = context.read<StockProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final productProvider = context.read<ProductProvider>();

    final settingsLocations = settingsProvider.locations;
    final productLocations = productProvider.availableLocationsFromProducts;
    final allLocations = <String>{
      ...settingsLocations,
      ...productLocations,
      if (txn.location.isNotEmpty) txn.location,
    }.toList()
      ..sort();

    final customController = TextEditingController();

    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          expand: false,
          builder: (ctx2, scrollController) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.emptyIcon(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_location_alt_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Change Damage Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPri(context),
                            ),
                          ),
                          Text(
                            txn.productName,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSec(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (txn.location.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Current: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTer(context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          txn.location,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  children: [
                    ...allLocations.map((loc) {
                      final isCurrent = loc == txn.location;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isCurrent
                              ? Icons.location_on_rounded
                              : Icons.location_on_outlined,
                          color: isCurrent
                              ? AppTheme.primaryColor
                              : AppTheme.textTer(context),
                          size: 22,
                        ),
                        title: Text(
                          loc,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isCurrent
                                ? AppTheme.primaryColor
                                : AppTheme.textPri(context),
                          ),
                        ),
                        trailing: isCurrent
                            ? const Icon(
                                Icons.check_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              )
                            : null,
                        onTap: isCurrent
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final ok = await stockProvider
                                    .updateTransactionLocation(txn.id, loc);
                                if (context.mounted && !ok) {
                                  showInfoSnackBar(context, stockProvider.errorMessage ?? 'Failed to update location');
                                }
                              },
                      );
                    }),
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Or enter a new location:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customController,
                            decoration: InputDecoration(
                              hintText: 'New location name',
                              hintStyle: TextStyle(fontSize: 14, color: AppTheme.textTer(context)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final loc = customController.text.trim();
                            if (loc.isEmpty || loc == txn.location) return;
                            Navigator.pop(ctx);
                            final ok = await stockProvider
                                .updateTransactionLocation(txn.id, loc);
                            if (context.mounted && !ok) {
                              showInfoSnackBar(context, stockProvider.errorMessage ?? 'Failed to update location');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Set'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      onTap: () {
        final productProvider = context.read<ProductProvider>();
        final product = productProvider.allProducts
            .where((p) => p.id == txn.productId)
            .firstOrNull;
        if (product != null) {
          context.pushAppRoute(AppRoutes.productDetail,
            extra: product,
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: product name + quantity badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.broken_image_rounded,
                    color: AppTheme.dangerColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txn.productName.isNotEmpty
                            ? txn.productName
                            : txn.productId,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPri(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormat.format(txn.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTer(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '-${txn.quantity}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.dangerColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Location row with change button
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppTheme.textTer(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Location: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSec(context),
                  ),
                ),
                Expanded(
                  child: Text(
                    txn.location.isNotEmpty ? txn.location : 'N/A',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPri(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showChangeLocationSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_location_alt_rounded,
                          size: 13,
                          color: AppTheme.primaryColor,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Change',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (txn.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              _DetailRow(
                icon: Icons.notes_rounded,
                label: 'Reason',
                value: txn.reason,
                isMultiline: true,
              ),
            ],
            const SizedBox(height: 6),
            _DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'Reported by',
              value: txn.userName.isNotEmpty ? txn.userName : txn.userId,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isMultiline;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isMultiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppTheme.textTer(context)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSec(context),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPri(context),
            ),
            maxLines: isMultiline ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}