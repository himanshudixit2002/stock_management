import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../models/stock_transaction_model.dart';
import 'file_helper.dart' as file_helper;

class ExportResult {
  final String fileName;
  final List<int> bytes;
  ExportResult(this.fileName, this.bytes);
}

class ExcelService {
  // ==================== EXPORT ====================

  Future<ExportResult> exportProducts(
    List<ProductModel> products,
    List<CategoryModel> categories,
  ) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['Products'];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#00897B'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = [
      'S.No', 'Product Name', 'Category', 'Subcategory', 'Locations',
      'Quantity', 'Unit', 'Cost Price', 'Selling Price', 'Status', 'Description',
      'Preferred Vendor',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (int row = 0; row < products.length; row++) {
      final product = products[row];
      final dataRow = row + 1;
      final locStr = product.locationQuantities.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: dataRow)).value = IntCellValue(row + 1);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: dataRow)).value = TextCellValue(product.name);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: dataRow)).value = TextCellValue(product.categoryName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: dataRow)).value = TextCellValue(product.subcategoryName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: dataRow)).value = TextCellValue(locStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: dataRow)).value = IntCellValue(product.quantity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: dataRow)).value = TextCellValue(product.unit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: dataRow)).value = DoubleCellValue(product.costPrice);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: dataRow)).value = DoubleCellValue(product.sellingPrice);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: dataRow)).value = TextCellValue(product.stockStatus);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: dataRow)).value = TextCellValue(product.description);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: dataRow)).value = TextCellValue(product.preferredVendorName);
    }

    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 25);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 18);
    sheet.setColumnWidth(4, 30);
    sheet.setColumnWidth(5, 10);
    sheet.setColumnWidth(6, 8);
    sheet.setColumnWidth(7, 12);
    sheet.setColumnWidth(8, 12);
    sheet.setColumnWidth(9, 12);
    sheet.setColumnWidth(10, 30);
    sheet.setColumnWidth(11, 20);

    final fileBytes = excel.save();
    if (fileBytes != null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return ExportResult('stock_report_$timestamp.xlsx', fileBytes);
    }
    throw Exception('Failed to generate Excel file');
  }

  Future<void> saveAndShare(ExportResult result) async {
    await file_helper.saveAndShareFile(result.fileName, result.bytes);
  }

  // ==================== IMPORT ====================

  Future<List<Map<String, dynamic>>> parseExcelFile(String filePath) async {
    final bytes = await file_helper.readFileBytes(filePath);
    return parseExcelBytes(bytes);
  }

  List<Map<String, dynamic>> parseExcelBytes(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final List<Map<String, dynamic>> products = [];

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];

    if (sheet == null || sheet.rows.isEmpty) {
      throw Exception('The Excel file is empty');
    }

    final headerRow = sheet.rows.first;
    final Map<String, int> columnMap = {};

    for (int i = 0; i < headerRow.length; i++) {
      final cellValue =
          headerRow[i]?.value?.toString().trim().toLowerCase() ?? '';
      if (cellValue.contains('name') && !cellValue.contains('category')) {
        columnMap['name'] = i;
      } else if (cellValue == 'category') {
        columnMap['category'] = i;
      } else if (cellValue.contains('subcategory')) {
        columnMap['subcategory'] = i;
      } else if (cellValue.contains('category')) {
        columnMap['category'] = i;
      } else if (cellValue.contains('quantity') ||
          cellValue.contains('qty') ||
          cellValue.contains('stock')) {
        columnMap['quantity'] = i;
      } else if (cellValue.contains('unit')) {
        columnMap['unit'] = i;
      } else if (cellValue.contains('description') ||
          cellValue.contains('desc')) {
        columnMap['description'] = i;
      } else if (cellValue.contains('cost') && cellValue.contains('price')) {
        columnMap['costPrice'] = i;
      } else if (cellValue.contains('selling') && cellValue.contains('price')) {
        columnMap['sellingPrice'] = i;
      }
    }

    for (int rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];

      if (row.every(
        (cell) =>
            cell?.value == null || cell!.value.toString().trim().isEmpty,
      )) {
        continue;
      }

      final productData = <String, dynamic>{};
      productData['name'] = _getCellString(row, columnMap['name']);
      productData['category'] = _getCellString(row, columnMap['category']);
      productData['quantity'] = _getCellInt(row, columnMap['quantity']);
      productData['unit'] =
          _getCellString(row, columnMap['unit'], defaultValue: 'pcs');
      productData['description'] =
          _getCellString(row, columnMap['description']);
      productData['costPrice'] = _getCellDouble(row, columnMap['costPrice']);
      productData['sellingPrice'] = _getCellDouble(row, columnMap['sellingPrice']);

      if (productData['name'].toString().isNotEmpty) {
        products.add(productData);
      }
    }

    return products;
  }

  List<ProductModel> convertToProducts(
    List<Map<String, dynamic>> data,
    Map<String, CategoryModel> categoryMap,
  ) {
    final now = DateTime.now();
    return data.map((item) {
      final categoryName = item['category']?.toString() ?? '';
      final category = categoryMap[categoryName.toLowerCase()];

      return ProductModel(
        id: '',
        name: item['name']?.toString() ?? '',
        categoryId: category?.id ?? '',
        categoryName: category?.name ?? categoryName,
        quantity: (item['quantity'] as num?)?.toInt() ?? 0,
        unit: item['unit']?.toString() ?? 'pcs',
        description: item['description']?.toString() ?? '',
        costPrice: (item['costPrice'] as num?)?.toDouble() ?? 0,
        sellingPrice: (item['sellingPrice'] as num?)?.toDouble() ?? 0,
        createdAt: now,
        updatedAt: now,
      );
    }).toList();
  }

  String _getCellString(
    List<Data?> row,
    int? colIndex, {
    String defaultValue = '',
  }) {
    if (colIndex == null || colIndex >= row.length) return defaultValue;
    return row[colIndex]?.value?.toString().trim() ?? defaultValue;
  }

  int _getCellInt(List<Data?> row, int? colIndex) {
    if (colIndex == null || colIndex >= row.length) return 0;
    final value = row[colIndex]?.value;
    if (value == null) return 0;
    return int.tryParse(value.toString().trim().split('.').first) ?? 0;
  }

  double _getCellDouble(List<Data?> row, int? colIndex) {
    if (colIndex == null || colIndex >= row.length) return 0;
    final value = row[colIndex]?.value;
    if (value == null) return 0;
    return double.tryParse(value.toString().trim()) ?? 0;
  }

  // ==================== MULTI-SHEET EXCEL EXPORT ====================

  Future<ExportResult> exportFullReport({
    required List<ProductModel> products,
    required List<StockTransactionModel> transactions,
    required Map<String, int> productCount,
    required Map<String, int> lowStock,
    required Map<String, int> outOfStock,
    required int totalProducts,
    required int lowStockCount,
    required int outOfStockCount,
    required double healthScore,
  }) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#00897B'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final sectionStyle = CellStyle(
      bold: true,
      fontSize: 13,
    );

    // ---- Sheet 1: Summary ----
    final summary = excel['Summary'];
    void addSummaryRow(Sheet s, int row, String label, String value) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(label);
      s.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = CellStyle(bold: true);
      s.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(value);
    }

    final titleCell = summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titleCell.value = TextCellValue('Inventory Summary Report');
    titleCell.cellStyle = sectionStyle;

    summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}');

    addSummaryRow(summary, 3, 'Inventory Health Score', '${healthScore.toInt()}/100');
    addSummaryRow(summary, 4, 'Total Products', '$totalProducts');
    addSummaryRow(summary, 5, 'Low Stock Items', '$lowStockCount');
    addSummaryRow(summary, 6, 'Out of Stock Items', '$outOfStockCount');
    addSummaryRow(summary, 7, 'Total Transactions', '${transactions.length}');

    summary.setColumnWidth(0, 25);
    summary.setColumnWidth(1, 20);

    // ---- Sheet 2: Products ----
    final prodSheet = excel['Products'];
    final prodHeaders = [
      'S.No', 'Product Name', 'Category', 'Locations',
      'Quantity', 'Unit', 'Status', 'Description',
    ];
    for (int i = 0; i < prodHeaders.length; i++) {
      final cell = prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(prodHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    for (int row = 0; row < products.length; row++) {
      final p = products[row];
      final r = row + 1;
      final locStr = p.locationQuantities.entries.map((e) => '${e.key}:${e.value}').join(', ');
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = IntCellValue(row + 1);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(p.name);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(p.categoryName);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(locStr);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = IntCellValue(p.quantity);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = TextCellValue(p.unit);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue(p.stockStatus);
      prodSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = TextCellValue(p.description);
    }
    prodSheet.setColumnWidth(1, 25);
    prodSheet.setColumnWidth(2, 18);
    prodSheet.setColumnWidth(3, 30);
    prodSheet.setColumnWidth(7, 30);

    // ---- Sheet 3: Transactions ----
    final txnSheet = excel['Transactions'];
    final txnHeaders = ['S.No', 'Date', 'Product Name', 'Type', 'Location', 'Quantity', 'User', 'Vendor', 'Reason'];
    for (int i = 0; i < txnHeaders.length; i++) {
      final cell = txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(txnHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    for (int row = 0; row < transactions.length; row++) {
      final t = transactions[row];
      final r = row + 1;
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = IntCellValue(row + 1);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(dateFormat.format(t.date));
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(t.productName);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(t.typeLabel);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(t.location);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = IntCellValue(t.quantity);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue(t.userName);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = TextCellValue(t.vendorName);
      txnSheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value = TextCellValue(t.reason);
    }
    txnSheet.setColumnWidth(1, 18);
    txnSheet.setColumnWidth(2, 25);
    txnSheet.setColumnWidth(4, 18);
    txnSheet.setColumnWidth(7, 25);

    // ---- Sheet 4: Categories ----
    final catSheet = excel['Categories'];
    final catHeaders = ['Category', 'Product Count', 'Low Stock', 'Out of Stock'];
    for (int i = 0; i < catHeaders.length; i++) {
      final cell = catSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(catHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    int catRow = 1;
    for (final cat in productCount.keys) {
      catSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: catRow)).value = TextCellValue(cat);
      catSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: catRow)).value = IntCellValue(productCount[cat] ?? 0);
      catSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: catRow)).value = IntCellValue(lowStock[cat] ?? 0);
      catSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: catRow)).value = IntCellValue(outOfStock[cat] ?? 0);
      catRow++;
    }
    catSheet.setColumnWidth(0, 20);

    final fileBytes = excel.save();
    if (fileBytes != null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return ExportResult('full_report_$timestamp.xlsx', fileBytes);
    }
    throw Exception('Failed to generate Excel file');
  }

  Future<ExportResult> generateImportTemplate() async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['Products'];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#00897B'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = [
      'Product Name', 'Category', 'Quantity', 'Unit', 'Description',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    final exampleData = [
      'Example Product', 'General', '50', 'pcs', 'Description here',
    ];
    for (int i = 0; i < exampleData.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value =
          TextCellValue(exampleData[i]);
    }

    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(4, 25);

    final fileBytes = excel.save();
    if (fileBytes != null) {
      return ExportResult('import_template.xlsx', fileBytes);
    }
    throw Exception('Failed to generate template file');
  }

  // ==================== CSV EXPORT ====================

  Future<ExportResult> exportProductsToCsv(List<ProductModel> products) async {
    final rows = <List<dynamic>>[
      ['S.No', 'Product Name', 'Category', 'Subcategory', 'Locations', 'Quantity', 'Unit', 'Cost Price', 'Selling Price', 'Status', 'Description', 'Preferred Vendor'],
    ];

    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final locStr = p.locationQuantities.entries.map((e) => '${e.key}:${e.value}').join('; ');
      rows.add([
        i + 1, p.name, p.categoryName, p.subcategoryName, locStr, p.quantity, p.unit, p.costPrice, p.sellingPrice, p.stockStatus, p.description, p.preferredVendorName,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ExportResult('products_$timestamp.csv', utf8.encode(csv));
  }

  Future<ExportResult> exportTransactionsToCsv(
      List<StockTransactionModel> transactions) async {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final rows = <List<dynamic>>[
      ['S.No', 'Date', 'Product Name', 'Type', 'Location', 'Quantity', 'User', 'Vendor', 'Reason'],
    ];

    for (int i = 0; i < transactions.length; i++) {
      final t = transactions[i];
      rows.add([
        i + 1, dateFormat.format(t.date), t.productName, t.typeLabel, t.location, t.quantity, t.userName, t.vendorName, t.reason,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ExportResult('transactions_$timestamp.csv', utf8.encode(csv));
  }

  Future<ExportResult> exportCategoryReportToCsv({
    required Map<String, int> productCount,
    required Map<String, int> lowStock,
    required Map<String, int> outOfStock,
  }) async {
    final rows = <List<dynamic>>[
      ['Category', 'Product Count', 'Low Stock Count', 'Out of Stock Count'],
    ];

    for (final cat in productCount.keys) {
      rows.add([
        cat, productCount[cat] ?? 0, lowStock[cat] ?? 0, outOfStock[cat] ?? 0,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ExportResult('category_report_$timestamp.csv', utf8.encode(csv));
  }

  Future<ExportResult> exportFullReportToCsv({
    required List<ProductModel> products,
    required List<StockTransactionModel> transactions,
    required Map<String, int> productCount,
    required Map<String, int> lowStock,
    required Map<String, int> outOfStock,
    required int totalProducts,
    required int lowStockCount,
    required int outOfStockCount,
  }) async {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final rows = <List<dynamic>>[];

    rows.add(['=== INVENTORY SUMMARY ===']);
    rows.add(['Total Products', totalProducts]);
    rows.add(['Low Stock Items', lowStockCount]);
    rows.add(['Out of Stock Items', outOfStockCount]);
    rows.add([]);

    rows.add(['=== CATEGORY BREAKDOWN ===']);
    rows.add(['Category', 'Product Count', 'Low Stock', 'Out of Stock']);
    for (final cat in productCount.keys) {
      rows.add([cat, productCount[cat] ?? 0, lowStock[cat] ?? 0, outOfStock[cat] ?? 0]);
    }
    rows.add([]);

    rows.add(['=== PRODUCTS ===']);
    rows.add(['S.No', 'Product Name', 'Category', 'Subcategory', 'Locations', 'Quantity', 'Unit', 'Cost Price', 'Selling Price', 'Status', 'Preferred Vendor']);
    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final locStr = p.locationQuantities.entries.map((e) => '${e.key}:${e.value}').join('; ');
      rows.add([i + 1, p.name, p.categoryName, p.subcategoryName, locStr, p.quantity, p.unit, p.costPrice, p.sellingPrice, p.stockStatus, p.preferredVendorName]);
    }
    rows.add([]);

    rows.add(['=== TRANSACTIONS ===']);
    rows.add(['S.No', 'Date', 'Product Name', 'Type', 'Location', 'Quantity', 'User', 'Vendor', 'Reason']);
    for (int i = 0; i < transactions.length; i++) {
      final t = transactions[i];
      rows.add([i + 1, dateFormat.format(t.date), t.productName, t.typeLabel, t.location, t.quantity, t.userName, t.vendorName, t.reason]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ExportResult('full_report_$timestamp.csv', utf8.encode(csv));
  }

  // ==================== CSV IMPORT ====================

  Future<List<Map<String, dynamic>>> parseCsvFile(String filePath) async {
    final bytes = await file_helper.readFileBytes(filePath);
    return parseCsvBytes(bytes);
  }

  List<Map<String, dynamic>> parseCsvBytes(Uint8List bytes) {
    final csvString = utf8.decode(bytes);
    final rows = const CsvToListConverter().convert(csvString);

    if (rows.isEmpty) {
      throw Exception('The CSV file is empty');
    }

    final List<Map<String, dynamic>> products = [];

    final headerRow = rows.first;
    final Map<String, int> columnMap = {};

    for (int i = 0; i < headerRow.length; i++) {
      final cellValue = headerRow[i].toString().trim().toLowerCase();
      if (cellValue.contains('name') && !cellValue.contains('category')) {
        columnMap['name'] = i;
      } else if (cellValue == 'category') {
        columnMap['category'] = i;
      } else if (cellValue.contains('subcategory')) {
        columnMap['subcategory'] = i;
      } else if (cellValue.contains('category')) {
        columnMap['category'] = i;
      } else if (cellValue.contains('quantity') ||
          cellValue.contains('qty') ||
          cellValue.contains('stock')) {
        columnMap['quantity'] = i;
      } else if (cellValue.contains('unit')) {
        columnMap['unit'] = i;
      } else if (cellValue.contains('description') ||
          cellValue.contains('desc')) {
        columnMap['description'] = i;
      } else if (cellValue.contains('cost') && cellValue.contains('price')) {
        columnMap['costPrice'] = i;
      } else if (cellValue.contains('selling') && cellValue.contains('price')) {
        columnMap['sellingPrice'] = i;
      }
    }

    for (int rowIdx = 1; rowIdx < rows.length; rowIdx++) {
      final row = rows[rowIdx];
      if (row.every(
          (cell) => cell == null || cell.toString().trim().isEmpty)) {
        continue;
      }

      final productData = <String, dynamic>{};
      productData['name'] = _getCsvCellString(row, columnMap['name']);
      productData['category'] = _getCsvCellString(row, columnMap['category']);
      productData['quantity'] = _getCsvCellInt(row, columnMap['quantity']);
      productData['unit'] =
          _getCsvCellString(row, columnMap['unit'], defaultValue: 'pcs');
      productData['description'] =
          _getCsvCellString(row, columnMap['description']);
      productData['costPrice'] = _getCsvCellDouble(row, columnMap['costPrice']);
      productData['sellingPrice'] = _getCsvCellDouble(row, columnMap['sellingPrice']);

      if (productData['name'].toString().isNotEmpty) {
        products.add(productData);
      }
    }

    return products;
  }

  String _getCsvCellString(List<dynamic> row, int? colIndex,
      {String defaultValue = ''}) {
    if (colIndex == null || colIndex >= row.length) return defaultValue;
    return row[colIndex]?.toString().trim() ?? defaultValue;
  }

  int _getCsvCellInt(List<dynamic> row, int? colIndex) {
    if (colIndex == null || colIndex >= row.length) return 0;
    final value = row[colIndex];
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim().split('.').first) ?? 0;
  }

  double _getCsvCellDouble(List<dynamic> row, int? colIndex) {
    if (colIndex == null || colIndex >= row.length) return 0;
    final value = row[colIndex];
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? 0;
  }
}
