import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../models/serial_model.dart';
import '../../providers/serial_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/product_picker.dart';

/// Registers a batch of serial numbers against one product.
class RegisterSerialsSheet extends StatefulWidget {
  const RegisterSerialsSheet({
    super.key,
    required this.products,
    required this.userId,
    required this.userName,
  });

  final List<ProductModel> products;
  final String userId;
  final String userName;

  @override
  State<RegisterSerialsSheet> createState() => _RegisterSerialsSheetState();
}

class _RegisterSerialsSheetState extends State<RegisterSerialsSheet> {
  final TextEditingController _numbers = TextEditingController();
  final TextEditingController _batchNumber = TextEditingController();

  ProductModel? _product;
  String _location = '';
  DateTime? _warrantyUntil;

  @override
  void initState() {
    super.initState();
    final locations = context.read<SettingsProvider>().locations;
    _location = locations.isEmpty ? 'Main' : locations.first;
    _numbers.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _numbers.dispose();
    _batchNumber.dispose();
    super.dispose();
  }

  /// One serial per line or comma. Blank entries are dropped, and duplicates
  /// within the paste are collapsed here so the count on screen matches what
  /// will actually be written.
  List<String> get _parsedNumbers {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in _numbers.text.split(RegExp(r'[\n,]'))) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(SerialModel.normalizeSerial(trimmed))) continue;
      out.add(trimmed);
    }
    return out;
  }

  Future<void> _pickProduct() async {
    final picked = await showProductPicker(
      context: context,
      products: widget.products,
      selectedProductId: _product?.id,
      title: 'Which product?',
    );
    if (picked != null && mounted) setState(() => _product = picked);
  }

  Future<void> _pickWarranty() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _warrantyUntil ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null && mounted) setState(() => _warrantyUntil = picked);
  }

  Future<void> _submit() async {
    final product = _product;
    if (product == null) {
      showErrorSnackBar(context, 'Choose a product first.');
      return;
    }
    final numbers = _parsedNumbers;
    if (numbers.isEmpty) {
      showErrorSnackBar(context, 'Enter at least one serial number.');
      return;
    }

    final now = DateTime.now();
    final provider = context.read<SerialProvider>();
    final accepted = await provider.register([
      for (final number in numbers)
        SerialModel(
          id: '',
          serialNumber: number,
          productId: product.id,
          productName: product.name,
          batchNumber: _batchNumber.text.trim(),
          location: _location,
          status: SerialStatus.inStock,
          warrantyUntil: _warrantyUntil,
          history: [
            SerialEvent(
              action: 'Registered',
              note: 'Received into $_location',
              userId: widget.userId,
              userName: widget.userName,
              at: now,
            ),
          ],
          createdBy: widget.userId,
          createdByName: widget.userName,
          createdAt: now,
          updatedAt: now,
        ),
    ]);

    if (!mounted) return;
    final rejected = provider.lastRejected;
    if (accepted == 0) {
      showErrorSnackBar(
        context,
        provider.errorMessage ??
            'Every number you entered is already on file.',
      );
      return;
    }

    Navigator.of(context).pop();
    if (rejected.isEmpty) {
      showSuccessSnackBar(context, 'Registered $accepted units.');
    } else {
      // Named rather than counted: the operator needs to know which labels to
      // go and check.
      showInfoSnackBar(
        context,
        'Registered $accepted. Already on file: ${rejected.take(5).join(', ')}'
        '${rejected.length > 5 ? ' and ${rejected.length - 5} more' : ''}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = context.watch<SettingsProvider>().locations;
    final busy = context.watch<SerialProvider>().isBusy;
    final count = _parsedNumbers.length;

    return GlassPanel(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.qr_code_2_rounded, color: AppTheme.indigoColor),
                SizedBox(width: 10),
                Text(
                  'Register serial numbers',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            EntityPickerField(
              label: 'Product',
              icon: Icons.inventory_2_rounded,
              value: _product?.name,
              placeholder: 'Choose a product',
              onTap: _pickProduct,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: locations.contains(_location)
                        ? _location
                        : null,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: [
                      for (final location in locations)
                        DropdownMenuItem(
                          value: location,
                          child: Text(location),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _location = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _batchNumber,
                    decoration: const InputDecoration(
                      labelText: 'Batch (optional)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numbers,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Serial numbers',
                helperText: count == 0
                    ? 'One per line, or comma separated'
                    : '$count unique number${count == 1 ? '' : 's'} ready',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickWarranty,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 18,
                      color: AppTheme.textSec(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _warrantyUntil == null
                            ? 'Warranty end date (optional)'
                            : 'Warranty until '
                                  '${_warrantyUntil!.day}/${_warrantyUntil!.month}/${_warrantyUntil!.year}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (_warrantyUntil != null)
                      IconButton(
                        onPressed: () => setState(() => _warrantyUntil = null),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy || count == 0 ? null : _submit,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  count == 0
                      ? 'Register'
                      : 'Register $count unit${count == 1 ? '' : 's'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
