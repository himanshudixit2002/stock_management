import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../models/batch_model.dart';
import '../../models/product_model.dart';
import '../../providers/batch_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/animations.dart';
import '../../widgets/success_overlay.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';

class AddBatchScreen extends StatefulWidget {
  const AddBatchScreen({super.key});

  @override
  State<AddBatchScreen> createState() => _AddBatchScreenState();
}

class _AddBatchScreenState extends State<AddBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _batchNumberController = TextEditingController();
  final _quantityController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  ProductModel? _selectedProduct;
  DateTime? _expiryDate;
  DateTime? _manufacturingDate;
  bool _isSaving = false;
  String _productSearch = '';

  @override
  void dispose() {
    _batchNumberController.dispose();
    _quantityController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isExpiry}) async {
    final initial = isExpiry
        ? (_expiryDate ?? DateTime.now().add(const Duration(days: 90)))
        : (_manufacturingDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isExpiry) {
          _expiryDate = picked;
        } else {
          _manufacturingDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      showInfoSnackBar(context, 'Please select a product');
      return;
    }
    if (_expiryDate == null) {
      showInfoSnackBar(context, 'Please select an expiry date');
      return;
    }

    setState(() => _isSaving = true);

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final now = DateTime.now();

    final batch = BatchModel(
      id: '',
      productId: _selectedProduct!.id,
      productName: _selectedProduct!.name,
      batchNumber: _batchNumberController.text.trim(),
      expiryDate: _expiryDate!,
      manufacturingDate: _manufacturingDate,
      quantity: int.tryParse(_quantityController.text.trim()) ?? 0,
      location: _locationController.text.trim(),
      notes: _notesController.text.trim(),
      createdBy: user?.uid ?? '',
      createdByName: user?.name ?? '',
      createdAt: now,
      updatedAt: now,
    );

    final success = await context.read<BatchProvider>().addBatch(batch);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        showSuccessOverlay(context, message: 'Batch added successfully');
      } else {
        showErrorSnackBar(
          context,
          context.read<BatchProvider>().errorMessage ?? 'Failed to add batch',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageBatches,
      featureName: 'Add Batch',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final products = context.watch<ProductProvider>().allProducts;
    final filtered = _productSearch.isEmpty
        ? products
        : products
              .where(
                (p) =>
                    p.name.toLowerCase().contains(_productSearch.toLowerCase()),
              )
              .toList();

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.add_rounded,
            color: AppTheme.primaryColor,
            title: 'Add Batch',
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
                          'Product',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Search product...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _selectedProduct != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () => setState(() {
                                      _selectedProduct = null;
                                      _productSearch = '';
                                    }),
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _productSearch = v),
                        ),
                        if (_selectedProduct != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedProduct!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_selectedProduct == null &&
                            _productSearch.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final p = filtered[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(p.name),
                                  subtitle: Text(
                                    '${p.categoryName} • ${p.quantity} ${p.unit}',
                                  ),
                                  onTap: () => setState(() {
                                    _selectedProduct = p;
                                    _productSearch = '';
                                  }),
                                );
                              },
                            ),
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
                          'Batch Details',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _batchNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Batch Number *',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Quantity *',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Required';
                            final n = int.tryParse(v.trim());
                            if (n == null || n <= 0)
                              return 'Enter a valid quantity';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _locationController,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
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
                          'Dates',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        _DatePickerTile(
                          label: 'Expiry Date *',
                          icon: Icons.event_rounded,
                          date: _expiryDate,
                          onTap: () => _pickDate(isExpiry: true),
                        ),
                        const SizedBox(height: 12),
                        _DatePickerTile(
                          label: 'Manufacturing Date',
                          icon: Icons.factory_outlined,
                          date: _manufacturingDate,
                          onTap: () => _pickDate(isExpiry: false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isSaving
                      ? SizedBox(
                          height: 52,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        )
                      : ShimmerButton(
                          label: 'Save Batch',
                          onPressed: _save,
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

class _DatePickerTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final DateTime? date;
  final VoidCallback onTap;

  const _DatePickerTile({
    required this.label,
    required this.icon,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.inputFill(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.inputBorder(context)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSec(context), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                date != null ? DateFormat.yMMMd().format(date!) : label,
                style: TextStyle(
                  fontSize: 15,
                  color: date != null
                      ? AppTheme.textPri(context)
                      : AppTheme.textSec(context),
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: AppTheme.textSec(context),
            ),
          ],
        ),
      ),
    );
  }
}
