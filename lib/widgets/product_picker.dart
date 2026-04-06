import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/product_model.dart';
import 'searchable_picker.dart';

/// Centralized product picker that opens a [showSearchablePicker] sheet.
/// Returns the selected [ProductModel], or null if dismissed.
Future<ProductModel?> showProductPicker({
  required BuildContext context,
  required List<ProductModel> products,
  String? selectedProductId,
  String title = 'Select Product',
}) async {
  final selectedId = await showSearchablePicker(
    context: context,
    title: title,
    selectedValue: selectedProductId,
    searchHint: 'Search by name or category...',
    items: products.map((p) {
      return PickerItem(
        value: p.id,
        label: p.name,
        subtitle: [
          if (p.categoryName.isNotEmpty) p.categoryName,
          '${p.quantity} ${p.unit}',
          if (p.company.isNotEmpty) p.company,
        ].join(' · '),
        icon: Icons.inventory_2_rounded,
        iconColor: AppTheme.getStockColor(
          p.quantity,
          threshold: p.lowStockThreshold,
        ),
      );
    }).toList(),
  );
  if (selectedId == null) return null;
  return products.where((p) => p.id == selectedId).firstOrNull;
}
