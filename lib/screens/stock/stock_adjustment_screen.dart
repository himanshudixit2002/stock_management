import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
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
import '../../widgets/product_picker.dart';
import '../../widgets/searchable_picker.dart';
import '../../config/permissions.dart';

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
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Are you sure you want to go back?',
      confirmLabel: 'Discard',
    );
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
    _actualCountCtrl.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _actualCountCtrl.removeListener(_onChanged);
    _actualCountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null || _selectedLocation == null) return;
    if (_difference == 0) {
      showInfoSnackBar(
        context,
        'Actual count matches current stock. No adjustment needed.',
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
              'Adjusted by ${_difference > 0 ? '+' : ''}$_difference ${_selectedProduct?.unit ?? 'units'}',
        );
      }
    } else {
      showErrorSnackBar(
        context,
        stockProvider.errorMessage ?? 'Adjustment failed',
      );
    }
  }

  Future<void> _pickProduct(List<ProductModel> products) async {
    final p = await showProductPicker(
      context: context,
      products: products,
      selectedProductId: _selectedProduct?.id,
    );
    if (p == null || !mounted) return;
    setState(() {
      _selectedProduct = p;
      _selectedLocation = null;
      _actualCountCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canAdjust =
        auth.currentUser?.hasPermission(AppPermissions.adjustStock) ?? false;

    if (!canAdjust) {
      return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.tune_rounded,
            color: AppTheme.warningColor,
            title: 'Stock Adjustment',
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
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

    if (_selectedProduct != null) {
      final fresh = products.where((p) => p.id == _selectedProduct!.id).firstOrNull;
      if (fresh != null) {
        _selectedProduct = fresh;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedProduct = null);
        });
      }
    }

    if (locations.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.tune_rounded,
            color: AppTheme.warningColor,
            title: 'Stock Adjustment',
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: Center(
            child: EmptyStateWidget(
              icon: Icons.location_off_rounded,
              title: 'No Locations Configured',
              subtitle: 'Add locations in Settings before adjusting stock.',
              buttonText: 'Go to Settings',
              onButtonPressed: () {
                Navigator.pushNamed(context, AppRoutes.settings, arguments: 'locations');
              },
            ),
          ),
        ),
      );
    }

    final locQty = _selectedProduct?.locationQuantities ?? {};
    final seen = <String>{};
    final allLocations = <String>[];
    for (final loc in locQty.keys) {
      if (seen.add(loc.toLowerCase())) allLocations.add(loc);
    }
    for (final loc in locations) {
      if (seen.add(loc.toLowerCase())) allLocations.add(loc);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.tune_rounded,
            color: AppTheme.warningColor,
            title: 'Stock Adjustment',
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: products.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.inventory_2_outlined,
                  title: 'No Products Yet',
                  subtitle: 'Add products before adjusting stock.',
                  buttonText: 'Add Product',
                  onButtonPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.addProduct),
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
                            // Product selector
                            GlassSectionCard(
                              title: 'Product & Location',
                              icon: Icons.inventory_2_rounded,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  GestureDetector(
                                    onTap: widget.product != null
                                        ? null
                                        : () => _pickProduct(products),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Product *',
                                        prefixIcon: const Icon(Icons.inventory_2_rounded),
                                        suffixIcon: widget.product == null
                                            ? const Icon(Icons.arrow_drop_down)
                                            : null,
                                        errorText: _selectedProduct == null &&
                                                _saving
                                            ? 'Select a product'
                                            : null,
                                      ),
                                      child: Text(
                                        _selectedProduct?.name ?? 'Tap to select product',
                                        style: TextStyle(
                                          color: _selectedProduct != null
                                              ? AppTheme.textPri(context)
                                              : AppTheme.textSec(context),
                                          fontWeight: _selectedProduct != null
                                              ? FontWeight.w500
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),

                                  if (_selectedProduct != null) ...[
                                    const SizedBox(height: 12),
                                    _StockSummary(product: _selectedProduct!),
                                    const SizedBox(height: 12),
                                    FormField<String>(
                                      validator: (_) => _selectedLocation == null ? 'Select a location' : null,
                                      builder: (field) => GestureDetector(
                                        onTap: () async {
                                          final result = await showSearchablePicker(
                                            context: context,
                                            title: 'Location',
                                            selectedValue: _selectedLocation,
                                            items: allLocations.map((l) {
                                              final qty = locQty[l];
                                              return PickerItem(
                                                value: l,
                                                label: l,
                                                subtitle: qty != null ? '$qty ${_selectedProduct!.unit}' : null,
                                                icon: Icons.place_rounded,
                                                iconColor: AppTheme.primaryColor,
                                              );
                                            }).toList(),
                                          );
                                          if (result != null) {
                                            setState(() {
                                              _selectedLocation = result;
                                              _actualCountCtrl.clear();
                                            });
                                            field.didChange(result);
                                          }
                                        },
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: 'Location *',
                                            prefixIcon: const Icon(Icons.place_rounded),
                                            errorText: field.errorText,
                                          ),
                                          child: Text(
                                            _selectedLocation ?? 'Tap to select',
                                            style: TextStyle(
                                              color: _selectedLocation != null ? null : AppTheme.textSec(context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            if (_selectedProduct != null &&
                                _selectedLocation != null) ...[
                              const SizedBox(height: 16),
                              GlassSectionCard(
                                title: 'Adjustment',
                                icon: Icons.calculate_rounded,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                'System Stock',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textSec(context),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '$_currentStock',
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.textPri(context),
                                                ),
                                              ),
                                              Text(
                                                _selectedProduct!.unit,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textSec(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          color: AppTheme.textSec(context).withValues(alpha: 0.4),
                                        ),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                'Actual Count',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textSec(context),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              SizedBox(
                                                width: 100,
                                                child: TextFormField(
                                                  controller: _actualCountCtrl,
                                                  keyboardType: TextInputType.number,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                  decoration: InputDecoration(
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                      borderSide: BorderSide.none,
                                                    ),
                                                    filled: true,
                                                    fillColor: AppTheme.inputFill(context),
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(vertical: 8),
                                                    hintText: '0',
                                                    hintStyle: TextStyle(
                                                      color: AppTheme.textSec(context)
                                                          .withValues(alpha: 0.4),
                                                    ),
                                                  ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.digitsOnly,
                                                  ],
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
                                        ),
                                      ],
                                    ),
                                    if (_actualCountCtrl.text.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      _DifferenceBadge(
                                        difference: _difference,
                                        unit: _selectedProduct!.unit,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              GlassPanel(
                                padding: const EdgeInsets.all(12),
                                child: TextFormField(
                                  controller: _reasonCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Reason (optional)',
                                    hintText: 'e.g. Physical count audit',
                                    prefixIcon: Icon(Icons.notes_rounded),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  maxLines: 1,
                                  textCapitalization: TextCapitalization.sentences,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _saving || _difference == 0
                                    ? null
                                    : _submit,
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
                                  _saving
                                      ? 'Saving...'
                                      : _difference == 0 &&
                                              _actualCountCtrl.text.isNotEmpty
                                          ? 'No Change Needed'
                                          : 'Apply Adjustment',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.warningColor,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
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

class _StockSummary extends StatelessWidget {
  final ProductModel product;
  const _StockSummary({required this.product});

  @override
  Widget build(BuildContext context) {
    final locQty = product.locationQuantities;
    if (locQty.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.warningColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: AppTheme.warningColor),
            const SizedBox(width: 8),
            Text(
              'No stock in any location',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.warningColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.inputFill(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ...locQty.entries.map((e) {
            final isLast = e.key == locQty.keys.last;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: AppTheme.dividerC(context),
                          width: 0.5,
                        ),
                      ),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    '${e.value} ${product.unit}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSec(context),
                  ),
                ),
                Text(
                  '${product.quantity} ${product.unit}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DifferenceBadge extends StatelessWidget {
  final int difference;
  final String unit;
  const _DifferenceBadge({required this.difference, required this.unit});

  @override
  Widget build(BuildContext context) {
    final color = difference == 0
        ? AppTheme.textSec(context)
        : difference > 0
            ? AppTheme.successColor
            : AppTheme.dangerColor;
    final icon = difference == 0
        ? Icons.check_circle_rounded
        : difference > 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;
    final label = difference == 0
        ? 'No difference'
        : '${difference > 0 ? '+' : ''}$difference $unit';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
