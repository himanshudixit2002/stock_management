import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../providers/stock_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/excel_service.dart';
import '../../../services/report_pdf_service.dart';
import '../../../services/report_analytics_service.dart';
import '../../../utils/responsive.dart';

class ReportsExportSheet extends StatefulWidget {
  const ReportsExportSheet({super.key});

  @override
  State<ReportsExportSheet> createState() => _ReportsExportSheetState();
}

class _ReportsExportSheetState extends State<ReportsExportSheet> {
  bool _isProcessing = false;

  Future<void> _exportPdf(BuildContext context) async {
    final stockProvider = context.read<StockProvider>();
    final productProvider = context.read<ProductProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isProcessing = true);
    try {
      final companyName = settingsProvider.companyId.isNotEmpty
          ? settingsProvider.companyId
          : 'Stock Management';
      final startDate = stockProvider.filterStartDate ?? DateTime.now().subtract(const Duration(days: 30));
      final endDate = stockProvider.filterEndDate ?? DateTime.now();

      final pMap = {for (final p in productProvider.products) p.id: p};
      final categoryRows = ReportAnalyticsService().generateCustomReport(
        transactions: stockProvider.recentTransactions,
        productMap: pMap,
        groupBy: 'category',
      );

      final now = DateTime.now();
      final currentEnd = stockProvider.filterEndDate ?? now;
      final currentStart = stockProvider.filterStartDate ?? currentEnd.subtract(const Duration(days: 30));
      final duration = currentEnd.difference(currentStart);
      final prevEnd = currentStart.subtract(const Duration(days: 1));
      final prevStart = prevEnd.subtract(duration);
      final prevStartDay = DateTime(prevStart.year, prevStart.month, prevStart.day);
      final prevEndExcl = DateTime(prevEnd.year, prevEnd.month, prevEnd.day + 1);

      final previousTx = stockProvider.allTransactions.where((t) {
        return !t.date.isBefore(prevStartDay) && t.date.isBefore(prevEndExcl);
      }).toList();

      final deltas = ReportAnalyticsService().computePeriodOverPeriodDeltas(
        currentTx: stockProvider.recentTransactions,
        previousTx: previousTx,
        productMap: pMap,
      );

      final insights = ReportAnalyticsService().generateAiExecutiveInsights(
        currentTx: stockProvider.recentTransactions,
        products: productProvider.products,
        deltas: deltas,
      );

      await ReportPdfService.printOrExportReport(
        companyName: companyName,
        startDate: startDate,
        endDate: endDate,
        transactions: stockProvider.recentTransactions,
        products: productProvider.products,
        categoryRows: categoryRows,
        aiInsights: insights,
      );

      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    final stockProvider = context.read<StockProvider>();
    final productProvider = context.read<ProductProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isProcessing = true);
    try {
      final excelService = ExcelService();
      final products = productProvider.products;
      final transactions = stockProvider.recentTransactions;

      final result = await excelService.exportFullReport(
        products: products,
        transactions: transactions,
        productCount: {},
        lowStock: {},
        outOfStock: {},
        totalProducts: products.length,
        lowStockCount: products.where((p) => p.quantity <= p.lowStockThreshold).length,
        outOfStockCount: products.where((p) => p.quantity <= 0).length,
        healthScore: 100,
      );

      await excelService.saveAndShare(result);

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Excel report exported successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Excel export error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: Responsive.sheetConstraints(context),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.output_rounded, color: AppTheme.primaryColor),
                const SizedBox(width: 10),
                Text(
                  'Export Executive Report',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select format for filtered transaction & inventory data.',
              style: TextStyle(color: AppTheme.textSec(context), fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_isProcessing)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                ),
                title: const Text('PDF Executive Report', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Formatted multi-page document with header, charts & tables'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _exportPdf(context),
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_chart_rounded, color: Colors.green),
                ),
                title: const Text('Excel Workbook (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Raw transactions and calculated summary worksheets'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _exportExcel(context),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
