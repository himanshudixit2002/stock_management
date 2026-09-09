import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/bom_model.dart';
import '../../providers/bom_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../widgets/glass_panel.dart';

/// Runs a BOM: pick how many runs and where, see exactly what it will consume.
class BuildAssemblySheet extends StatefulWidget {
  const BuildAssemblySheet({
    super.key,
    required this.bom,
    required this.userId,
    required this.userName,
    this.reverse = false,
  });

  final BomModel bom;
  final String userId;
  final String userName;

  /// True for an unbuild: the finished goods are consumed and the components
  /// come back.
  final bool reverse;

  @override
  State<BuildAssemblySheet> createState() => _BuildAssemblySheetState();
}

class _BuildAssemblySheetState extends State<BuildAssemblySheet> {
  final TextEditingController _runs = TextEditingController(text: '1');
  String _location = '';

  @override
  void initState() {
    super.initState();
    final locations = context.read<SettingsProvider>().locations;
    _location = locations.isEmpty ? 'Main' : locations.first;
    _runs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _runs.dispose();
    super.dispose();
  }

  int get _runCount => int.tryParse(_runs.text.trim()) ?? 0;

  /// On-hand quantity per product at the selected location.
  Map<String, int> _availableAt(BuildContext context) {
    final products = context.watch<ProductProvider>().analyticsProducts;
    return {
      for (final product in products)
        product.id: product.availableAtLocation(_location),
    };
  }

  Future<void> _submit() async {
    final runs = _runCount;
    if (runs <= 0) {
      showErrorSnackBar(context, 'Enter how many runs to make.');
      return;
    }
    final provider = context.read<BomProvider>();
    final units = await provider.runAssembly(
      bom: widget.bom,
      runs: runs,
      location: _location,
      userId: widget.userId,
      userName: widget.userName,
      reverse: widget.reverse,
    );
    if (!mounted) return;
    if (units == null) {
      showErrorSnackBar(
        context,
        provider.errorMessage ?? 'That did not go through.',
      );
      return;
    }
    Navigator.of(context).pop();
    showSuccessSnackBar(
      context,
      widget.reverse
          ? 'Unbuilt $units × ${widget.bom.outputProductName}.'
          : 'Built $units × ${widget.bom.outputProductName}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bom = widget.bom;
    final available = _availableAt(context);
    final maxRuns = bom.maxRunsFrom(available);
    final runs = _runCount;
    final consumption = bom.consumptionFor(runs);
    final busy = context.watch<BomProvider>().isBusy;
    final locations = context.watch<SettingsProvider>().locations;
    final title = widget.reverse ? 'Unbuild' : 'Build';

    // On an unbuild the flow runs backwards, so the thing that must be in
    // stock is the finished product, not the components.
    final blocked = widget.reverse
        ? (available[bom.outputProductId] ?? 0) < bom.outputFor(runs)
        : runs > maxRuns;

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.reverse
                      ? Icons.undo_rounded
                      : Icons.precision_manufacturing_rounded,
                  color: AppTheme.violetColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$title — ${bom.name}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _runs,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Runs',
                      helperText: widget.reverse
                          ? null
                          : (maxRuns > 0
                                ? 'Up to $maxRuns with stock on hand'
                                : 'Not enough components at $_location'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.reverse ? 'Returns to stock' : 'Consumes',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final component in bom.components)
              _ComponentRow(
                name: component.productName,
                needed: consumption[component.productId] ?? 0,
                available: available[component.productId] ?? 0,
                // On an unbuild these come back rather than going out, so a
                // shortfall is not a blocker.
                checkStock: !widget.reverse,
              ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  widget.reverse
                      ? Icons.remove_circle_outline_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 16,
                  color: widget.reverse
                      ? AppTheme.dangerColor
                      : AppTheme.successColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.reverse ? 'Takes back' : 'Produces'} '
                    '${bom.outputFor(runs)} × ${bom.outputProductName}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy || runs <= 0 || blocked ? null : _submit,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  blocked && !widget.reverse
                      ? 'Not enough stock'
                      : '$title $runs run${runs == 1 ? '' : 's'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.name,
    required this.needed,
    required this.available,
    required this.checkStock,
  });

  final String name;
  final int needed;
  final int available;
  final bool checkStock;

  @override
  Widget build(BuildContext context) {
    final short = checkStock && needed > available;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            checkStock ? '$needed of $available' : '$needed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: short ? AppTheme.dangerColor : AppTheme.textSec(context),
            ),
          ),
        ],
      ),
    );
  }
}
