import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../models/vendor_model.dart';
import '../models/stock_transaction_model.dart';
import 'file_helper.dart' as file_helper;

class ExportResult {
  final String fileName;
  final List<int> bytes;
  ExportResult(this.fileName, this.bytes);
}

class ParseResult {
  final List<Map<String, dynamic>> data;
  final int skippedRows;
  ParseResult(this.data, this.skippedRows);
}

class ExcelService {
  // ==================== EXPORT ====================

  Future<ExportResult> exportProducts(
    List<ProductModel> products,
    List<CategoryModel> categories,
  ) async {
    final excel = Excel.createExcel();
    final sheet =
        excel[excel.tables.keys.first]; // use default sheet, rename after

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#00897B'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = [
      'S.No',
      'Product Name',
      'Category',
      'Company',
      'Size',
      'Barcode',
      'Locations',
      'Quantity',
      'Unit',
      'Cost Price',
      'Selling Price',
      'Low Stock Threshold',
      'Status',
      'Description',
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
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: dataRow)).value = TextCellValue(product.company);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: dataRow)).value = TextCellValue(product.size);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: dataRow)).value = TextCellValue(product.barcode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: dataRow)).value = TextCellValue(locStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: dataRow)).value = IntCellValue(product.quantity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: dataRow)).value = TextCellValue(product.unit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: dataRow)).value = DoubleCellValue(product.costPrice);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: dataRow)).value = DoubleCellValue(product.sellingPrice);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: dataRow)).value = IntCellValue(product.lowStockThreshold);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: dataRow)).value = TextCellValue(product.stockStatus);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: dataRow)).value = TextCellValue(product.description);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: dataRow)).value = TextCellValue(product.preferredVendorName);
    }

    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 25);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 18);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 18);
    sheet.setColumnWidth(6, 30);
    sheet.setColumnWidth(7, 10);
    sheet.setColumnWidth(8, 8);
    sheet.setColumnWidth(9, 12);
    sheet.setColumnWidth(10, 12);
    sheet.setColumnWidth(11, 18);
    sheet.setColumnWidth(12, 12);
    sheet.setColumnWidth(13, 30);
    sheet.setColumnWidth(14, 20);

    excel.rename(excel.tables.keys.first, 'Products');
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

  // ==================== EXPORT FOR UPDATE ====================

  Future<ExportResult> exportProductsForUpdate(
    List<ProductModel> products,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.tables.keys.first];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final idHeaderStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#B71C1C'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = [
      'ID',
      'Product Name',
      'Category',
      'Company',
      'Size',
      'Barcode',
      'Locations',
      'Quantity',
      'Unit',
      'Cost Price',
      'Selling Price',
      'Low Stock Threshold',
      'Description',
      'Preferred Vendor',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = i == 0 ? idHeaderStyle : headerStyle;
    }

    for (int row = 0; row < products.length; row++) {
      final product = products[row];
      final dataRow = row + 1;
      final locStr = product.locationQuantities.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: dataRow)).value = TextCellValue(product.id);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: dataRow)).value = TextCellValue(product.name);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: dataRow)).value = TextCellValue(product.categoryName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: dataRow)).value = TextCellValue(product.company);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: dataRow)).value = TextCellValue(product.size);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: dataRow)).value = TextCellValue(product.barcode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: dataRow)).value = TextCellValue(locStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: dataRow)).value = IntCellValue(product.quantity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: dataRow)).value = TextCellValue(product.unit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: dataRow)).value = DoubleCellValue(product.costPrice);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: dataRow)).value = DoubleCellValue(product.sellingPrice);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: dataRow)).value = IntCellValue(product.lowStockThreshold);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: dataRow)).value = TextCellValue(product.description);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: dataRow)).value = TextCellValue(product.preferredVendorName);
    }

    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 25);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 18);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 18);
    sheet.setColumnWidth(6, 30);
    sheet.setColumnWidth(7, 10);
    sheet.setColumnWidth(8, 8);
    sheet.setColumnWidth(9, 12);
    sheet.setColumnWidth(10, 12);
    sheet.setColumnWidth(11, 18);
    sheet.setColumnWidth(12, 30);
    sheet.setColumnWidth(13, 20);

    excel.rename(excel.tables.keys.first, 'Products');
    final fileBytes = excel.save();
    if (fileBytes != null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return ExportResult('products_for_update_$timestamp.xlsx', fileBytes);
    }
    throw Exception('Failed to generate Excel file');
  }

  // ==================== PARSE FOR UPDATE ====================

  ParseResult parseForUpdate(Uint8List bytes) {
    late final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      rethrow;
    }
    final List<Map<String, dynamic>> products = [];

    if (excel.tables.isEmpty) {
      throw Exception('The Excel file has no sheets');
    }

    final sheetName = excel.tables.containsKey('Products')
        ? 'Products'
        : excel.tables.keys.first;
    final sheet = excel.tables[sheetName];

    if (sheet == null || sheet.rows.isEmpty) {
      throw Exception('The Excel file is empty');
    }
    if (sheet.rows.length < 2) {
      throw Exception('The file has headers but no data rows');
    }

    final headerRow = sheet.rows.first;
    final Map<String, int> columnMap = {};

    for (int i = 0; i < headerRow.length; i++) {
      final cellValue =
          headerRow[i]?.value?.toString().trim().toLowerCase() ?? '';
      if (cellValue == 'id') {
        columnMap['id'] = i;
      } else if (cellValue.contains('name') &&
          !cellValue.contains('category') &&
          !cellValue.contains('company')) {
        columnMap['name'] = i;
      } else if (cellValue.contains('category')) {
        columnMap['category'] = i;
      } else if (cellValue.contains('company') ||
          cellValue.contains('brand')) {
        columnMap['company'] = i;
      } else if (cellValue == 'size') {
        columnMap['size'] = i;
      } else if (cellValue.contains('location')) {
        columnMap['locations'] = i;
      } else if (cellValue.contains('threshold') ||
          cellValue.contains('low stock')) {
        columnMap['lowStockThreshold'] = i;
      } else if (cellValue.contains('quantity') ||
          cellValue.contains('qty') ||
          cellValue == 'stock') {
        columnMap['quantity'] = i;
      } else if (cellValue.contains('unit')) {
        columnMap['unit'] = i;
      } else if (cellValue.contains('description') ||
          cellValue.contains('desc')) {
        columnMap['description'] = i;
      } else if (cellValue.contains('cost') && cellValue.contains('price')) {
        columnMap['costPrice'] = i;
      } else if (cellValue.contains('selling') &&
          cellValue.contains('price')) {
        columnMap['sellingPrice'] = i;
      } else if (cellValue.contains('vendor') ||
          cellValue.contains('preferred vendor')) {
        columnMap['preferredVendor'] = i;
      } else if (cellValue == 'barcode' || cellValue.contains('barcode')) {
        columnMap['barcode'] = i;
      }
    }

    int skippedNoName = 0;

    for (int rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];

      if (row.every(
        (cell) =>
            cell?.value == null || cell!.value.toString().trim().isEmpty,
      )) {
        continue;
      }

      final productData = <String, dynamic>{};
      productData['id'] = _getCellString(row, columnMap['id']);
      productData['name'] = _getCellString(row, columnMap['name']);
      productData['category'] = _getCellString(row, columnMap['category']);
      productData['company'] = _getCellString(row, columnMap['company']);
      productData['size'] = _getCellString(row, columnMap['size']);
      productData['barcode'] = _getCellString(row, columnMap['barcode']);
      productData['locations'] = _getCellString(row, columnMap['locations']);
      productData['quantity'] = _getCellInt(row, columnMap['quantity']);
      productData['unit'] = _getCellString(
        row,
        columnMap['unit'],
        defaultValue: 'pcs',
      );
      productData['description'] = _getCellString(
        row,
        columnMap['description'],
      );
      productData['costPrice'] = _getCellDouble(row, columnMap['costPrice']);
      productData['sellingPrice'] = _getCellDouble(
        row,
        columnMap['sellingPrice'],
      );
      productData['lowStockThreshold'] = _getCellInt(
        row,
        columnMap['lowStockThreshold'],
      );
      productData['preferredVendor'] = _getCellString(
        row,
        columnMap['preferredVendor'],
      );
      productData['barcode'] = _getCellString(row, columnMap['barcode']);

      if (productData['name'].toString().isNotEmpty) {
        products.add(productData);
      } else {
        skippedNoName++;
      }
    }

    return ParseResult(products, skippedNoName);
  }

  // ==================== DIFF FOR UPDATE ====================

  List<ProductUpdateDiff> diffProducts(
    List<Map<String, dynamic>> parsedRows,
    List<ProductModel> currentProducts,
    Map<String, CategoryModel> categoryMap,
    Map<String, VendorModel> vendorMap,
  ) {
    final productMap = <String, ProductModel>{};
    final barcodeIndex = <String, ProductModel>{};
    final compositeIdx = <String, ProductModel>{};
    for (final p in currentProducts) {
      productMap[p.id] = p;
      if (p.barcode.isNotEmpty) {
        barcodeIndex.putIfAbsent(p.barcode.trim().toLowerCase(), () => p);
      }
      final key = compositeKey(p.name, p.categoryName, p.company, p.size);
      if (key != '|||') {
        compositeIdx[key] = p;
      }
    }

    final diffs = <ProductUpdateDiff>[];
    for (final row in parsedRows) {
      var id = row['id']?.toString().trim() ?? '';
      final name = row['name']?.toString().trim() ?? '';

      // If ID is empty or not found, try to match by barcode or composite key
      if (id.isEmpty || !productMap.containsKey(id)) {
        ProductModel? match;
        final barcode = row['barcode']?.toString().trim() ?? '';
        if (barcode.isNotEmpty) {
          match = barcodeIndex[barcode.toLowerCase()];
        }
        if (match == null && name.isNotEmpty) {
          final cat = row['category']?.toString().trim() ?? '';
          final company = row['company']?.toString().trim() ?? '';
          final size = row['size']?.toString().trim() ?? '';
          final key = compositeKey(name, cat, company, size);
          if (key != '|||') {
            match = compositeIdx[key];
          }
        }

        if (match != null) {
          id = match.id;
          row['id'] = id;
        } else {
          diffs.add(ProductUpdateDiff(
            productId: id,
            productName: name,
            status: id.isEmpty
                ? UpdateStatus.newProduct
                : UpdateStatus.error,
            errorMessage: id.isNotEmpty && !productMap.containsKey(id)
                ? 'Product ID not found in database'
                : null,
            fieldChanges: [],
            parsedData: row,
          ));
          continue;
        }
      }

      final existing = productMap[id]!;
      final changes = <FieldChange>[];

      final catName = row['category']?.toString().trim() ?? '';
      final vendorName = row['preferredVendor']?.toString().trim() ?? '';
      final locStr = row['locations']?.toString().trim() ?? '';
      final parsedLoc = _parseLocationString(locStr);
      final locQty = parsedLoc.isNotEmpty
          ? parsedLoc.values.fold<int>(0, (a, b) => a + b)
          : _parseInt(row['quantity']);

      void check(String field, String oldVal, String newVal) {
        if (oldVal.trim().toLowerCase() != newVal.trim().toLowerCase()) {
          changes.add(FieldChange(field: field, oldValue: oldVal, newValue: newVal));
        }
      }

      void checkNum(String field, num oldVal, num newVal) {
        if (oldVal != newVal) {
          changes.add(FieldChange(
            field: field,
            oldValue: oldVal.toString(),
            newValue: newVal.toString(),
          ));
        }
      }

      check('Name', existing.name, name);
      check('Category', existing.categoryName, catName);
      check('Company', existing.company, row['company']?.toString().trim() ?? '');
      check('Size', existing.size, row['size']?.toString().trim() ?? '');
      check('Unit', existing.unit, row['unit']?.toString().trim() ?? 'pcs');
      check('Description', existing.description, row['description']?.toString().trim() ?? '');
      check('Preferred Vendor', existing.preferredVendorName, vendorName);

      checkNum('Cost Price', existing.costPrice, _parseDouble(row['costPrice']));
      checkNum('Selling Price', existing.sellingPrice, _parseDouble(row['sellingPrice']));

      int threshold = _parseInt(row['lowStockThreshold']);
      if (threshold <= 0) threshold = existing.lowStockThreshold;
      checkNum('Low Stock Threshold', existing.lowStockThreshold, threshold);

      final existingLocStr = existing.locationQuantities.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      final newLocStr = parsedLoc.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      if (parsedLoc.isNotEmpty) {
        check('Locations', existingLocStr, newLocStr);
      }
      if (parsedLoc.isEmpty && locQty != existing.quantity) {
        checkNum('Quantity', existing.quantity, locQty);
      }

      diffs.add(ProductUpdateDiff(
        productId: id,
        productName: changes.any((c) => c.field == 'Name') ? name : existing.name,
        status: changes.isEmpty ? UpdateStatus.unchanged : UpdateStatus.modified,
        fieldChanges: changes,
        parsedData: row,
      ));
    }

    return diffs;
  }

  // ==================== IMPORT ====================

  Future<ParseResult> parseExcelFile(String filePath) async {
    final bytes = await file_helper.readFileBytes(filePath);
    return parseExcelBytes(bytes);
  }

  ParseResult parseExcelBytes(Uint8List bytes) {
    late final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DEBUG_IMPORT] excel decode failed: $e');
      }
      rethrow;
    }
    final List<Map<String, dynamic>> products = [];

    if (excel.tables.isEmpty) {
      throw Exception('The Excel file has no sheets');
    }

    // Prefer Products sheet for multi-sheet files (e.g. exported Full Report)
    final sheetName = excel.tables.containsKey('Products')
        ? 'Products'
        : excel.tables.keys.first;
    final sheet = excel.tables[sheetName];

    if (sheet == null || sheet.rows.isEmpty) {
      throw Exception('The Excel file is empty');
    }

    if (sheet.rows.length < 2) {
      throw Exception('The file has headers but no data rows');
    }

    final headerRow = sheet.rows.first;
    final Map<String, int> columnMap = {};

    for (int i = 0; i < headerRow.length; i++) {
      final cellValue =
          headerRow[i]?.value?.toString().trim().toLowerCase() ?? '';
      if (cellValue.contains('name') &&
          !cellValue.contains('category') &&
          !cellValue.contains('company')) {
        columnMap['name'] = i;
      } else if (cellValue.contains('category')) {
        columnMap['category'] = i;
      } else if (cellValue.contains('company') || cellValue.contains('brand')) {
        columnMap['company'] = i;
      } else if (cellValue == 'size') {
        columnMap['size'] = i;
      } else if (cellValue.contains('location')) {
        columnMap['locations'] = i;
      } else if (cellValue.contains('threshold') ||
          cellValue.contains('low stock')) {
        columnMap['lowStockThreshold'] = i;
      } else if (cellValue.contains('quantity') ||
          cellValue.contains('qty') ||
          cellValue == 'stock') {
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
      } else if (cellValue.contains('vendor') ||
          cellValue.contains('preferred vendor')) {
        columnMap['preferredVendor'] = i;
      } else if (cellValue == 'barcode' || cellValue.contains('barcode')) {
        columnMap['barcode'] = i;
      }
    }

    int dataStartRow = 1;

    if (!columnMap.containsKey('name')) {
      dataStartRow = 0;
      _inferColumnsFromData(sheet.rows, columnMap);
    }

    int skippedNoName = 0;

    for (int rowIdx = dataStartRow; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];

      if (row.every(
        (cell) => cell?.value == null || cell!.value.toString().trim().isEmpty,
      )) {
        continue;
      }

      final productData = <String, dynamic>{};
      productData['name'] = _getCellString(row, columnMap['name']);
      productData['category'] = _getCellString(row, columnMap['category']);
      productData['company'] = _getCellString(row, columnMap['company']);
      productData['size'] = _getCellString(row, columnMap['size']);
      productData['locations'] = _getCellString(row, columnMap['locations']);
      productData['quantity'] = _getCellInt(row, columnMap['quantity']);
      productData['unit'] = _getCellString(
        row,
        columnMap['unit'],
        defaultValue: 'pcs',
      );
      productData['description'] = _getCellString(
        row,
        columnMap['description'],
      );
      productData['costPrice'] = _getCellDouble(row, columnMap['costPrice']);
      productData['sellingPrice'] = _getCellDouble(
        row,
        columnMap['sellingPrice'],
      );
      productData['lowStockThreshold'] = _getCellInt(
        row,
        columnMap['lowStockThreshold'],
      );
      productData['preferredVendor'] = _getCellString(
        row,
        columnMap['preferredVendor'],
      );
      productData['barcode'] = _getCellString(row, columnMap['barcode']);

      if (productData['name'].toString().isNotEmpty) {
        products.add(productData);
      } else {
        skippedNoName++;
      }
    }

    return ParseResult(products, skippedNoName);
  }

  /// Converts parsed spreadsheet data to [ProductModel] list.
  /// [fallbackLocations] - when Locations column is empty, uses the first location
  /// from this list instead of a hardcoded placeholder. Pass Settings locations.
  List<ProductModel> convertToProducts(
    List<Map<String, dynamic>> data,
    Map<String, CategoryModel> categoryMap,
    Map<String, VendorModel> vendorMap, {
    List<String>? fallbackLocations,
  }) {
    final now = DateTime.now();
    final defaultLoc =
        (fallbackLocations != null && fallbackLocations.isNotEmpty)
        ? fallbackLocations.first
        : 'Default';
    return data.map((item) {
      final categoryName = item['category']?.toString() ?? '';
      final category = categoryMap[categoryName.toLowerCase()];

      final vendorName = item['preferredVendor']?.toString().trim() ?? '';
      final vendor = vendorName.isNotEmpty
          ? vendorMap[vendorName.toLowerCase()]
          : null;

      var locQuantities = _parseLocationString(
        item['locations']?.toString() ?? '',
      );
      var quantity = _parseInt(item['quantity']);

      int threshold = _parseInt(item['lowStockThreshold']);
      if (threshold <= 0) {
        threshold = 10; // Fallback to default 10 if not provided or invalid
      }

      if (locQuantities.isNotEmpty) {
        final locSum = locQuantities.values.fold(0, (sum, v) => sum + v);
        quantity = locSum;
        // When locations are names only (e.g. "pos1" without ":123"), they parse as 0.
        // Use the Quantity column: for a single location assign all; for multiple, assign to first.
        if (locSum == 0) {
          final qtyFromCol = _parseInt(item['quantity']);
          if (qtyFromCol > 0) {
            quantity = qtyFromCol;
            final keys = locQuantities.keys.toList();
            if (keys.length == 1) {
              locQuantities = {keys.single: qtyFromCol};
            } else {
              locQuantities = {for (var k in keys) k: 0};
              locQuantities[keys.first] = qtyFromCol;
            }
          }
        }
      } else if (quantity > 0) {
        locQuantities = {defaultLoc: quantity};
      }

      final unitVal = item['unit']?.toString().trim();

      return ProductModel(
        id: '',
        name: item['name']?.toString() ?? '',
        categoryId: category?.id ?? '',
        categoryName: category?.name ?? categoryName,
        company: item['company']?.toString() ?? '',
        size: item['size']?.toString() ?? '',
        quantity: quantity,
        unit: (unitVal != null && unitVal.isNotEmpty) ? unitVal : 'pcs',
        locationQuantities: locQuantities,
        description: item['description']?.toString() ?? '',
        lowStockThreshold: threshold,
        costPrice: _parseDouble(item['costPrice']),
        sellingPrice: _parseDouble(item['sellingPrice']),
        barcode: item['barcode']?.toString().trim() ?? '',
        preferredVendorId: vendor?.id ?? '',
        preferredVendorName: vendor?.name ?? vendorName,
        createdAt: now,
        updatedAt: now,
      );
    }).toList();
  }

  Map<String, int> parseLocationString(String locStr) => _parseLocationString(locStr);
  int parseIntValue(dynamic value) => _parseInt(value);
  double parseDoubleValue(dynamic value) => _parseDouble(value);

  /// Builds a composite key for matching: name|category|company|size (lowercase, trimmed)
  static String compositeKey(String name, String category, String company, String size) {
    return '${name.trim().toLowerCase()}|${category.trim().toLowerCase()}|${company.trim().toLowerCase()}|${size.trim().toLowerCase()}';
  }

  /// Smart merge: matches imported rows against existing products by barcode then composite key.
  /// Returns two lists: products to update (with merged data) and truly new products.
  SmartMergeResult matchExistingProducts({
    required List<ProductModel> importedProducts,
    required List<ProductModel> existingProducts,
  }) {
    final barcodeIndex = <String, ProductModel>{};
    final compositeIndex = <String, ProductModel>{};

    for (final p in existingProducts) {
      if (p.barcode.isNotEmpty) {
        barcodeIndex.putIfAbsent(p.barcode.trim().toLowerCase(), () => p);
      }
      final key = compositeKey(p.name, p.categoryName, p.company, p.size);
      if (key != '|||') {
        compositeIndex[key] = p;
      }
    }

    final updates = <MergedProduct>[];
    final newProducts = <ProductModel>[];

    for (final imported in importedProducts) {
      ProductModel? match;

      if (imported.barcode.isNotEmpty) {
        match = barcodeIndex[imported.barcode.trim().toLowerCase()];
      }
      if (match == null) {
        final key = compositeKey(imported.name, imported.categoryName, imported.company, imported.size);
        if (key != '|||') {
          match = compositeIndex[key];
        }
      }

      if (match != null) {
        updates.add(MergedProduct(
          existing: match,
          imported: imported,
          merged: match.copyWith(
            quantity: match.quantity + imported.quantity,
            locationQuantities: _mergeLocations(match.locationQuantities, imported.locationQuantities),
            costPrice: imported.costPrice > 0 ? imported.costPrice : match.costPrice,
            sellingPrice: imported.sellingPrice > 0 ? imported.sellingPrice : match.sellingPrice,
            barcode: imported.barcode.isNotEmpty ? imported.barcode : match.barcode,
            description: imported.description.isNotEmpty ? imported.description : match.description,
            lowStockThreshold: imported.lowStockThreshold > 0 ? imported.lowStockThreshold : match.lowStockThreshold,
            updatedAt: DateTime.now(),
          ),
        ));
      } else {
        newProducts.add(imported);
      }
    }

    return SmartMergeResult(updates: updates, newProducts: newProducts);
  }

  Map<String, int> _mergeLocations(Map<String, int> existing, Map<String, int> imported) {
    final result = Map<String, int>.from(existing);
    for (final entry in imported.entries) {
      result[entry.key] = (result[entry.key] ?? 0) + entry.value;
    }
    return result;
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) {
      final strValue = value.trim().replaceAll(',', '');
      if (strValue.isEmpty) return 0;
      return int.tryParse(strValue.split('.').first) ?? 0;
    }
    return 0;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final strValue = value
          .trim()
          .replaceAll(',', '')
          .replaceAll(RegExp(r'[^\d.]'), '');
      if (strValue.isEmpty) return 0;
      return double.tryParse(strValue) ?? 0;
    }
    return 0;
  }

  /// Parses "Location1:10, Location2:5" or "Location1:10; Location2:5" into a map.
  /// If no colon is present (e.g. "Warehouse"), it assumes a quantity of 0.
  Map<String, int> _parseLocationString(String locStr) {
    if (locStr.trim().isEmpty) return {};
    final result = <String, int>{};
    final parts = locStr.split(RegExp(r'[,;]'));
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final colonIdx = trimmed.lastIndexOf(':');
      if (colonIdx > 0) {
        final name = trimmed.substring(0, colonIdx).trim();
        final qty = int.tryParse(trimmed.substring(colonIdx + 1).trim()) ?? 0;
        if (name.isNotEmpty) result[name] = qty;
      } else {
        if (trimmed.isNotEmpty) result[trimmed] = 0;
      }
    }
    return result;
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
    if (value is IntCellValue) return value.value;
    if (value is DoubleCellValue) return value.value.toInt();

    final strValue = value.toString().trim().replaceAll(',', '');
    if (strValue.isEmpty) return 0;
    return int.tryParse(strValue.split('.').first) ?? 0;
  }

  double _getCellDouble(List<Data?> row, int? colIndex) {
    if (colIndex == null || colIndex >= row.length) return 0;
    final value = row[colIndex]?.value;
    if (value == null) return 0;
    if (value is DoubleCellValue) return value.value;
    if (value is IntCellValue) return value.value.toDouble();

    final strValue = value
        .toString()
        .trim()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^\d.]'), '');
    if (strValue.isEmpty) return 0;
    return double.tryParse(strValue) ?? 0;
  }

  /// When no header row is detected, infer column roles from the first
  /// few data rows by inspecting cell types and value patterns.
  /// Uses cardinality analysis to distinguish category (few unique values)
  /// from product name (many unique values).
  void _inferColumnsFromData(
    List<List<Data?>> rows,
    Map<String, int> columnMap,
  ) {
    if (rows.isEmpty) return;
    final firstRow = rows.first;
    final numCols = firstRow.length;

    final textCols = <int>[];
    final intCols = <int>[];

    for (int i = 0; i < numCols; i++) {
      final val = firstRow[i]?.value;
      if (val == null) continue;
      if (val is IntCellValue ||
          val is DoubleCellValue ||
          int.tryParse(val.toString()) != null) {
        intCols.add(i);
      } else if (val is TextCellValue) {
        textCols.add(i);
      }
    }

    if (textCols.length >= 2 && rows.length > 3) {
      final sampleSize = rows.length < 20 ? rows.length : 20;

      int uniqueCount(int col) {
        final unique = <String>{};
        for (int r = 0; r < sampleSize; r++) {
          final row = rows[r];
          if (col < row.length && row[col]?.value != null) {
            unique.add(row[col]!.value.toString().trim().toLowerCase());
          }
        }
        return unique.length;
      }

      final firstUnique = uniqueCount(textCols[0]);
      final secondUnique = uniqueCount(textCols[1]);

      if (firstUnique < secondUnique) {
        columnMap['category'] = textCols[0];
        columnMap['name'] = textCols[1];
      } else {
        columnMap['name'] = textCols[0];
        columnMap['category'] = textCols[1];
      }

      final remainingRoles = ['size', 'unit', 'locations', 'description'];
      int roleIdx = 0;
      for (
        int i = 2;
        i < textCols.length && roleIdx < remainingRoles.length;
        i++
      ) {
        columnMap[remainingRoles[roleIdx++]] = textCols[i];
      }
    } else {
      final textRoles = [
        'name',
        'category',
        'size',
        'unit',
        'locations',
        'description',
      ];
      for (int i = 0; i < textCols.length && i < textRoles.length; i++) {
        columnMap[textRoles[i]] = textCols[i];
      }
    }

    // For integer columns: skip the first (likely a serial number),
    // the next is quantity; if more, treat as costPrice, sellingPrice, lowStockThreshold.
    final numRoles = intCols.length > 1
        ? intCols.sublist(1)
        : List<int>.from(intCols);
    final numNames = [
      'quantity',
      'costPrice',
      'sellingPrice',
      'lowStockThreshold',
    ];
    for (int i = 0; i < numRoles.length && i < numNames.length; i++) {
      columnMap[numNames[i]] = numRoles[i];
    }
  }

  /// CSV version: infer column roles when no header row is detected.
  void _inferColumnsFromCsvData(
    List<List<dynamic>> rows,
    Map<String, int> columnMap,
  ) {
    if (rows.isEmpty) return;
    final firstRow = rows.first;
    final numCols = firstRow.length;

    final textCols = <int>[];
    final intCols = <int>[];

    for (int i = 0; i < numCols; i++) {
      final val = firstRow[i];
      if (val == null) continue;
      final str = val.toString().trim();
      if (str.isEmpty) continue;
      if (int.tryParse(str.split('.').first) != null ||
          double.tryParse(str.replaceAll(',', '')) != null) {
        intCols.add(i);
      } else {
        textCols.add(i);
      }
    }

    if (textCols.length >= 2 && rows.length > 3) {
      final sampleSize = rows.length < 20 ? rows.length : 20;

      int uniqueCount(int col) {
        final unique = <String>{};
        for (int r = 0; r < sampleSize; r++) {
          final row = rows[r];
          if (col < row.length && row[col] != null) {
            unique.add(row[col].toString().trim().toLowerCase());
          }
        }
        return unique.length;
      }

      final firstUnique = uniqueCount(textCols[0]);
      final secondUnique = uniqueCount(textCols[1]);

      if (firstUnique < secondUnique) {
        columnMap['category'] = textCols[0];
        columnMap['name'] = textCols[1];
      } else {
        columnMap['name'] = textCols[0];
        columnMap['category'] = textCols[1];
      }

      final remainingRoles = ['size', 'unit', 'locations', 'description'];
      int roleIdx = 0;
      for (
        int i = 2;
        i < textCols.length && roleIdx < remainingRoles.length;
        i++
      ) {
        columnMap[remainingRoles[roleIdx++]] = textCols[i];
      }
    } else {
      final textRoles = [
        'name',
        'category',
        'size',
        'unit',
        'locations',
        'description',
      ];
      for (int i = 0; i < textCols.length && i < textRoles.length; i++) {
        columnMap[textRoles[i]] = textCols[i];
      }
    }

    final numRoles = intCols.length > 1
        ? intCols.sublist(1)
        : List<int>.from(intCols);
    final numNames = [
      'quantity',
      'costPrice',
      'sellingPrice',
      'lowStockThreshold',
    ];
    for (int i = 0; i < numRoles.length && i < numNames.length; i++) {
      columnMap[numNames[i]] = numRoles[i];
    }
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
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final defaultSheet = excel.tables.keys.first;
    excel.rename(defaultSheet, 'Summary');
    final summary = excel['Summary'];
    final prodSheet = excel['Products'];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#00897B'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final sectionStyle = CellStyle(bold: true, fontSize: 13);

    // ---- Sheet 1: Summary ----
    void addSummaryRow(Sheet s, int row, String label, String value) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          TextCellValue(label);
      s
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = CellStyle(
        bold: true,
      );
      s.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
          TextCellValue(value);
    }

    final titleCell = summary.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    titleCell.value = TextCellValue('Inventory Summary Report');
    titleCell.cellStyle = sectionStyle;

    summary
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .value = TextCellValue(
      'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
    );

    addSummaryRow(
      summary,
      3,
      'Inventory Health Score',
      '${healthScore.toInt()}/100',
    );
    addSummaryRow(summary, 4, 'Total Products', '$totalProducts');
    addSummaryRow(summary, 5, 'Low Stock Items', '$lowStockCount');
    addSummaryRow(summary, 6, 'Out of Stock Items', '$outOfStockCount');
    addSummaryRow(summary, 7, 'Total Transactions', '${transactions.length}');

    summary.setColumnWidth(0, 25);
    summary.setColumnWidth(1, 20);

    // ---- Sheet 2: Products ----
    final prodHeaders = [
      'S.No',
      'Product Name',
      'Category',
      'Company',
      'Size',
      'Locations',
      'Quantity',
      'Unit',
      'Cost Price',
      'Selling Price',
      'Low Stock Threshold',
      'Status',
      'Description',
      'Preferred Vendor',
    ];
    for (int i = 0; i < prodHeaders.length; i++) {
      final cell = prodSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(prodHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    for (int row = 0; row < products.length; row++) {
      final p = products[row];
      final r = row + 1;
      final locStr = p.locationQuantities.entries
          .map((e) => '${e.key}:${e.value}')
          .join(', ');
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = IntCellValue(
        row + 1,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = TextCellValue(
        p.name,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = TextCellValue(
        p.categoryName,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = TextCellValue(
        p.company,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = TextCellValue(
        p.size,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r))
          .value = TextCellValue(
        locStr,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r))
          .value = IntCellValue(
        p.quantity,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r))
          .value = TextCellValue(
        p.unit,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r))
          .value = DoubleCellValue(
        p.costPrice,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r))
          .value = DoubleCellValue(
        p.sellingPrice,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r))
          .value = IntCellValue(
        p.lowStockThreshold,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r))
          .value = TextCellValue(
        p.stockStatus,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: r))
          .value = TextCellValue(
        p.description,
      );
      prodSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: r))
          .value = TextCellValue(
        p.preferredVendorName,
      );
    }
    prodSheet.setColumnWidth(1, 25);
    prodSheet.setColumnWidth(2, 18);
    prodSheet.setColumnWidth(3, 18);
    prodSheet.setColumnWidth(4, 14);
    prodSheet.setColumnWidth(5, 30);
    prodSheet.setColumnWidth(8, 12);
    prodSheet.setColumnWidth(9, 12);
    prodSheet.setColumnWidth(10, 18);
    prodSheet.setColumnWidth(12, 30);
    prodSheet.setColumnWidth(13, 20);

    // ---- Sheet 3: Transactions ----
    final txnSheet = excel['Transactions'];
    final txnHeaders = [
      'S.No',
      'Date',
      'Product Name',
      'Type',
      'Location',
      'Quantity',
      'User',
      'Vendor',
      'Reason',
    ];
    for (int i = 0; i < txnHeaders.length; i++) {
      final cell = txnSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(txnHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    for (int row = 0; row < transactions.length; row++) {
      final t = transactions[row];
      final r = row + 1;
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = IntCellValue(
        row + 1,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = TextCellValue(
        dateFormat.format(t.date),
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = TextCellValue(
        t.productName,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = TextCellValue(
        t.typeLabel,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = TextCellValue(
        t.location,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r))
          .value = IntCellValue(
        t.quantity,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r))
          .value = TextCellValue(
        t.userName,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r))
          .value = TextCellValue(
        t.vendorName,
      );
      txnSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r))
          .value = TextCellValue(
        t.reason,
      );
    }
    txnSheet.setColumnWidth(1, 18);
    txnSheet.setColumnWidth(2, 25);
    txnSheet.setColumnWidth(4, 18);
    txnSheet.setColumnWidth(7, 25);

    // ---- Sheet 4: Categories ----
    final catSheet = excel['Categories'];
    final catHeaders = [
      'Category',
      'Product Count',
      'Low Stock',
      'Out of Stock',
    ];
    for (int i = 0; i < catHeaders.length; i++) {
      final cell = catSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(catHeaders[i]);
      cell.cellStyle = headerStyle;
    }
    int catRow = 1;
    for (final cat in productCount.keys) {
      catSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: catRow))
          .value = TextCellValue(
        cat,
      );
      catSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: catRow))
          .value = IntCellValue(
        productCount[cat] ?? 0,
      );
      catSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: catRow))
          .value = IntCellValue(
        lowStock[cat] ?? 0,
      );
      catSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: catRow))
          .value = IntCellValue(
        outOfStock[cat] ?? 0,
      );
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
    final sheet =
        excel[excel.tables.keys.first]; // use default sheet, rename after
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#00897B'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = [
      'Product Name',
      'Category',
      'Company',
      'Size',
      'Barcode',
      'Locations',
      'Quantity',
      'Unit',
      'Cost Price',
      'Selling Price',
      'Low Stock Threshold',
      'Description',
      'Preferred Vendor',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    final exampleData = [
      'Example Product',
      'General',
      'Brand A',
      '10x10',
      '1234567890',
      'pos1',
      '50',
      'pcs',
      '100',
      '150',
      '10',
      'Description here',
      'Vendor A',
    ];
    for (int i = 0; i < exampleData.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
          .value = TextCellValue(
        exampleData[i],
      );
    }

    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 18);
    sheet.setColumnWidth(6, 12);
    sheet.setColumnWidth(7, 12);
    sheet.setColumnWidth(8, 20);
    sheet.setColumnWidth(9, 20);
    sheet.setColumnWidth(10, 25);
    sheet.setColumnWidth(11, 20);

    excel.rename(excel.tables.keys.first, 'Products');
    final fileBytes = excel.save();
    if (fileBytes != null) {
      return ExportResult('import_template.xlsx', fileBytes);
    }
    throw Exception('Failed to generate template file');
  }

  // ==================== CSV EXPORT ====================

  Future<ExportResult> exportProductsToCsv(List<ProductModel> products) async {
    final rows = <List<dynamic>>[
      [
        'S.No',
        'Product Name',
        'Category',
        'Company',
        'Size',
        'Locations',
        'Quantity',
        'Unit',
        'Cost Price',
        'Selling Price',
        'Low Stock Threshold',
        'Status',
        'Description',
        'Preferred Vendor',
      ],
    ];

    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final locStr = p.locationQuantities.entries
          .map((e) => '${e.key}:${e.value}')
          .join('; ');
      rows.add([
        i + 1,
        p.name,
        p.categoryName,
        p.company,
        p.size,
        locStr,
        p.quantity,
        p.unit,
        p.costPrice,
        p.sellingPrice,
        p.lowStockThreshold,
        p.stockStatus,
        p.description,
        p.preferredVendorName,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ExportResult('products_$timestamp.csv', utf8.encode(csv));
  }

  Future<ExportResult> exportTransactionsToCsv(
    List<StockTransactionModel> transactions,
  ) async {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final rows = <List<dynamic>>[
      [
        'S.No',
        'Date',
        'Product Name',
        'Type',
        'Location',
        'Quantity',
        'User',
        'Vendor',
        'Reason',
      ],
    ];

    for (int i = 0; i < transactions.length; i++) {
      final t = transactions[i];
      rows.add([
        i + 1,
        dateFormat.format(t.date),
        t.productName,
        t.typeLabel,
        t.location,
        t.quantity,
        t.userName,
        t.vendorName,
        t.reason,
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
        cat,
        productCount[cat] ?? 0,
        lowStock[cat] ?? 0,
        outOfStock[cat] ?? 0,
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
      rows.add([
        cat,
        productCount[cat] ?? 0,
        lowStock[cat] ?? 0,
        outOfStock[cat] ?? 0,
      ]);
    }
    rows.add([]);

    rows.add(['=== PRODUCTS ===']);
    rows.add([
      'S.No',
      'Product Name',
      'Category',
      'Company',
      'Size',
      'Locations',
      'Quantity',
      'Unit',
      'Cost Price',
      'Selling Price',
      'Low Stock Threshold',
      'Status',
      'Preferred Vendor',
    ]);
    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final locStr = p.locationQuantities.entries
          .map((e) => '${e.key}:${e.value}')
          .join('; ');
      rows.add([
        i + 1,
        p.name,
        p.categoryName,
        p.company,
        p.size,
        locStr,
        p.quantity,
        p.unit,
        p.costPrice,
        p.sellingPrice,
        p.lowStockThreshold,
        p.stockStatus,
        p.preferredVendorName,
      ]);
    }
    rows.add([]);

    rows.add(['=== TRANSACTIONS ===']);
    rows.add([
      'S.No',
      'Date',
      'Product Name',
      'Type',
      'Location',
      'Quantity',
      'User',
      'Vendor',
      'Reason',
    ]);
    for (int i = 0; i < transactions.length; i++) {
      final t = transactions[i];
      rows.add([
        i + 1,
        dateFormat.format(t.date),
        t.productName,
        t.typeLabel,
        t.location,
        t.quantity,
        t.userName,
        t.vendorName,
        t.reason,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return ExportResult('full_report_$timestamp.csv', utf8.encode(csv));
  }

  // ==================== CSV IMPORT ====================

  Future<ParseResult> parseCsvFile(String filePath) async {
    final bytes = await file_helper.readFileBytes(filePath);
    return parseCsvBytes(bytes);
  }

  ParseResult parseCsvBytes(Uint8List bytes) {
    late final String csvString;
    try {
      csvString = utf8.decode(bytes);
    } catch (_) {
      throw Exception(
        'Could not read the CSV file. It may be corrupted or use an unsupported encoding.',
      );
    }
    final rows = const CsvToListConverter().convert(csvString);

    if (rows.isEmpty) {
      throw Exception('The CSV file is empty');
    }

    final List<Map<String, dynamic>> products = [];

    final headerRow = rows.first;
    final Map<String, int> columnMap = {};

    for (int i = 0; i < headerRow.length; i++) {
      final cellValue = headerRow[i].toString().trim().toLowerCase();
      if (cellValue.contains('name') &&
          !cellValue.contains('category') &&
          !cellValue.contains('company')) {
        columnMap['name'] = i;
      } else if (cellValue.contains('category')) {
        columnMap['category'] = i;
      } else if (cellValue.contains('company') || cellValue.contains('brand')) {
        columnMap['company'] = i;
      } else if (cellValue == 'size') {
        columnMap['size'] = i;
      } else if (cellValue.contains('location')) {
        columnMap['locations'] = i;
      } else if (cellValue.contains('threshold') ||
          cellValue.contains('low stock')) {
        columnMap['lowStockThreshold'] = i;
      } else if (cellValue.contains('quantity') ||
          cellValue.contains('qty') ||
          cellValue == 'stock') {
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
      } else if (cellValue.contains('vendor') ||
          cellValue.contains('preferred vendor')) {
        columnMap['preferredVendor'] = i;
      } else if (cellValue.contains('barcode') || cellValue == 'sku') {
        columnMap['barcode'] = i;
      }
    }

    int dataStartRow = 1;
    if (!columnMap.containsKey('name')) {
      dataStartRow = 0;
      _inferColumnsFromCsvData(rows, columnMap);
    }

    int skippedNoName = 0;
    for (int rowIdx = dataStartRow; rowIdx < rows.length; rowIdx++) {
      final row = rows[rowIdx];
      if (row.every((cell) => cell == null || cell.toString().trim().isEmpty)) {
        continue;
      }

      final productData = <String, dynamic>{};
      productData['name'] = _getCsvCellString(row, columnMap['name']);
      productData['category'] = _getCsvCellString(row, columnMap['category']);
      productData['company'] = _getCsvCellString(row, columnMap['company']);
      productData['size'] = _getCsvCellString(row, columnMap['size']);
      productData['locations'] = _getCsvCellString(row, columnMap['locations']);
      productData['quantity'] = _getCsvCellInt(row, columnMap['quantity']);
      productData['unit'] = _getCsvCellString(
        row,
        columnMap['unit'],
        defaultValue: 'pcs',
      );
      productData['description'] = _getCsvCellString(
        row,
        columnMap['description'],
      );
      productData['costPrice'] = _getCsvCellDouble(row, columnMap['costPrice']);
      productData['sellingPrice'] = _getCsvCellDouble(
        row,
        columnMap['sellingPrice'],
      );
      productData['lowStockThreshold'] = _getCsvCellInt(
        row,
        columnMap['lowStockThreshold'],
      );
      productData['preferredVendor'] = _getCsvCellString(
        row,
        columnMap['preferredVendor'],
      );
      productData['barcode'] = _getCsvCellString(row, columnMap['barcode']);

      if (productData['name'].toString().isNotEmpty) {
        products.add(productData);
      } else {
        skippedNoName++;
      }
    }

    return ParseResult(products, skippedNoName);
  }

  String _getCsvCellString(
    List<dynamic> row,
    int? colIndex, {
    String defaultValue = '',
  }) {
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
    final strValue = value
        .toString()
        .trim()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^\d.]'), '');
    if (strValue.isEmpty) return 0;
    return double.tryParse(strValue) ?? 0;
  }
}

// ==================== DIFF MODELS ====================

enum UpdateStatus { modified, newProduct, unchanged, error }

class FieldChange {
  final String field;
  final String oldValue;
  final String newValue;

  const FieldChange({
    required this.field,
    required this.oldValue,
    required this.newValue,
  });
}

class ProductUpdateDiff {
  final String productId;
  final String productName;
  final UpdateStatus status;
  final List<FieldChange> fieldChanges;
  final Map<String, dynamic> parsedData;
  final String? errorMessage;

  const ProductUpdateDiff({
    required this.productId,
    required this.productName,
    required this.status,
    required this.fieldChanges,
    required this.parsedData,
    this.errorMessage,
  });
}

class MergedProduct {
  final ProductModel existing;
  final ProductModel imported;
  final ProductModel merged;

  const MergedProduct({
    required this.existing,
    required this.imported,
    required this.merged,
  });
}

class SmartMergeResult {
  final List<MergedProduct> updates;
  final List<ProductModel> newProducts;

  const SmartMergeResult({required this.updates, required this.newProducts});

  int get updateCount => updates.length;
  int get newCount => newProducts.length;
}
