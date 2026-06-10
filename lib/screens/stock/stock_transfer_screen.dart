import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/quantity_stepper.dart';
import '../../config/routes.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_overlay.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/product_picker.dart';
import '../../config/permissions.dart';

class StockTransferScreen extends StatefulWidget {
  final ProductModel? product;

  const StockTransferScreen({super.key, this.product});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  var _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  ProductModel? _selectedProduct;
  String _fromLocation = '';
  String? _toLocation;
  bool _isLoading = false;
  bool get _hasUnsavedChanges =>
      _quantityController.text.trim().isNotEmpty ||
      _toLocation != null ||
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

  int get _availableAtFrom {
    if (_selectedProduct == null || _fromLocation.isEmpty) return 0;
    return _selectedProduct!.locationQuantities[_fromLocation] ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.product;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<bool> _confirmTransfer(int qty) async {
    final toLocation = _toLocation!;
    return showConfirmDialog(
      context,
      title: 'Confirm Transfer',
      message:
          'Transfer $qty ${_selectedProduct?.unit ?? "pcs"} of "${_selectedProduct?.name}"\n\n'
          'From: $_fromLocation\nTo: $toLocation',
      confirmLabel: 'Transfer',
      icon: Icons.swap_horiz_rounded,
      iconColor: AppTheme.primaryColor,
    );
  }

  Future<void> _transfer() async {
    if (_isLoading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      showErrorSnackBar(context, 'Please select a product');
      return;
    }
    if (_fromLocation.isEmpty) {
      showErrorSnackBar(context, 'Please select source location');
      return;
    }

    if (_toLocation == null || _toLocation!.isEmpty) {
      showErrorSnackBar(context, 'Please select destination location');
      return;
    }

    final toLocation = _toLocation!;
    if (toLocation == _fromLocation) {
      showErrorSnackBar(context, 'Source and destination must be different');
      return;
    }

    final qty = int.tryParse(_quantityController.text);
    if (qty == null || qty <= 0) return;
    if (!await _confirmTransfer(qty)) return;
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

    final success = await context.read<StockProvider>().transferStock(
      productId: _selectedProduct!.id,
      productName: _selectedProduct!.name,
      quantity: qty,
      fromLocation: _fromLocation,
      toLocation: toLocation,
      userId: user.uid,
      userName: user.name,
      reason: _reasonController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.read<ProductProvider>().refreshProducts();
      HapticFeedback.mediumImpact();
      _quantityController.clear();
      _reasonController.clear();
      setState(() {
        if (widget.product == null) _selectedProduct = null;
        _fromLocation = '';
        _toLocation = null;
        _submitted = false;
        _formKey = GlobalKey<FormState>();
      });
      showSuccessOverlay(context, message: 'Stock transferred successfully');
    } else {
      showErrorSnackBar(
        context,
        context.read<StockProvider>().errorMessage ??
            'Failed to transfer stock',
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
    final locs = p.locationQuantities.entries
        .where((e) => e.value > 0)
        .toList();
    setState(() {
      _selectedProduct = p;
      _fromLocation = locs.length == 1 ? locs.first.key : '';
      _toLocation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.transfer)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Transfer')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final products = context.watch<ProductProvider>().allProducts;
    final settingsLocations = context.watch<SettingsProvider>().locations;

    final productLocations =
        _selectedProduct?.locationQuantities.entries
            .where((e) => e.value > 0)
            .toList() ??
        [];

    if (products.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.swap_horiz_rounded,
            color: AppTheme.indigoColor,
            title: 'Transfer Stock',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.inventory_2_rounded,
          title: 'No Products Yet',
          subtitle: 'Add your first product to start transferring stock.',
          buttonText: 'Add Product',
          onButtonPressed: () {
            Navigator.pushNamed(context, AppRoutes.addProduct);
          },
        ),
      );
    }

    if (settingsLocations.length < 2) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.swap_horiz_rounded,
            color: AppTheme.indigoColor,
            title: 'Transfer Stock',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.location_off_rounded,
          title: 'Not Enough Locations',
          subtitle:
              'You need at least two locations to transfer stock. Add locations in Settings.',
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
              icon: Icons.swap_horiz_rounded,
              color: AppTheme.indigoColor,
              title: 'Transfer Stock',
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
                    padding: const EdgeInsets.all(20),
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

                          const SizedBox(height: 20),

                          // From location
                          if (_selectedProduct != null &&
                              productLocations.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: GestureDetector(
                                onTap: () async {
                                  final result = await showSearchablePicker(
                                    context: context,
                                    title: 'From Location',
                                    selectedValue: _fromLocation.isEmpty
                                        ? null
                                        : _fromLocation,
                                    addNewLabel: 'Add new location',
                                    addNewValue: '__create_new__',
                                    items: productLocations.map((e) {
                                      final loc = e.key;
                                      final qty = e.value;
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
                                      setState(() {
                                        _fromLocation = newName;
                                        if (_toLocation == newName)
                                          _toLocation = null;
                                      });
                                    }
                                  } else {
                                    setState(() {
                                      _fromLocation = result;
                                      if (_toLocation == result)
                                        _toLocation = null;
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'From Location *',
                                    prefixIcon: const Icon(
                                      Icons.location_on_rounded,
                                    ),
                                    suffixIcon: _fromLocation.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _fromLocation = '',
                                            ),
                                          )
                                        : const Icon(Icons.arrow_drop_down),
                                    errorText:
                                        _submitted && _fromLocation.isEmpty
                                        ? 'Select from location'
                                        : null,
                                  ),
                                  child: Text(
                                    _fromLocation.isEmpty
                                        ? 'Select from location'
                                        : _fromLocation,
                                    style: TextStyle(
                                      color: _fromLocation.isNotEmpty
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

                          // To location
                          if (_fromLocation.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: GestureDetector(
                                onTap: () async {
                                  final toItems = settingsLocations
                                      .where((l) => l != _fromLocation)
                                      .map(
                                        (loc) => PickerItem(
                                          value: loc,
                                          label: loc,
                                          icon: Icons.location_on_rounded,
                                          iconColor: AppTheme.warningColor,
                                        ),
                                      )
                                      .toList();
                                  final result = await showSearchablePicker(
                                    context: context,
                                    title: 'To Location',
                                    selectedValue: _toLocation,
                                    addNewLabel: 'Add new location',
                                    addNewValue: '__create_new__',
                                    items: toItems,
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
                                      setState(() => _toLocation = newName);
                                    }
                                  } else {
                                    setState(() => _toLocation = result);
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'To Location *',
                                    prefixIcon: const Icon(
                                      Icons.location_on_rounded,
                                    ),
                                    suffixIcon: _toLocation != null
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _toLocation = null,
                                            ),
                                          )
                                        : const Icon(Icons.arrow_drop_down),
                                    errorText: _submitted && _toLocation == null
                                        ? 'Select to location'
                                        : null,
                                  ),
                                  child: Text(
                                    _toLocation ?? 'Select to location',
                                    style: TextStyle(
                                      color: _toLocation != null
                                          ? AppTheme.textPri(context)
                                          : AppTheme.textSec(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          if (_fromLocation.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Available at $_fromLocation: $_availableAtFrom ${_selectedProduct?.unit ?? "pcs"}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSec(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                          if (_fromLocation.isNotEmpty)
                            QuantityStepper(
                              controller: _quantityController,
                              label: 'Quantity to Transfer *',
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
                                if (qty > _availableAtFrom) {
                                  return 'Exceeds stock at $_fromLocation ($_availableAtFrom)';
                                }
                                return null;
                              },
                            ),

                          if (_fromLocation.isNotEmpty) ...[
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _reasonController,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Notes (optional)',
                                prefixIcon: Icon(Icons.note_rounded),
                                hintText: 'e.g., Restocking shop floor',
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 32),

                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _quantityController,
                              builder: (context, value, _) {
                                final qty = int.tryParse(value.text) ?? 0;
                                final exceedsStock = qty > _availableAtFrom;
                                return ElevatedButton.icon(
                                  onPressed: _isLoading || exceedsStock
                                      ? null
                                      : _transfer,
                                  icon: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.swap_horiz_rounded),
                                  label: const Text('Transfer Stock'),
                                );
                              },
                            ),
                          ],
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
