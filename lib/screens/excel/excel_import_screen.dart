import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/excel_service.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/theme.dart';
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
  String? _error;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: kIsWeb,
      );

      if (result != null && result.files.single.name.isNotEmpty) {
        setState(() {
          _fileName = result.files.single.name;
          _filePath = result.files.single.path;
          _isLoading = true;
          _error = null;
          _parsedData = null;
        });

        try {
          List<Map<String, dynamic>> data;
          final isCsv = _fileName!.toLowerCase().endsWith('.csv');

          if (kIsWeb) {
            final bytes = result.files.single.bytes;
            if (bytes == null) throw Exception('Could not read file bytes');
            data = isCsv
                ? _excelService.parseCsvBytes(bytes)
                : _excelService.parseExcelBytes(bytes);
          } else {
            if (_filePath == null) throw Exception('No file path available');
            data = isCsv
                ? await _excelService.parseCsvFile(_filePath!)
                : await _excelService.parseExcelFile(_filePath!);
          }

          setState(() {
            _parsedData = data;
            _isLoading = false;
          });
        } catch (e) {
          setState(() {
            _error = 'Could not read the file. Please check the format and try again.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Could not open file picker. Please try again.';
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
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final categoryProvider = context.read<CategoryProvider>();
      final productProvider = context.read<ProductProvider>();
      final categoryMap = categoryProvider.getCategoryNameMap();

      final existingCategories = categoryMap.keys.toSet();
      final dataCategories = _parsedData!
          .map((d) => d['category']?.toString().trim() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();

      for (final catName in dataCategories) {
        if (!existingCategories.contains(catName.toLowerCase())) {
          await categoryProvider.addCategory(
            catName,
            userId: user.uid,
            userName: user.name,
          );
        }
      }

      final updatedCategoryMap = await categoryProvider.fetchCategoryNameMap();

      final products = _excelService.convertToProducts(
        _parsedData!,
        updatedCategoryMap,
      );

      final count = await productProvider.bulkAddProducts(
        products,
        userId: user.uid,
        userName: user.name,
      );

      setState(() => _isImporting = false);

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
        _error = 'Import failed. Please check your data and try again.';
        _isImporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission('canImport')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Import Data')),
        body: const Center(child: Text('You do not have permission to access this feature.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.infoColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.file_upload_rounded, color: AppTheme.infoColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Import Data'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'File Format (Excel / CSV)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your Excel (.xlsx) or CSV (.csv) file should have these columns in the first row:',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: const [
                        Chip(label: Text('Product Name'), padding: EdgeInsets.zero),
                        Chip(label: Text('Category'), padding: EdgeInsets.zero),
                        Chip(label: Text('Company'), padding: EdgeInsets.zero),
                        Chip(label: Text('Size'), padding: EdgeInsets.zero),
                        Chip(label: Text('Quantity'), padding: EdgeInsets.zero),
                        Chip(label: Text('Unit'), padding: EdgeInsets.zero),
                        Chip(label: Text('Cost Price'), padding: EdgeInsets.zero),
                        Chip(label: Text('Selling Price'), padding: EdgeInsets.zero),
                        Chip(label: Text('Description'), padding: EdgeInsets.zero),
                        Chip(label: Text('Locations'), padding: EdgeInsets.zero),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            TextButton.icon(
              onPressed: () async {
                try {
                  final result = await _excelService.generateImportTemplate();
                  await _excelService.saveAndShare(result);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not generate template. Please try again.'),
                        backgroundColor: AppTheme.dangerColor,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download Template'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _isLoading || _isImporting ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName ?? 'Select File (.xlsx / .csv)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
              ),
            ),

            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.file_present,
                      size: 18, color: AppTheme.successColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _fileName!,
                      style: const TextStyle(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.dangerColor),
                ),
              ),
            ],

            if (_isLoading) ...[
              const SizedBox(height: 24),
              const LoadingWidget(message: 'Reading file...'),
            ],

            if (_parsedData != null && _parsedData!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Preview (${_parsedData!.length} products)',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _parsedData = null;
                        _fileName = null;
                        _filePath = null;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Company')),
                      DataColumn(label: Text('Size')),
                      DataColumn(label: Text('Qty')),
                      DataColumn(label: Text('Unit')),
                      DataColumn(label: Text('Cost')),
                      DataColumn(label: Text('Sell')),
                    ],
                    rows: _parsedData!.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return DataRow(cells: [
                        DataCell(Text('${index + 1}')),
                        DataCell(Text(item['name']?.toString() ?? '')),
                        DataCell(Text(item['category']?.toString() ?? '')),
                        DataCell(Text(item['company']?.toString() ?? '')),
                        DataCell(Text(item['size']?.toString() ?? '')),
                        DataCell(Text(item['quantity']?.toString() ?? '0')),
                        DataCell(Text(item['unit']?.toString() ?? 'pcs')),
                        DataCell(Text(item['costPrice']?.toString() ?? '0')),
                        DataCell(Text(item['sellingPrice']?.toString() ?? '0')),
                      ]);
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _isImporting ? null : _importData,
                icon: _isImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload),
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
          ],
        ),
          ),
        ),
      ),
    );
  }
}
