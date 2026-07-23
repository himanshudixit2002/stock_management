import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/invoice_model.dart';
import '../models/billing_settings_model.dart';
import 'excel_service.dart';
import 'file_helper.dart' as file_helper;

class BillingPdfService {
  static final _dateFormat = DateFormat('dd MMM yyyy');
  static final _numFormat = NumberFormat('#,##0.00');

  static pw.Font? _notoSans;

  Future<pw.Font> _loadFont() async {
    if (_notoSans != null) return _notoSans!;
    try {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      _notoSans = pw.Font.ttf(data);
    } catch (_) {
      _notoSans = pw.Font.helvetica();
    }
    return _notoSans!;
  }

  String _fmt(double v, String symbol) => '$symbol${_numFormat.format(v)}';

  // ==================== A4 INVOICE PDF ====================

  Future<ExportResult> generateInvoicePdf(
    InvoiceModel invoice,
    BillingSettings bs,
  ) async {
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildHeader(invoice, bs, sym),
          pw.SizedBox(height: 20),
          _buildCustomerBlock(invoice),
          pw.SizedBox(height: 16),
          _buildItemsTable(invoice, bs, sym),
          pw.SizedBox(height: 12),
          _buildTotals(invoice, bs, sym),
          if (invoice.payments.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _buildPaymentHistory(invoice, sym),
          ],
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Notes:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
            pw.SizedBox(height: 4),
            pw.Text(invoice.notes, style: const pw.TextStyle(fontSize: 9)),
          ],
        ],
        footer: (context) => _buildFooter(bs, context),
      ),
    );

    final bytes = await pdf.save();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return ExportResult(
      'invoice_${invoice.invoiceNumber}_$timestamp.pdf',
      bytes,
    );
  }

  pw.Widget _buildHeader(InvoiceModel invoice, BillingSettings bs, String sym) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (bs.businessName.isNotEmpty)
                pw.Text(
                  bs.businessName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (bs.businessAddress.isNotEmpty)
                pw.Text(
                  bs.businessAddress,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              if (bs.businessPhone.isNotEmpty)
                pw.Text(
                  'Phone: ${bs.businessPhone}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              if (bs.businessEmail.isNotEmpty)
                pw.Text(
                  'Email: ${bs.businessEmail}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              if (bs.taxId.isNotEmpty)
                pw.Text(
                  '${bs.taxLabel} ID: ${bs.taxId}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              invoice.isPurchase ? 'PURCHASE BILL' : 'INVOICE',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '# ${invoice.invoiceNumber}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Date: ${_dateFormat.format(invoice.invoiceDate)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Due: ${_dateFormat.format(invoice.dueDate)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: pw.BoxDecoration(
                color: invoice.isPaid
                    ? PdfColors.green100
                    : invoice.isOverdue
                    ? PdfColors.red100
                    : PdfColors.blue100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                invoice.statusLabel.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: invoice.isPaid
                      ? PdfColors.green800
                      : invoice.isOverdue
                      ? PdfColors.red800
                      : PdfColors.blue800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildCustomerBlock(InvoiceModel invoice) {
    final isPurchase = invoice.isPurchase;
    final partyLabel = isPurchase ? 'Bill From:' : 'Bill To:';
    final partyName = isPurchase ? invoice.vendorName : invoice.customerName;
    final phone = isPurchase ? '' : invoice.customerPhone;
    final address = isPurchase ? '' : invoice.customerAddress;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            partyLabel,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            partyName,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if (phone.isNotEmpty)
            pw.Text(phone, style: const pw.TextStyle(fontSize: 9)),
          if (address.isNotEmpty)
            pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildItemsTable(
    InvoiceModel invoice,
    BillingSettings bs,
    String sym,
  ) {
    final headers = ['#', 'Item', 'Qty', 'Price'];
    if (bs.enableDiscounts) headers.add('Disc%');
    if (bs.enableTax) headers.add('${bs.taxLabel}%');
    headers.add('Total');

    final data = <List<String>>[];
    for (var i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      final row = [
        '${i + 1}',
        item.productName,
        '${item.quantity} ${item.unit}',
        _fmt(item.unitPrice, sym),
      ];
      if (bs.enableDiscounts) {
        row.add(item.discountPercent > 0 ? '${item.discountPercent}%' : '-');
      }
      if (bs.enableTax) {
        row.add(item.taxRate > 0 ? '${item.taxRate}%' : '-');
      }
      row.add(_fmt(item.lineTotal, sym));
      data.add(row);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellHeight: 24,
      cellAlignments: {
        0: pw.Alignment.center,
        headers.length - 1: pw.Alignment.centerRight,
      },
      headerAlignments: {
        0: pw.Alignment.center,
        headers.length - 1: pw.Alignment.centerRight,
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  pw.Widget _buildTotals(InvoiceModel invoice, BillingSettings bs, String sym) {
    final rows = <pw.Widget>[
      _totalRow('Subtotal', _fmt(invoice.subtotal, sym)),
    ];
    if (bs.enableDiscounts && invoice.totalDiscount > 0) {
      rows.add(_totalRow('Discount', '- ${_fmt(invoice.totalDiscount, sym)}'));
    }
    if (bs.enableTax && invoice.totalTax > 0) {
      rows.add(_totalRow(bs.taxLabel, _fmt(invoice.totalTax, sym)));
    }
    rows.add(pw.Divider(thickness: 0.5));
    rows.add(
      _totalRow(
        'Grand Total',
        _fmt(invoice.grandTotal, sym),
        bold: true,
        size: 12,
      ),
    );
    if (bs.enablePaymentTracking) {
      rows.add(_totalRow('Amount Paid', _fmt(invoice.amountPaid, sym)));
      rows.add(
        _totalRow(
          'Amount Due',
          _fmt(invoice.amountDue, sym),
          bold: true,
          color: invoice.amountDue > 0 ? PdfColors.red700 : PdfColors.green700,
        ),
      );
    }

    return pw.Row(
      children: [
        pw.Spacer(),
        pw.SizedBox(width: 220, child: pw.Column(children: rows)),
      ],
    );
  }

  pw.Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
    double size = 10,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: size,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPaymentHistory(InvoiceModel invoice, String sym) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Payment History',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        ...invoice.payments.map(
          (p) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              children: [
                pw.Text(
                  _dateFormat.format(p.date),
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(width: 12),
                pw.Text(p.methodLabel, style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(width: 12),
                pw.Text(
                  _fmt(p.amount, sym),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (p.referenceNumber.isNotEmpty) ...[
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'Ref: ${p.referenceNumber}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildFooter(BillingSettings bs, pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
        if (bs.invoiceFooter.isNotEmpty)
          pw.Text(
            bs.invoiceFooter,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            textAlign: pw.TextAlign.center,
          ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey400),
        ),
      ],
    );
  }

  // ==================== THERMAL RECEIPT PDF ====================

  Future<ExportResult> generateReceiptPdf(
    InvoiceModel invoice,
    BillingSettings bs,
  ) async {
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final pdf = pw.Document(theme: theme);
    const receiptWidth = 80.0 * PdfPageFormat.mm;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(receiptWidth, double.infinity, marginAll: 8),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (bs.businessName.isNotEmpty)
              pw.Text(
                bs.businessName,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            if (bs.businessAddress.isNotEmpty)
              pw.Text(
                bs.businessAddress,
                style: const pw.TextStyle(fontSize: 7),
                textAlign: pw.TextAlign.center,
              ),
            if (bs.businessPhone.isNotEmpty)
              pw.Text(bs.businessPhone, style: const pw.TextStyle(fontSize: 7)),
            if (bs.taxId.isNotEmpty)
              pw.Text(
                '${bs.taxLabel}: ${bs.taxId}',
                style: const pw.TextStyle(fontSize: 7),
              ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${invoice.isPurchase ? "Bill" : "Invoice"}: ${invoice.invoiceNumber}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _dateFormat.format(invoice.invoiceDate),
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                '${invoice.isPurchase ? "Vendor" : "Customer"}: ${invoice.partyName}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            ...invoice.items.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      item.productName,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${item.quantity} x ${_fmt(item.unitPrice, sym)}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.Text(
                          _fmt(item.lineTotal, sym),
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  _fmt(invoice.subtotal, sym),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            if (invoice.totalDiscount > 0)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Discount', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                    '- ${_fmt(invoice.totalDiscount, sym)}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            if (invoice.totalTax > 0)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(bs.taxLabel, style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                    _fmt(invoice.totalTax, sym),
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            pw.Divider(thickness: 1),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _fmt(invoice.grandTotal, sym),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Paid', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  _fmt(invoice.amountPaid, sym),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Due',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _fmt(invoice.amountDue, sym),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5),
            if (bs.invoiceFooter.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  bs.invoiceFooter,
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Thank you!',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return ExportResult(
      'receipt_${invoice.invoiceNumber}_$timestamp.pdf',
      bytes,
    );
  }

  // ==================== CUSTOMER STATEMENT PDF ====================

  Future<ExportResult> generateCustomerStatement({
    required String customerName,
    required List<InvoiceModel> invoices,
    required DateTime startDate,
    required DateTime endDate,
    required BillingSettings bs,
  }) async {
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final pdf = pw.Document(theme: theme);

    final filtered =
        invoices
            .where(
              (i) =>
                  !i.isCancelled &&
                  !i.invoiceDate.isBefore(startDate) &&
                  !i.invoiceDate.isAfter(endDate.add(const Duration(days: 1))),
            )
            .toList()
          ..sort((a, b) => a.invoiceDate.compareTo(b.invoiceDate));

    double runningBalance = 0;
    final rows = <List<String>>[];
    for (final inv in filtered) {
      runningBalance += inv.amountDue;
      rows.add([
        _dateFormat.format(inv.invoiceDate),
        inv.invoiceNumber,
        inv.statusLabel,
        _fmt(inv.grandTotal, sym),
        _fmt(inv.amountPaid, sym),
        _fmt(inv.amountDue, sym),
        _fmt(runningBalance, sym),
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Text(
            'Customer Statement',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal,
            ),
          ),
          pw.SizedBox(height: 8),
          if (bs.businessName.isNotEmpty)
            pw.Text(
              bs.businessName,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Customer: $customerName',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Period: ${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Invoice #',
              'Status',
              'Total',
              'Paid',
              'Due',
              'Balance',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellHeight: 22,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  'Outstanding Balance: ${_fmt(runningBalance, sym)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
        footer: (context) => _buildFooter(bs, context),
      ),
    );

    final bytes = await pdf.save();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return ExportResult(
      'statement_${customerName.replaceAll(' ', '_')}_$timestamp.pdf',
      bytes,
    );
  }

  // ==================== VENDOR STATEMENT PDF ====================

  Future<ExportResult> generateVendorStatement({
    required String vendorName,
    required List<InvoiceModel> invoices,
    required DateTime startDate,
    required DateTime endDate,
    required BillingSettings bs,
  }) async {
    final sym = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final pdf = pw.Document(theme: theme);

    final filtered =
        invoices
            .where(
              (i) =>
                  !i.isCancelled &&
                  !i.invoiceDate.isBefore(startDate) &&
                  !i.invoiceDate.isAfter(endDate.add(const Duration(days: 1))),
            )
            .toList()
          ..sort((a, b) => a.invoiceDate.compareTo(b.invoiceDate));

    double runningBalance = 0;
    final rows = <List<String>>[];
    for (final inv in filtered) {
      runningBalance += inv.amountDue;
      rows.add([
        _dateFormat.format(inv.invoiceDate),
        inv.invoiceNumber,
        inv.statusLabel,
        _fmt(inv.grandTotal, sym),
        _fmt(inv.amountPaid, sym),
        _fmt(inv.amountDue, sym),
        _fmt(runningBalance, sym),
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Text(
            'Vendor Statement',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal,
            ),
          ),
          pw.SizedBox(height: 8),
          if (bs.businessName.isNotEmpty)
            pw.Text(
              bs.businessName,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Vendor: $vendorName',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Period: ${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Bill #',
              'Status',
              'Total',
              'Paid',
              'Due',
              'Balance',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellHeight: 22,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  'Outstanding Balance: ${_fmt(runningBalance, sym)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
        footer: (context) => _buildFooter(bs, context),
      ),
    );

    final bytes = await pdf.save();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return ExportResult(
      'vendor_statement_${vendorName.replaceAll(' ', '_')}_$timestamp.pdf',
      bytes,
    );
  }

  // ==================== PRINT / SHARE ====================

  Future<void> printInvoice(InvoiceModel invoice, BillingSettings bs) async {
    final result = await generateInvoicePdf(invoice, bs);
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(result.bytes),
    );
  }

  Future<void> shareInvoice(InvoiceModel invoice, BillingSettings bs) async {
    final result = await generateInvoicePdf(invoice, bs);
    await file_helper.saveAndShareFile(result.fileName, result.bytes);
  }

  Future<void> printReceipt(InvoiceModel invoice, BillingSettings bs) async {
    final result = await generateReceiptPdf(invoice, bs);
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(result.bytes),
    );
  }
}
