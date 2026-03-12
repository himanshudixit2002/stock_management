import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/success_overlay.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';

class AddEditProductScreen extends StatefulWidget {
  final ProductModel? product;

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  var _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _lowStockController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedCompany;
  String? _selectedSize;
  String _selectedUnit = 'pcs';
  String? _selectedVendorId;
  String? _selectedVendorName;
  bool _isLoading = false;
  CategoryModel? _pendingNewCategory;

  bool get isEditing => widget.product != null;

  bool get _hasUnsavedChanges {
    if (isEditing) {
      final p = widget.product!;
      final origCost = p.costPrice > 0 ? p.costPrice.toString() : '';
      final origSelling = p.sellingPrice > 0 ? p.sellingPrice.toString() : '';
      final origVendor = p.preferredVendorId.isEmpty
          ? null
          : p.preferredVendorId;
      return _nameController.text.trim() != p.name ||
          _descriptionController.text.trim() != p.description ||
          _selectedCategoryId != (p.categoryId.isEmpty ? null : p.categoryId) ||
          _selectedCompany != (p.company.isEmpty ? null : p.company) ||
          _selectedSize != (p.size.isEmpty ? null : p.size) ||
          _selectedUnit != p.unit ||
          _lowStockController.text.trim() != p.lowStockThreshold.toString() ||
          _costPriceController.text.trim() != origCost ||
          _sellingPriceController.text.trim() != origSelling ||
          _selectedVendorId != origVendor;
    }
    return _nameController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _selectedCategoryId != null ||
        _selectedCompany != null ||
        _selectedSize != null ||
        _costPriceController.text.trim().isNotEmpty ||
        _sellingPriceController.text.trim().isNotEmpty ||
        _selectedVendorId != null;
  }

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

  final List<String> _units = [
    'pcs',
    'kg',
    'ltr',
    'box',
    'pack',
    'dozen',
    'meter',
    'set',
    'sqft',
    'bundle',
  ];

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final p = widget.product!;
      _nameController.text = p.name;
      _descriptionController.text = p.description;
      _lowStockController.text = p.lowStockThreshold.toString();
      _selectedCategoryId = p.categoryId.isEmpty ? null : p.categoryId;
      _selectedCompany = p.company.isEmpty ? null : p.company;
      _selectedSize = p.size.isEmpty ? null : p.size;
      _selectedUnit = p.unit;
      if (p.costPrice > 0) _costPriceController.text = p.costPrice.toString();
      if (p.sellingPrice > 0) {
        _sellingPriceController.text = p.sellingPrice.toString();
      }
      _selectedVendorId = p.preferredVendorId.isEmpty
          ? null
          : p.preferredVendorId;
      _selectedVendorName = p.preferredVendorName.isEmpty
          ? null
          : p.preferredVendorName;
    } else {
      _lowStockController.text = '10';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _lowStockController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
  }

  Future<CategoryModel?> _showCreateCategoryDialog(
    BuildContext context,
    CategoryProvider categoryProvider,
  ) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<CategoryModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name *',
                  prefixIcon: Icon(Icons.category),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter category name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final user = context.read<AuthProvider>().currentUser;
              final newCategory = await categoryProvider.addCategory(
                nameController.text.trim(),
                description: descController.text.trim(),
                userId: user?.uid ?? '',
                userName: user?.name ?? '',
              );

              if (newCategory != null && context.mounted) {
                Navigator.pop(context, newCategory);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDuplicate(String name) async {
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
            const Text('Duplicate Name'),
          ],
        ),
        content: Text(
          'A product named "$name" already exists. Do you want to add it anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _saveProduct() async {
    if (_isLoading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
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

    final categoryProvider = context.read<CategoryProvider>();
    final category =
        categoryProvider.getCategoryById(_selectedCategoryId!) ??
        (_pendingNewCategory?.id == _selectedCategoryId
            ? _pendingNewCategory
            : null);
    final now = DateTime.now();

    final product = ProductModel(
      id: isEditing ? widget.product!.id : '',
      name: _nameController.text.trim(),
      categoryId: _selectedCategoryId!,
      categoryName: category?.name ?? '',
      company: _selectedCompany ?? '',
      size: _selectedSize ?? '',
      quantity: isEditing ? widget.product!.quantity : 0,
      unit: _selectedUnit,
      locationQuantities: isEditing
          ? widget.product!.locationQuantities
          : const {},
      description: _descriptionController.text.trim(),
      lowStockThreshold: int.tryParse(_lowStockController.text) ?? 10,
      costPrice: double.tryParse(_costPriceController.text) ?? 0,
      sellingPrice: double.tryParse(_sellingPriceController.text) ?? 0,
      createdAt: isEditing ? widget.product!.createdAt : now,
      updatedAt: now,
      createdBy: isEditing ? widget.product!.createdBy : user.uid,
      createdByName: isEditing ? widget.product!.createdByName : user.name,
      updatedBy: user.uid,
      updatedByName: user.name,
      preferredVendorId: _selectedVendorId ?? '',
      preferredVendorName: _selectedVendorName ?? '',
      lastVendorId: isEditing ? widget.product!.lastVendorId : '',
      lastVendorName: isEditing ? widget.product!.lastVendorName : '',
      vendorPrices: isEditing ? widget.product!.vendorPrices : const {},
    );

    final productProvider = context.read<ProductProvider>();
    final existingProducts = productProvider.allProducts;
    final isDuplicate = existingProducts.any(
      (p) =>
          p.name.toLowerCase() == product.name.toLowerCase() &&
          p.id != product.id,
    );
    if (isDuplicate && !await _confirmDuplicate(product.name)) return;

    setState(() => _isLoading = true);

    bool success;
    if (isEditing) {
      success = await productProvider.updateProduct(product);
    } else {
      success = await productProvider.addProduct(product);
    }

    setState(() => _isLoading = false);

    if (success && mounted) {
      HapticFeedback.lightImpact();
      showSuccessOverlay(
        context,
        message: isEditing ? 'Product updated!' : 'Product added!',
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(productProvider.errorMessage ?? 'Something went wrong'),
          backgroundColor: AppTheme.dangerColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

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
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Product' : 'Add Product'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.formMaxWidth(context),
              ),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassSectionCard(
                        title: 'Basic Info',
                        icon: Icons.inventory_2_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CustomTextField(
                              controller: _nameController,
                              label: 'Product Name *',
                              hint: 'e.g., Ceramic Floor Tile 2x2',
                              prefixIcon: Icons.inventory_2_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter product name';
                                }
                                if (value.trim().length < 2) {
                                  return 'Name must be at least 2 characters';
                                }
                                if (value.trim().length > 100) {
                                  return 'Name must be under 100 characters';
                                }
                                return null;
                              },
                            ),

                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedCategoryId,
                                decoration: const InputDecoration(
                                  labelText: 'Category *',
                                  prefixIcon: Icon(Icons.category_rounded),
                                ),
                                hint: const Text('Select Category'),
                                items: [
                                  ...categoryProvider.categories.map((
                                    category,
                                  ) {
                                    return DropdownMenuItem(
                                      value: category.id,
                                      child: Text(category.name),
                                    );
                                  }),
                                  if (_pendingNewCategory != null &&
                                      !categoryProvider.categories.any(
                                        (c) => c.id == _pendingNewCategory!.id,
                                      ))
                                    DropdownMenuItem(
                                      value: _pendingNewCategory!.id,
                                      child: Text(_pendingNewCategory!.name),
                                    ),
                                  const DropdownMenuItem(
                                    value: '__create_new__',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Create new category...'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == '__create_new__') {
                                    final newCategory =
                                        await _showCreateCategoryDialog(
                                          context,
                                          categoryProvider,
                                        );
                                    if (newCategory != null && mounted) {
                                      setState(() {
                                        _selectedCategoryId = newCategory.id;
                                        _pendingNewCategory = newCategory;
                                      });
                                    } else {
                                      setState(() {
                                        _selectedCategoryId = null;
                                        _pendingNewCategory = null;
                                      });
                                    }
                                  } else {
                                    setState(() {
                                      _selectedCategoryId = value;
                                      _pendingNewCategory = null;
                                    });
                                  }
                                },
                                validator: (value) {
                                  if (value == null ||
                                      value.isEmpty ||
                                      value == '__create_new__') {
                                    return 'Please select a category';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            // Company dropdown
                            if (settingsProvider.companies.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedCompany,
                                  decoration: InputDecoration(
                                    labelText: 'Company / Brand',
                                    prefixIcon: const Icon(
                                      Icons.business_rounded,
                                    ),
                                    suffixIcon: _selectedCompany != null
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _selectedCompany = null,
                                            ),
                                          )
                                        : null,
                                  ),
                                  hint: const Text('Select Company'),
                                  items: settingsProvider.companies.map((c) {
                                    return DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    );
                                  }).toList(),
                                  onChanged: (value) =>
                                      setState(() => _selectedCompany = value),
                                ),
                              ),

                            // Size dropdown
                            if (settingsProvider.sizes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedSize,
                                  decoration: InputDecoration(
                                    labelText: 'Size',
                                    prefixIcon: const Icon(
                                      Icons.straighten_rounded,
                                    ),
                                    suffixIcon: _selectedSize != null
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _selectedSize = null,
                                            ),
                                          )
                                        : null,
                                  ),
                                  hint: const Text('Select Size'),
                                  items: settingsProvider.sizes.map((s) {
                                    return DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    );
                                  }).toList(),
                                  onChanged: (value) =>
                                      setState(() => _selectedSize = value),
                                ),
                              ),

                            CustomTextField(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'Optional product description',
                              prefixIcon: Icons.description_rounded,
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GlassSectionCard(
                        title: 'Stock Settings',
                        icon: Icons.settings_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedUnit,
                                      decoration: const InputDecoration(
                                        labelText: 'Unit',
                                        prefixIcon: Icon(
                                          Icons.straighten_rounded,
                                        ),
                                      ),
                                      items: _units.map((unit) {
                                        return DropdownMenuItem(
                                          value: unit,
                                          child: Text(unit),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedUnit = value ?? 'pcs';
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CustomTextField(
                                    controller: _lowStockController,
                                    label: 'Low Stock Alert',
                                    hint: '10',
                                    helperText: 'Alert threshold',
                                    prefixIcon: Icons.warning_amber_rounded,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: (value) {
                                      if (value != null && value.isNotEmpty) {
                                        final threshold = int.tryParse(value);
                                        if (threshold == null ||
                                            threshold < 0) {
                                          return 'Invalid';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          if (!settings.pricingEnabled) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 16),
                              GlassSectionCard(
                                title: 'Pricing',
                                icon: Icons.money_rounded,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: CustomTextField(
                                        controller: _costPriceController,
                                        label: 'Cost Price',
                                        hint: '0.00',
                                        prefixIcon: Icons.money_rounded,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                        validator: (v) {
                                          if (v != null && v.isNotEmpty) {
                                            final val = double.tryParse(v);
                                            if (val != null && val < 0) {
                                              return 'Price cannot be negative';
                                            }
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: CustomTextField(
                                        controller: _sellingPriceController,
                                        label: 'Selling Price',
                                        hint: '0.00',
                                        prefixIcon: Icons.sell_rounded,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                        validator: (v) {
                                          if (v != null && v.isNotEmpty) {
                                            final val = double.tryParse(v);
                                            if (val != null && val < 0) {
                                              return 'Price cannot be negative';
                                            }
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      Consumer<SettingsProvider>(
                        builder: (context, settings, _) {
                          if (!settings.vendorsEnabled) {
                            return const SizedBox.shrink();
                          }
                          final vendorProvider = context
                              .watch<VendorProvider>();
                          final activeVendors = vendorProvider.activeVendors;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 16),
                              GlassSectionCard(
                                title: 'Vendor',
                                icon: Icons.local_shipping_rounded,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedVendorId,
                                  decoration: InputDecoration(
                                    labelText: 'Preferred Vendor',
                                    prefixIcon: const Icon(
                                      Icons.local_shipping_rounded,
                                    ),
                                    suffixIcon: _selectedVendorId != null
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(() {
                                              _selectedVendorId = null;
                                              _selectedVendorName = null;
                                            }),
                                          )
                                        : null,
                                  ),
                                  hint: const Text('Select preferred vendor'),
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
                                      _selectedVendorId = value;
                                      _selectedVendorName = v?.name;
                                    });
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      if (isEditing &&
                          widget.product!.locationQuantities.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        GlassSectionCard(
                          title: 'Stock by Location',
                          icon: Icons.location_on_rounded,
                          child: Column(
                            children: [
                              ...widget.product!.locationQuantities.entries.map((
                                e,
                              ) {
                                final isLast =
                                    e.key ==
                                    widget
                                        .product!
                                        .locationQuantities
                                        .keys
                                        .last;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: isLast
                                        ? null
                                        : Border(
                                            bottom: BorderSide(
                                              color: AppTheme.dividerColor,
                                            ),
                                          ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 16,
                                        color: AppTheme.primaryColor,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          e.key,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '${e.value} ${widget.product!.unit}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.05,
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${widget.product!.quantity} ${widget.product!.unit}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (!isEditing)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Stock quantity and locations are managed via Stock In operations after creating the product.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),

                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveProduct,
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
                                isEditing
                                    ? Icons.save_rounded
                                    : Icons.add_rounded,
                              ),
                        label: Text(
                          isEditing ? 'Update Product' : 'Add Product',
                        ),
                      ),

                      const SizedBox(height: 20),
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
