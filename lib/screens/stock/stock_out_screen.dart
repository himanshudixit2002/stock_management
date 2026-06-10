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
import '../../models/stock_hold_model.dart';

class StockOutScreen extends StatefulWidget {
  final ProductModel? product;
  final HoldActionArgs? holdAction;

  const StockOutScreen({super.key, this.product, this.holdAction});

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

  /// When set, the screen is despatching units directly from this hold
  /// (reduces both held reservation and on-hand stock).
  StockHoldModel? _fromHold;
  bool _holdPrefillApplied = false;

  /// Max quantity allowed for the current operation. When despatching from a
  /// hold this is the hold's remaining qty capped by the on-hand stock at the
  /// chosen despatch location; otherwise it is the unheld available stock.
  int get _maxQty {
    if (_fromHold != null) {
      final held = _fromHold!.remainingQuantity;
      if (_selectedLocation.isEmpty) return held;
      final onHand =
          _selectedProduct?.locationQuantities[_selectedLocation] ?? 0;
      return onHand < held ? onHand : held;
    }
    return _availableAtLocation;
  }

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
    return _selectedProduct!.availableAtLocation(_selectedLocation);
  }

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.product;
    _fromHold = widget.holdAction?.hold;
    if (_fromHold != null) {
      // Location-less holds choose a despatch location below; legacy
      // location-bound holds keep their reserved location.
      if (_fromHold!.hasLocation) _selectedLocation = _fromHold!.location;
    } else if (_selectedProduct != null) {
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
      message:
          'Remove $qty ${_selectedProduct?.unit ?? "pcs"} of "${_selectedProduct?.name}" from $_selectedLocation?\n\n'
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
      message:
          'Are you sure you want to remove $qty items? Please confirm this is correct.',
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
    if (_fromHold != null) {
      if (qty > _fromHold!.remainingQuantity) {
        showErrorSnackBar(
          context,
          'Cannot despatch more than held qty (${_fromHold!.remainingQuantity}).',
        );
        return;
      }
      final onHand =
          _selectedProduct?.locationQuantities[_selectedLocation] ?? 0;
      if (qty > onHand) {
        showErrorSnackBar(
          context,
          'Only $onHand on hand at $_selectedLocation.',
        );
        return;
      }
    }
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
    final stockProvider = context.read<StockProvider>();
    final bool success;
    if (_fromHold != null) {
      success = await stockProvider.dispatchHoldQuantity(
        holdId: _fromHold!.id,
        quantity: qty,
        userId: user.uid,
        userName: user.name,
        location: _selectedLocation,
        reason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : 'Despatched from held stock'
                '${_fromHold!.challanNumber.isNotEmpty ? ' (Challan ${_fromHold!.challanNumber})' : ''}',
      );
    } else {
      success = await stockProvider.removeStock(
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
    }

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
        if (widget.product == null && _fromHold == null) {
          _selectedProduct = null;
        }
        _selectedLocation = '';
        _selectedVendorId = '';
        _selectedVendorName = '';
        _submitted = false;
        _fromHold = null;
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
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
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
              Navigator.pushNamed(context, AppRoutes.createPurchaseOrder);
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
              style: TextStyle(color: AppTheme.surface(context)),
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
    final locs = p.locationQuantities.entries
        .where((e) => p.availableAtLocation(e.key) > 0)
        .toList();
    setState(() {
      _selectedProduct = p;
      _fromHold = null;
      _selectedLocation = locs.length == 1 ? locs.first.key : '';
      _locationController.clear();
    });
    await _maybePromptDespatchFromHeld(p);
  }

  /// If the picked product has held stock, offer to despatch directly from a
  /// hold (by challan) instead of a normal stock out.
  Future<void> _maybePromptDespatchFromHeld(ProductModel product) async {
    final stockProvider = context.read<StockProvider>();
    // Only manual holds can be despatched directly here. Sales-order holds must
    // be dispatched from the order so its status/dispatched qty stays in sync.
    final manualHolds = stockProvider
        .activeHoldsForProduct(product.id)
        .where((h) => h.isManual)
        .toList();
    if (manualHolds.isEmpty || !mounted) return;
    final totalHeld =
        manualHolds.fold<int>(0, (s, h) => s + h.remainingQuantity);
    final yes = await showConfirmDialog(
      context,
      title: 'Despatch from held stock?',
      message:
          '${product.name} has $totalHeld unit(s) on manual hold across '
          '${manualHolds.length} challan(s). Despatch from held stock?',
      confirmLabel: 'Yes, from held',
      cancelLabel: 'No, normal',
      icon: Icons.lock_clock_rounded,
      iconColor: AppTheme.warningColor,
    );
    if (!yes || !mounted) return;
    await _chooseHoldToDespatch(manualHolds);
  }

  Future<void> _chooseHoldToDespatch(List<StockHoldModel> holds) async {
    StockHoldModel? picked;
    if (holds.length == 1) {
      picked = holds.first;
    } else {
      final pickedId = await showSearchablePicker(
        context: context,
        title: 'Select Challan',
        items: holds
            .map(
              (h) => PickerItem(
                value: h.id,
                label: h.challanNumber.isEmpty
                    ? 'No challan'
                    : 'Challan ${h.challanNumber}',
                subtitle: '${h.location} • ${h.remainingQuantity} held',
                icon: Icons.receipt_long_rounded,
                iconColor: AppTheme.warningColor,
              ),
            )
            .toList(),
      );
      if (pickedId == null || !mounted) return;
      picked = holds.firstWhere((h) => h.id == pickedId);
    }
    setState(() {
      _fromHold = picked;
      _selectedLocation = picked!.location;
      _quantityController.text = '${picked.remainingQuantity}';
    });
  }

  void _exitHoldMode() {
    setState(() {
      _fromHold = null;
      _quantityController.clear();
      final locs = _selectedProduct?.locationQuantities.entries
              .where((e) => _selectedProduct!.availableAtLocation(e.key) > 0)
              .toList() ??
          [];
      _selectedLocation = locs.length == 1 ? locs.first.key : '';
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

    // Resolve the product for a hold deep-link (Despatch from dashboard).
    if (_fromHold != null && _selectedProduct == null) {
      _selectedProduct = allProducts.cast<ProductModel?>().firstWhere(
        (p) => p!.id == _fromHold!.productId,
        orElse: () => null,
      );
    }
    if (_fromHold != null && !_holdPrefillApplied) {
      _holdPrefillApplied = true;
      if (_fromHold!.hasLocation) _selectedLocation = _fromHold!.location;
      if (_quantityController.text.trim().isEmpty) {
        _quantityController.text = '${_fromHold!.remainingQuantity}';
      }
    }

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
              p.availableQuantity > 0 &&
              p.locationQuantities.keys.any(
                (loc) => p.availableAtLocation(loc) > 0,
              ),
        )
        .toList();

    final productLocations =
        _selectedProduct?.locationQuantities.entries
            .where((e) => _selectedProduct!.availableAtLocation(e.key) > 0)
            .map((e) => e.key)
            .toList() ??
        [];

    final holdMode = _fromHold != null;
    // When despatching a hold we can pull from any location that physically
    // holds stock (the reservation isn't tied to a location).
    final dispatchLocations =
        _selectedProduct?.locationQuantities.entries
            .where((e) => e.value > 0)
            .map((e) => e.key)
            .toList() ??
        [];
    final locationOptions = holdMode ? dispatchLocations : productLocations;

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

    if (products.isEmpty && _fromHold == null) {
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
          onButtonPressed: () =>
              Navigator.pushReplacementNamed(context, AppRoutes.stockIn),
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

                        // Despatch-from-held banner
                        if (_fromHold != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warningColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.warningColor.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock_clock_rounded,
                                  color: AppTheme.warningColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Despatching from held stock',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.warningColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${_fromHold!.challanNumber.isEmpty ? 'No challan' : 'Challan ${_fromHold!.challanNumber}'} • '
                                        '${_fromHold!.remainingQuantity} held'
                                        '${_fromHold!.hasLocation ? ' • ${_fromHold!.location}' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSec(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _exitHoldMode,
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Stock by location breakdown
                        if (_fromHold == null &&
                            _selectedProduct != null &&
                            _selectedProduct!
                                .locationQuantities
                                .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.06,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warehouse_rounded,
                                      size: 16,
                                      color: AppTheme.primaryColor,
                                    ),
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
                                      'On Hand: ${_selectedProduct!.quantity} ${_selectedProduct!.unit} • Available: ${_selectedProduct!.availableQuantity}',
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
                                          '${e.value} ${_selectedProduct!.unit}'
                                          '${(_selectedProduct!.heldLocationQuantities[e.key] ?? 0) > 0 ? ' (${_selectedProduct!.availableAtLocation(e.key)} available)' : ''}',
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

                        // Location selector (shown for normal stock out and for
                        // hold despatch, where the user chooses the source).
                        if (_selectedProduct != null &&
                            locationOptions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: GestureDetector(
                              onTap: () async {
                                final result = await showSearchablePicker(
                                  context: context,
                                  title: holdMode
                                      ? 'Despatch From'
                                      : 'Location',
                                  selectedValue: _selectedLocation.isEmpty
                                      ? null
                                      : _selectedLocation,
                                  addNewLabel:
                                      holdMode ? null : 'Add new location',
                                  addNewValue:
                                      holdMode ? null : '__create_new__',
                                  items: locationOptions.map((loc) {
                                    final onHand =
                                        _selectedProduct!
                                            .locationQuantities[loc] ??
                                        0;
                                    final available = _selectedProduct!
                                        .availableAtLocation(loc);
                                    return PickerItem(
                                      value: loc,
                                      label: loc,
                                      subtitle: holdMode
                                          ? '$onHand on hand ${_selectedProduct!.unit}'
                                          : '$available available • $onHand on hand ${_selectedProduct!.unit}',
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
                                  labelText: holdMode
                                      ? 'Despatch From *'
                                      : 'Location *',
                                  prefixIcon: const Icon(
                                    Icons.location_on_rounded,
                                  ),
                                  suffixIcon: _selectedLocation.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () => setState(
                                            () => _selectedLocation = '',
                                          ),
                                        )
                                      : const Icon(Icons.arrow_drop_down),
                                  errorText:
                                      _submitted && _selectedLocation.isEmpty
                                      ? 'Please select a location'
                                      : null,
                                ),
                                child: Text(
                                  _selectedLocation.isEmpty
                                      ? (holdMode
                                          ? 'Select despatch location'
                                          : 'Select location')
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
                            locationOptions.isEmpty)
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
                              _fromHold != null
                                  ? 'Despatching up to $_maxQty of ${_fromHold!.remainingQuantity} held from $_selectedLocation'
                                  : 'Available at $_selectedLocation: $_availableAtLocation ${_selectedProduct?.unit ?? "pcs"}',
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
                            if (qty > _maxQty) {
                              return _fromHold != null
                                  ? 'Exceeds held qty ($_maxQty)'
                                  : 'Exceeds stock at $_selectedLocation ($_maxQty)';
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
                            final vendorProvider = context
                                .watch<VendorProvider>();
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
                                    items: activeVendors
                                        .map(
                                          (v) => PickerItem(
                                            value: v.id,
                                            label: v.name,
                                            icon: Icons.local_shipping_rounded,
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

                        const SizedBox(height: 32),

                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _quantityController,
                          builder: (context, value, _) {
                            final qty = int.tryParse(value.text) ?? 0;
                            final exceedsStock = qty > _maxQty;
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
                                  : Icon(
                                      _fromHold != null
                                          ? Icons.local_shipping_rounded
                                          : Icons.check_rounded,
                                    ),
                              label: Text(
                                _fromHold != null
                                    ? 'Despatch from Hold'
                                    : 'Remove Stock',
                              ),
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
