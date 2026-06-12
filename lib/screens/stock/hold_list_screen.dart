import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/stock_hold_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/stock_summary_card.dart';

class HoldListScreen extends StatefulWidget {
  const HoldListScreen({super.key});

  @override
  State<HoldListScreen> createState() => _HoldListScreenState();
}

class _HoldListScreenState extends State<HoldListScreen> {
  String _search = '';

  bool _matches(StockHoldModel hold) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return hold.productName.toLowerCase().contains(q) ||
        hold.location.toLowerCase().contains(q) ||
        hold.challanNumber.toLowerCase().contains(q) ||
        hold.reason.toLowerCase().contains(q) ||
        hold.sourceId.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewStockHolds,
      featureName: 'Stock Holds',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final stockProvider = context.watch<StockProvider>();
    final all = stockProvider.stockHolds;

    // Group active holds by challan number (the dashboard's organizing key).
    final grouped = <String, List<StockHoldModel>>{};
    for (final hold in stockProvider.activeHolds) {
      if (hold.remainingQuantity <= 0) continue;
      if (!_matches(hold)) continue;
      grouped.putIfAbsent(hold.challanNumber.trim(), () => []).add(hold);
    }
    final challanKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    final totalHeld = stockProvider.activeHolds.fold<int>(
      0,
      (sum, hold) => sum + hold.remainingQuantity,
    );
    final activeCount = stockProvider.activeHolds.length;
    final consumedCount = all
        .where((hold) => hold.status == StockHoldStatus.consumed)
        .length;
    final releasedCount = all
        .where((hold) => hold.status == StockHoldStatus.released)
        .length;
    final isMobile = Responsive.isMobile(context);
    final hPad = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.lock_clock_rounded,
          color: AppTheme.warningColor,
          title: 'Hold Dashboard',
        ),
        actions: [
          IconButton(
            tooltip: 'Create Hold',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.stockHold),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: AnimatedGradientBackground(
        colors: AppTheme.scaffoldGrad(context).colors,
        child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by challan, product, location...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _search = value.trim()),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: isMobile
                    ? Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _miniStat(
                                  title: 'Total Held',
                                  value: '$totalHeld',
                                  icon: Icons.lock_clock_rounded,
                                  color: AppTheme.warningColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _miniStat(
                                  title: 'Active',
                                  value: '$activeCount',
                                  icon: Icons.pause_circle_rounded,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _miniStat(
                                  title: 'Consumed',
                                  value: '$consumedCount',
                                  icon: Icons.check_circle_rounded,
                                  color: AppTheme.successColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _miniStat(
                                  title: 'Released',
                                  value: '$releasedCount',
                                  icon: Icons.lock_open_rounded,
                                  color: AppTheme.infoColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final cols = Responsive.isDesktop(context) ? 4 : 2;
                          const spacing = 8.0;
                          final cardWidth =
                              (constraints.maxWidth - spacing * (cols - 1)) /
                                  cols;
                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              SizedBox(
                                width: cardWidth,
                                child: StockSummaryCard(
                                  title: 'Total Held',
                                  value: '$totalHeld',
                                  icon: Icons.lock_clock_rounded,
                                  color: AppTheme.warningColor,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: StockSummaryCard(
                                  title: 'Active',
                                  value: '$activeCount',
                                  icon: Icons.pause_circle_rounded,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: StockSummaryCard(
                                  title: 'Consumed',
                                  value: '$consumedCount',
                                  icon: Icons.check_circle_rounded,
                                  color: AppTheme.successColor,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: StockSummaryCard(
                                  title: 'Released',
                                  value: '$releasedCount',
                                  icon: Icons.lock_open_rounded,
                                  color: AppTheme.infoColor,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: isMobile
                    ? Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pushNamed(
                                context,
                                AppRoutes.stockHold,
                              ),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Create Hold'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pushNamed(
                                context,
                                AppRoutes.stockRelease,
                              ),
                              icon: const Icon(Icons.playlist_remove_rounded),
                              label: const Text('Unhold by Challan'),
                            ),
                          ),
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.stockHold,
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create Hold'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.stockRelease,
                            ),
                            icon: const Icon(Icons.playlist_remove_rounded),
                            label: const Text('Unhold by Challan'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: challanKeys.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.lock_clock_outlined,
                        title: 'No Active Holds',
                        subtitle:
                            'Create a hold with a challan number to reserve stock.',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
                        physics: const BouncingScrollPhysics(),
                        itemCount: challanKeys.length,
                        itemBuilder: (context, index) {
                          final challan = challanKeys[index];
                          final holds = grouped[challan]!;
                          return FadeSlideIn(
                            index: index,
                            child: _ChallanGroupCard(
                              challan: challan,
                              holds: holds,
                              onUnhold: _openUnholdSheet,
                              onDespatch: _despatchHold,
                              onManageOrder: _manageOrder,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Compact stat tile used in the phone summary grid. Lays the value and
  /// label out beside the icon so it stays short and never overflows the way
  /// the full-height [StockSummaryCard] did inside a fixed-height row.
  Widget _miniStat({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return GlassCard(
      borderRadius: 14,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _despatchHold(StockHoldModel hold) {
    Navigator.pushNamed(
      context,
      AppRoutes.stockOut,
      arguments: HoldActionArgs(hold: hold),
    );
  }

  void _manageOrder(StockHoldModel hold) {
    if (hold.sourceId.isEmpty) {
      showInfoSnackBar(context, 'Linked order not found.');
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.salesOrderDetail,
      arguments: hold.sourceId,
    );
  }

  Future<void> _openUnholdSheet(StockHoldModel hold) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final controller = TextEditingController(text: '${hold.remainingQuantity}');
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface(context),
      constraints: Responsive.sheetConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        String? error;
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.dividerStrongC(context),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.lock_open_rounded),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Unhold stock',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _prefillRow('Challan No.',
                          hold.challanNumber.isEmpty ? '-' : hold.challanNumber),
                      _prefillRow('Product', hold.productName),
                      _prefillRow('Location',
                          hold.hasLocation ? hold.location : 'Any location'),
                      _prefillRow('Held qty', '${hold.remainingQuantity}'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Quantity to unhold',
                          errorText: error,
                          prefixIcon: const Icon(Icons.numbers_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            final qty = int.tryParse(controller.text.trim());
                            if (qty == null || qty <= 0) {
                              setSheet(() => error = 'Enter a valid quantity');
                              return;
                            }
                            if (qty > hold.remainingQuantity) {
                              setSheet(() => error =
                                  'Cannot exceed held qty (${hold.remainingQuantity})');
                              return;
                            }
                            Navigator.pop(sheetCtx, qty);
                          },
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text('Unhold'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || result == null) return;
    final ok = await context.read<StockProvider>().releaseStockHoldQuantity(
          holdId: hold.id,
          quantity: result,
          userId: user.uid,
          userName: user.name,
          reason: hold.challanNumber.isEmpty
              ? 'Manual unhold'
              : 'Unhold challan ${hold.challanNumber}',
        );
    if (!mounted) return;
    if (ok) {
      context.read<ProductProvider>().refreshProductsByIds([hold.productId]);
      HapticFeedback.mediumImpact();
      showInfoSnackBar(context, 'Unheld $result ${hold.productName}');
    } else {
      showErrorSnackBar(
        context,
        context.read<StockProvider>().errorMessage ?? 'Failed to unhold.',
      );
    }
  }

  Widget _prefillRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallanGroupCard extends StatelessWidget {
  final String challan;
  final List<StockHoldModel> holds;
  final void Function(StockHoldModel) onUnhold;
  final void Function(StockHoldModel) onDespatch;
  final void Function(StockHoldModel) onManageOrder;

  const _ChallanGroupCard({
    required this.challan,
    required this.holds,
    required this.onUnhold,
    required this.onDespatch,
    required this.onManageOrder,
  });

  @override
  Widget build(BuildContext context) {
    final totalHeld =
        holds.fold<int>(0, (sum, h) => sum + h.remainingQuantity);
    final isSalesOrder =
        holds.isNotEmpty && holds.first.sourceType == StockHoldSourceType.salesOrder;
    final title = challan.isEmpty ? 'No challan' : 'Challan $challan';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 16,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSalesOrder
                          ? Icons.receipt_long_rounded
                          : Icons.receipt_rounded,
                      color: AppTheme.warningColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${holds.length} product${holds.length == 1 ? '' : 's'} • $totalHeld held',
                          style: TextStyle(
                            color: AppTheme.textSec(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSalesOrder)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.infoColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Sales Order',
                        style: TextStyle(
                          color: AppTheme.infoColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(height: 18),
              ...holds.map((hold) => _HoldRow(
                    hold: hold,
                    onUnhold: () => onUnhold(hold),
                    onDespatch: () => onDespatch(hold),
                    onManageOrder: () => onManageOrder(hold),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldRow extends StatelessWidget {
  final StockHoldModel hold;
  final VoidCallback onUnhold;
  final VoidCallback onDespatch;
  final VoidCallback onManageOrder;

  const _HoldRow({
    required this.hold,
    required this.onUnhold,
    required this.onDespatch,
    required this.onManageOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hold.productName.isEmpty
                          ? hold.productId
                          : hold.productName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${hold.hasLocation ? hold.location : 'Any location'} • Held ${hold.remainingQuantity}',
                      style: TextStyle(
                        color: AppTheme.textSec(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${hold.remainingQuantity}',
                  style: TextStyle(
                    color: AppTheme.warningColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hold.isManual)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onUnhold,
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('Unhold'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onDespatch,
                    icon: const Icon(Icons.local_shipping_rounded, size: 16),
                    label: const Text('Despatch'),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.textSec(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Reserved by sales order — dispatch or cancel from the order.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppTheme.infoColor,
                ),
                onPressed: onManageOrder,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Manage Order'),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
