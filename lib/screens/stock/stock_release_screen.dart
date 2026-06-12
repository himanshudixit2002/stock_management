import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/sales_order_model.dart';
import '../../models/stock_hold_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/stock_provider.dart';
import '../../services/database_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/searchable_picker.dart';

class StockReleaseScreen extends StatefulWidget {
  final ProductModel? product;
  final String? initialChallan;
  const StockReleaseScreen({super.key, this.product, this.initialChallan});

  @override
  State<StockReleaseScreen> createState() => _StockReleaseScreenState();
}

class _StockReleaseScreenState extends State<StockReleaseScreen> {
  String _search = '';
  bool _isLoading = false;
  String? _challanFilter;
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    final c = widget.initialChallan?.trim();
    if (c != null && c.isNotEmpty) _challanFilter = c;
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _qtyCtrl(StockHoldModel hold) {
    return _qtyControllers.putIfAbsent(
      hold.id,
      () => TextEditingController(text: '${hold.remainingQuantity}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.releaseStock,
      featureName: 'Stock Release',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final stockProvider = context.watch<StockProvider>();
    final challans = stockProvider.activeChallans;
    final holds = stockProvider.activeHolds.where((hold) {
      if (widget.product != null && hold.productId != widget.product!.id) {
        return false;
      }
      if (_challanFilter != null &&
          hold.challanNumber.trim() != _challanFilter) {
        return false;
      }
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return hold.productName.toLowerCase().contains(q) ||
          hold.location.toLowerCase().contains(q) ||
          hold.challanNumber.toLowerCase().contains(q) ||
          hold.sourceId.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.play_circle_rounded,
          color: AppTheme.successColor,
          title: 'Unhold / Dispatch',
        ),
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
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  8,
                  Responsive.horizontalPadding(context),
                  8,
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search holds by product, challan, location...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _search = value.trim()),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickChallan(challans),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: Text(
                          _challanFilter == null
                              ? 'Filter by Challan'
                              : 'Challan: $_challanFilter',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_challanFilter != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Clear challan filter',
                        onPressed: () => setState(() => _challanFilter = null),
                        icon: const Icon(Icons.clear_rounded),
                      ),
                    ],
                  ],
                ),
              ),
              if (_challanFilter != null &&
                  holds.where((h) => h.isManual).length > 1)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    8,
                    Responsive.horizontalPadding(context),
                    0,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _unholdEntireChallan(
                              holds.where((h) => h.isManual).toList()),
                      icon: const Icon(Icons.playlist_remove_rounded),
                      label: Text('Unhold all in $_challanFilter'),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: holds.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.lock_open_rounded,
                        title: 'No Active Holds',
                        subtitle:
                            'There are no active holds available to release.',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(
                          horizontal: Responsive.horizontalPadding(context),
                        ),
                        physics: const BouncingScrollPhysics(),
                        itemCount: holds.length,
                        itemBuilder: (context, index) {
                          final hold = holds[index];
                          final order =
                              hold.sourceType == StockHoldSourceType.salesOrder
                              ? context
                                    .watch<SalesOrderProvider>()
                                    .getOrderById(hold.sourceId)
                              : null;
                          final needsDispatch =
                              _needsDispatchAction(hold, order);
                          // A sales-order hold whose order was deleted or
                          // cancelled is orphaned: allow releasing it directly
                          // so its reservation can be cleaned up.
                          final orderOrphaned =
                              hold.sourceType ==
                                      StockHoldSourceType.salesOrder &&
                                  (order == null ||
                                      order.status == SOStatus.cancelled);
                          return FadeSlideIn(
                            index: index,
                            child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              borderRadius: 14,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.warningColor
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.pause_circle_rounded,
                                            color: AppTheme.warningColor,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                hold.productName.isEmpty
                                                    ? hold.productId
                                                    : hold.productName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                hold.hasLocation
                                                    ? hold.location
                                                    : 'Any location',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.textSec(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _sourceLabel(hold),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppTheme.textSec(context),
                                                ),
                                              ),
                                              if (order != null) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Order status: ${order.statusLabel}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: needsDispatch
                                                        ? AppTheme.warningColor
                                                        : AppTheme.textSec(
                                                            context),
                                                    fontWeight: needsDispatch
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor
                                                .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Held ${hold.remainingQuantity}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (needsDispatch) ...[
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 96,
                                            child: TextField(
                                              controller: _qtyCtrl(hold),
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Qty',
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _isLoading
                                                  ? null
                                                  : () =>
                                                      _dispatchSalesOrderForHold(
                                                          hold, order!),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.indigoColor,
                                              ),
                                              icon: const Icon(
                                                Icons.local_shipping_rounded,
                                                size: 16,
                                              ),
                                              label: const Text('Dispatch'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Dispatches only this product line. '
                                        'Other items on the order stay reserved.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                    ]
                                    else if (hold.isManual ||
                                        orderOrphaned) ...[
                                      if (orderOrphaned)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Text(
                                            order == null
                                                ? 'Linked order no longer exists. '
                                                      'Release this leftover hold.'
                                                : 'Linked order is cancelled. '
                                                      'Release this leftover hold.',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.warningColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 96,
                                            child: TextField(
                                              controller: _qtyCtrl(hold),
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Qty',
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _isLoading
                                                  ? null
                                                  : () => _unholdHold(hold),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.successColor,
                                              ),
                                              icon: const Icon(
                                                Icons.lock_open_rounded,
                                              ),
                                              label: const Text('Unhold'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: _isLoading
                                              ? null
                                              : () => Navigator.pushNamed(
                                                    context,
                                                    AppRoutes.stockOut,
                                                    arguments:
                                                        HoldActionArgs(
                                                            hold: hold),
                                                  ),
                                          icon: const Icon(
                                            Icons.local_shipping_rounded,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'Despatch (pick location)',
                                          ),
                                        ),
                                      ),
                                    ]
                                    else
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Reserved by sales order. '
                                              'Cancel the order to release this hold.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppTheme.textSec(context),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          OutlinedButton.icon(
                                            onPressed: hold.sourceId.isEmpty
                                                ? null
                                                : () => Navigator.pushNamed(
                                                      context,
                                                      AppRoutes
                                                          .salesOrderDetail,
                                                      arguments: hold.sourceId,
                                                    ),
                                            icon: const Icon(
                                              Icons.open_in_new_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Order'),
                                          ),
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
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _pickChallan(List<String> challans) async {
    if (challans.isEmpty) {
      showInfoSnackBar(context, 'No active challans to filter.');
      return;
    }
    final picked = await showSearchablePicker(
      context: context,
      title: 'Select Challan',
      selectedValue: _challanFilter,
      items: challans
          .map(
            (c) => PickerItem(
              value: c,
              label: c,
              icon: Icons.receipt_long_rounded,
              iconColor: AppTheme.primaryColor,
            ),
          )
          .toList(),
    );
    if (picked != null && mounted) {
      setState(() => _challanFilter = picked);
    }
  }

  Future<void> _unholdHold(StockHoldModel hold) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final qty = int.tryParse(_qtyCtrl(hold).text.trim());
    if (qty == null || qty <= 0) {
      showErrorSnackBar(context, 'Enter a valid quantity.');
      return;
    }
    if (qty > hold.remainingQuantity) {
      showErrorSnackBar(
        context,
        'Cannot exceed held qty (${hold.remainingQuantity}).',
      );
      return;
    }
    final stockProvider = context.read<StockProvider>();
    setState(() => _isLoading = true);
    final ok = await stockProvider.releaseStockHoldQuantity(
      holdId: hold.id,
      quantity: qty,
      userId: user.uid,
      userName: user.name,
      reason: hold.challanNumber.isEmpty
          ? 'Manual unhold'
          : 'Unhold challan ${hold.challanNumber}',
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      _qtyControllers.remove(hold.id)?.dispose();
      context.read<ProductProvider>().refreshProductsByIds([hold.productId]);
      showSuccessSnackBar(context, 'Unheld $qty ${hold.productName}');
    } else {
      showErrorSnackBar(
        context,
        stockProvider.errorMessage ?? 'Could not unhold.',
      );
    }
  }

  Future<void> _unholdEntireChallan(List<StockHoldModel> holds) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final confirm = await showConfirmDialog(
      context,
      title: 'Unhold entire challan?',
      message:
          'Release all ${holds.length} held items for challan $_challanFilter? '
          'Use this when the order is cancelled.',
      confirmLabel: 'Unhold All',
    );
    if (!confirm || !mounted) return;
    final stockProvider = context.read<StockProvider>();
    setState(() => _isLoading = true);
    var failures = 0;
    for (final hold in holds) {
      final ok = await stockProvider.releaseStockHoldQuantity(
        holdId: hold.id,
        quantity: hold.remainingQuantity,
        userId: user.uid,
        userName: user.name,
        reason: 'Unhold challan ${hold.challanNumber} (cancelled)',
      );
      if (!ok) failures++;
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (failures == 0) {
      context
          .read<ProductProvider>()
          .refreshProductsByIds(holds.map((h) => h.productId));
      showSuccessSnackBar(context, 'Challan $_challanFilter fully unheld');
      setState(() => _challanFilter = null);
    } else {
      showErrorSnackBar(context, '$failures item(s) could not be unheld.');
    }
  }

  bool _needsDispatchAction(StockHoldModel hold, SalesOrderModel? order) {
    return hold.sourceType == StockHoldSourceType.salesOrder &&
        order != null &&
        (order.status == SOStatus.draft || order.status == SOStatus.confirmed);
  }

  String _sourceLabel(StockHoldModel hold) {
    final challan =
        hold.challanNumber.isEmpty ? '' : 'Challan ${hold.challanNumber} • ';
    if (hold.sourceType == StockHoldSourceType.salesOrder) {
      return '${challan}Sales Order';
    }
    if (hold.sourceType == StockHoldSourceType.invoice) {
      return '${challan}Invoice';
    }
    return '${challan}Manual Hold';
  }

  Future<void> _dispatchSalesOrderForHold(
    StockHoldModel hold,
    SalesOrderModel order,
  ) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    if (!user.hasPermission(AppPermissions.dispatchSalesOrders)) {
      showErrorSnackBar(
        context,
        'You do not have permission to dispatch sales orders.',
      );
      return;
    }

    // How many units of this product line to dispatch now (capped at held).
    final qty = int.tryParse(_qtyCtrl(hold).text.trim());
    if (qty == null || qty <= 0) {
      showErrorSnackBar(context, 'Enter a valid quantity.');
      return;
    }
    if (qty > hold.remainingQuantity) {
      showErrorSnackBar(
        context,
        'Cannot exceed held qty (${hold.remainingQuantity}).',
      );
      return;
    }

    // Map this product's hold qty onto the matching order line(s).
    final dispatchByIndex = <int, int>{};
    var toDispatch = qty;
    for (var i = 0; i < order.items.length; i++) {
      if (toDispatch <= 0) break;
      final item = order.items[i];
      if (item.productId != hold.productId) continue;
      final take = item.remainingToDispatch < toDispatch
          ? item.remainingToDispatch
          : toDispatch;
      if (take <= 0) continue;
      dispatchByIndex[i] = take;
      toDispatch -= take;
    }
    if (dispatchByIndex.isEmpty) {
      showErrorSnackBar(context, 'Nothing left to dispatch on this order line.');
      return;
    }

    final locations = context.read<SettingsProvider>().locations;
    if (locations.isEmpty) {
      showErrorSnackBar(context, 'Configure locations in Settings first.');
      return;
    }
    String? selectedLocation;
    final pickedLocation = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Dispatch Sales Order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This hold belongs to order ${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length).toUpperCase()}. Select dispatch location.',
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final result = await showSearchablePicker(
                    context: context,
                    title: 'Location',
                    selectedValue: selectedLocation,
                    items: locations
                        .map(
                          (loc) => PickerItem(
                            value: loc,
                            label: loc,
                            icon: Icons.location_on_rounded,
                            iconColor: AppTheme.primaryColor,
                          ),
                        )
                        .toList(),
                  );
                  if (result != null) {
                    setDialogState(() => selectedLocation = result);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    prefixIcon: Icon(Icons.location_on_rounded),
                  ),
                  child: Text(
                    selectedLocation ?? 'Tap to select',
                    style: TextStyle(
                      color: selectedLocation == null
                          ? AppTheme.textSec(context)
                          : AppTheme.textPri(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedLocation == null
                  ? null
                  : () => Navigator.pop(ctx, selectedLocation),
              child: const Text('Dispatch'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || pickedLocation == null) return;
    setState(() => _isLoading = true);
    final settings = context.read<SettingsProvider>();
    final ok = await context.read<SalesOrderProvider>().dispatchOrderItems(
      order: order,
      dispatchByItemIndex: dispatchByIndex,
      userId: user.uid,
      userName: user.name,
      location: pickedLocation,
      db: DatabaseService()..setCompanyId(settings.companyId),
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      _qtyControllers.remove(hold.id)?.dispose();
      context.read<ProductProvider>().invalidateAnalytics();
      context.read<ProductProvider>().refreshProductsByIds([hold.productId]);
      showSuccessSnackBar(
        context,
        'Dispatched $qty ${hold.productName}. Hold consumed automatically.',
      );
      return;
    }
    showErrorSnackBar(
      context,
      context.read<SalesOrderProvider>().errorMessage ?? 'Dispatch failed.',
    );
  }
}
