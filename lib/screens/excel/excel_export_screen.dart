import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/excel_service.dart';
import '../../services/database_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/product_provider.dart';
import '../../config/theme.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/responsive.dart';

class ExcelExportScreen extends StatefulWidget {
  const ExcelExportScreen({super.key});

  @override
  State<ExcelExportScreen> createState() => _ExcelExportScreenState();
}

class _ExcelExportScreenState extends State<ExcelExportScreen> {
  final ExcelService _excelService = ExcelService();
  final DatabaseService _databaseService = DatabaseService();

  bool _isExporting = false;
  ExportResult? _exportResult;
  String? _error;

  String _format = 'csv';
  String _reportType = 'products';

  Future<void> _export() async {
    setState(() {
      _isExporting = true;
      _error = null;
      _exportResult = null;
    });

    try {
      ExportResult result;

      switch (_reportType) {
        case 'products':
          result = await _exportProducts();
          break;
        case 'transactions':
          result = await _exportTransactions();
          break;
        case 'categories':
          result = await _exportCategories();
          break;
        case 'full':
          result = await _exportFull();
          break;
        default:
          throw Exception('Unknown report type');
      }

      if (!mounted) return;
      setState(() {
        _exportResult = result;
        _isExporting = false;
      });

      {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report generated successfully!'),
            backgroundColor: AppTheme.successColor,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Export failed. Please try again or choose a different format.';
        _isExporting = false;
      });
    }
  }

  Future<ExportResult> _exportProducts() async {
    final categories = context.read<CategoryProvider>().categories;
    final products = await _databaseService.getAllProductsOnce();
    if (products.isEmpty) throw Exception('No products to export');

    if (_format == 'csv') {
      return await _excelService.exportProductsToCsv(products);
    } else {
      return await _excelService.exportProducts(products, categories);
    }
  }

  Future<ExportResult> _exportTransactions() async {
    final transactions = await _databaseService.getAllTransactionsOnce();
    if (transactions.isEmpty) throw Exception('No transactions to export');
    return await _excelService.exportTransactionsToCsv(transactions);
  }

  Future<ExportResult> _exportCategories() async {
    final productProvider = context.read<ProductProvider>();
    return await _excelService.exportCategoryReportToCsv(
      productCount: productProvider.productCountByCategory,
      lowStock: productProvider.lowStockByCategory,
      outOfStock: productProvider.outOfStockByCategory,
    );
  }

  Future<ExportResult> _exportFull() async {
    final productProvider = context.read<ProductProvider>();
    final products = await _databaseService.getAllProductsOnce();
    final transactions = await _databaseService.getAllTransactionsOnce();

    if (_format == 'excel') {
      return await _excelService.exportFullReport(
        products: products,
        transactions: transactions,
        productCount: productProvider.productCountByCategory,
        lowStock: productProvider.lowStockByCategory,
        outOfStock: productProvider.outOfStockByCategory,
        totalProducts: productProvider.totalProducts,
        lowStockCount: productProvider.lowStockCount,
        outOfStockCount: productProvider.outOfStockCount,
        healthScore: productProvider.inventoryHealthScore,
      );
    }
    return await _excelService.exportFullReportToCsv(
      products: products,
      transactions: transactions,
      productCount: productProvider.productCountByCategory,
      lowStock: productProvider.lowStockByCategory,
      outOfStock: productProvider.outOfStockByCategory,
      totalProducts: productProvider.totalProducts,
      lowStockCount: productProvider.lowStockCount,
      outOfStockCount: productProvider.outOfStockCount,
    );
  }

  Future<void> _shareFile() async {
    if (_exportResult != null) {
      try {
        await _excelService.saveAndShare(_exportResult!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not share the file. Please try again.'),
              backgroundColor: AppTheme.dangerColor,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null && !user.hasPermission('canExport')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Export Data')),
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
                color: AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.file_download_rounded, color: AppTheme.successColor, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Export Data'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Responsive.formMaxWidth(context)),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.file_download_rounded,
                        size: 56,
                        color: AppTheme.successColor.withValues(alpha: 0.8)),
                    const SizedBox(height: 12),
                    Text('Export Data',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose the report type and format to generate your export file.',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text('Report Type',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildReportTypeSelector(),
            const SizedBox(height: 20),

            Text('File Format',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _FormatOption(
                    label: 'CSV (.csv)',
                    icon: Icons.description_outlined,
                    isSelected: _format == 'csv',
                    onTap: () => setState(() => _format = 'csv'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormatOption(
                    label: 'Excel (.xlsx)',
                    icon: Icons.table_chart_outlined,
                    isSelected: _format == 'excel',
                    onTap: () => setState(() => _format = 'excel'),
                    enabled: _reportType == 'products' || _reportType == 'full',
                  ),
                ),
              ],
            ),
            if (_format == 'excel' && _reportType != 'products' && _reportType != 'full')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Excel format is available for Products and Full Report. Other reports will export as CSV.',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange[700]),
                ),
              ),
            const SizedBox(height: 24),

            if (_isExporting) ...[
              const LoadingWidget(message: 'Generating report...'),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.download),
                label: Text(
                    'Generate ${_reportType == 'full' ? 'Full ' : ''}Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
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
                child: Text(_error!,
                    style: const TextStyle(color: AppTheme.dangerColor)),
              ),
            ],

            if (_exportResult != null) ...[
              const SizedBox(height: 20),
              Card(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: AppTheme.successColor),
                          SizedBox(width: 8),
                          Text('File Generated Successfully!',
                              style: TextStyle(
                                  color: AppTheme.successColor,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _shareFile,
                        icon: const Icon(Icons.share),
                        label: const Text('Download / Share File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
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
      ),
    );
  }

  Widget _buildReportTypeSelector() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ReportTypeOption(
                label: 'Products',
                subtitle: 'All inventory items',
                icon: Icons.inventory_2_outlined,
                isSelected: _reportType == 'products',
                onTap: () => setState(() => _reportType = 'products'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportTypeOption(
                label: 'Transactions',
                subtitle: 'Stock movements',
                icon: Icons.history,
                isSelected: _reportType == 'transactions',
                onTap: () => setState(() => _reportType = 'transactions'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ReportTypeOption(
                label: 'Categories',
                subtitle: 'Category analytics',
                icon: Icons.category_outlined,
                isSelected: _reportType == 'categories',
                onTap: () => setState(() => _reportType = 'categories'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportTypeOption(
                label: 'Full Report',
                subtitle: 'Everything combined',
                icon: Icons.summarize_outlined,
                isSelected: _reportType == 'full',
                onTap: () => setState(() => _reportType = 'full'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReportTypeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReportTypeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor
                  : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 28,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textPrimary)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final bool enabled;

  const _FormatOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor
                  : AppTheme.dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : (enabled
                          ? AppTheme.textSecondary
                          : AppTheme.dividerColor)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (enabled
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary))),
            ],
          ),
        ),
      ),
    );
  }
}
