import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/stock_transaction_model.dart';
import '../models/product_model.dart';
import 'report_analytics_service.dart';

class ReportPdfService {
  static final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('MMM dd, yyyy HH:mm');
  static final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0, locale: 'en_IN');

  static pw.Font? _notoSans;

  static Future<pw.Font> _loadFont() async {
    if (_notoSans != null) return _notoSans!;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      _notoSans = pw.Font.ttf(fontData);
    } catch (_) {
      _notoSans = pw.Font.helvetica();
    }
    return _notoSans!;
  }

  /// Generates a professional multi-page Executive Inventory & Sales PDF document.
  static Future<Uint8List> generateExecutivePdfReport({
    required String companyName,
    required DateTime startDate,
    required DateTime endDate,
    required List<StockTransactionModel> transactions,
    required List<ProductModel> products,
    required List<CustomReportRow> categoryRows,
    required List<String> aiInsights,
  }) async {
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final pdf = pw.Document(
      title: '$companyName Executive Inventory Report',
      author: companyName,
      theme: theme,
    );

    int totalIn = 0;
    int totalOut = 0;
    int totalDamage = 0;
    double totalRevenue = 0.0;
    double totalValuation = 0.0;

    final pMap = {for (final p in products) p.id: p};

    for (final p in products) {
      totalValuation += (p.quantity * p.costPrice);
    }

    for (final tx in transactions) {
      final p = pMap[tx.productId];
      final price = p?.sellingPrice ?? 0.0;
      final cost = p?.costPrice ?? 0.0;

      if (tx.type == TransactionType.stockIn) {
        totalIn += tx.quantity;
      } else if (tx.type == TransactionType.stockOut) {
        totalOut += tx.quantity;
        totalRevenue += (tx.quantity * (price > 0 ? price : cost));
      } else if (tx.type == TransactionType.damage) {
        totalDamage += tx.quantity;
      }
    }

    final netMovement = totalIn - totalOut - totalDamage;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(companyName, startDate, endDate, context.pageNumber),
        footer: (context) => _buildFooter(context.pageNumber, context.pagesCount),
        build: (context) => [
          pw.SizedBox(height: 10),
          _buildKpiSummaryGrid(
            totalValuation: totalValuation,
            totalRevenue: totalRevenue,
            totalIn: totalIn,
            totalOut: totalOut,
            totalDamage: totalDamage,
            netMovement: netMovement,
          ),
          pw.SizedBox(height: 20),

          if (aiInsights.isNotEmpty) ...[
            _buildAiInsightsSection(aiInsights),
            pw.SizedBox(height: 20),
          ],

          pw.Text(
            'Category Performance Breakdown',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
          ),
          pw.SizedBox(height: 8),
          _buildCategoryTable(categoryRows),
          pw.SizedBox(height: 20),

          pw.Text(
            'Recent Transaction Activity (Sample)',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
          ),
          pw.SizedBox(height: 8),
          _buildTransactionsTable(transactions.take(15).toList()),
          pw.SizedBox(height: 24),

          _buildSignatureBlock(),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printOrExportReport({
    required String companyName,
    required DateTime startDate,
    required DateTime endDate,
    required List<StockTransactionModel> transactions,
    required List<ProductModel> products,
    required List<CustomReportRow> categoryRows,
    required List<String> aiInsights,
  }) async {
    final pdfBytes = await generateExecutivePdfReport(
      companyName: companyName,
      startDate: startDate,
      endDate: endDate,
      transactions: transactions,
      products: products,
      categoryRows: categoryRows,
      aiInsights: aiInsights,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '${companyName.replaceAll(' ', '_')}_Report_${_dateFormat.format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _buildHeader(String companyName, DateTime start, DateTime end, int pageNumber) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName.toUpperCase(),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
              ),
              pw.Text(
                'Executive Inventory & Operational Performance Report',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Date Range: ${_dateFormat.format(start)} - ${_dateFormat.format(end)}',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
              ),
              pw.Text(
                'Generated: ${_dateTimeFormat.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(int currentPage, int totalPages) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Confidential - Internal Business Intelligence Report',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page $currentPage of $totalPages',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildKpiSummaryGrid({
    required double totalValuation,
    required double totalRevenue,
    required int totalIn,
    required int totalOut,
    required int totalDamage,
    required int netMovement,
  }) {
    return pw.Row(
      children: [
        _kpiBox('Asset Valuation', _currencyFormat.format(totalValuation), PdfColors.blue100, PdfColors.blue900),
        pw.SizedBox(width: 8),
        _kpiBox('Est. Revenue', _currencyFormat.format(totalRevenue), PdfColors.green100, PdfColors.green900),
        pw.SizedBox(width: 8),
        _kpiBox('Stock In', '$totalIn units', PdfColors.teal50, PdfColors.teal900),
        pw.SizedBox(width: 8),
        _kpiBox('Stock Out', '$totalOut units', PdfColors.orange50, PdfColors.orange900),
        pw.SizedBox(width: 8),
        _kpiBox('Damaged', '$totalDamage units', PdfColors.red50, PdfColors.red900),
      ],
    );
  }

  static pw.Widget _kpiBox(String title, String value, PdfColor bg, PdfColor textCol) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: textCol)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: textCol)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildAiInsightsSection(List<String> insights) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.indigo200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Executive AI Summary & Observations', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
          pw.SizedBox(height: 6),
          ...insights.map((insight) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(insight, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.blueGrey900)),
              )),
        ],
      ),
    );
  }

  static pw.Widget _buildCategoryTable(List<CustomReportRow> rows) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerLeft,
      headers: ['Category / Group', 'Est. Revenue', 'Cost', 'Est. Profit', 'Margin %', 'Stock In', 'Stock Out', 'Damage'],
      data: rows.map((r) => [
            r.groupName,
            _currencyFormat.format(r.salesRevenue),
            _currencyFormat.format(r.estimatedCost),
            _currencyFormat.format(r.profit),
            '${r.profitMarginPct.toStringAsFixed(1)}%',
            '${r.stockInQty}',
            '${r.stockOutQty}',
            '${r.damageQty}',
          ]).toList(),
    );
  }

  static pw.Widget _buildTransactionsTable(List<StockTransactionModel> txs) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
      cellStyle: const pw.TextStyle(fontSize: 7),
      headers: ['Date', 'Product', 'Type', 'Qty', 'User', 'Reason / Location'],
      data: txs.map((tx) => [
            _dateTimeFormat.format(tx.date),
            tx.productName,
            tx.typeLabel,
            '${tx.quantity}',
            tx.userName.isNotEmpty ? tx.userName : tx.userId,
            tx.reason.isNotEmpty ? tx.reason : tx.location,
          ]).toList(),
    );
  }

  static pw.Widget _buildSignatureBlock() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(width: 140, height: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 4),
            pw.Text('Prepared By / Store Manager', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(width: 140, height: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 4),
            pw.Text('Approved By / Auditor', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      ],
    );
  }
}
