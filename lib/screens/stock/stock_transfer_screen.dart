import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_overlay.dart';
import '../products/add_edit_product_screen.dart';

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
  String _productSearch = '';

  bool get _hasUnsavedChanges =>
      _quantityController.text.trim().isNotEmpty ||
      _toLocation != null ||
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

  String _locationBreakdown(ProductModel p) {
    final lq = p.locationQuantities;
    if (lq.isEmpty) return 'No stock';
    if (lq.length <= 2) {
      return lq.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    return '${lq.length} locations \u2022 ${p.quantity} total';
  }

  Future<bool> _confirmTransfer(int qty) async {
    final toLocation = _toLocation!;
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
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Confirm Transfer'),
          ],
        ),
        content: Text(
          'Transfer $qty ${_selectedProduct?.unit ?? "pcs"} of "${_selectedProduct?.name}"\n\n'
          'From: $_fromLocation\nTo: $toLocation',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _transfer() async {
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
    if (_fromLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select source location'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_toLocation == null || _toLocation!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select destination location'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final toLocation = _toLocation!;
    if (toLocation == _fromLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source and destination must be different'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<StockProvider>().errorMessage ??
                'Failed to transfer stock',
          ),
          backgroundColor: AppTheme.dangerColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showProductPicker(List<ProductModel> products) {
    _productSearch = '';
    final multiLocationProducts = products
        .where((p) => p.locationQuantities.entries.any((e) => e.value > 0))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _productSearch.isEmpty
                ? multiLocationProducts
                : multiLocationProducts
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
                                  'No products with stock found',
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
                                    _fromLocation = '';
                                    _toLocation = null;
                                    _productSearch = '';
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
    if (user != null && !user.hasPermission('canTransfer')) {
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddEditProductScreen()),
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
              icon: Icons.swap_horiz_rounded,
              color: AppTheme.indigoColor,
              title: 'Transfer Stock',
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

                          // From location
                          if (_selectedProduct != null &&
                              productLocations.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: DropdownButtonFormField<String>(
                                initialValue: _fromLocation.isEmpty
                                    ? null
                                    : _fromLocation,
                                decoration: const InputDecoration(
                                  labelText: 'From Location *',
                                  prefixIcon: Icon(Icons.location_on_rounded),
                                ),
                                hint: const Text('Select source'),
                                items: productLocations.map((e) {
                                  return DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      '${e.key} (${e.value} ${_selectedProduct!.unit})',
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _fromLocation = value ?? '';
                                  });
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please select source location';
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

                          // To location
                          if (_fromLocation.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: DropdownButtonFormField<String>(
                                initialValue: _toLocation,
                                decoration: InputDecoration(
                                  labelText: 'To Location *',
                                  prefixIcon: const Icon(
                                    Icons.location_on_outlined,
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
                                      : null,
                                ),
                                hint: const Text('Select destination'),
                                items: settingsLocations
                                    .where((l) => l != _fromLocation)
                                    .map((loc) {
                                      return DropdownMenuItem(
                                        value: loc,
                                        child: Text(loc),
                                      );
                                    })
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _toLocation = value),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please select destination location';
                                  }
                                  if (value == _fromLocation) {
                                    return 'Must be different from source';
                                  }
                                  return null;
                                },
                              ),
                            ),

                          if (_fromLocation.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Available at $_fromLocation: $_availableAtFrom ${_selectedProduct?.unit ?? "pcs"}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                          if (_fromLocation.isNotEmpty)
                            TextFormField(
                              controller: _quantityController,
                              decoration: InputDecoration(
                                labelText: 'Quantity to Transfer *',
                                prefixIcon: const Icon(
                                  Icons.swap_horiz_rounded,
                                ),
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
