import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/excel_service.dart';
import '../../services/database_service.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/vendor_model.dart';
import '../../models/product_model.dart';
import '../../config/theme.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/responsive.dart';

class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  final ExcelService _excelService = ExcelService();

  String? _filePath;
  String? _fileName;
  List<Map<String, dynamic>>? _parsedData;
  bool _isLoading = false;
  bool _isImporting = false;
  bool _isDownloadingTemplate = false;
  String? _error;

  int _skippedRows = 0;

  int get _currentStep {
    if (_parsedData != null && _parsedData!.isNotEmpty) return 3;
    if (_fileName != null) return 2;
    return 1;
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: kIsWeb ? FileType.any : FileType.custom,
        allowedExtensions: kIsWeb ? null : ['xlsx', 'csv'],
        withData: kIsWeb,
      );

      if (result != null && result.files.single.name.isNotEmpty) {
        final pickedName = result.files.single.name.toLowerCase();
        if (!pickedName.endsWith('.xlsx') && !pickedName.endsWith('.csv')) {
          setState(() {
            _error =
                'Unsupported file type. Please select an .xlsx or .csv file.';
          });
          return;
        }

        setState(() {
          _fileName = result.files.single.name;
          _filePath = kIsWeb ? null : result.files.single.path;
          _isLoading = true;
          _error = null;
          _parsedData = null;
        });

        try {
          ParseResult parseResult;
          final isCsv = _fileName!.toLowerCase().endsWith('.csv');

          if (kIsWeb) {
            final bytes = result.files.single.bytes;
            if (bytes == null) {
              throw Exception(
                'Could not read file bytes on web. Please try again.',
              );
            }
            parseResult = isCsv
                ? _excelService.parseCsvBytes(bytes)
                : _excelService.parseExcelBytes(bytes);
          } else {
            if (_filePath == null) throw Exception('No file path available');
            parseResult = isCsv
                ? await _excelService.parseCsvFile(_filePath!)
                : await _excelService.parseExcelFile(_filePath!);
          }

          if (parseResult.data.isEmpty) {
            setState(() {
              _error =
                  'No products found in the file. Make sure the file has data rows.';
              _isLoading = false;
            });
            return;
          }

          setState(() {
            _parsedData = parseResult.data;
            _skippedRows = parseResult.skippedRows;
            _isLoading = false;
          });
        } catch (e) {
          setState(() {
            _error =
                'Could not read the file: ${e.toString().replaceAll('Exception: ', '')}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Could not open file picker: ${e.toString()}';
      });
    }
  }

  Future<void> _importData() async {
    if (_parsedData == null || _parsedData!.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final user = context.read<AuthProvider>().currentUser;
      if (user == null) {
        setState(() => _isImporting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please log in again.'),
              backgroundColor: AppTheme.dangerColor,
            ),
          );
        }
        return;
      }
      final categoryProvider = context.read<CategoryProvider>();
      final vendorProvider = context.read<VendorProvider>();
      final productProvider = context.read<ProductProvider>();
      final settingsProvider = context.read<SettingsProvider>();

      final categoryMap = categoryProvider.getCategoryNameMap();
      final vendorMap = vendorProvider.getVendorNameMap();

      final existingCategories = categoryMap.keys.toSet();
      final dataCategories = _parsedData!
          .map((d) => d['category']?.toString().trim() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();

      try {
        for (final catName in dataCategories) {
          if (!existingCategories.contains(catName.toLowerCase())) {
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
      } catch (e) {
        throw Exception('Failed to create missing categories: $e');
      }

      final existingVendors = vendorMap.keys.toSet();
      final dataVendors = _parsedData!
          .map((d) => d['preferredVendor']?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet();

      final now = DateTime.now();
      try {
        for (final vendorName in dataVendors) {
          if (!existingVendors.contains(vendorName.toLowerCase())) {
            final newVendor = VendorModel(
              id: '',
              name: vendorName,
              createdAt: now,
              updatedAt: now,
              createdBy: user.uid,
              createdByName: user.name,
            );
            final addedVendor = await vendorProvider.addVendor(newVendor);
            if (addedVendor != null) {
              vendorMap[vendorName.toLowerCase()] = addedVendor;
            }
          }
        }
      } catch (e) {
        throw Exception('Failed to create missing vendors: $e');
      }

      List<ProductModel> products;
      try {
        products = _excelService.convertToProducts(
          _parsedData!,
          categoryMap,
          vendorMap,
          fallbackLocations: settingsProvider.locations,
        );
      } catch (e) {
        throw Exception('Failed to process product data: $e');
      }

      // Sync companies, locations, sizes from import to Settings so filters work
      final companies = products
          .map((p) => p.company)
          .where((c) => c.trim().isNotEmpty)
          .toSet()
          .toList();
      final locations = products
          .expand((p) => p.locationQuantities.keys)
          .where((l) => l.trim().isNotEmpty)
          .toSet()
          .toList();
      final sizes = products
          .map((p) => p.size)
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();
      if (companies.isNotEmpty) {
        await settingsProvider.addCompaniesFromImport(companies);
      }
      if (locations.isNotEmpty) {
        await settingsProvider.addLocationsFromImport(locations);
      }
      if (sizes.isNotEmpty) await settingsProvider.addSizesFromImport(sizes);

      // Check for potential duplicates and warn user
      final existingKeys = productProvider.allProducts.map((p) {
        final n = (p.name).trim().toLowerCase();
        final c = (p.categoryName).trim().toLowerCase();
        final co = (p.company).trim().toLowerCase();
        final s = (p.size).trim().toLowerCase();
        return '$n|$c|$co|$s';
      }).toSet();
      int potentialDuplicates = 0;
      for (final p in products) {
        final key =
            '${(p.name).trim().toLowerCase()}|${(p.categoryName).trim().toLowerCase()}|${(p.company).trim().toLowerCase()}|${(p.size).trim().toLowerCase()}';
        if (existingKeys.contains(key)) potentialDuplicates++;
      }
      if (potentialDuplicates > 0 && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Potential Duplicates'),
            content: Text(
              '$potentialDuplicates product(s) may already exist with the same name, category, company, and size. Importing will create duplicates.\n\nDo you want to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor,
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          setState(() => _isImporting = false);
          return;
        }
      }

      int count = 0;
      try {
        count = await productProvider.bulkAddProducts(
          products,
          userId: user.uid,
          userName: user.name,
        );
      } catch (e) {
        throw Exception('Failed to save products to database: $e');
      }

      setState(() => _isImporting = false);

      if (count == 0) {
        throw Exception(
          productProvider.errorMessage ??
              'No products were imported. Please try again.',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $count products!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isImporting = false;
      });
    }
  }

  void _clearFile() {
    setState(() {
      _parsedData = null;
      _fileName = null;
      _filePath = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null || !user.hasPermission('canImport')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Import Data')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.file_upload_rounded,
          color: AppTheme.infoColor,
          title: 'Import Data',
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStepSection(
                    stepNumber: 1,
                    title: 'Prepare Your File',
                    isActive: true,
                    isCompleted: _currentStep > 1,
                    hasConnector: true,
                    child: _buildStep1Content(),
                  ),
                  _buildStepSection(
                    stepNumber: 2,
                    title: 'Select & Upload File',
                    isActive: _currentStep >= 2,
                    isCompleted: _currentStep > 2,
                    hasConnector: true,
                    child: _buildStep2Content(),
                  ),
                  _buildStepSection(
                    stepNumber: 3,
                    title: 'Preview & Import',
                    isActive: _currentStep >= 3,
                    isCompleted: false,
                    hasConnector: false,
                    child: _buildStep3Content(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepSection({
    required int stepNumber,
    required String title,
    required bool isActive,
    required bool isCompleted,
    required bool hasConnector,
    required Widget child,
  }) {
    final circleColor = isCompleted
        ? AppTheme.successColor
        : isActive
        ? AppTheme.primaryColor
        : AppTheme.textSecondary.withValues(alpha: 0.3);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTheme.surfaceColor,
                        size: 18,
                      )
                    : Text(
                        '$stepNumber',
                        style: TextStyle(
                          color: isActive
                              ? AppTheme.surfaceColor
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
            if (hasConnector)
              Container(
                width: 2,
                height: 24,
                color: isCompleted
                    ? AppTheme.successColor.withValues(alpha: 0.4)
                    : AppTheme.dividerColor,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: GlassPanel(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(16),
                  useContentVariant: true,
                  child: child,
                ),
              ),
              if (hasConnector) const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep1Content() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_rounded,
                size: 18,
                color: AppTheme.infoColor,
              ),
              const SizedBox(width: 6),
              const Text(
                'Supported formats: .xlsx, .csv',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Your file should have these columns (with or without headers):',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          _buildColumnTable(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.infoColor.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_fix_high_rounded,
                  size: 16,
                  color: AppTheme.infoColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Files without headers are also supported \u2014 columns will be auto-detected.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.infoColor.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isDownloadingTemplate
                  ? null
                  : () async {
                      if (_isDownloadingTemplate) return;
                      setState(() => _isDownloadingTemplate = true);
                      try {
                        final result = await _excelService
                            .generateImportTemplate();
                        await _excelService.saveAndShare(result);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Template downloaded successfully.',
                              ),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not generate template: ${e.toString().replaceAll('Exception: ', '')}',
                              ),
                              backgroundColor: AppTheme.dangerColor,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isDownloadingTemplate = false);
                        }
                      }
                    },
              icon: _isDownloadingTemplate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                _isDownloadingTemplate ? 'Downloading...' : 'Download Template',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _runSyncFromProducts(context),
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Sync Settings from existing products'),
          ),
        ],
      ),
    );
  }

  Future<void> _runSyncFromProducts(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync Settings from existing products'),
        content: const Text(
          'Add companies, locations, and sizes from your existing products to Settings. '
          'Use this if you imported products before this sync was available.\n\n'
          'This will read all products. For large inventories it may take a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sync'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    setState(() => _isLoading = true);
    try {
      final user = context.read<AuthProvider>().currentUser;
      if (user == null || user.companyId.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not determine company. Please try again.'),
              backgroundColor: AppTheme.dangerColor,
            ),
          );
        }
        return;
      }

      final db = DatabaseService();
      db.setCompanyId(user.companyId);
      final products = await db.getAllProductsOnce();

      if (!context.mounted) return;
      final settingsProvider = context.read<SettingsProvider>();
      await settingsProvider.syncFromProductList(products);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Companies: ${settingsProvider.companies.length}, '
            'Locations: ${settingsProvider.locations.length}, '
            'Sizes: ${settingsProvider.sizes.length}',
          ),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString()}'),
            backgroundColor: AppTheme.dangerColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildColumnTable() {
    // Order matches the download template and export format
    const columns = [
      ['Product Name', 'required'],
      ['Category', ''],
      ['Company', ''],
      ['Size', ''],
      ['Locations', 'pos1 or pos1:123'],
      ['Quantity', ''],
      ['Unit', 'default: pcs'],
      ['Cost Price', ''],
      ['Selling Price', ''],
      ['Low Stock Threshold', 'default: 10'],
      ['Description', ''],
      ['Preferred Vendor', ''],
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.06),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Column',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Note',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            ...columns.map(
              (col) => TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.dividerColor, width: 0.5),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(col[0], style: const TextStyle(fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      col[1],
                      style: TextStyle(
                        fontSize: 11,
                        color: col[1] == 'required'
                            ? AppTheme.dangerColor
                            : AppTheme.textSecondary,
                        fontWeight: col[1] == 'required'
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_fileName != null && _parsedData == null && !_isLoading) ...[
          _buildFileChip(),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _isLoading || _isImporting ? null : _pickFile,
          icon: Icon(
            _fileName != null
                ? Icons.swap_horiz_rounded
                : Icons.upload_file_rounded,
          ),
          label: Text(
            _fileName != null ? 'Change File' : 'Select File (.xlsx / .csv)',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
        if (_isLoading) ...[
          const SizedBox(height: 16),
          const LoadingWidget(message: 'Reading file...'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dangerColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.dangerColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.dangerColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.dangerColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFileChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.file_present_rounded,
            size: 18,
            color: AppTheme.successColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _fileName!,
              style: const TextStyle(
                color: AppTheme.successColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: _clearFile,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Content() {
    if (_parsedData == null || _parsedData!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.inputFillColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          children: [
            Icon(
              Icons.table_chart_outlined,
              size: 36,
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Data preview will appear here after you select a file.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_fileName != null) ...[
          _buildFileChip(),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.preview_rounded,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_parsedData!.length} products found',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _isImporting ? null : _clearFile,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_skippedRows > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.infoColor.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AppTheme.infoColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$_skippedRows rows were skipped because they were missing a product name.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.infoColor.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warningColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.warningColor.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppTheme.warningColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Note: Importing will create new products. To update stock for existing products, use the Stock In feature.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.warningColor.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              headingRowColor: WidgetStateProperty.all(
                AppTheme.primaryColor.withValues(alpha: 0.04),
              ),
              columns: const [
                DataColumn(
                  label: Text(
                    '#',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Name',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Category',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Company',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Size',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Locations',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Qty',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Unit',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Cost',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Sell',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Threshold',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Vendor',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              rows: _parsedData!.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(item['name']?.toString() ?? '')),
                    DataCell(Text(item['category']?.toString() ?? '')),
                    DataCell(Text(item['company']?.toString() ?? '')),
                    DataCell(Text(item['size']?.toString() ?? '')),
                    DataCell(Text(item['locations']?.toString() ?? '')),
                    DataCell(Text(item['quantity']?.toString() ?? '0')),
                    DataCell(Text(item['unit']?.toString() ?? 'pcs')),
                    DataCell(Text(item['costPrice']?.toString() ?? '0')),
                    DataCell(Text(item['sellingPrice']?.toString() ?? '0')),
                    DataCell(
                      Text(
                        item['lowStockThreshold']?.toString() == '0'
                            ? '10'
                            : (item['lowStockThreshold']?.toString() ?? '10'),
                      ),
                    ),
                    DataCell(Text(item['preferredVendor']?.toString() ?? '')),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _isImporting ? null : _importData,
          icon: _isImporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.surfaceColor,
                  ),
                )
              : const Icon(Icons.cloud_upload_rounded),
          label: Text(
            _isImporting
                ? 'Importing...'
                : 'Import ${_parsedData!.length} Products',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.successColor,
          ),
        ),
      ],
    );
  }
}
