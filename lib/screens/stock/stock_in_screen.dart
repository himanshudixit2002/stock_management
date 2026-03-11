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
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_overlay.dart';
import '../products/add_edit_product_screen.dart';
import '../settings/settings_screen.dart';

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
  String _productSearch = '';

  bool get _hasUnsavedChanges =>
      _quantityController.text.trim().isNotEmpty ||
      _selectedLocation != null ||
      _reasonController.text.trim().isNotEmpty ||
      (_selectedProduct != null && widget.product == null);

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

  String _locationBreakdown(ProductModel p) {
    final lq = p.locationQuantities;
    if (lq.isEmpty) return 'No stock';
    if (lq.length <= 2) {
      return lq.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    return '${lq.length} locations \u2022 ${p.quantity} total';
  }

  Future<bool> _confirmLargeQuantity(int qty) async {
    if (qty <= 100) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.warningColor,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('Large Quantity'),
          ],
        ),
        content: Text(
          'Are you sure you want to add $qty items? Please confirm this is correct.',
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

  Future<void> _addStock() async {
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

    if (_selectedLocation == null || _selectedLocation!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
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
      context.read<ProductProvider>().refreshProducts();
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
      showSuccessOverlay(context, message: 'Stock added successfully');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<StockProvider>().errorMessage ?? 'Failed to add stock',
          ),
          backgroundColor: AppTheme.dangerColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showProductPicker(List<ProductModel> products) {
    _productSearch = '';
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
                      .where(
                        (p) =>
                            p.name.toLowerCase().contains(
                              _productSearch.toLowerCase(),
                            ) ||
                            p.categoryName.toLowerCase().contains(
                              _productSearch.toLowerCase(),
                            ),
                      )
                      .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.emptyStateIcon,
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
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 48,
                                  color: AppTheme.iconMuted,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No products match your search',
                                  style: TextStyle(
                                    color: AppTheme.textTertiary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              final isSelected = _selectedProduct?.id == p.id;
                              final stockColor = AppTheme.getStockColor(
                                p.quantity,
                                threshold: p.lowStockThreshold,
                              );
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: AppTheme.primaryColor
                                    .withValues(alpha: 0.08),
                                shape: isSelected
                                    ? RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.3),
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedProduct = p;
                                    _productSearch = '';
                                    if (p.preferredVendorId.isNotEmpty) {
                                      _selectedVendorId = p.preferredVendorId;
                                      _selectedVendorName =
                                          p.preferredVendorName;
                                    } else {
                                      _selectedVendorId = '';
                                      _selectedVendorName = '';
                                    }
                                  });
                                  Navigator.pop(context);
                                },
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: stockColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2_rounded,
                                    color: stockColor,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${p.categoryName} \u2022 ${_locationBreakdown(p)}',
                                  style: const TextStyle(fontSize: 12),
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
    if (user != null && !user.hasPermission('canStockIn')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock In')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final products = context.watch<ProductProvider>().allProducts;
    final settingsLocations = context.watch<SettingsProvider>().locations;

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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddEditProductScreen()),
            );
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: AppBarTitleRow(
              icon: Icons.add_circle_rounded,
              color: AppTheme.successColor,
              title: 'Stock In',
            ),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.scaffoldGradient,
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
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.inputBorderColor,
                                  ),
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
                                    const Icon(
                                      Icons.arrow_drop_down_rounded,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Location selector
                          DropdownButtonFormField<String>(
                            initialValue: _selectedLocation,
                            decoration: InputDecoration(
                              labelText: 'Location *',
                              prefixIcon: const Icon(Icons.location_on_rounded),
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
                                  : null,
                            ),
                            hint: const Text('Select location'),
                            items: settingsLocations.map((loc) {
                              final qty =
                                  _selectedProduct?.locationQuantities[loc];
                              return DropdownMenuItem(
                                value: loc,
                                child: Text(
                                  qty != null ? '$loc ($qty in stock)' : loc,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _selectedLocation = value),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please select a location';
                              }
                              return null;
                            },
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
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedVendorId.isEmpty
                                      ? null
                                      : _selectedVendorId,
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
                                    final v = vendorProvider.getVendorById(
                                      value ?? '',
                                    );
                                    setState(() {
                                      _selectedVendorId = value ?? '';
                                      _selectedVendorName = v?.name ?? '';
                                    });
                                  },
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _quantityController,
                            decoration: InputDecoration(
                              labelText: 'Quantity to Add *',
                              prefixIcon: const Icon(Icons.add_rounded),
                              suffixText: _selectedProduct?.unit ?? 'pcs',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
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
                          const SizedBox(height: 32),

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
