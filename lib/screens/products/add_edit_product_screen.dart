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

class AddEditProductScreen extends StatefulWidget {
  final ProductModel? product;

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _lowStockController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  String _selectedUnit = 'pcs';
  String? _selectedVendorId;
  String? _selectedVendorName;
  bool _isLoading = false;
  CategoryModel? _pendingNewCategory;

  bool get isEditing => widget.product != null;

  final List<String> _units = [
    'pcs', 'kg', 'ltr', 'box', 'pack', 'dozen', 'meter', 'set', 'sqft', 'bundle',
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
      _selectedSubcategoryId = p.subcategoryId.isEmpty ? null : p.subcategoryId;
      _selectedUnit = p.unit;
      if (p.costPrice > 0) _costPriceController.text = p.costPrice.toString();
      if (p.sellingPrice > 0) _sellingPriceController.text = p.sellingPrice.toString();
      _selectedVendorId = p.preferredVendorId.isEmpty ? null : p.preferredVendorId;
      _selectedVendorName = p.preferredVendorName.isEmpty ? null : p.preferredVendorName;
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

  void _showSubcategoryPicker(BuildContext context, List<CategoryModel> subcats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _SubcategoryPickerSheet(
          subcats: subcats,
          selectedId: _selectedSubcategoryId,
          categoryId: _selectedCategoryId!,
          onSelected: (id) {
            setState(() => _selectedSubcategoryId = id);
            Navigator.pop(sheetContext);
          },
          onCreated: (newSub) {
            setState(() => _selectedSubcategoryId = newSub.id);
            Navigator.pop(sheetContext);
          },
        );
      },
    );
  }

  Future<bool> _confirmDuplicate(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppTheme.warningColor, size: 24),
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
    final category = categoryProvider.getCategoryById(_selectedCategoryId!) ??
        (_pendingNewCategory?.id == _selectedCategoryId
            ? _pendingNewCategory
            : null);
    final subcategory = _selectedSubcategoryId != null
        ? categoryProvider.getCategoryById(_selectedSubcategoryId!)
        : null;
    final now = DateTime.now();

    final product = ProductModel(
      id: isEditing ? widget.product!.id : '',
      name: _nameController.text.trim(),
      categoryId: _selectedCategoryId!,
      categoryName: category?.name ?? '',
      subcategoryId: subcategory?.id ?? '',
      subcategoryName: subcategory?.name ?? '',
      quantity: isEditing ? widget.product!.quantity : 0,
      unit: _selectedUnit,
      locationQuantities:
          isEditing ? widget.product!.locationQuantities : const {},
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
    final isDuplicate = existingProducts.any((p) =>
        p.name.toLowerCase() == product.name.toLowerCase() &&
        p.id != product.id);
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
          content:
              Text(productProvider.errorMessage ?? 'Something went wrong'),
          backgroundColor: AppTheme.dangerColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
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
              child: Icon(
                isEditing ? Icons.edit_rounded : Icons.add_box_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(isEditing ? 'Edit Product' : 'Add Product'),
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
              _SectionHeader(title: 'Basic Info'),
              const SizedBox(height: 12),

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
                  value: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    prefixIcon: Icon(Icons.category_rounded),
                  ),
                  hint: const Text('Select Category'),
                  items: [
                    ...categoryProvider.topLevelCategories.map((category) {
                      return DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      );
                    }),
                    if (_pendingNewCategory != null &&
                        _pendingNewCategory!.isTopLevel &&
                        !categoryProvider.categories
                            .any((c) => c.id == _pendingNewCategory!.id))
                      DropdownMenuItem(
                        value: _pendingNewCategory!.id,
                        child: Text(_pendingNewCategory!.name),
                      ),
                    const DropdownMenuItem(
                      value: '__create_new__',
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Create new category...'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == '__create_new__') {
                      final newCategory = await _showCreateCategoryDialog(
                        context,
                        categoryProvider,
                      );
                      if (newCategory != null && mounted) {
                        setState(() {
                          _selectedCategoryId = newCategory.id;
                          _pendingNewCategory = newCategory;
                          _selectedSubcategoryId = null;
                        });
                      } else {
                        setState(() {
                          _selectedCategoryId = null;
                          _pendingNewCategory = null;
                          _selectedSubcategoryId = null;
                        });
                      }
                    } else {
                      setState(() {
                        _selectedCategoryId = value;
                        _pendingNewCategory = null;
                        _selectedSubcategoryId = null;
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

              if (_selectedCategoryId != null &&
                  _selectedCategoryId != '__create_new__') ...[
                Builder(builder: (context) {
                  final subcats = categoryProvider.getSubcategoriesOf(_selectedCategoryId!);
                  final isAdmin = context.read<AuthProvider>().isAdmin;
                  if (subcats.isEmpty && !isAdmin) return const SizedBox.shrink();
                  final selectedSub = _selectedSubcategoryId != null
                      ? categoryProvider.getCategoryById(_selectedSubcategoryId!)
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: GestureDetector(
                      onTap: () => _showSubcategoryPicker(context, subcats),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Subcategory (optional)',
                          prefixIcon: Icon(Icons.subdirectory_arrow_right_rounded),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: selectedSub != null
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Text(selectedSub.name,
                                        style: const TextStyle(fontSize: 15)),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedSubcategoryId = null),
                                    child: Icon(Icons.close_rounded, size: 18, color: Colors.grey[500]),
                                  ),
                                ],
                              )
                            : Text('Select Subcategory',
                                style: TextStyle(color: Colors.grey[600], fontSize: 15)),
                      ),
                    ),
                  );
                }),
              ],

              CustomTextField(
                controller: _descriptionController,
                label: 'Description',
                hint: 'Optional product description',
                prefixIcon: Icons.description_rounded,
                maxLines: 2,
              ),

              const SizedBox(height: 8),
              _SectionHeader(title: 'Stock Settings'),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        value: _selectedUnit,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          prefixIcon: Icon(Icons.straighten_rounded),
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
                          if (threshold == null || threshold < 0) {
                            return 'Invalid';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  if (!settings.pricingEnabled) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _SectionHeader(title: 'Pricing'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _costPriceController,
                              label: 'Cost Price',
                              hint: '0.00',
                              prefixIcon: Icons.money_rounded,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _sellingPriceController,
                              label: 'Selling Price',
                              hint: '0.00',
                              prefixIcon: Icons.sell_rounded,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  if (!settings.vendorsEnabled) return const SizedBox.shrink();
                  final vendorProvider = context.watch<VendorProvider>();
                  final activeVendors = vendorProvider.activeVendors;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _SectionHeader(title: 'Vendor'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedVendorId,
                        decoration: InputDecoration(
                          labelText: 'Preferred Vendor',
                          prefixIcon: const Icon(Icons.local_shipping_rounded),
                          suffixIcon: _selectedVendorId != null
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
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
                          final v = vendorProvider.getVendorById(value ?? '');
                          setState(() {
                            _selectedVendorId = value;
                            _selectedVendorName = v?.name;
                          });
                        },
                      ),
                    ],
                  );
                },
              ),

              if (isEditing && widget.product!.locationQuantities.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionHeader(title: 'Stock by Location'),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.inputFillColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      ...widget.product!.locationQuantities.entries.map((e) {
                        final isLast = e.key == widget.product!.locationQuantities.keys.last;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: isLast ? null : Border(
                              bottom: BorderSide(color: AppTheme.dividerColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 16, color: AppTheme.primaryColor),
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
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(14)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    : Icon(isEditing ? Icons.save_rounded : Icons.add_rounded),
                label: Text(isEditing ? 'Update Product' : 'Add Product'),
              ),

              const SizedBox(height: 20),
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

class _SubcategoryPickerSheet extends StatefulWidget {
  final List<CategoryModel> subcats;
  final String? selectedId;
  final String categoryId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<CategoryModel> onCreated;

  const _SubcategoryPickerSheet({
    required this.subcats,
    required this.selectedId,
    required this.categoryId,
    required this.onSelected,
    required this.onCreated,
  });

  @override
  State<_SubcategoryPickerSheet> createState() => _SubcategoryPickerSheetState();
}

class _SubcategoryPickerSheetState extends State<_SubcategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.subcats
        : widget.subcats.where((s) =>
            s.name.toLowerCase().contains(_query.toLowerCase())).toList();
    final isAdmin = context.read<AuthProvider>().isAdmin;
    final parentCategory = context.read<CategoryProvider>().getCategoryById(widget.categoryId);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 20, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text('Select Subcategory',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text('${widget.subcats.length} items',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: widget.subcats.length > 8,
                decoration: InputDecoration(
                  hintText: 'Search subcategories...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.inputBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.inputBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primaryColor),
                  ),
                  filled: true,
                  fillColor: AppTheme.inputFillColor,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _PickerTile(
                    title: 'None',
                    isSelected: widget.selectedId == null,
                    icon: Icons.remove_circle_outline,
                    onTap: () => widget.onSelected(null),
                  ),
                  if (filtered.isEmpty && _query.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No match for "$_query"',
                            style: TextStyle(color: Colors.grey[500])),
                      ),
                    )
                  else
                    ...filtered.map((sub) => _PickerTile(
                      title: sub.name,
                      subtitle: sub.description.isNotEmpty ? sub.description : null,
                      isSelected: widget.selectedId == sub.id,
                      icon: Icons.label_outline_rounded,
                      onTap: () => widget.onSelected(sub.id),
                    )),
                  if (isAdmin && parentCategory != null) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: AppTheme.primaryColor, size: 18),
                      ),
                      title: const Text('Add New Subcategory',
                          style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      onTap: () => _showQuickAddSubcategory(context, parentCategory),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickAddSubcategory(BuildContext context, CategoryModel parent) async {
    final nameController = TextEditingController(text: _query);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<CategoryModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Subcategory'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text('Under: ${parent.name}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Subcategory Name *',
                  prefixIcon: Icon(Icons.label_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final user = ctx.read<AuthProvider>().currentUser;
              final catProvider = ctx.read<CategoryProvider>();
              final newSub = await catProvider.addCategory(
                nameController.text.trim(),
                userId: user?.uid ?? '',
                userName: user?.name ?? '',
                parentId: parent.id,
                parentName: parent.name,
              );
              if (newSub != null && ctx.mounted) {
                Navigator.pop(ctx, newSub);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      widget.onCreated(result);
    }
  }
}

class _PickerTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerTile({
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20,
          color: isSelected ? AppTheme.primaryColor : Colors.grey[500]),
      title: Text(title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
          )),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 11))
          : null,
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: AppTheme.primaryColor, size: 20)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: onTap,
      dense: true,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
