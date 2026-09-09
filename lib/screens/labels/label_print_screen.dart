import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/label_pdf_service.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/product_picker.dart';

/// Composes a printable sheet of barcode / shelf labels.
class LabelPrintScreen extends StatefulWidget {
  const LabelPrintScreen({super.key, this.initialProduct});

  /// Pre-seeds the sheet, so "Print label" from a product opens here ready to
  /// go rather than on an empty basket.
  final ProductModel? initialProduct;

  @override
  State<LabelPrintScreen> createState() => _LabelPrintScreenState();
}

class _LabelPrintScreenState extends State<LabelPrintScreen> {
  final List<LabelRequest> _requests = [];
  LabelOptions _options = const LabelOptions();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialProduct;
    if (seed != null) _requests.add(LabelRequest(product: seed));
  }

  Future<void> _addProduct() async {
    final products = context.read<ProductProvider>().analyticsProducts;
    final picked = await showProductPicker(
      context: context,
      products: products,
      title: 'Add product to sheet',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final idx = _requests.indexWhere((r) => r.product.id == picked.id);
      if (idx == -1) {
        _requests.add(LabelRequest(product: picked));
      } else {
        // Already on the sheet: a second pick means "one more of these",
        // which is what a person reaching for the same product twice means.
        _requests[idx] = _requests[idx].copyWith(
          copies: _requests[idx].copies + 1,
        );
      }
    });
  }

  /// Seeds the sheet with everything currently low on stock — the labels most
  /// likely to be needed after a restock.
  void _addLowStock() {
    final low = context.read<ProductProvider>().lowStockProducts;
    if (low.isEmpty) {
      showInfoSnackBar(context, 'Nothing is below its reorder level.');
      return;
    }
    setState(() {
      for (final product in low) {
        if (_requests.any((r) => r.product.id == product.id)) continue;
        _requests.add(LabelRequest(product: product));
      }
    });
  }

  void _setCopies(int index, int copies) {
    setState(() {
      if (copies <= 0) {
        _requests.removeAt(index);
      } else {
        _requests[index] = _requests[index].copyWith(copies: copies);
      }
    });
  }

  Future<void> _run(Future<void> Function() action, String failureMessage) async {
    if (_busy || _requests.isEmpty) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '$failureMessage ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.printLabels,
      featureName: 'Label Printing',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final options = _options.copyWith(
      currencySymbol: Money.symbolOf(context),
      companyName: settings.company?.displayName ?? '',
    );
    final labels = LabelPdfService.labelCount(_requests);
    final pages = LabelPdfService.pageCount(_requests, options.layout);

    return AppScreenScaffold(
      icon: Icons.local_offer_rounded,
      title: 'Label Printing',
      subtitle: labels == 0
          ? 'Barcode and shelf labels'
          : '$labels label${labels == 1 ? '' : 's'} · $pages '
                'page${pages == 1 ? '' : 's'}',
      iconColor: AppTheme.violetColor,
      actions: [
        IconButton(
          onPressed: _addProduct,
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add product',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          FormSection(
            title: 'Sheet',
            icon: Icons.grid_view_rounded,
            index: 0,
            children: [
              DropdownButtonFormField<String>(
                initialValue: options.layout.id,
                decoration: const InputDecoration(labelText: 'Layout'),
                items: [
                  for (final preset in LabelLayout.presets)
                    DropdownMenuItem(value: preset.id, child: Text(preset.name)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  setState(
                    () => _options = _options.copyWith(
                      layout: LabelLayout.byId(id),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LabelSymbology>(
                initialValue: options.symbology,
                decoration: const InputDecoration(labelText: 'Barcode'),
                items: const [
                  DropdownMenuItem(
                    value: LabelSymbology.code128,
                    child: Text('Code 128 (any code)'),
                  ),
                  DropdownMenuItem(
                    value: LabelSymbology.ean13,
                    child: Text('EAN-13 (13-digit retail)'),
                  ),
                  DropdownMenuItem(
                    value: LabelSymbology.qr,
                    child: Text('QR code'),
                  ),
                  DropdownMenuItem(
                    value: LabelSymbology.none,
                    child: Text('No barcode'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(
                    () => _options = _options.copyWith(symbology: value),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: 'What to show',
            icon: Icons.tune_rounded,
            index: 1,
            children: [
              _Toggle(
                label: 'Price',
                value: options.showPrice,
                onChanged: (v) =>
                    setState(() => _options = _options.copyWith(showPrice: v)),
              ),
              _Toggle(
                label: 'Code under the barcode',
                value: options.showSku,
                onChanged: (v) =>
                    setState(() => _options = _options.copyWith(showSku: v)),
              ),
              _Toggle(
                label: 'Size / variant',
                value: options.showSize,
                onChanged: (v) =>
                    setState(() => _options = _options.copyWith(showSize: v)),
              ),
              _Toggle(
                label: 'Company name',
                value: options.showCompanyName,
                onChanged: (v) => setState(
                  () => _options = _options.copyWith(showCompanyName: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FormSection(
            title: 'Products',
            subtitle: 'Set how many labels each product needs',
            icon: Icons.inventory_2_rounded,
            index: 2,
            trailing: TextButton.icon(
              onPressed: _addLowStock,
              icon: const Icon(Icons.warning_amber_rounded, size: 16),
              label: const Text('Add low stock'),
            ),
            children: [
              if (_requests.isEmpty)
                const EmptyStateWidget(
                  icon: Icons.local_offer_rounded,
                  title: 'No products on the sheet yet',
                  subtitle:
                      'Add products to print barcode or shelf labels for them.',
                )
              else
                for (var i = 0; i < _requests.length; i++)
                  _LabelRow(
                    request: _requests[i],
                    symbology: options.symbology,
                    onCopies: (copies) => _setCopies(i, copies),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _requests.isEmpty
                      ? null
                      : () => _run(
                          () => LabelPdfService.shareSheet(
                            requests: _requests,
                            options: options,
                          ),
                          'Could not export the sheet.',
                        ),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Save PDF'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || _requests.isEmpty
                      ? null
                      : () => _run(
                          () => LabelPdfService.printSheet(
                            requests: _requests,
                            options: options,
                          ),
                          'Could not open the print dialog.',
                        ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_rounded),
                  label: const Text('Print'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({
    required this.request,
    required this.symbology,
    required this.onCopies,
  });

  final LabelRequest request;
  final LabelSymbology symbology;
  final ValueChanged<int> onCopies;

  @override
  Widget build(BuildContext context) {
    final code = LabelPdfService.codeFor(request.product, symbology);
    final usingFallback =
        code != null && request.product.barcode.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    code == null
                        ? 'No barcode'
                        : (usingFallback
                              ? 'No barcode on file — using the product id'
                              : code),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: usingFallback
                          ? AppTheme.warningColor
                          : AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => onCopies(request.copies - 1),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              tooltip: 'One fewer',
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${request.copies}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onCopies(request.copies + 1),
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'One more',
            ),
          ],
        ),
      ),
    );
  }
}
