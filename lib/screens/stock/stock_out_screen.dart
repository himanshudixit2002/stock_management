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
import '../../utils/responsive.dart';
import '../../widgets/success_overlay.dart';

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
  String _productSearch = '';

  bool get _hasUnsavedChanges =>
      _quantityController.text.trim().isNotEmpty ||
      _locationController.text.trim().isNotEmpty ||
      _reasonController.text.trim().isNotEmpty ||
      (_selectedProduct != null && widget.product == null);

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Are you sure you want to go back?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
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

  String _locationBreakdown(ProductModel p) {
    final lq = p.locationQuantities;
    if (lq.isEmpty) return 'No stock';
    if (lq.length <= 2) {
      return lq.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    return '${lq.length} locations \u2022 ${p.quantity} total';
  }

  Future<bool> _confirmStockOut(int qty) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.outbox_rounded,
                  color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Confirm Stock Out'),
          ],
        ),
        content: Text(
          'Remove $qty ${_selectedProduct?.unit ?? "pcs"} of "${_selectedProduct?.name}" from $_selectedLocation?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmLargeQuantity(int qty) async {
    if (qty <= 100) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppTheme.warningColor, size: 24),
            const SizedBox(width: 8),
            const Text('Large Quantity'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove $qty items? Please confirm this is correct.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _removeStock() async {
    if (_isLoading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    if (_selectedLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please log in again.'),
            backgroundColor: AppTheme.dangerColor,
            duration: Duration(seconds: 4),
          ),
        );
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
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Stock removed successfully');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<StockProvider>().errorMessage ??
              'Failed to remove stock'),
          backgroundColor: AppTheme.dangerColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showProductPicker(List<ProductModel> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _productSearch.isEmpty
                ? products
                : products
                    .where((p) =>
                        p.name.toLowerCase().contains(
                            _productSearch.toLowerCase()) ||
                        p.categoryName.toLowerCase().contains(
                            _productSearch.toLowerCase()))
                    .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) {
                        setModalState(() => _productSearch = v);
                      },
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 48,
                                    color: Colors.grey[350]),
                                const SizedBox(height: 8),
                                Text(
                                  'No products match your search',
                                  style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              final isSelected = _selectedProduct?.id == p.id;
                              final stockColor =
                                  AppTheme.getStockColor(p.quantity,
                                      threshold:
                                          p.lowStockThreshold);
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                                shape: isSelected ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                                ) : null,
                                onTap: () {
                                  final locs = p.locationQuantities.entries
                                      .where((e) => e.value > 0)
                                      .toList();
                                  setState(() {
                                    _selectedProduct = p;
                                    _selectedLocation = locs.length == 1 ? locs.first.key : '';
                                    _locationController.clear();
                                    _productSearch = '';
                                  });
                                  Navigator.pop(context);
                                },
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: stockColor
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                      Icons.inventory_2_rounded,
                                      color: stockColor,
                                      size: 20),
                                ),
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${p.categoryName} \u2022 ${_locationBreakdown(p)}',
                                  style:
                                      const TextStyle(fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  '${p.quantity} ${p.unit}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: stockColor,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission('canStockOut')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock Out')),
        body: const Center(child: Text('You do not have permission to access this feature.')),
      );
    }

    final products = context.watch<ProductProvider>().allProducts;

    final productLocations = _selectedProduct?.locationQuantities.entries
            .where((e) => e.value > 0)
            .map((e) => e.key)
            .toList() ??
        [];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) Navigator.of(context).pop();
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
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.remove_circle_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Stock Out'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
        child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Form(
          key: _formKey,
          autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Product *',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: AppTheme.inputFillColor,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => _showProductPicker(products),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.inputBorderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2_rounded,
                          color: _selectedProduct != null
                              ? AppTheme.primaryColor
                              : AppTheme.textSecondary,
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
                              : const Text(
                                  'Tap to select a product...',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded,
                            color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Location selector - only product's existing locations
              if (_selectedProduct != null && productLocations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: DropdownButtonFormField<String>(
                    value: _selectedLocation.isEmpty
                        ? null
                        : _selectedLocation,
                    decoration: const InputDecoration(
                      labelText: 'Location *',
                      prefixIcon: Icon(Icons.location_on_rounded),
                    ),
                    hint: const Text('Select location'),
                    items: productLocations.map((loc) {
                      final qty =
                          _selectedProduct!.locationQuantities[loc] ??
                              0;
                      return DropdownMenuItem(
                        value: loc,
                        child: Text(
                            '$loc ($qty ${_selectedProduct!.unit})'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedLocation = value ?? '';
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a location';
                      }
                      return null;
                    },
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
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              TextFormField(
                controller: _quantityController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Quantity to Remove *',
                  prefixIcon: const Icon(Icons.remove_rounded),
                  suffixText: _selectedProduct?.unit ?? 'pcs',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
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
                  if (!settings.vendorsEnabled) return const SizedBox.shrink();
                  final vendorProvider = context.watch<VendorProvider>();
                  final activeVendors = vendorProvider.activeVendors;
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DropdownButtonFormField<String>(
                      value: _selectedVendorId.isEmpty ? null : _selectedVendorId,
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
                            : null,
                      ),
                      hint: const Text('Select vendor'),
                      items: activeVendors.map((v) {
                        return DropdownMenuItem(
                          value: v.id,
                          child: Text(v.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        final v = vendorProvider.getVendorById(value ?? '');
                        setState(() {
                          _selectedVendorId = value ?? '';
                          _selectedVendorName = v?.name ?? '';
                        });
                      },
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
                                color: Colors.white),
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
    );
  }
}
