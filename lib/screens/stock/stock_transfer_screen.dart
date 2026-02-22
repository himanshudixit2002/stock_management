import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/success_overlay.dart';

class StockTransferScreen extends StatefulWidget {
  final ProductModel? product;

  const StockTransferScreen({super.key, this.product});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _toLocationController = TextEditingController();

  ProductModel? _selectedProduct;
  String _fromLocation = '';
  bool _isLoading = false;
  String _productSearch = '';

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
    _toLocationController.dispose();
    super.dispose();
  }

  String _normalizeLocation(String raw) {
    return raw
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
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
    final toLocation = _normalizeLocation(_toLocationController.text.trim());
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
              child: const Icon(Icons.swap_horiz_rounded,
                  color: AppTheme.primaryColor, size: 20),
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

    final rawTo = _toLocationController.text.trim();
    if (rawTo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter destination location'),
          backgroundColor: AppTheme.dangerColor,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final toLocation = _normalizeLocation(rawTo);
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
      HapticFeedback.mediumImpact();
      showSuccessOverlay(context, message: 'Stock transferred successfully');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<StockProvider>().errorMessage ??
              'Failed to transfer stock'),
          backgroundColor: AppTheme.dangerColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showProductPicker(List<ProductModel> products) {
    final multiLocationProducts =
        products.where((p) => p.locationQuantities.isNotEmpty).toList();

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
                    .where((p) =>
                        p.name
                            .toLowerCase()
                            .contains(_productSearch.toLowerCase()) ||
                        p.categoryName
                            .toLowerCase()
                            .contains(_productSearch.toLowerCase()))
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
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 48, color: Colors.grey[350]),
                                const SizedBox(height: 8),
                                Text(
                                  'No products with stock found',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              final stockColor = AppTheme.getStockColor(
                                  p.quantity,
                                  threshold: p.lowStockThreshold);
                              return ListTile(
                                onTap: () {
                                  setState(() {
                                    _selectedProduct = p;
                                    _fromLocation = '';
                                    _toLocationController.clear();
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
    final products = context.watch<ProductProvider>().allProducts;
    final availableLocations =
        context.watch<ProductProvider>().availableLocations;

    final productLocations = _selectedProduct?.locationQuantities.entries
            .where((e) => e.value > 0)
            .toList() ??
        [];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF6366F1), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Transfer Stock'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
        child: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
                      border:
                          Border.all(color: AppTheme.inputBorderColor),
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

              // From location
              if (_selectedProduct != null && productLocations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<String>(
                    value: _fromLocation.isEmpty ? null : _fromLocation,
                    decoration: const InputDecoration(
                      labelText: 'From Location *',
                      prefixIcon: Icon(Icons.location_on_rounded),
                    ),
                    hint: const Text('Select source'),
                    items: productLocations.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Text(
                            '${e.key} (${e.value} ${_selectedProduct!.unit})'),
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

              if (_selectedProduct != null && productLocations.isEmpty)
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

              // To location (autocomplete)
              if (_fromLocation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      final otherLocs = availableLocations
                          .where((l) => l != _fromLocation)
                          .toList();
                      if (textEditingValue.text.isEmpty) {
                        return otherLocs;
                      }
                      final query = textEditingValue.text.toLowerCase();
                      return otherLocs
                          .where((l) => l.toLowerCase().contains(query));
                    },
                    onSelected: (selection) {
                      _toLocationController.text = selection;
                    },
                    fieldViewBuilder: (context, textController, focusNode,
                        onFieldSubmitted) {
                      textController.addListener(() {
                        _toLocationController.text = textController.text;
                      });
                      return TextFormField(
                        controller: textController,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'To Location *',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          helperText: 'Select existing or type new location',
                          helperMaxLines: 2,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter destination location';
                          }
                          final normalized = _normalizeLocation(value.trim());
                          if (normalized == _fromLocation) {
                            return 'Must be different from source';
                          }
                          return null;
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                      Icons.location_on_outlined,
                                      size: 18),
                                  title: Text(option),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
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
                    prefixIcon: const Icon(Icons.swap_horiz_rounded),
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
                                  color: Colors.white),
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
    );
  }
}
