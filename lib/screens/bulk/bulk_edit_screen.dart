import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/success_overlay.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/animations.dart';
import '../../config/app_navigation.dart';

class BulkEditScreen extends StatefulWidget {
  const BulkEditScreen({super.key});

  @override
  State<BulkEditScreen> createState() => _BulkEditScreenState();
}

class _BulkEditScreenState extends State<BulkEditScreen> {
  int _currentStep = 0;
  String _searchQuery = '';

  final Set<String> _selectedProductIds = {};
  final Set<String> _selectedFields = {};

  String? _newCategory;
  String? _newCompany;
  String? _newSize;
  final _thresholdController = TextEditingController();

  bool _isApplying = false;

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  List<ProductModel> get _allProducts =>
      context.read<ProductProvider>().allProducts;

  List<ProductModel> get _selectedProducts =>
      _allProducts.where((p) => _selectedProductIds.contains(p.id)).toList();

  void _nextStep() {
    if (_currentStep == 0 && _selectedProductIds.isEmpty) {
      showErrorSnackBar(context, 'Select at least one product');
      return;
    }
    if (_currentStep == 1 && _selectedFields.isEmpty) {
      showErrorSnackBar(context, 'Select at least one field to edit');
      return;
    }
    setState(() => _currentStep++);
  }

  void _prevStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _apply() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      setState(() => _isApplying = false);
      return;
    }

    final categories = context.read<CategoryProvider>().categories;
    final now = DateTime.now();

    final updatedProducts = _selectedProducts.map((p) {
      var updated = p.copyWith(updatedAt: now);
      if (_selectedFields.contains('category') && _newCategory != null) {
        final cat = categories.where((c) => c.name == _newCategory).firstOrNull;
        if (cat != null) {
          updated = updated.copyWith(
            categoryId: cat.id,
            categoryName: cat.name,
          );
        }
      }
      if (_selectedFields.contains('company') && _newCompany != null) {
        updated = updated.copyWith(company: _newCompany);
      }
      if (_selectedFields.contains('size') && _newSize != null) {
        updated = updated.copyWith(size: _newSize);
      }
      if (_selectedFields.contains('threshold')) {
        final threshold = int.tryParse(_thresholdController.text);
        if (threshold != null && threshold >= 0) {
          updated = updated.copyWith(lowStockThreshold: threshold);
        }
      }
      return updated;
    }).toList();

    try {
      final productProvider = context.read<ProductProvider>();
      await productProvider.bulkUpdateProducts(
        updatedProducts,
        userId: user.uid,
        userName: user.name,
      );
      if (!mounted) return;
      showSuccessOverlay(
        context,
        message: '${updatedProducts.length} products updated',
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.bulkEdit,
      featureName: 'Bulk Edit',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final products = context.watch<ProductProvider>().allProducts;

    final bool isEmpty = products.isEmpty;

    return AppScreenScaffold(
      icon: Icons.edit_note_rounded,
      title: 'Bulk Edit',
      iconColor: AppTheme.indigoColor,
      isEmpty: isEmpty,
      emptyState: EmptyStateWidget(
        icon: Icons.edit_note_rounded,
        title: 'No Products',
        subtitle: 'Add products first to use bulk edit.',
        buttonText: 'Add Product',
        onButtonPressed: () => context.pushAppRoute(AppRoutes.addProduct),
      ),
      header: isEmpty ? null : _buildStepIndicator(),
      bottomNavigationBar: isEmpty ? null : _buildBottomBar(),
      body: _buildStepContent(products),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Select', 'Fields', 'Values', 'Preview'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i == _currentStep;
          final isDone = i < _currentStep;
          return Expanded(
            child: Row(
              children: [
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isDone
                          ? AppTheme.primaryColor
                          : AppTheme.dividerC(context),
                    ),
                  ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isActive || isDone
                        ? AppTheme.primaryColor
                        : AppTheme.dividerC(context),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? Colors.white
                                  : AppTheme.textSec(context),
                            ),
                          ),
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isDone
                          ? AppTheme.primaryColor
                          : AppTheme.dividerC(context),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(List<ProductModel> products) {
    switch (_currentStep) {
      case 0:
        return _buildStep1(products);
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1(List<ProductModel> products) {
    final lower = _searchQuery.toLowerCase();
    final filtered = _searchQuery.isEmpty
        ? products
        : products
              .where(
                (p) =>
                    p.name.toLowerCase().contains(lower) ||
                    p.categoryName.toLowerCase().contains(lower),
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${_selectedProductIds.length} selected',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedProductIds.length == products.length) {
                      _selectedProductIds.clear();
                    } else {
                      _selectedProductIds
                        ..clear()
                        ..addAll(products.map((p) => p.id));
                    }
                  });
                },
                child: Text(
                  _selectedProductIds.length == products.length
                      ? 'Deselect All'
                      : 'Select All',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search products...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final p = filtered[index];
              final selected = _selectedProductIds.contains(p.id);
              final tile = CheckboxListTile(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedProductIds.add(p.id);
                    } else {
                      _selectedProductIds.remove(p.id);
                    }
                  });
                },
                title: Text(
                  p.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${p.categoryName} • ${p.quantity} ${p.unit}',
                  style: const TextStyle(fontSize: 12),
                ),
                activeColor: AppTheme.primaryColor,
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              );
              // Cap entrance animations for large product lists.
              return index < 15
                  ? AnimatedListItem(index: index, child: tile)
                  : tile;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final fields = [
      ('category', 'Category', Icons.category_rounded),
      ('company', 'Company / Brand', Icons.business_rounded),
      ('size', 'Sub-Category', Icons.label_rounded),
      ('threshold', 'Low Stock Threshold', Icons.warning_amber_rounded),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Choose which fields to update:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 12),
        ...fields.indexed.map((entry) {
          final i = entry.$1;
          final f = entry.$2;
          final selected = _selectedFields.contains(f.$1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FadeSlideIn(
              index: i,
              child: GlassPanel(
              useContentVariant: true,
              borderRadius: 14,
              child: CheckboxListTile(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedFields.add(f.$1);
                    } else {
                      _selectedFields.remove(f.$1);
                    }
                  });
                },
                title: Row(
                  children: [
                    Icon(f.$3, size: 20, color: AppTheme.primaryColor),
                    const SizedBox(width: 10),
                    Text(
                      f.$2,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                activeColor: AppTheme.primaryColor,
              ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3() {
    final settings = context.watch<SettingsProvider>();
    final categories = context.watch<CategoryProvider>().categories;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Set new values:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 16),
        if (_selectedFields.contains('category')) ...[
          GestureDetector(
            onTap: () async {
              final result = await showSearchablePicker(
                context: context,
                title: 'Category',
                selectedValue: _newCategory,
                items: categories
                    .map(
                      (c) => PickerItem(
                        value: c.name,
                        label: c.name,
                        icon: Icons.category_rounded,
                        iconColor: AppTheme.primaryColor,
                      ),
                    )
                    .toList(),
              );
              if (result != null) setState(() => _newCategory = result);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'New Category',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              child: Text(
                _newCategory ?? 'Tap to select',
                style: TextStyle(
                  color: _newCategory != null
                      ? null
                      : AppTheme.textSec(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_selectedFields.contains('company')) ...[
          GestureDetector(
            onTap: () async {
              final result = await showSearchablePicker(
                context: context,
                title: 'Company / Brand',
                selectedValue: _newCompany,
                items: settings.companies
                    .map(
                      (c) => PickerItem(
                        value: c,
                        label: c,
                        icon: Icons.business_rounded,
                        iconColor: AppTheme.primaryColor,
                      ),
                    )
                    .toList(),
              );
              if (result != null) setState(() => _newCompany = result);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'New Company / Brand',
                prefixIcon: Icon(Icons.business_rounded),
              ),
              child: Text(
                _newCompany ?? 'Tap to select',
                style: TextStyle(
                  color: _newCompany != null ? null : AppTheme.textSec(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_selectedFields.contains('size')) ...[
          GestureDetector(
            onTap: () async {
              final result = await showSearchablePicker(
                context: context,
                title: 'Sub-Category',
                selectedValue: _newSize,
                items: settings.sizes
                    .map(
                      (s) => PickerItem(
                        value: s,
                        label: s,
                        icon: Icons.label_rounded,
                        iconColor: AppTheme.primaryColor,
                      ),
                    )
                    .toList(),
              );
              if (result != null) setState(() => _newSize = result);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'New Sub-Category',
                prefixIcon: Icon(Icons.label_rounded),
              ),
              child: Text(
                _newSize ?? 'Tap to select',
                style: TextStyle(
                  color: _newSize != null ? null : AppTheme.textSec(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_selectedFields.contains('threshold')) ...[
          TextFormField(
            controller: _thresholdController,
            decoration: const InputDecoration(
              labelText: 'New Low Stock Threshold',
              prefixIcon: Icon(Icons.warning_amber_rounded),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildStep4() {
    final selected = _selectedProducts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassPanel(
          useContentVariant: true,
          borderRadius: 14,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Summary',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _summaryRow('Products', '${selected.length}'),
              if (_selectedFields.contains('category') && _newCategory != null)
                _summaryRow('Category', _newCategory!),
              if (_selectedFields.contains('company') && _newCompany != null)
                _summaryRow('Company', _newCompany!),
              if (_selectedFields.contains('size') && _newSize != null)
                _summaryRow('Sub-Category', _newSize!),
              if (_selectedFields.contains('threshold') &&
                  _thresholdController.text.isNotEmpty)
                _summaryRow('Threshold', _thresholdController.text),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Products to update:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...selected.indexed.map((entry) {
          final tile = Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_2_rounded, size: 18),
              title: Text(entry.$2.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${entry.$2.categoryName} • ${entry.$2.quantity} ${entry.$2.unit}',
                style: const TextStyle(fontSize: 11),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              tileColor: AppTheme.inputFill(context),
            ),
          );
          return entry.$1 < 15
              ? AnimatedListItem(index: entry.$1, child: tile)
              : tile;
        }),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: AppTheme.textSec(context), fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Padding(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _prevStep,
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _currentStep < 3
                      ? ShimmerButton(
                          label: 'Next',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: _nextStep,
                        )
                      : SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isApplying ? null : _apply,
                            icon: _isApplying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              'Apply to ${_selectedProductIds.length} Products',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
