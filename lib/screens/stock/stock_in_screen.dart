import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/success_overlay.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/product_picker.dart';
import '../../config/routes.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';

class StockInScreen extends StatefulWidget {
  final ProductModel? product;

  const StockInScreen({super.key, this.product});

  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  var _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  ProductModel? _selectedProduct;
  String? _selectedLocation;
  String _selectedVendorId = '';
  String _selectedVendorName = '';
  bool _isLoading = false;

  bool get _hasUnsavedChanges =>
      _quantityController.text.trim().isNotEmpty ||
      _selectedLocation != null ||
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

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.product;
    _autoPopulateVendor();
  }

  void _autoPopulateVendor() {
    if (_selectedProduct != null &&
        _selectedProduct!.preferredVendorId.isNotEmpty) {
      _selectedVendorId = _selectedProduct!.preferredVendorId;
      _selectedVendorName = _selectedProduct!.preferredVendorName;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<bool> _confirmLargeQuantity(int qty) async {
    if (qty <= 100) return true;
    return showConfirmDialog(
      context,
      title: 'Large Quantity',
      message:
          'Are you sure you want to add $qty items? Please confirm this is correct.',
      confirmLabel: 'Confirm',
      iconColor: AppTheme.warningColor,
    );
  }

  Future<void> _addStock() async {
    if (_isLoading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      showErrorSnackBar(context, 'Please select a product');
      return;
    }

    if (_selectedLocation == null || _selectedLocation!.isEmpty) {
      showErrorSnackBar(context, 'Please select a location');
      return;
    }

    final location = _selectedLocation!;

    final qty = int.tryParse(_quantityController.text);
    if (qty == null || qty <= 0) return;
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
    final success = await context.read<StockProvider>().addStock(
      productId: _selectedProduct!.id,
      productName: _selectedProduct!.name,
      quantity: qty,
      location: location,
      userId: user.uid,
      userName: user.name,
      reason: _reasonController.text.trim(),
      vendorId: _selectedVendorId,
      vendorName: _selectedVendorName,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final productId = _selectedProduct!.id;
      final productName = _selectedProduct!.name;
      final quantity = qty;
      final undoLocation = location;
      final vendorId = _selectedVendorId;
      final vendorName = _selectedVendorName;
      final stockProvider = context.read<StockProvider>();
      final productProvider = context.read<ProductProvider>();
      final messenger = ScaffoldMessenger.of(context);
      final uid = user.uid;
      final userName = user.name;

      productProvider.refreshProducts();
      HapticFeedback.mediumImpact();
      _quantityController.clear();
      _reasonController.clear();
      setState(() {
        if (widget.product == null) _selectedProduct = null;
        _selectedLocation = null;
        _selectedVendorId = '';
        _selectedVendorName = '';
        _submitted = false;
        _formKey = GlobalKey<FormState>();
      });
      messenger.hideCurrentSnackBar();
      showSuccessOverlay(context, message: 'Stock added successfully');
      Future.delayed(const Duration(milliseconds: 1300), () {
        if (!context.mounted) return;
        showUndoSnackBar(
          context,
          'Added $quantity to $productName. Undo?',
          () async {
            final undone = await stockProvider.removeStock(
              productId: productId,
              productName: productName,
              quantity: quantity,
              location: undoLocation,
              userId: uid,
              userName: userName,
              reason: 'Undo stock-in',
              vendorId: vendorId,
              vendorName: vendorName,
            );
            if (undone) {
              productProvider.refreshProducts();
              messenger.hideCurrentSnackBar();
              if (context.mounted) {
                showSuccessSnackBar(context, 'Stock-in undone');
              }
            }
          },
        );
      });
    } else {
      showErrorSnackBar(
        context,
        context.read<StockProvider>().errorMessage ?? 'Failed to add stock',
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
      if (p.preferredVendorId.isNotEmpty) {
        _selectedVendorId = p.preferredVendorId;
        _selectedVendorName = p.preferredVendorName;
      } else {
        _selectedVendorId = '';
        _selectedVendorName = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.stockIn,
      featureName: 'Stock In',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final products = context.watch<ProductProvider>().allProducts;
    final settingsLocations = context.watch<SettingsProvider>().locations;

    // Keep _selectedProduct in sync with provider data
    if (_selectedProduct != null) {
      final fresh = products.cast<ProductModel?>().firstWhere(
        (p) => p!.id == _selectedProduct!.id,
        orElse: () => null,
      );
      if (fresh != null && fresh != _selectedProduct) {
        _selectedProduct = fresh;
      }
    }

    if (products.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.add_circle_rounded,
            color: AppTheme.successColor,
            title: 'Stock In',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.inventory_2_rounded,
          title: 'No Products Yet',
          subtitle: 'Add your first product to start receiving stock.',
          buttonText: 'Add Product',
          onButtonPressed: () {
            Navigator.pushNamed(context, AppRoutes.addProduct);
          },
        ),
      );
    }

    if (settingsLocations.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.add_circle_rounded,
            color: AppTheme.successColor,
            title: 'Stock In',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.location_off_rounded,
          title: 'No Locations Configured',
          subtitle: 'Add locations in Settings before receiving stock.',
          buttonText: 'Go to Settings',
          onButtonPressed: () {
            Navigator.pushNamed(
              context,
              AppRoutes.settings,
              arguments: 'locations',
            );
          },
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
              icon: Icons.add_circle_rounded,
              color: AppTheme.successColor,
              title: 'Stock In',
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
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
                  child: GlassPanel(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    useContentVariant: true,
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
                                                color: AppTheme.textSec(
                                                  context,
                                                ),
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

                          const SizedBox(height: 12),

                          // Location selector
                          GestureDetector(
                            onTap: () async {
                              final result = await showSearchablePicker(
                                context: context,
                                title: 'Location',
                                selectedValue: _selectedLocation,
                                addNewLabel: 'Add new location',
                                addNewValue: '__create_new__',
                                items: settingsLocations.map((loc) {
                                  final qty =
                                      _selectedProduct?.locationQuantities[loc];
                                  return PickerItem(
                                    value: loc,
                                    label: loc,
                                    subtitle: qty != null
                                        ? '$qty in stock'
                                        : null,
                                    icon: Icons.location_on_rounded,
                                    iconColor: AppTheme.primaryColor,
                                  );
                                }).toList(),
                              );
                              if (result == null || !mounted) return;
                              if (result == '__create_new__') {
                                final settingsProvider = context
                                    .read<SettingsProvider>();
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
                                prefixIcon: const Icon(
                                  Icons.location_on_rounded,
                                ),
                                suffixIcon: _selectedLocation != null
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () => setState(
                                          () => _selectedLocation = null,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_drop_down),
                                errorText:
                                    _submitted && _selectedLocation == null
                                    ? 'Please select a location'
                                    : null,
                              ),
                              child: Text(
                                _selectedLocation ?? 'Select location',
                                style: TextStyle(
                                  color: _selectedLocation != null
                                      ? AppTheme.textPri(context)
                                      : AppTheme.textSec(context),
                                ),
                              ),
                            ),
                          ),

                          Consumer<SettingsProvider>(
                            builder: (context, settings, _) {
                              if (!settings.vendorsEnabled) {
                                return const SizedBox.shrink();
                              }
                              final vendorProvider = context
                                  .watch<VendorProvider>();
                              final activeVendors =
                                  vendorProvider.activeVendors;
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
                                      items: activeVendors
                                          .map(
                                            (v) => PickerItem(
                                              value: v.id,
                                              label: v.name,
                                              icon:
                                                  Icons.local_shipping_rounded,
                                            ),
                                          )
                                          .toList(),
                                    );
                                    if (result != null && mounted) {
                                      final v = vendorProvider.getVendorById(
                                        result,
                                      );
                                      setState(() {
                                        _selectedVendorId = result;
                                        _selectedVendorName = v?.name ?? '';
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Vendor (optional)',
                                      prefixIcon: const Icon(
                                        Icons.local_shipping_rounded,
                                      ),
                                      suffixIcon: _selectedVendorId.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                              ),
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

                          const SizedBox(height: 16),

                          QuantityStepper(
                            controller: _quantityController,
                            label: 'Quantity to Add *',
                            unitsPerPack: _selectedProduct?.unitsPerPack ?? 1,
                            packUnit: _selectedProduct?.packUnit ?? 'box',
                            baseUnit: _selectedProduct?.baseUnit ?? 'pcs',
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter quantity';
                              }
                              final qty = int.tryParse(value);
                              if (qty == null || qty <= 0) {
                                return 'Enter a valid quantity';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _reasonController,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                              prefixIcon: Icon(Icons.note_rounded),
                              hintText: 'e.g., New shipment received',
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 20),

                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _addStock,
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
                            label: const Text('Add Stock'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successColor,
                            ),
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
      ),
    );
  }
}
