import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/product_model.dart';
import 'file_helper.dart' as file_helper;

/// Which barcode symbology a sheet is rendered in.
enum LabelSymbology { code128, ean13, qr, none }

/// A label grid: how many labels fit on a page and how big each one is.
class LabelLayout {
  const LabelLayout({
    required this.id,
    required this.name,
    required this.columns,
    required this.rows,
    required this.pageFormat,
    this.marginMm = 8,
    this.gutterMm = 3,
  });

  final String id;
  final String name;
  final int columns;
  final int rows;
  final PdfPageFormat pageFormat;
  final double marginMm;
  final double gutterMm;

  int get perPage => columns * rows;

  /// The presets offered in the designer. A4 rather than Letter first: this
  /// app's users are on A4 paper.
  static const LabelLayout a4Grid24 = LabelLayout(
    id: 'a4-24',
    name: 'A4 — 24 per sheet (3 x 8)',
    columns: 3,
    rows: 8,
    pageFormat: PdfPageFormat.a4,
  );

  static const LabelLayout a4Grid40 = LabelLayout(
    id: 'a4-40',
    name: 'A4 — 40 per sheet (4 x 10)',
    columns: 4,
    rows: 10,
    pageFormat: PdfPageFormat.a4,
  );

  static const LabelLayout a4Grid12 = LabelLayout(
    id: 'a4-12',
    name: 'A4 — 12 per sheet (2 x 6)',
    columns: 2,
    rows: 6,
    pageFormat: PdfPageFormat.a4,
  );

  static const LabelLayout shelfStrip = LabelLayout(
    id: 'shelf',
    name: 'A4 — 8 shelf strips (1 x 8)',
    columns: 1,
    rows: 8,
    pageFormat: PdfPageFormat.a4,
    marginMm: 10,
    gutterMm: 4,
  );

  static const List<LabelLayout> presets = [
    a4Grid24,
    a4Grid40,
    a4Grid12,
    shelfStrip,
  ];

  static LabelLayout byId(String id) =>
      presets.firstWhere((l) => l.id == id, orElse: () => a4Grid24);
}

/// One product and how many labels of it to print.
class LabelRequest {
  const LabelRequest({required this.product, this.copies = 1});

  final ProductModel product;
  final int copies;

  LabelRequest copyWith({int? copies}) =>
      LabelRequest(product: product, copies: copies ?? this.copies);
}

/// What goes on the label, beyond the name.
class LabelOptions {
  const LabelOptions({
    this.layout = LabelLayout.a4Grid24,
    this.symbology = LabelSymbology.code128,
    this.showPrice = true,
    this.showSku = true,
    this.showCompanyName = false,
    this.showSize = false,
    this.currencySymbol = '',
    this.companyName = '',
  });

  final LabelLayout layout;
  final LabelSymbology symbology;
  final bool showPrice;
  final bool showSku;
  final bool showCompanyName;
  final bool showSize;
  final String currencySymbol;
  final String companyName;

  LabelOptions copyWith({
    LabelLayout? layout,
    LabelSymbology? symbology,
    bool? showPrice,
    bool? showSku,
    bool? showCompanyName,
    bool? showSize,
    String? currencySymbol,
    String? companyName,
  }) => LabelOptions(
    layout: layout ?? this.layout,
    symbology: symbology ?? this.symbology,
    showPrice: showPrice ?? this.showPrice,
    showSku: showSku ?? this.showSku,
    showCompanyName: showCompanyName ?? this.showCompanyName,
    showSize: showSize ?? this.showSize,
    currencySymbol: currencySymbol ?? this.currencySymbol,
    companyName: companyName ?? this.companyName,
  );
}

/// Builds printable barcode and shelf-label sheets.
///
/// The app has been able to scan barcodes since long before it could produce
/// one, which left every workspace generating labels somewhere else and pasting
/// codes back in by hand.
class LabelPdfService {
  static pw.Font? _font;

  static Future<pw.Font> _loadFont() async {
    if (_font != null) return _font!;
    try {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      _font = pw.Font.ttf(data);
    } catch (_) {
      // Bundled font missing (or unreadable on web) — Helvetica keeps the
      // sheet printable rather than failing the whole export.
      _font = pw.Font.helvetica();
    }
    return _font!;
  }

  /// The total number of labels [requests] will render.
  static int labelCount(List<LabelRequest> requests) =>
      requests.fold(0, (acc, r) => acc + (r.copies > 0 ? r.copies : 0));

  /// How many pages that fills at [layout].
  static int pageCount(List<LabelRequest> requests, LabelLayout layout) {
    final labels = labelCount(requests);
    if (labels == 0 || layout.perPage == 0) return 0;
    return (labels + layout.perPage - 1) ~/ layout.perPage;
  }

  /// The barcode value for [product], or null when there is nothing to encode.
  ///
  /// Falls back to the product id so a catalog that never filled in barcodes
  /// still gets a scannable, unique label rather than a blank box.
  static String? codeFor(ProductModel product, LabelSymbology symbology) {
    if (symbology == LabelSymbology.none) return null;
    final raw = product.barcode.trim();
    final value = raw.isNotEmpty ? raw : product.id;
    return value.isEmpty ? null : value;
  }

  static pw.Barcode _barcodeFor(LabelSymbology symbology, String value) {
    switch (symbology) {
      case LabelSymbology.qr:
        return pw.Barcode.qrCode();
      case LabelSymbology.ean13:
        return RegExp(r'^\d{12,13}$').hasMatch(value)
            ? pw.Barcode.ean13()
            : pw.Barcode.code128();
      case LabelSymbology.code128:
      case LabelSymbology.none:
        return pw.Barcode.code128();
    }
  }

  static Future<Uint8List> build({
    required List<LabelRequest> requests,
    required LabelOptions options,
  }) async {
    final font = await _loadFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document(theme: theme);
    final layout = options.layout;

    // Flattened once so page slicing is a simple range: copies are just
    // repeats, and expanding them lazily per page would make the last page's
    // arithmetic needlessly fiddly.
    final flat = <ProductModel>[
      for (final request in requests)
        for (var i = 0; i < request.copies; i++) request.product,
    ];
    if (flat.isEmpty) return doc.save();

    final perPage = layout.perPage;
    final pages = (flat.length + perPage - 1) ~/ perPage;

    for (var page = 0; page < pages; page++) {
      final slice = flat.sublist(
        page * perPage,
        ((page + 1) * perPage).clamp(0, flat.length),
      );
      doc.addPage(
        pw.Page(
          pageFormat: layout.pageFormat.copyWith(
            marginLeft: layout.marginMm * PdfPageFormat.mm,
            marginRight: layout.marginMm * PdfPageFormat.mm,
            marginTop: layout.marginMm * PdfPageFormat.mm,
            marginBottom: layout.marginMm * PdfPageFormat.mm,
          ),
          build: (context) => _buildGrid(slice, options),
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _buildGrid(
    List<ProductModel> products,
    LabelOptions options,
  ) {
    final layout = options.layout;
    final gutter = layout.gutterMm * PdfPageFormat.mm;
    final rows = <pw.Widget>[];

    for (var r = 0; r < layout.rows; r++) {
      final cells = <pw.Widget>[];
      for (var c = 0; c < layout.columns; c++) {
        final index = r * layout.columns + c;
        cells.add(
          pw.Expanded(
            child: index < products.length
                ? _buildLabel(products[index], options)
                : pw.SizedBox(),
          ),
        );
        if (c < layout.columns - 1) cells.add(pw.SizedBox(width: gutter));
      }
      rows.add(pw.Expanded(child: pw.Row(children: cells)));
      if (r < layout.rows - 1) rows.add(pw.SizedBox(height: gutter));
    }

    return pw.Column(children: rows);
  }

  static pw.Widget _buildLabel(ProductModel product, LabelOptions options) {
    final code = codeFor(product, options.symbology);
    final priceText = options.currencySymbol.isEmpty
        ? product.sellingPrice.toStringAsFixed(2)
        : '${options.currencySymbol}${product.sellingPrice.toStringAsFixed(2)}';

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (options.showCompanyName && options.companyName.isNotEmpty)
            pw.Text(
              options.companyName,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700),
            ),
          pw.Text(
            product.name,
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
          if (options.showSize && product.size.isNotEmpty)
            pw.Text(
              product.size,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700),
            ),
          if (code != null) ...[
            pw.SizedBox(height: 2),
            pw.Expanded(
              child: pw.BarcodeWidget(
                barcode: _barcodeFor(options.symbology, code),
                data: code,
                drawText: false,
                color: PdfColors.black,
              ),
            ),
          ],
          if (options.showSku && code != null)
            pw.Text(
              code,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: const pw.TextStyle(fontSize: 5, letterSpacing: 0.4),
            ),
          if (options.showPrice)
            pw.Text(
              priceText,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
        ],
      ),
    );
  }

  /// Opens the platform print dialog with the sheet.
  static Future<void> printSheet({
    required List<LabelRequest> requests,
    required LabelOptions options,
  }) async {
    final bytes = await build(requests: requests, options: options);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'labels_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  /// Saves/shares the sheet as a file, for workflows with no printer attached.
  static Future<void> shareSheet({
    required List<LabelRequest> requests,
    required LabelOptions options,
  }) async {
    final bytes = await build(requests: requests, options: options);
    await file_helper.saveAndShareFile(
      'labels_${DateTime.now().millisecondsSinceEpoch}.pdf',
      bytes,
    );
  }
}
