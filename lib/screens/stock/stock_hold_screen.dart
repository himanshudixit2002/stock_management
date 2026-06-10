import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/stock_hold_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/success_overlay.dart';

/// A single editable line in the hold batch (one product + quantity).
class _HoldLine {
  final ProductModel product;
  final TextEditingController qtyController;

  _HoldLine({required this.product})
      : qtyController = TextEditingController(text: '1');

  void dispose() => qtyController.dispose();
}

class StockHoldScreen extends StatefulWidget {
  final ProductModel? product;
  const StockHoldScreen({super.key, this.product});

  @override
  State<StockHoldScreen> createState() => _StockHoldScreenState();
}

class _StockHoldScreenState extends State<StockHoldScreen> {
  final _formKey = GlobalKey<FormState>();
  final _challanController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_HoldLine> _lines = [];
  DateTime? _expiresAt;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _lines.add(_HoldLine(product: widget.product!));
    }
  }

  @override
  void dispose() {
    _challanController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  int get _totalQty => _lines.fold<int>(0, (sum, line) {
        return sum + (int.tryParse(line.qtyController.text.trim()) ?? 0);
      });

  /// Latest version of a product from the provider (stock can change live).
  ProductModel _liveProduct(ProductModel product) {
    final products = context.read<ProductProvider>().allProducts;
    return products.firstWhere(
      (p) => p.id == product.id,
      orElse: () => product,
    );
  }

  Future<void> _addLine(List<ProductModel> products) async {
    final alreadyAdded = _lines.map((l) => l.product.id).toSet();
    final selectable =
        products.where((p) => !alreadyAdded.contains(p.id)).toList();
    if (selectable.isEmpty) {
      showInfoSnackBar(context, 'All products are already in the list.');
      return;
    }
    final product = await showProductPicker(
      context: context,
      products: selectable,
      title: 'Add Product to Hold',
    );
    if (product == null || !mounted) return;
    setState(() => _lines.add(_HoldLine(product: product)));
  }

  void _removeLine(_HoldLine line) {
    setState(() {
      _lines.remove(line);
      line.dispose();
    });
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (_lines.isEmpty) {
      showErrorSnackBar(context, 'Add at least one product to hold.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    final items = <StockHoldBatchItem>[];
    for (final line in _lines) {
      final qty = int.tryParse(line.qtyController.text.trim()) ?? 0;
      if (qty <= 0) continue;
      items.add(
        StockHoldBatchItem(
          productId: line.product.id,
          productName: line.product.name,
          quantity: qty,
        ),
      );
    }
    if (items.isEmpty) {
      showErrorSnackBar(context, 'Enter a quantity for at least one product.');
      return;
    }

    setState(() => _isLoading = true);
    final ok = await context.read<StockProvider>().createStockHoldsBatch(
          items: items,
          userId: user.uid,
          userName: user.name,
          challanNumber: _challanController.text.trim(),
          reason: _reasonController.text.trim(),
          notes: _notesController.text.trim(),
          expiresAt: _expiresAt,
        );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      context.read<ProductProvider>().refreshProducts();
      HapticFeedback.mediumImpact();
      showSuccessOverlay(
        context,
        message: items.length == 1
            ? 'Stock hold created'
            : '${items.length} holds created',
      );
      _challanController.clear();
      _reasonController.clear();
      _notesController.clear();
      setState(() {
        for (final line in _lines) {
          line.dispose();
        }
        _lines.clear();
        _expiresAt = null;
      });
    } else {
      showErrorSnackBar(
        context,
        context.read<StockProvider>().errorMessage ?? 'Failed to create hold.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.holdStock)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Hold')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }
    final products = context.watch<ProductProvider>().allProducts;
    if (products.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.pause_circle_rounded,
            color: AppTheme.warningColor,
            title: 'Stock Hold',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.inventory_2_rounded,
          title: 'No Products',
          subtitle: 'Create products before putting stock on hold.',
          buttonText: 'Add Product',
          onButtonPressed: () =>
              Navigator.pushNamed(context, AppRoutes.addProduct),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.pause_circle_rounded,
          color: AppTheme.warningColor,
          title: 'Stock Hold',
        ),
        actions: [
          IconButton(
            tooltip: 'View Holds',
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.stockHolds),
            icon: const Icon(Icons.lock_clock_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                children: [
                  _infoBanner(),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _challanController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Challan No. *',
                      hintText: 'One challan for all items below',
                      prefixIcon: Icon(Icons.receipt_long_rounded),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Challan number is required'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  _itemsHeader(products),
                  const SizedBox(height: 8),
                  if (_lines.isEmpty)
                    _emptyItemsHint()
                  else
                    ..._lines.map(_buildLineCard),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      prefixIcon: Icon(Icons.info_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365),
                        ),
                        initialDate: _expiresAt ?? DateTime.now(),
                      );
                      if (picked != null && mounted) {
                        setState(() => _expiresAt = picked);
                      }
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      _expiresAt == null
                          ? 'Set Expiry (optional)'
                          : 'Expiry: ${MaterialLocalizations.of(context).formatCompactDate(_expiresAt!)}',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || _lines.isEmpty ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.pause_circle_rounded),
                      label: Text(
                        _lines.length <= 1
                            ? 'Create Hold'
                            : 'Create ${_lines.length} Holds',
                      ),
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
                      icon: const Icon(Icons.play_circle_rounded),
                      label: const Text('Release / Dispatch'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reserve stock for one or more products under a single challan. '
              'No location is needed now \u2014 pick the despatch location when '
              'you release the stock.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsHeader(List<ProductModel> products) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _lines.isEmpty
                ? 'Items to hold'
                : '${_lines.length} item${_lines.length == 1 ? '' : 's'} \u2022 $_totalQty total',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _addLine(products),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Product'),
        ),
      ],
    );
  }

  Widget _emptyItemsHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: AppTheme.textSec(context),
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            'No products added yet',
            style: TextStyle(
              color: AppTheme.textSec(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Add Product" to start building the hold.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSec(context), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLineCard(_HoldLine line) {
    final product = _liveProduct(line.product);
    final available = product.availableQuantity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Available $available ${product.unit}',
                          style: TextStyle(
                            fontSize: 12,
                            color: available <= 0
                                ? AppTheme.dangerColor
                                : AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => _removeLine(line),
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              QuantityStepper(
                controller: line.qtyController,
                label: 'Quantity to Hold *',
                unitsPerPack: product.unitsPerPack,
                packUnit: product.packUnit,
                baseUnit: product.baseUnit,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter quantity';
                  }
                  final qty = int.tryParse(value);
                  if (qty == null || qty <= 0) {
                    return 'Enter valid quantity';
                  }
                  if (qty > available) {
                    return 'Exceeds available quantity ($available)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
