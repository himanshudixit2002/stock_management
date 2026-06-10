import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/excel_service.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/product_model.dart';
import '../../config/theme.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../config/permissions.dart';

class ExcelUpdateScreen extends StatefulWidget {
  const ExcelUpdateScreen({super.key});

  @override
  State<ExcelUpdateScreen> createState() => _ExcelUpdateScreenState();
}

class _ExcelUpdateScreenState extends State<ExcelUpdateScreen> {
  final ExcelService _excelService = ExcelService();

  bool _isExporting = false;
  bool _isParsing = false;
  bool _isApplying = false;
  String? _error;

  String? _fileName;
  List<ProductUpdateDiff>? _diffs;
  List<Map<String, dynamic>>? _parsedData;

  int get _modifiedCount =>
      _diffs?.where((d) => d.status == UpdateStatus.modified).length ?? 0;
  int get _newCount =>
      _diffs?.where((d) => d.status == UpdateStatus.newProduct).length ?? 0;
  int get _unchangedCount =>
      _diffs?.where((d) => d.status == UpdateStatus.unchanged).length ?? 0;
  int get _errorCount =>
      _diffs?.where((d) => d.status == UpdateStatus.error).length ?? 0;

  int get _currentStep {
    if (_diffs != null) return 3;
    if (_fileName != null) return 2;
    return 1;
  }

  Future<void> _downloadForUpdate() async {
    setState(() {
      _isExporting = true;
      _error = null;
    });
    try {
      final products = context.read<ProductProvider>().allProducts;
      if (products.isEmpty) {
        setState(() {
          _error = 'No products to export. Add products first.';
          _isExporting = false;
        });
        return;
      }
      final result = await _excelService.exportProductsForUpdate(products);
      await _excelService.saveAndShare(result);
      if (mounted) {
        HapticFeedback.mediumImpact();
        showSuccessSnackBar(
          context,
          'Exported ${products.length} products for editing',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Export failed: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _pickAndParse() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: kIsWeb ? FileType.any : FileType.custom,
        allowedExtensions: kIsWeb ? null : ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.single.name.isEmpty) return;

      final pickedName = result.files.single.name.toLowerCase();
      if (!pickedName.endsWith('.xlsx')) {
        setState(() {
          _error =
              'Please select an .xlsx file (the file you downloaded in Step 1).';
        });
        return;
      }

      setState(() {
        _fileName = result.files.single.name;
        _isParsing = true;
        _error = null;
        _diffs = null;
        _parsedData = null;
      });

      try {
        final bytes = result.files.single.bytes;
        if (bytes == null) {
          throw Exception('Could not read file bytes. Please try again.');
        }

        final parseResult = _excelService.parseForUpdate(bytes);
        if (parseResult.data.isEmpty) {
          setState(() {
            _error = 'No products found in the file.';
            _isParsing = false;
          });
          return;
        }

        _parsedData = parseResult.data;

        if (!mounted) return;
        final categoryProvider = context.read<CategoryProvider>();
        final vendorProvider = context.read<VendorProvider>();
        final productProvider = context.read<ProductProvider>();

        final categoryMap = categoryProvider.getCategoryNameMap();
        final vendorMap = vendorProvider.getVendorNameMap();

        final diffs = _excelService.diffProducts(
          parseResult.data,
          productProvider.allProducts,
          categoryMap,
          vendorMap,
        );

        setState(() {
          _diffs = diffs;
          _isParsing = false;
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            _error =
                'Could not read the file: ${e.toString().replaceAll('Exception: ', '')}';
            _isParsing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not open file picker: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _applyChanges() async {
    if (_diffs == null || _parsedData == null) return;

    final modified = _diffs!
        .where((d) => d.status == UpdateStatus.modified)
        .toList();
    final newProducts = _diffs!
        .where((d) => d.status == UpdateStatus.newProduct)
        .toList();

    if (modified.isEmpty && newProducts.isEmpty) {
      showInfoSnackBar(context, 'No changes to apply.');
      return;
    }

    setState(() {
      _isApplying = true;
      _error = null;
    });

    try {
      final user = context.read<AuthProvider>().currentUser;
      if (user == null) {
        setState(() => _isApplying = false);
        if (mounted) {
          showErrorSnackBar(context, 'Session expired. Please log in again.');
        }
        return;
      }

      final categoryProvider = context.read<CategoryProvider>();
      final vendorProvider = context.read<VendorProvider>();
      final productProvider = context.read<ProductProvider>();
      final settingsProvider = context.read<SettingsProvider>();

      final categoryMap = categoryProvider.getCategoryNameMap();
      final vendorMap = vendorProvider.getVendorNameMap();

      // Create missing categories and vendors
      final allParsedData = [
        ...modified,
        ...newProducts,
      ].map((d) => d.parsedData);
      final dataCategories = allParsedData
          .map((d) => d['category']?.toString().trim() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();

      for (final catName in dataCategories) {
        if (!categoryMap.keys.contains(catName.toLowerCase())) {
          final newCategory = await categoryProvider.addCategory(
            catName,
            userId: user.uid,
            userName: user.name,
          );
          if (newCategory != null) {
            categoryMap[catName.toLowerCase()] = newCategory;
          }
        }
      }

      final dataVendors = allParsedData
          .map((d) => d['preferredVendor']?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet();
      final existingVendors = vendorMap.keys.toSet();
      final missingVendors =
          dataVendors
              .where((v) => !existingVendors.contains(v.toLowerCase()))
              .toList()
            ..sort();
      if (missingVendors.isNotEmpty) {
        final preview = missingVendors.take(5).join(', ');
        final suffix = missingVendors.length > 5 ? ' and more' : '';
        throw Exception(
          'Update references vendors without phone numbers configured: '
          '$preview$suffix. Create these vendors with phone numbers in '
          'Manage Vendors, then retry update.',
        );
      }

      int updatedCount = 0;
      int addedCount = 0;

      // Bulk update modified products
      if (modified.isNotEmpty) {
        final existingProducts = productProvider.allProducts;
        final existingMap = <String, ProductModel>{};
        for (final p in existingProducts) {
          existingMap[p.id] = p;
        }

        final productsToUpdate = <ProductModel>[];
        for (final diff in modified) {
          final existing = existingMap[diff.productId];
          if (existing == null) continue;

          final data = diff.parsedData;
          final catName = data['category']?.toString().trim() ?? '';
          final category = categoryMap[catName.toLowerCase()];
          final vendorName = data['preferredVendor']?.toString().trim() ?? '';
          final vendor = vendorName.isNotEmpty
              ? vendorMap[vendorName.toLowerCase()]
              : null;

          final locStr = data['locations']?.toString().trim() ?? '';
          var locQuantities = _excelService.parseLocationString(locStr);
          var quantity = _excelService.parseIntValue(data['quantity']);

          if (locQuantities.isNotEmpty) {
            final locSum = locQuantities.values.fold<int>(0, (a, b) => a + b);
            quantity = locSum;
            if (locSum == 0 && quantity > 0) {
              final keys = locQuantities.keys.toList();
              if (keys.length == 1) {
                locQuantities = {keys.single: quantity};
              }
            }
          } else {
            locQuantities = existing.locationQuantities;
            if (quantity != existing.quantity &&
                existing.locationQuantities.length == 1) {
              final loc = existing.locationQuantities.keys.first;
              locQuantities = {loc: quantity};
            } else {
              quantity = existing.quantity;
            }
          }

          int threshold = _excelService.parseIntValue(
            data['lowStockThreshold'],
          );
          if (threshold <= 0) threshold = existing.lowStockThreshold;

          final unitVal = data['unit']?.toString().trim() ?? '';

          productsToUpdate.add(
            existing.copyWith(
              name: data['name']?.toString().trim() ?? existing.name,
              categoryId: category?.id ?? existing.categoryId,
              categoryName: category?.name ?? catName,
              company: data['company']?.toString().trim() ?? existing.company,
              size: data['size']?.toString().trim() ?? existing.size,
              quantity: quantity,
              unit: unitVal.isNotEmpty ? unitVal : existing.unit,
              locationQuantities: locQuantities,
              description:
                  data['description']?.toString().trim() ??
                  existing.description,
              lowStockThreshold: threshold,
              costPrice: _excelService.parseDoubleValue(data['costPrice']),
              sellingPrice: _excelService.parseDoubleValue(
                data['sellingPrice'],
              ),
              preferredVendorId: vendor?.id ?? existing.preferredVendorId,
              preferredVendorName: vendor?.name ?? vendorName,
            ),
          );
        }

        if (productsToUpdate.isNotEmpty) {
          updatedCount = await productProvider.bulkUpdateProducts(
            productsToUpdate,
            userId: user.uid,
            userName: user.name,
          );
        }
      }

      // Bulk add new products
      if (newProducts.isNotEmpty) {
        final newParsedData = newProducts.map((d) => d.parsedData).toList();
        final products = _excelService.convertToProducts(
          newParsedData,
          categoryMap,
          vendorMap,
          fallbackLocations: settingsProvider.locations,
        );

        if (products.isNotEmpty) {
          addedCount = await productProvider.bulkAddProducts(
            products,
            userId: user.uid,
            userName: user.name,
          );
        }
      }

      // Sync settings
      await settingsProvider.syncFromProductList(productProvider.allProducts);

      await productProvider.refreshProducts();

      if (mounted) {
        HapticFeedback.mediumImpact();
        final parts = <String>[];
        if (updatedCount > 0) parts.add('$updatedCount updated');
        if (addedCount > 0) parts.add('$addedCount added');
        showSuccessSnackBar(context, 'Done! ${parts.join(', ')}');
        setState(() {
          _diffs = null;
          _parsedData = null;
          _fileName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Update failed: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _reset() {
    setState(() {
      _fileName = null;
      _diffs = null;
      _parsedData = null;
      _error = null;
    });
  }

  Future<void> _onPullRefreshCatalog() async {
    final product = context.read<ProductProvider>();
    final cid = product.companyId;
    if (cid.isNotEmpty) {
      await product.refreshProducts();
      if (!mounted) return;
      context.read<CategoryProvider>().initialize(companyId: cid);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null || !user.hasPermission(AppPermissions.importData)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Update from Excel')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final hPad = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const Text('Update from Excel'),
        actions: [
          if (_currentStep > 1)
            Tooltip(
              message: 'Start over',
              child: TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Start Over'),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(context),
              ),
              child: RefreshIndicator(
                onRefresh: _onPullRefreshCatalog,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStepIndicator(),
                      const SizedBox(height: 16),
                      if (_error != null) _buildError(),
                      if (_currentStep == 1) _buildStep1(),
                      if (_currentStep == 2) _buildStep2(),
                      if (_currentStep == 3) _buildStep3(),
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

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _stepDot(1, 'Download'),
        _stepLine(1),
        _stepDot(2, 'Upload'),
        _stepLine(2),
        _stepDot(3, 'Review & Apply'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppTheme.primaryColor : AppTheme.surface(context),
            border: Border.all(
              color: isActive
                  ? AppTheme.primaryColor
                  : AppTheme.glassBorderCont(context),
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '$step',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? Colors.white
                          : AppTheme.textTer(context),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent
                ? AppTheme.primaryColor
                : AppTheme.textTer(context),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _stepLine(int afterStep) {
    final isActive = _currentStep > afterStep;
    return Expanded(
      flex: 1,
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: isActive
            ? AppTheme.primaryColor
            : AppTheme.glassBorderCont(context),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: AppTheme.dangerColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTheme.dangerColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _error = null),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppTheme.textTer(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    final productCount = context.watch<ProductProvider>().allProducts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          borderRadius: 14,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Step 1: Download Current Data',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPri(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Export products as Excel for editing.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _instructionRow(
                  '1',
                  'Download the file below ($productCount products)',
                ),
                _instructionRow('2', 'Open it in Excel or Google Sheets'),
                _instructionRow(
                  '3',
                  'Edit product names, categories, prices, etc.',
                ),
                _instructionRow(
                  '4',
                  'Do NOT change the ID column (first column)',
                ),
                _instructionRow(
                  '5',
                  'Save and come back to upload the modified file',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _downloadForUpdate,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isExporting
                            ? 'Exporting...'
                            : 'Download Products Excel',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _pickAndParse,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'I already have the file, upload now',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _instructionRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return GlassCard(
      borderRadius: 14,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isParsing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Analyzing changes...',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const Icon(
                Icons.upload_file_rounded,
                size: 40,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 10),
              Text(
                'File: $_fileName',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPri(context),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Processing...',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSec(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStep3() {
    if (_diffs == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _summaryCard(
              'Modified',
              _modifiedCount,
              Icons.edit_rounded,
              AppTheme.primaryColor,
            ),
            const SizedBox(width: 8),
            _summaryCard(
              'New',
              _newCount,
              Icons.add_circle_outline,
              AppTheme.successColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _summaryCard(
              'Unchanged',
              _unchangedCount,
              Icons.check_circle_outline,
              AppTheme.textTer(context),
            ),
            const SizedBox(width: 8),
            _summaryCard(
              'Errors',
              _errorCount,
              Icons.warning_amber_rounded,
              AppTheme.dangerColor,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Modified products list
        if (_modifiedCount > 0) ...[
          _sectionTitle('Modified Products', _modifiedCount),
          const SizedBox(height: 8),
          ..._diffs!
              .where((d) => d.status == UpdateStatus.modified)
              .map((d) => _ModifiedProductCard(diff: d)),
          const SizedBox(height: 16),
        ],

        // New products list
        if (_newCount > 0) ...[
          _sectionTitle('New Products', _newCount),
          const SizedBox(height: 8),
          ..._diffs!
              .where((d) => d.status == UpdateStatus.newProduct)
              .map((d) => _NewProductCard(diff: d)),
          const SizedBox(height: 16),
        ],

        // Errors list
        if (_errorCount > 0) ...[
          _sectionTitle('Errors', _errorCount),
          const SizedBox(height: 8),
          ..._diffs!
              .where((d) => d.status == UpdateStatus.error)
              .map((d) => _ErrorCard(diff: d)),
          const SizedBox(height: 16),
        ],

        if (_modifiedCount > 0 || _newCount > 0) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _isApplying ? null : _applyChanges,
              icon: _isApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _isApplying
                      ? 'Applying...'
                      : 'Apply $_modifiedCount updates, $_newCount new',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],

        if (_modifiedCount == 0 && _newCount == 0) ...[
          const SizedBox(height: 12),
          GlassCard(
            borderRadius: 12,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 36,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No changes detected',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All products in the file match your current data.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryCard(String label, int count, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        borderRadius: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPri(context),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModifiedProductCard extends StatefulWidget {
  final ProductUpdateDiff diff;
  const _ModifiedProductCard({required this.diff});

  @override
  State<_ModifiedProductCard> createState() => _ModifiedProductCardState();
}

class _ModifiedProductCardState extends State<_ModifiedProductCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        borderRadius: 10,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: AppTheme.primaryColor,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.diff.productName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPri(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.diff.fieldChanges.length} field(s) changed',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.textTer(context),
                    size: 18,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...widget.diff.fieldChanges.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 56,
                            maxWidth: 90,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              c.field,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSec(context),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.oldValue.isEmpty ? '(empty)' : c.oldValue,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.dangerColor,
                                  decoration: TextDecoration.lineThrough,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                c.newValue.isEmpty ? '(empty)' : c.newValue,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.successColor,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NewProductCard extends StatelessWidget {
  final ProductUpdateDiff diff;
  const _NewProductCard({required this.diff});

  @override
  Widget build(BuildContext context) {
    final data = diff.parsedData;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        borderRadius: 10,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.add_circle_outline,
                  color: AppTheme.successColor,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name']?.toString() ?? 'Unnamed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [data['category'], data['company'], data['size']]
                          .where((v) => v != null && v.toString().isNotEmpty)
                          .join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTer(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.successColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final ProductUpdateDiff diff;
  const _ErrorCard({required this.diff});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        borderRadius: 10,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.dangerColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      diff.productName.isNotEmpty
                          ? diff.productName
                          : 'Unknown product',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(context),
                      ),
                    ),
                    if (diff.errorMessage != null)
                      Text(
                        diff.errorMessage!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.dangerColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
