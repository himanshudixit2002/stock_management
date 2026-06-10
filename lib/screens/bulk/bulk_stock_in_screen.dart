import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/success_overlay.dart';
import '../../widgets/product_picker.dart';
import '../../config/app_navigation.dart';

class _BulkRow {
  ProductModel? product;
  final TextEditingController qtyController;
  String? location;

  _BulkRow() : qtyController = TextEditingController();

  void dispose() {
    qtyController.dispose();
  }
}

class BulkStockInScreen extends StatefulWidget {
  const BulkStockInScreen({super.key});

  @override
  State<BulkStockInScreen> createState() => _BulkStockInScreenState();
}

class _BulkStockInScreenState extends State<BulkStockInScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<_BulkRow> _rows = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _addRow();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_BulkRow()));
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  bool _validate() {
    if (!_formKey.currentState!.validate()) return false;
    for (final row in _rows) {
      if (row.product == null) {
        showErrorSnackBar(context, 'Please select a product for each row');
        return false;
      }
      if (row.location == null || row.location!.isEmpty) {
        showErrorSnackBar(context, 'Please select a location for each row');
        return false;
      }
    }
    return true;
  }

  Future<void> _submitAll() async {
    if (_isSubmitting || !_validate()) return;
    setState(() => _isSubmitting = true);

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final stockProvider = context.read<StockProvider>();
    int successCount = 0;
    String? lastError;

    for (final row in _rows) {
      final qty = int.tryParse(row.qtyController.text) ?? 0;
      if (qty <= 0 || row.product == null || row.location == null) continue;

      final success = await stockProvider.addStock(
        productId: row.product!.id,
        productName: row.product!.name,
        quantity: qty,
        location: row.location!,
        userId: user.uid,
        userName: user.name,
        reason: 'Bulk stock in',
      );

      if (success) {
        successCount++;
      } else {
        lastError = stockProvider.errorMessage;
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (successCount == _rows.length) {
      context.read<ProductProvider>().refreshProducts();
      HapticFeedback.mediumImpact();
      showSuccessOverlay(
        context,
        message: '$successCount items stocked in successfully',
      );
    } else if (successCount > 0) {
      context.read<ProductProvider>().refreshProducts();
      showInfoSnackBar(
        context,
        '$successCount of ${_rows.length} succeeded. ${lastError ?? ""}',
      );
    } else {
      showErrorSnackBar(context, lastError ?? 'Failed to add stock');
    }
  }

  void _showProductPicker(int rowIndex) async {
    final products = context.read<ProductProvider>().allProducts;
    final p = await showProductPicker(
      context: context,
      products: products,
      selectedProductId: _rows[rowIndex].product?.id,
    );
    if (p == null || !mounted) return;
    setState(() => _rows[rowIndex].product = p);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission(AppPermissions.bulkStockIn)) {
      return Scaffold(
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.playlist_add_rounded,
            color: AppTheme.successColor,
            title: 'Bulk Stock In',
          ),
        ),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final products = context.watch<ProductProvider>().allProducts;
    final locations = context.watch<SettingsProvider>().locations;

    if (products.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const AppBarTitleRow(
            icon: Icons.playlist_add_rounded,
            color: AppTheme.successColor,
            title: 'Bulk Stock In',
          ),
        ),
        body: EmptyStateWidget(
          icon: Icons.inventory_2_rounded,
          title: 'No Products Yet',
          subtitle: 'Add products before using bulk stock in.',
          buttonText: 'Add Product',
          onButtonPressed: () => context.pushAppRoute(AppRoutes.addProduct),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.playlist_add_rounded,
          color: AppTheme.successColor,
          title: 'Bulk Stock In',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.all(
                        Responsive.horizontalPadding(context),
                      ),
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassPanel(
                            useContentVariant: true,
                            borderRadius: 16,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Item ${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppTheme.textPri(context),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_rows.length > 1)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          color: AppTheme.dangerColor,
                                          size: 20,
                                        ),
                                        onPressed: () => _removeRow(index),
                                        tooltip: 'Remove row',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Material(
                                  color: AppTheme.inputFill(context),
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    onTap: () => _showProductPicker(index),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppTheme.inputBorder(context),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.inventory_2_rounded,
                                            color: row.product != null
                                                ? AppTheme.primaryColor
                                                : AppTheme.textSec(context),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              row.product?.name ??
                                                  'Select product...',
                                              style: TextStyle(
                                                fontWeight: row.product != null
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: row.product != null
                                                    ? AppTheme.textPri(context)
                                                    : AppTheme.textSec(context),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.arrow_drop_down_rounded,
                                            color: AppTheme.textSec(context),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: row.qtyController,
                                        decoration: const InputDecoration(
                                          labelText: 'Qty *',
                                          prefixIcon: Icon(Icons.add_rounded),
                                          isDense: true,
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        validator: (v) {
                                          if (v == null || v.isEmpty)
                                            return 'Required';
                                          final qty = int.tryParse(v);
                                          if (qty == null || qty <= 0)
                                            return 'Invalid';
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: row.location,
                                        decoration: const InputDecoration(
                                          labelText: 'Location *',
                                          isDense: true,
                                        ),
                                        items: locations
                                            .map(
                                              (l) => DropdownMenuItem(
                                                value: l,
                                                child: Text(l),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) =>
                                            setState(() => row.location = v),
                                        validator: (v) {
                                          if (v == null || v.isEmpty)
                                            return 'Required';
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(
                      Responsive.horizontalPadding(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _addRow,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Add Another Item'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submitAll,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text('Submit All (${_rows.length} items)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
