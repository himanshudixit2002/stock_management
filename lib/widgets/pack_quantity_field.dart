import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../utils/unit_conversion.dart';

/// Packs and loose pieces side by side — "2 box + 3 pcs" — for dialogs and
/// dense rows where [QuantityStepper] is too large.
///
/// [controller] always holds the total in base units, so a caller reads it
/// exactly as it read a plain quantity field before packs existed. With no
/// pack ([unitsPerPack] of 1) it is that plain field.
class PackQuantityField extends StatefulWidget {
  const PackQuantityField({
    super.key,
    required this.controller,
    this.unitsPerPack = 1,
    this.packUnit = 'box',
    this.baseUnit = 'pcs',
    this.label = 'Quantity',
    this.hint,
    this.autofocus = false,
    this.dense = false,
    this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final int unitsPerPack;
  final String packUnit;
  final String baseUnit;
  final String label;
  final String? hint;
  final bool autofocus;

  /// Compact fields for rows in a list.
  final bool dense;

  /// The new total in base units, after every edit.
  final ValueChanged<int>? onChanged;

  /// Checked against the total's text, as a plain quantity field's would be,
  /// so it slots into a [Form] in place of one.
  final FormFieldValidator<String>? validator;

  @override
  State<PackQuantityField> createState() => _PackQuantityFieldState();
}

class _PackQuantityFieldState extends State<PackQuantityField> {
  final _packs = TextEditingController();
  final _pieces = TextEditingController();

  /// Set while this widget writes the total, so its own write does not come
  /// back through the listener and re-split the pieces mid-typing ("15 pcs"
  /// jumping to "1 box 5 pcs" under the cursor).
  bool _writing = false;

  bool get _hasPack => widget.unitsPerPack > 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTotalChanged);
    _split();
  }

  @override
  void didUpdateWidget(covariant PackQuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTotalChanged);
      widget.controller.addListener(_onTotalChanged);
    }
    // A different product, or the same one after a conversion: the total
    // stands and the split is redrawn for the new pack.
    if (oldWidget.controller != widget.controller ||
        oldWidget.unitsPerPack != widget.unitsPerPack) {
      _split();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTotalChanged);
    _packs.dispose();
    _pieces.dispose();
    super.dispose();
  }

  void _onTotalChanged() {
    if (_writing) return;
    _split();
    if (mounted) setState(() {});
  }

  void _split() {
    if (!_hasPack) return;
    final total = int.tryParse(widget.controller.text.trim());
    if (total == null) {
      _packs.text = '';
      _pieces.text = '';
      return;
    }
    final split = splitBaseQuantity(
      baseQuantity: total,
      unitsPerPack: widget.unitsPerPack,
    );
    _packs.text = split.packs == 0 ? '' : '${split.packs}';
    _pieces.text = split.pieces == 0 ? '' : '${split.pieces}';
  }

  void _onPartChanged(String _) {
    final packs = int.tryParse(_packs.text.trim()) ?? 0;
    final pieces = int.tryParse(_pieces.text.trim()) ?? 0;
    final total = toBaseQuantity(
      packs: packs,
      pieces: pieces,
      unitsPerPack: widget.unitsPerPack,
    );
    _writing = true;
    widget.controller.text =
        _packs.text.trim().isEmpty && _pieces.text.trim().isEmpty
        ? ''
        : '$total';
    _writing = false;
    widget.onChanged?.call(total);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final validator = widget.validator;
    if (validator == null) return _buildFields(context, null);
    return FormField<String>(
      validator: (_) => validator(widget.controller.text),
      builder: (field) => _buildFields(context, field.errorText),
    );
  }

  Widget _buildFields(BuildContext context, String? errorText) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    if (!_hasPack) {
      return TextField(
        controller: widget.controller,
        keyboardType: TextInputType.number,
        inputFormatters: digits,
        autofocus: widget.autofocus,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          suffixText: widget.baseUnit,
          isDense: widget.dense,
          errorText: errorText,
        ),
        onChanged: (value) =>
            widget.onChanged?.call(int.tryParse(value.trim()) ?? 0),
      );
    }

    final total = int.tryParse(widget.controller.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _packs,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                autofocus: widget.autofocus,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: '0',
                  suffixText: widget.packUnit,
                  isDense: widget.dense,
                ),
                onChanged: _onPartChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _pieces,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: '+ loose',
                  hintText: '0',
                  suffixText: widget.baseUnit,
                  isDense: widget.dense,
                ),
                onChanged: _onPartChanged,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            errorText ??
                '1 ${widget.packUnit} = ${widget.unitsPerPack} '
                    '${widget.baseUnit} · total $total ${widget.baseUnit}',
            style: TextStyle(
              fontSize: 12,
              color: errorText == null
                  ? AppTheme.textSec(context)
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
