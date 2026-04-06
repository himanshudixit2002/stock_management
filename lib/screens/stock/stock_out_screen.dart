import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/success_overlay.dart';
import '../../config/permissions.dart';

class StockOutScreen extends StatefulWidget {
  final ProductModel? product;

  const StockOutScreen({super.key, this.product});

  @override
  State<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends State<StockOutScreen> {
  var _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _locationController = TextEditingController();

  ProductModel? _selectedProduct;
  String _selectedLocation = '';
  String _selectedVendorId = '';
  String _selectedVendorName = '';
  bool _isLoading = false;

  bool get _hasUnsavedChanges =>
      _quantityController.text.trim().isNotEmpty ||
      _locationController.text.trim().isNotEmpty ||
      _reasonController.text.trim().isNotEmpty ||
      (_selectedProduct != null && widget.product == null);

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Are you sure you want to go back?',
      confirmLabel: 'Discard',
    );
  }

  int get _availableAtLocation {
    if (_selectedProduct == null || _selectedLocation.isEmpty) return 0;
    return _selectedProduct!.locationQuantities[_selectedLocation] ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.product;
    if (_selectedProduct != null) {
      final locs = _selectedProduct!.locationQuantities.entries
          .where((e) => e.value > 0)
          .toList();
      if (locs.length == 1) _selectedLocation = locs.first.key;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _locationController.dispose();
    super.dispose();
  }



  Future<bool> _confirmStockOut(int qty) async {
    return showConfirmDialog(
      context,
      title: 'Confirm Stock Out',
      message: 'Remove $qty ${_selectedProduct?.unit ?? "pcs"} of "${_selectedProduct?.name}" from $_selectedLocation?\n\n'
          'This action cannot be undone.',
      confirmLabel: 'Confirm',
      icon: Icons.outbox_rounded,
      iconColor: AppTheme.primaryColor,
    );
  }

  Future<bool> _confirmLargeQuantity(int qty) async {
    if (qty <= 100) return true;
    return showConfirmDialog(
      context,
      title: 'Large Quantity',
      message: 'Are you sure you want to remove $qty items? Please confirm this is correct.',
      confirmLabel: 'Confirm',
      iconColor: AppTheme.warningColor,
    );
  }

  Future<void> _removeStock() async {
    if (_isLoading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      showErrorSnackBar(context, 'Please select a product');
      return;
    }
    if (_selectedLocation.isEmpty) {
      showErrorSnackBar(context, 'Please select a location');
      return;
    }

    final qty = int.tryParse(_quantityController.text);
    if (qty == null || qty <= 0) return;
    if (!await _confirmStockOut(qty)) return;
    if (!await _confirmLargeQuantity(qty)) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        showErrorSnackBar(context, 'Session expired. Please log in again.');
      }
      return;
    }
    final success = await context.read<StockProvider>().removeStock(
      productId: _selectedProduct!.id,
      productName: _selectedProduct!.name,
      quantity: qty,
      location: _selectedLocation,
      userId: user.uid,
      userName: user.name,
      reason: _reasonController.text.trim(),
      vendorId: _selectedVendorId,
      vendorName: _selectedVendorName,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.read<ProductProvider>().refreshProducts();
      HapticFeedback.mediumImpact();
      final productName = _selectedProduct!.name;
      final newQuantity = _selectedProduct!.quantity - qty;
      final threshold = _selectedProduct!.lowStockThreshold;
      _quantityController.clear();
      _reasonController.clear();
      _locationController.clear();
      setState(() {
        if (widget.product == null) _selectedProduct = null;
        _selectedLocation = '';
        _selectedVendorId = '';
        _selectedVendorName = '';
        _submitted = false;
        _formKey = GlobalKey<FormState>();
      });
      showSuccessOverlay(context, message: 'Stock removed successfully');
      if (mounted && newQuantity < threshold) {
        _showLowStockBanner(context, productName);
      }
    } else {
      showErrorSnackBar(
        context,
        context.read<StockProvider>().errorMessage ?? 'Failed to remove stock',
      );
    }
  }

  void _showLowStockBanner(BuildContext context, String productName) {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text(
          '$productName is now low stock. Create PO?',
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        backgroundColor: AppTheme.warningColor,
        leading: Icon(
          Icons.warning_amber_rounded,
          color: AppTheme.surface(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Navigator.pushNamed(
                context,
                AppRoutes.createPurchaseOrder,
              );
            },
            child: Text(
              'Create PO',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.surface(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: Text(
              'Dismiss',
              style: TextStyle(
                color: AppTheme.surface(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProduct(List<ProductModel> products) async {
    final p = await showProductPicker(
      context: context,
      products: products,
      selectedProductId: _selectedProduct?.id,
    );
    if (p == null || !mounted) return;
    final locs = p.locationQuantities.entries.where((e) => e.value > 0).toList();
    setState(() {
      _selectedProduct = p;
      _selectedLocation = locs.length == 1 ? locs.first.key : '';
      _locationController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.stockOut)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Out')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final allProducts = context.watch<ProductProvider>().allProducts;

    // Keep _selectedProduct in sync with provider data
    if (_selectedProduct != null) {
      final fresh = allProducts.cast<ProductModel?>().firstWhere(
        (p) => p!.id == _selectedProduct!.id,
        orElse: () => null,
      );
      if (fresh != null && fresh != _selectedProduct) {
        _selectedProduct = fresh;
      }
    }

    final products = allProducts
        .where(
          (p) =>
              p.quantity > 0 && p.locationQuantities.values.any((q) => q > 0),
        )
        .toList();

    final productLocations =
        _selectedProduct?.locationQuantities.entries
            .where((e) => e.value > 0)
            .map((e) => e.key)
            .toList() ??
        [];

    if (allProducts.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.remove_circle_rounded,
            color: AppTheme.primaryColor,
            title: 'Stock Out',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.inventory_2_rounded,
          title: 'No Products Yet',
          subtitle: 'Add your first product to start dispatching stock.',
          buttonText: 'Add Product',
          onButtonPressed: () {
            Navigator.pushNamed(context, AppRoutes.addProduct);
          },
        ),
      );
    }

    if (products.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.remove_circle_rounded,
            color: AppTheme.primaryColor,
            title: 'Stock Out',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.inventory_2_outlined,
          title: 'No Stock Available',
          subtitle:
              'All products are out of stock. Add stock before dispatching.',
          buttonText: 'Go to Stock In',
          onButtonPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.stockIn),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          if (_submitted) {
            setState(() {
              _submitted = false;
              _formKey = GlobalKey<FormState>();
            });
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.bg(context),
          appBar: AppBar(
            title: AppBarTitleRow(
              icon: Icons.remove_circle_rounded,
              color: AppTheme.primaryColor,
              title: 'Stock Out',
            ),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: AppTheme.scaffoldGrad(context),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.formMaxWidth(context),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(
                    Responsive.horizontalPadding(context),
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Select Product *',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Material(
                          color: AppTheme.inputFill(context),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => _pickProduct(products),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppTheme.inputBorder(context),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2_rounded,
                                    color: _selectedProduct != null
                                        ? AppTheme.primaryColor
                                        : AppTheme.textSec(context),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _selectedProduct != null
                                        ? Text(
                                            _selectedProduct!.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          )
                                        : Text(
                                            'Tap to select a product...',
                                            style: TextStyle(
                                              color: AppTheme.textSec(context),
                                              fontSize: 15,
                                            ),
                                          ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: AppTheme.textSec(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Stock by location breakdown
                        if (_selectedProduct != null &&
                            _selectedProduct!.locationQuantities.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warehouse_rounded, size: 16, color: AppTheme.primaryColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Stock by Location',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Total: ${_selectedProduct!.quantity} ${_selectedProduct!.unit}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSec(context),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ..._selectedProduct!.locationQuantities.entries.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_rounded,
                                          size: 14,
                                          color: e.value > 0
                                              ? AppTheme.textSec(context)
                                              : AppTheme.textTer(context),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            e.key,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textPri(context),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${e.value} ${_selectedProduct!.unit}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: e.value > 0
                                                ? AppTheme.textPri(context)
                                                : AppTheme.textTer(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Location selector
                        if (_selectedProduct != null &&
                            productLocations.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: GestureDetector(
                              onTap: () async {
                                final result = await showSearchablePicker(
                                  context: context,
                                  title: 'Location',
                                  selectedValue:
                                      _selectedLocation.isEmpty
                                          ? null
                                          : _selectedLocation,
                                  addNewLabel: 'Add new location',
                                  addNewValue: '__create_new__',
                                  items: productLocations.map((loc) {
                                    final qty =
                                        _selectedProduct!
                                            .locationQuantities[loc] ??
                                        0;
                                    return PickerItem(
                                      value: loc,
                                      label: loc,
                                      subtitle:
                                          '$qty ${_selectedProduct!.unit}',
                                      icon: Icons.location_on_rounded,
                                      iconColor: AppTheme.primaryColor,
                                    );
                                  }).toList(),
                                );
                                if (result == null || !mounted) return;
                                if (result == '__create_new__') {
                                  final settingsProvider =
                                      context.read<SettingsProvider>();
                                  final newName = await showAddNameDialog(
                                    context,
                                    title: 'Add new location',
                                    labelText: 'Location name',
                                    hint: 'e.g. Main Warehouse',
                                    onAdd: (name) =>
                                        settingsProvider.addLocation(name),
                                  );
                                  if (newName != null && mounted) {
                                    setState(() => _selectedLocation = newName);
                                  }
                                } else {
                                  setState(() => _selectedLocation = result);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Location *',
                                  prefixIcon:
                                      const Icon(Icons.location_on_rounded),
                                  suffixIcon: _selectedLocation.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () => setState(
                                              () => _selectedLocation = ''),
                                        )
                                      : const Icon(Icons.arrow_drop_down),
                                  errorText: _submitted &&
                                          _selectedLocation.isEmpty
                                      ? 'Please select a location'
                                      : null,
                                ),
                                child: Text(
                                  _selectedLocation.isEmpty
                                      ? 'Select location'
                                      : _selectedLocation,
                                  style: TextStyle(
                                    color: _selectedLocation.isNotEmpty
                                        ? AppTheme.textPri(context)
                                        : AppTheme.textSec(context),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (_selectedProduct != null &&
                            productLocations.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'No stock at any location for this product.',
                              style: TextStyle(
                                color: AppTheme.dangerColor,
                                fontSize: 13,
                              ),
                            ),
                          ),

                        if (_selectedLocation.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Available at $_selectedLocation: $_availableAtLocation ${_selectedProduct?.unit ?? "pcs"}',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSec(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                        QuantityStepper(
                          controller: _quantityController,
                          label: 'Quantity to Remove *',
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter quantity';
                            }
                            final qty = int.tryParse(value);
                            if (qty == null || qty <= 0) {
                              return 'Enter a valid quantity';
                            }
                            if (qty > _availableAtLocation) {
                              return 'Exceeds stock at $_selectedLocation ($_availableAtLocation)';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _reasonController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Reason (optional)',
                            prefixIcon: Icon(Icons.note_rounded),
                            hintText: 'e.g., Sold to customer, Returned',
                          ),
                          maxLines: 2,
                        ),

                        Consumer<SettingsProvider>(
                          builder: (context, settings, _) {
                            if (!settings.vendorsEnabled) {
                              return const SizedBox.shrink();
                            }
                            final vendorProvider = context.watch<VendorProvider>();
                            final activeVendors = vendorProvider.activeVendors;
                            return Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: GestureDetector(
                                onTap: () async {
                                  final result = await showSearchablePicker(
                                    context: context,
                                    title: 'Vendor',
                                    selectedValue: _selectedVendorId.isEmpty
                                        ? null
                                        : _selectedVendorId,
                                    items: activeVendors.map((v) => PickerItem(
                                      value: v.id,
                                      label: v.name,
                                      icon: Icons.local_shipping_rounded,
                                    )).toList(),
                                  );
                                  if (result != null && mounted) {
                                    final v = vendorProvider.getVendorById(result);
                                    setState(() {
                                      _selectedVendorId = result;
                                      _selectedVendorName = v?.name ?? '';
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Vendor (optional)',
                                    prefixIcon: const Icon(Icons.local_shipping_rounded),
                                    suffixIcon: _selectedVendorId.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 18),
                                            onPressed: () => setState(() {
                                              _selectedVendorId = '';
                                              _selectedVendorName = '';
                                            }),
                                          )
                                        : const Icon(Icons.arrow_drop_down),
                                  ),
                                  child: Text(
                                    _selectedVendorName.isEmpty
                                        ? 'Select vendor'
                                        : _selectedVendorName,
                                    style: TextStyle(
                                      color: _selectedVendorName.isNotEmpty
                                          ? AppTheme.textPri(context)
                                          : AppTheme.textSec(context),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 32),

                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _quantityController,
                          builder: (context, value, _) {
                            final qty = int.tryParse(value.text) ?? 0;
                            final exceedsStock = qty > _availableAtLocation;
                            return ElevatedButton.icon(
                              onPressed: _isLoading || exceedsStock
                                  ? null
                                  : _removeStock,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: const Text('Remove Stock'),
                            );
                          },
                        ),
                      ],
                    ),
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
