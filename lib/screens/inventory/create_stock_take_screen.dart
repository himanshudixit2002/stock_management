import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/stock_take_model.dart';
import '../../providers/stock_take_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/category_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/searchable_picker.dart';

class CreateStockTakeScreen extends StatefulWidget {
  const CreateStockTakeScreen({super.key});

  @override
  State<CreateStockTakeScreen> createState() => _CreateStockTakeScreenState();
}

class _CreateStockTakeScreenState extends State<CreateStockTakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedLocation;
  String? _selectedCategory;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final productProvider = context.read<ProductProvider>();
    final allProducts = productProvider.analyticsProducts;

    var filtered = allProducts.toList();
    if (_selectedLocation != null && _selectedLocation!.isNotEmpty) {
      filtered = filtered
          .where((p) => p.locationQuantities.containsKey(_selectedLocation))
          .toList();
    }
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      filtered = filtered
          .where((p) => p.categoryName == _selectedCategory)
          .toList();
    }

    final items = filtered
        .map(
          (p) => StockTakeItem(
            productId: p.id,
            productName: p.name,
            expectedQty: p.quantity,
            countedQty: 0,
            variance: 0,
          ),
        )
        .toList();

    final stockTake = StockTakeModel(
      id: '',
      name: _nameController.text.trim(),
      status: StockTakeStatus.inProgress,
      locationFilter: _selectedLocation ?? '',
      categoryFilter: _selectedCategory ?? '',
      createdBy: user?.uid ?? '',
      createdByName: user?.name ?? '',
      startedAt: DateTime.now(),
      items: items,
    );

    final success = await context.read<StockTakeProvider>().addStockTake(
      stockTake,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        showSuccessSnackBar(
          context,
          'Stock take created with ${items.length} items',
        );
        Navigator.pop(context);
      } else {
        showErrorSnackBar(
          context,
          context.read<StockTakeProvider>().errorMessage ??
              'Failed to create stock take',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageStockTakes,
      featureName: 'New Stock Take',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final settings = context.watch<SettingsProvider>();
    final categories = context.watch<CategoryProvider>().categories;
    final locations = settings.locations.isNotEmpty
        ? settings.locations
        : context.watch<ProductProvider>().availableLocations;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.add_task_rounded,
            color: AppTheme.indigoColor,
            title: 'New Stock Take',
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                  vertical: 16,
                ),
                children: [
                  GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock Take Details',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name *',
                            hintText: 'e.g. Monthly Count - March',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filters (optional)',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Only products matching these filters will be included.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            final result = await showSearchablePicker(
                              context: context,
                              title: 'Location',
                              selectedValue: _selectedLocation,
                              items: [
                                const PickerItem(
                                  value: '__all__',
                                  label: 'All Locations',
                                  icon: Icons.public_rounded,
                                ),
                                ...locations.map(
                                  (loc) => PickerItem(
                                    value: loc,
                                    label: loc,
                                    icon: Icons.location_on_outlined,
                                    iconColor: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            );
                            if (result != null) {
                              setState(
                                () => _selectedLocation = result == '__all__'
                                    ? null
                                    : result,
                              );
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                            child: Text(_selectedLocation ?? 'All Locations'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            final result = await showSearchablePicker(
                              context: context,
                              title: 'Category',
                              selectedValue: _selectedCategory,
                              items: [
                                const PickerItem(
                                  value: '__all__',
                                  label: 'All Categories',
                                  icon: Icons.public_rounded,
                                ),
                                ...categories.map(
                                  (cat) => PickerItem(
                                    value: cat.name,
                                    label: cat.name,
                                    icon: Icons.category_outlined,
                                    iconColor: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            );
                            if (result != null) {
                              setState(
                                () => _selectedCategory = result == '__all__'
                                    ? null
                                    : result,
                              );
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            child: Text(_selectedCategory ?? 'All Categories'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: AppTheme.infoColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Products will be auto-populated with their current quantities as expected values. You can then count each item.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _create,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create & Start Counting'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
