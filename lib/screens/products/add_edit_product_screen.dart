import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/searchable_picker.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/app_navigation.dart';

class AddEditProductScreen extends StatefulWidget {
  final ProductModel? product;

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  var _formKey = GlobalKey<FormState>();
  final _nameFormKey = GlobalKey<FormFieldState>();
  final _categoryFormKey = GlobalKey<FormFieldState>();
  final _lowStockFormKey = GlobalKey<FormFieldState>();
  final _costPriceFormKey = GlobalKey<FormFieldState>();
  final _sellingPriceFormKey = GlobalKey<FormFieldState>();
  bool _submitted = false;
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
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

  bool get hasTemplate => widget.product != null;
  bool get isEditing => hasTemplate && (widget.product!.id.isNotEmpty);

  bool get _hasUnsavedChanges {
    if (isEditing) {
      final p = widget.product!;
      final origCost = p.costPrice > 0 ? p.costPrice.toString() : '';
      final origSelling = p.sellingPrice > 0 ? p.sellingPrice.toString() : '';
      final origVendor = p.preferredVendorId.isEmpty
          ? null
          : p.preferredVendorId;
      return _nameController.text.trim() != p.name ||
          _barcodeController.text.trim() != p.barcode ||
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
        _barcodeController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _selectedCategoryId != null ||
        _selectedCompany != null ||
        _selectedSize != null ||
        _costPriceController.text.trim().isNotEmpty ||
        _sellingPriceController.text.trim().isNotEmpty ||
        _selectedVendorId != null;
  }

  Future<void> _openBarcodeCapture() async {
    final code = await context.pushAppRoute<String?>(
      AppRoutes.barcodeScanner,
      extra: const BarcodeScannerArgs(captureOnly: true),
    );
    if (!mounted) return;
    if (code != null && code.isNotEmpty) {
      setState(() => _barcodeController.text = code);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Are you sure you want to go back?',
      confirmLabel: 'Discard',
    );
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
    if (hasTemplate) {
      final p = widget.product!;
      _nameController.text = p.name;
      _barcodeController.text = isEditing ? p.barcode : '';
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
      _barcodeController.text = _generateBarcode();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _lowStockController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
  }

  String _generateBarcode() {
    final rng = Random();
    final now = DateTime.now();
    final base = '${now.millisecondsSinceEpoch}'.substring(1, 13);
    final digits = base.split('').map((c) => int.parse(c)).toList();
    // Replace last digit with a random one for uniqueness across fast calls
    digits[11] = rng.nextInt(10);
    // EAN-13 check digit
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      sum += digits[i] * (i.isEven ? 1 : 3);
    }
    final check = (10 - (sum % 10)) % 10;
    return '${digits.join()}$check';
  }

  Future<String?> _showAddSizeDialog(
    BuildContext context,
    SettingsProvider settingsProvider,
  ) async {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Add new sub-category'),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Sub-category name',
                  hintText: 'e.g. Small, Medium, Type A',
                  errorText: errorText,
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (errorText != null) setDialogState(() => errorText = null);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setDialogState(() => errorText = 'Enter a name');
                    return;
                  }
                  final ok = await settingsProvider.addSize(name);
                  if (!ctx.mounted) return;
                  if (ok) {
                    Navigator.pop(ctx, name);
                  } else {
                    setDialogState(() => errorText = 'Already exists');
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
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
    return showConfirmDialog(
      context,
      title: 'Duplicate Name',
      message:
          'A product named "$name" already exists. Do you want to add it anyway?',
      confirmLabel: 'Add Anyway',
      iconColor: AppTheme.warningColor,
    );
  }

  void _showCreateCompanyDialog(SettingsProvider settingsProvider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Company / Brand'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter company name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) async {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            final ok = await settingsProvider.addCompany(name);
            if (ok && mounted) {
              setState(() => _selectedCompany = name);
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final ok = await settingsProvider.addCompany(name);
              if (ok && mounted) {
                setState(() => _selectedCompany = name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _scrollFirstInvalidFieldIntoView() {
    final pricing = context.read<SettingsProvider>().pricingEnabled;
    final keys = <GlobalKey<FormFieldState>>[
      _nameFormKey,
      _categoryFormKey,
      _lowStockFormKey,
    ];
    if (pricing) {
      keys.add(_costPriceFormKey);
      keys.add(_sellingPriceFormKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final k in keys) {
        if (k.currentState?.hasError == true) {
          final ctx = k.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: 0.12,
            );
          }
          break;
        }
      }
    });
  }

  Future<void> _saveProduct() async {
    if (_isLoading) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) {
      _scrollFirstInvalidFieldIntoView();
      return;
    }
    if (_selectedCategoryId == null) {
      _scrollFirstInvalidFieldIntoView();
      showErrorSnackBar(context, 'Please select a category');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      if (mounted) {
        showErrorSnackBar(context, 'Session expired. Please log in again.');
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
      barcode: _barcodeController.text.trim(),
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
      showErrorSnackBar(
        context,
        productProvider.errorMessage ?? 'Something went wrong',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final requiredPerm = isEditing
        ? AppPermissions.editProducts
        : AppPermissions.addProducts;

    return PermissionGate(
      permission: requiredPerm,
      featureName: isEditing ? 'Edit Product' : 'Add Product',
      child: PopScope(
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
                        GlassSectionCard(
                          title: 'Basic Info',
                          icon: Icons.inventory_2_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CustomTextField(
                                controller: _nameController,
                                formFieldKey: _nameFormKey,
                                label: 'Product Name *',
                                hint: 'e.g., Product Name',
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

                              if (settingsProvider.barcodeEnabled)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppTheme.spacingLG,
                                  ),
                                  child: TextFormField(
                                    controller: _barcodeController,
                                    decoration: InputDecoration(
                                      labelText: 'Barcode',
                                      hintText:
                                          'Auto-generated or enter manually',
                                      prefixIcon: const Icon(
                                        Icons.qr_code_rounded,
                                      ),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              kIsWeb
                                                  ? Icons.keyboard_rounded
                                                  : Icons
                                                        .qr_code_scanner_rounded,
                                              size: 20,
                                            ),
                                            tooltip: kIsWeb
                                                ? 'Enter barcode'
                                                : 'Scan barcode',
                                            onPressed: _openBarcodeCapture,
                                          ),
                                          if (_barcodeController
                                              .text
                                              .isNotEmpty)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                                size: 18,
                                              ),
                                              tooltip: 'Copy barcode',
                                              onPressed: () {
                                                Clipboard.setData(
                                                  ClipboardData(
                                                    text:
                                                        _barcodeController.text,
                                                  ),
                                                );
                                                HapticFeedback.selectionClick();
                                                showInfoSnackBar(
                                                  context,
                                                  'Barcode copied',
                                                );
                                              },
                                            ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 20,
                                            ),
                                            tooltip: 'Generate new barcode',
                                            onPressed: () {
                                              setState(() {
                                                _barcodeController.text =
                                                    _generateBarcode();
                                              });
                                              HapticFeedback.lightImpact();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    keyboardType: TextInputType.text,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[a-zA-Z0-9\-\._ ]'),
                                      ),
                                      LengthLimitingTextInputFormatter(64),
                                    ],
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),

                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: FormField<String>(
                                  key: _categoryFormKey,
                                  initialValue: _selectedCategoryId ?? '',
                                  validator: (value) {
                                    if (value == null ||
                                        value.isEmpty ||
                                        value == '__create_new__') {
                                      return 'Please select a category';
                                    }
                                    return null;
                                  },
                                  builder: (formState) {
                                    final categoryName =
                                        _selectedCategoryId != null
                                        ? (categoryProvider
                                                  .getCategoryById(
                                                    _selectedCategoryId!,
                                                  )
                                                  ?.name ??
                                              ((_pendingNewCategory?.id ==
                                                      _selectedCategoryId)
                                                  ? _pendingNewCategory!.name
                                                  : null))
                                        : null;
                                    return GestureDetector(
                                      onTap: () async {
                                        final result = await showSearchablePicker(
                                          context: context,
                                          title: 'Category',
                                          selectedValue: _selectedCategoryId,
                                          addNewLabel: 'Add new category',
                                          addNewValue: '__create_new__',
                                          items: [
                                            ...categoryProvider.categories.map(
                                              (c) => PickerItem(
                                                value: c.id,
                                                label: c.name,
                                                icon: Icons.category_rounded,
                                              ),
                                            ),
                                            if (_pendingNewCategory != null &&
                                                !categoryProvider.categories
                                                    .any(
                                                      (c) =>
                                                          c.id ==
                                                          _pendingNewCategory!
                                                              .id,
                                                    ))
                                              PickerItem(
                                                value: _pendingNewCategory!.id,
                                                label:
                                                    _pendingNewCategory!.name,
                                                icon: Icons.category_rounded,
                                              ),
                                          ],
                                        );
                                        if (result == null || !mounted) return;
                                        if (result == '__create_new__') {
                                          final newCategory =
                                              await _showCreateCategoryDialog(
                                                context,
                                                categoryProvider,
                                              );
                                          if (newCategory != null && mounted) {
                                            setState(() {
                                              _selectedCategoryId =
                                                  newCategory.id;
                                              _pendingNewCategory = newCategory;
                                            });
                                            formState.didChange(newCategory.id);
                                          } else if (mounted) {
                                            setState(() {
                                              _selectedCategoryId = null;
                                              _pendingNewCategory = null;
                                            });
                                            formState.didChange('');
                                          }
                                        } else {
                                          setState(() {
                                            _selectedCategoryId = result;
                                            _pendingNewCategory = null;
                                          });
                                          formState.didChange(result);
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: InputDecoration(
                                          labelText: 'Category *',
                                          prefixIcon: const Icon(
                                            Icons.category_rounded,
                                          ),
                                          errorText: formState.errorText,
                                          suffixIcon:
                                              _selectedCategoryId != null
                                              ? IconButton(
                                                  icon: const Icon(
                                                    Icons.close_rounded,
                                                    size: 18,
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      _selectedCategoryId =
                                                          null;
                                                      _pendingNewCategory =
                                                          null;
                                                    });
                                                    formState.didChange('');
                                                  },
                                                )
                                              : const Icon(
                                                  Icons.arrow_drop_down,
                                                ),
                                        ),
                                        child: Text(
                                          categoryName ?? 'Select Category',
                                          style: TextStyle(
                                            color: _selectedCategoryId != null
                                                ? AppTheme.textPri(context)
                                                : AppTheme.textSec(context),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: GestureDetector(
                                  onTap: () async {
                                    final result = await showSearchablePicker(
                                      context: context,
                                      title: 'Company / Brand',
                                      selectedValue: _selectedCompany,
                                      addNewLabel: 'Add new company',
                                      addNewValue: '__create_new__',
                                      items: settingsProvider.companies
                                          .map(
                                            (c) => PickerItem(
                                              value: c,
                                              label: c,
                                              icon: Icons.business_rounded,
                                            ),
                                          )
                                          .toList(),
                                    );
                                    if (result == null || !mounted) return;
                                    if (result == '__create_new__') {
                                      _showCreateCompanyDialog(
                                        settingsProvider,
                                      );
                                    } else {
                                      setState(() => _selectedCompany = result);
                                    }
                                  },
                                  child: InputDecorator(
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
                                          : const Icon(Icons.arrow_drop_down),
                                    ),
                                    child: Text(
                                      _selectedCompany ?? 'Select Company',
                                      style: TextStyle(
                                        color: _selectedCompany != null
                                            ? AppTheme.textPri(context)
                                            : AppTheme.textSec(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: GestureDetector(
                                  onTap: () async {
                                    final result = await showSearchablePicker(
                                      context: context,
                                      title: 'Sub-Category',
                                      selectedValue: _selectedSize,
                                      addNewLabel: 'Add new sub-category',
                                      addNewValue: '__create_new__',
                                      items: settingsProvider.sizes
                                          .map(
                                            (s) => PickerItem(
                                              value: s,
                                              label: s,
                                              icon: Icons.label_rounded,
                                            ),
                                          )
                                          .toList(),
                                    );
                                    if (result == null || !mounted) return;
                                    if (result == '__create_new__') {
                                      final newSize = await _showAddSizeDialog(
                                        context,
                                        settingsProvider,
                                      );
                                      if (newSize != null && mounted) {
                                        setState(() => _selectedSize = newSize);
                                      }
                                    } else {
                                      setState(() => _selectedSize = result);
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Sub-Category',
                                      prefixIcon: const Icon(
                                        Icons.label_rounded,
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
                                          : const Icon(Icons.arrow_drop_down),
                                    ),
                                    child: Text(
                                      _selectedSize ?? 'Select Sub-Category',
                                      style: TextStyle(
                                        color: _selectedSize != null
                                            ? AppTheme.textPri(context)
                                            : AppTheme.textSec(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              CustomTextField(
                                controller: _descriptionController,
                                label: 'Description',
                                hint:
                                    'Brief details (variant, color, material...)',
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
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedUnit,
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
                                      formFieldKey: _lowStockFormKey,
                                      label: 'Low Stock Alert',
                                      hint: 'e.g., 10',
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
                                          formFieldKey: _costPriceFormKey,
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
                                          formFieldKey: _sellingPriceFormKey,
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
                                  child: GestureDetector(
                                    onTap: () async {
                                      final result = await showSearchablePicker(
                                        context: context,
                                        title: 'Preferred Vendor',
                                        selectedValue: _selectedVendorId,
                                        items: activeVendors
                                            .map(
                                              (v) => PickerItem(
                                                value: v.id,
                                                label: v.name,
                                                subtitle: v.email.isNotEmpty
                                                    ? v.email
                                                    : null,
                                                icon: Icons
                                                    .local_shipping_rounded,
                                                iconColor:
                                                    AppTheme.primaryColor,
                                              ),
                                            )
                                            .toList(),
                                      );
                                      if (result != null) {
                                        final v = vendorProvider.getVendorById(
                                          result,
                                        );
                                        setState(() {
                                          _selectedVendorId = result;
                                          _selectedVendorName = v?.name;
                                        });
                                      }
                                    },
                                    child: InputDecorator(
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
                                      child: Text(
                                        _selectedVendorName ??
                                            'Select preferred vendor',
                                        style: TextStyle(
                                          color: _selectedVendorName != null
                                              ? null
                                              : AppTheme.textSec(context),
                                        ),
                                      ),
                                    ),
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
                                                color: AppTheme.dividerC(
                                                  context,
                                                ),
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
                                          color: AppTheme.textPri(context),
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
                                color: AppTheme.textSec(context),
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

                        const SizedBox(height: 12),
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