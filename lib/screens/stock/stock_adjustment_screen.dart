import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_overlay.dart';

class StockAdjustmentScreen extends StatefulWidget {
  final ProductModel? product;
  const StockAdjustmentScreen({super.key, this.product});

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _actualCountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  ProductModel? _selectedProduct;
  String? _selectedLocation;
  bool _saving = false;

  bool get _hasUnsavedChanges =>
      _actualCountCtrl.text.trim().isNotEmpty ||
      _reasonCtrl.text.trim().isNotEmpty ||
      (_selectedProduct != null && widget.product == null) ||
      _selectedLocation != null;

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to go back?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  int get _currentStock {
    if (_selectedProduct == null || _selectedLocation == null) return 0;
    return _selectedProduct!.locationQuantities[_selectedLocation] ?? 0;
  }

  int get _difference {
    final actual = int.tryParse(_actualCountCtrl.text) ?? 0;
    return actual - _currentStock;
  }

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _selectedProduct = widget.product;
    }
  }

  @override
  void dispose() {
    _actualCountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null || _selectedLocation == null) return;
    if (_difference == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Actual count matches current stock. No adjustment needed.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final stockProvider = context.read<StockProvider>();
    final reason = _reasonCtrl.text.trim().isEmpty
        ? 'Stock adjustment'
        : _reasonCtrl.text.trim();

    final success = await stockProvider.recordAdjustment(
      productId: _selectedProduct!.id,
      productName: _selectedProduct!.name,
      adjustmentDelta: _difference,
      location: _selectedLocation!,
      userId: auth.currentUser!.uid,
      userName: auth.currentUser!.name,
      reason: 'Adjustment: $reason',
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      context.read<ProductProvider>().refreshProducts();
      if (mounted) {
        showSuccessOverlay(
          context,
          message:
              'Stock adjusted by ${_difference > 0 ? '+' : ''}$_difference ${_selectedProduct?.unit ?? 'units'}',
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(stockProvider.errorMessage ?? 'Adjustment failed'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canAdjust =
        auth.currentUser?.hasPermission('canAdjustStock') ?? false;

    if (!canAdjust) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.tune_rounded,
            color: AppTheme.warningColor,
            title: 'Stock Adjustment',
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
          child: const Center(
            child: EmptyStateWidget(
              icon: Icons.lock_outline_rounded,
              title: 'Access Restricted',
              subtitle:
                  'Only admins and super admins can adjust stock. Contact your administrator.',
            ),
          ),
        ),
      );
    }

    final productProvider = context.watch<ProductProvider>();
    final settings = context.watch<SettingsProvider>();
    final products = productProvider.allProducts;
    final locations = settings.locations;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.tune_rounded,
            color: AppTheme.warningColor,
            title: 'Stock Adjustment',
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
          child: products.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.inventory_2_outlined,
                  title: 'No Products Yet',
                  subtitle: 'Add products before adjusting stock.',
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.all(
                    Responsive.horizontalPadding(context),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: Responsive.formMaxWidth(context),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GlassPanel(
                              borderRadius: 20,
                              padding: const EdgeInsets.all(20),
                              useContentVariant: true,
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.tune_rounded,
                                    size: 40,
                                    color: AppTheme.warningColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Adjust Stock Count',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Enter the actual physical count after a stock audit. The difference will be recorded automatically.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            GlassSectionCard(
                              title: 'Product',
                              icon: Icons.inventory_2_rounded,
                              child: DropdownButtonFormField<ProductModel>(
                                initialValue: _selectedProduct,
                                decoration: const InputDecoration(
                                  labelText: 'Select Product',
                                  prefixIcon: Icon(Icons.search_rounded),
                                ),
                                isExpanded: true,
                                items: products
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Text(
                                          p.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (p) => setState(() {
                                  _selectedProduct = p;
                                  _selectedLocation = null;
                                  _actualCountCtrl.clear();
                                }),
                                validator: (v) =>
                                    v == null ? 'Select a product' : null,
                              ),
                            ),
                            const SizedBox(height: 16),

                            GlassSectionCard(
                              title: 'Location',
                              icon: Icons.location_on_rounded,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedLocation,
                                decoration: const InputDecoration(
                                  labelText: 'Select Location',
                                  prefixIcon: Icon(Icons.place_rounded),
                                ),
                                isExpanded: true,
                                items: locations
                                    .map(
                                      (l) => DropdownMenuItem(
                                        value: l,
                                        child: Text(l),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (l) => setState(() {
                                  _selectedLocation = l;
                                  _actualCountCtrl.clear();
                                }),
                                validator: (v) =>
                                    v == null ? 'Select a location' : null,
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (_selectedProduct != null &&
                                _selectedLocation != null) ...[
                              GlassSectionCard(
                                title: 'Stock Count',
                                icon: Icons.calculate_rounded,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _InfoBox(
                                            label: 'Current Stock',
                                            value: '$_currentStock',
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _actualCountCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Actual Count',
                                              prefixIcon: Icon(
                                                Icons.edit_rounded,
                                              ),
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            onChanged: (_) => setState(() {}),
                                            validator: (v) {
                                              if (v == null || v.isEmpty) {
                                                return 'Required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_actualCountCtrl.text.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color:
                                              (_difference == 0
                                                      ? AppTheme.textSecondary
                                                      : _difference > 0
                                                      ? AppTheme.successColor
                                                      : AppTheme.dangerColor)
                                                  .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              _difference == 0
                                                  ? Icons.check_circle_rounded
                                                  : _difference > 0
                                                  ? Icons.arrow_upward_rounded
                                                  : Icons
                                                        .arrow_downward_rounded,
                                              color: _difference == 0
                                                  ? AppTheme.textSecondary
                                                  : _difference > 0
                                                  ? AppTheme.successColor
                                                  : AppTheme.dangerColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _difference == 0
                                                  ? 'No difference'
                                                  : 'Difference: ${_difference > 0 ? '+' : ''}$_difference ${_selectedProduct!.unit}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: _difference == 0
                                                    ? AppTheme.textSecondary
                                                    : _difference > 0
                                                    ? AppTheme.successColor
                                                    : AppTheme.dangerColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            GlassSectionCard(
                              title: 'Reason',
                              icon: Icons.note_rounded,
                              child: TextFormField(
                                controller: _reasonCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Reason for adjustment',
                                  hintText: 'e.g. Physical count audit',
                                  prefixIcon: Icon(Icons.notes_rounded),
                                ),
                                maxLines: 2,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                            const SizedBox(height: 24),

                            ElevatedButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(
                                _saving ? 'Saving...' : 'Apply Adjustment',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.warningColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.inputFillColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
