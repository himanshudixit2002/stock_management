import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../models/product_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/billing_pdf_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/fast_pos_checkout.dart';
import '../../utils/product_search.dart';
import '../../widgets/empty_state_widget.dart';
import '../../utils/responsive.dart';
import '../../widgets/searchable_picker.dart' show PickerItem, showSearchablePicker;
import '../../widgets/success_overlay.dart';

class FastPosScreen extends StatefulWidget {
  const FastPosScreen({super.key});

  @override
  State<FastPosScreen> createState() => _FastPosScreenState();
}

class _FastPosScreenState extends State<FastPosScreen> {
  final _scrollCtrl = ScrollController();
  final Map<String, _CartLine> _cart = {};
  final NumberFormat _numFmt = NumberFormat('#,##0.00');

  CustomerModel? _selectedCustomer;
  FastCheckoutMode _checkoutMode = FastCheckoutMode.paidNow;
  String _paymentMethod = 'cash';
  bool _printReceipt = false;
  bool _isResolvingAdd = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductProvider>().loadAnalytics();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<_CartLine> get _cartLines => _cart.values.toList();

  int get _cartItemCount =>
      _cartLines.fold(0, (sum, line) => sum + line.quantity);

  String _key(String productId, String location) => '$productId|$location';

  String get _currencySymbol {
    final s = context.read<BillingSettingsProvider>().settings.currencySymbol;
    return s.isNotEmpty ? s : '₹';
  }

  /// Locations that currently hold available stock for [product], best first.
  /// Falls back to the default location when the product has no per-location
  /// data but still reports availability (legacy / unlocated stock).
  List<String> _locationsWithStock(ProductModel product) {
    final configured = context.read<SettingsProvider>().locations;
    final all = <String>{...configured, ...product.locationQuantities.keys};
    final locs = all
        .where((l) => l.trim().isNotEmpty && product.availableAtLocation(l) > 0)
        .toList()
      ..sort(
        (a, b) =>
            product.availableAtLocation(b).compareTo(product.availableAtLocation(a)),
      );
    if (locs.isEmpty && product.availableQuantity > 0) {
      return [configured.isNotEmpty ? configured.first : 'Main'];
    }
    return locs;
  }

  Future<List<ProductModel>> _ensureProductCatalogReady({
    bool showFeedback = true,
  }) async {
    final productProvider = context.read<ProductProvider>();
    var products = productProvider.analyticsProducts;
    if (products.isNotEmpty) return products;

    try {
      await productProvider.loadAnalytics();
      products = productProvider.analyticsProducts;
    } catch (_) {}

    if (products.isEmpty && mounted && showFeedback) {
      final msg = productProvider.errorMessage;
      showInfoSnackBar(
        context,
        msg == null || msg.isEmpty
            ? 'Products are still syncing. Please try again in a moment.'
            : msg,
      );
    }
    return products;
  }

  Future<void> _resolveQueryAndAdd(
    String rawQuery, {
    bool preferBarcode = false,
  }) async {
    if (_isResolvingAdd) return;
    setState(() => _isResolvingAdd = true);
    try {
      final query = rawQuery.trim();
      if (query.isEmpty) {
        await _pickProduct();
        return;
      }
      final products = await _ensureProductCatalogReady();
      if (!mounted || products.isEmpty) return;

      final candidates = rankedProductsByBarcodeOrName(products, query, limit: 50);
      if (candidates.isEmpty) {
        showInfoSnackBar(context, 'No product found for "$query"');
        return;
      }

      final barcodeMatches = candidates
          .where((p) => productMatchesBarcodeScan(p, query))
          .toList();
      if (barcodeMatches.length == 1) {
        await _addProduct(barcodeMatches.first);
        return;
      }

      final exactNameMatches = candidates
          .where((p) => p.name.toLowerCase() == query.toLowerCase())
          .toList();
      if (exactNameMatches.length == 1) {
        await _addProduct(exactNameMatches.first);
        return;
      }

      if (!preferBarcode && candidates.length == 1) {
        await _addProduct(candidates.first);
        return;
      }

      final top = candidates.take(20).toList();
      final selected = await showSearchablePicker(
        context: context,
        title: 'Pick product',
        items: top
            .map(
              (p) => PickerItem(
                value: p.id,
                label: p.name,
                subtitle: p.barcode.isEmpty
                    ? 'Stock ${p.availableQuantity} ${p.baseUnit}'
                    : '${p.barcode} • Stock ${p.availableQuantity} ${p.baseUnit}',
              ),
            )
            .toList(),
      );
      if (!mounted || selected == null) return;
      await _addProduct(top.firstWhere((p) => p.id == selected));
    } finally {
      if (mounted) {
        setState(() => _isResolvingAdd = false);
      }
    }
  }

  Future<void> _pickProduct() async {
    final products = await _ensureProductCatalogReady();
    if (!mounted || products.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: Responsive.sheetConstraints(context),
      builder: (_) => _ProductPickerSheet(
        products: products,
        symbol: _currencySymbol,
        numFmt: _numFmt,
        locationsWithStock: _locationsWithStock,
        onAddAtLocation: _tryAddAtLocation,
      ),
    );
  }

  Future<void> _scanAndAdd() async {
    final code = await Navigator.pushNamed(
      context,
      AppRoutes.barcodeScanner,
      arguments: const BarcodeScannerArgs(captureOnly: true),
    );
    if (!mounted || code is! String || code.trim().isEmpty) return;
    await _resolveQueryAndAdd(code.trim(), preferBarcode: true);
  }

  /// Attempts to add one unit of [product] at [location]. Returns an error
  /// message when it cannot, or null on success.
  String? _tryAddAtLocation(ProductModel product, String location) {
    final key = _key(product.id, location);
    final existing = _cart[key];
    final available = product.availableAtLocation(location);
    final nextQty = (existing?.quantity ?? 0) + 1;
    if (available <= 0) {
      return '${product.name} is out of stock at $location.';
    }
    if (nextQty > available) {
      return 'Only $available ${product.baseUnit} available at $location.';
    }
    setState(() {
      if (existing != null) {
        _cart[key] = existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _cart[key] = _CartLine(
          product: product,
          quantity: 1,
          unitPrice: product.sellingPrice,
          location: location,
        );
      }
    });
    HapticFeedback.selectionClick();
    return null;
  }

  Future<void> _addProduct(ProductModel product, {String? location}) async {
    var loc = location;
    if (loc == null) {
      final locs = _locationsWithStock(product);
      if (locs.isEmpty) {
        showInfoSnackBar(context, '${product.name} is out of available stock.');
        return;
      }
      if (locs.length == 1) {
        loc = locs.first;
      } else {
        loc = await _chooseLocation(product);
        if (!mounted || loc == null) return;
      }
    }
    final err = _tryAddAtLocation(product, loc);
    if (err != null && mounted) {
      showInfoSnackBar(context, err);
    }
  }

  Future<String?> _chooseLocation(
    ProductModel product, {
    String? current,
  }) async {
    final locs = _locationsWithStock(product);
    if (locs.isEmpty) {
      showInfoSnackBar(context, '${product.name} is out of available stock.');
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface(context),
      constraints: Responsive.sheetConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.dividerStrongC(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    const Icon(Icons.warehouse_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select location • ${product.name}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: locs.length,
                  itemBuilder: (_, i) {
                    final loc = locs[i];
                    final isCurrent = loc == current;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppTheme.primaryColor.withValues(alpha: 0.12),
                        child: Text(
                          '${product.availableAtLocation(loc)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      title: Text(loc),
                      subtitle: Text(
                        '${product.availableAtLocation(loc)} ${product.baseUnit} available',
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check_circle_rounded)
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(ctx, loc);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _changeQty(_CartLine line, int delta) {
    final next = line.quantity + delta;
    final available = line.product.availableAtLocation(line.location);
    if (next > available) {
      showInfoSnackBar(
        context,
        'Only $available ${line.product.baseUnit} available at ${line.location}.',
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      final key = _key(line.product.id, line.location);
      if (next <= 0) {
        _cart.remove(key);
      } else {
        _cart[key] = line.copyWith(quantity: next);
      }
    });
  }

  void _setUnitPrice(_CartLine line, String value, {bool notify = false}) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) {
      if (notify) {
        showInfoSnackBar(context, 'Enter a valid price');
      }
      return;
    }
    setState(() {
      _cart[_key(line.product.id, line.location)] =
          line.copyWith(unitPrice: parsed);
    });
  }

  Future<void> _changeLineLocation(_CartLine line) async {
    final newLoc = await _chooseLocation(line.product, current: line.location);
    if (!mounted || newLoc == null || newLoc == line.location) return;
    final available = line.product.availableAtLocation(newLoc);
    if (available <= 0) {
      showInfoSnackBar(context, 'No stock at $newLoc.');
      return;
    }
    final oldKey = _key(line.product.id, line.location);
    final newKey = _key(line.product.id, newLoc);
    final existing = _cart[newKey];
    final combined = (existing?.quantity ?? 0) + line.quantity;
    final capped = combined > available ? available : combined;
    setState(() {
      _cart.remove(oldKey);
      _cart[newKey] = (existing ?? line).copyWith(
        quantity: capped,
        location: newLoc,
      );
    });
    if (capped < combined && mounted) {
      showInfoSnackBar(context, 'Capped to $available available at $newLoc.');
    }
  }

  Future<void> _openQtyEditor(_CartLine line) async {
    final controller = TextEditingController(text: '${line.quantity}');
    final qty = await showDialog<int>(
      context: context,
      builder: (context) {
        final maxQty = line.product.availableAtLocation(line.location);
        return AlertDialog(
          title: Text('Set quantity • ${line.product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available at ${line.location}: $maxQty ${line.product.baseUnit}'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: '0 to remove',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Remove'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < 0) {
                  showInfoSnackBar(context, 'Enter a valid quantity');
                  return;
                }
                if (parsed > maxQty) {
                  showInfoSnackBar(
                    context,
                    'Only $maxQty ${line.product.baseUnit} available.',
                  );
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    if (!mounted || qty == null) return;
    setState(() {
      final key = _key(line.product.id, line.location);
      if (qty <= 0) {
        _cart.remove(key);
      } else {
        _cart[key] = line.copyWith(quantity: qty);
      }
    });
  }

  Future<void> _openPriceEditor(_CartLine line) async {
    final controller = TextEditingController(
      text: line.unitPrice.toStringAsFixed(2),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Set price • ${line.product.name}'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Unit Price',
              hintText: 'Enter amount',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null || parsed < 0) {
                  showInfoSnackBar(context, 'Enter a valid price');
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    if (!mounted || value == null) return;
    _setUnitPrice(line, value.toStringAsFixed(2), notify: true);
  }

  Future<void> _pickCustomer() async {
    final customers = context.read<CustomerProvider>().activeCustomers;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Customer (optional)',
      selectedValue: _selectedCustomer?.id,
      items: customers
          .map(
            (c) =>
                PickerItem(value: c.id, label: c.name, subtitle: c.phone.isEmpty ? null : c.phone),
          )
          .toList(),
    );
    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedCustomer = customers.firstWhere((c) => c.id == selected);
    });
  }

  Future<bool> _revalidateCartStock() async {
    final productProvider = context.read<ProductProvider>();
    try {
      productProvider.invalidateAnalytics();
      await productProvider.loadAnalytics();
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'Could not refresh latest stock. Please try again.',
        );
      }
      return false;
    }
    if (!mounted) return false;
    final latestById = {
      for (final p in productProvider.analyticsProducts) p.id: p,
    };
    final issues = <String>[];
    final refreshed = <String, _CartLine>{};
    for (final line in _cartLines) {
      final latest = latestById[line.product.id];
      if (latest == null) {
        issues.add('${line.product.name} is no longer available.');
        continue;
      }
      final availableAtLocation = latest.availableAtLocation(line.location);
      if (availableAtLocation < line.quantity) {
        issues.add(
          '${latest.name}: need ${line.quantity}, ${line.location} has $availableAtLocation.',
        );
      }
      refreshed[_key(latest.id, line.location)] = line.copyWith(product: latest);
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(refreshed);
    });
    if (issues.isNotEmpty) {
      showErrorSnackBar(
        context,
        'Stock changed. Please update cart.\n${issues.take(3).join('\n')}',
      );
      return false;
    }
    return true;
  }

  /// Runs the full checkout. Returns the invoice number on success, else null.
  Future<String?> _completeSale() async {
    if (_cart.isEmpty) {
      showInfoSnackBar(context, 'Add at least one item');
      return null;
    }
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      showErrorSnackBar(context, 'Session expired. Please login again.');
      return null;
    }

    final billing = context.read<BillingProvider>();
    final bs = context.read<BillingSettingsProvider>().settings;
    final defaultLocation =
        context.read<SettingsProvider>().locations.firstOrNull ?? 'Main';
    final cartIsValid = await _revalidateCartStock();
    if (!mounted) return null;
    if (!cartIsValid) return null;
    final now = DateTime.now();

    final invoiceNumber = await billing.getNextInvoiceNumber(bs.invoicePrefix);
    if (!mounted) return null;
    if (invoiceNumber == null) {
      showErrorSnackBar(context, 'Could not generate invoice number');
      return null;
    }

    final payload = buildFastPosInvoice(
      cartEntries: _cartLines
          .map(
            (line) => FastPosCartEntry(
              product: line.product,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              location: line.location,
            ),
          )
          .toList(),
      billingSettings: bs,
      invoiceNumber: invoiceNumber,
      now: now,
      userId: user.uid,
      userName: user.name,
      customer: _selectedCustomer,
      mode: _checkoutMode,
      paymentMethod: _paymentMethod,
    );
    if (payload.totals.grandTotal <= 0) {
      showInfoSnackBar(context, 'Total must be greater than 0');
      return null;
    }

    final id = await billing.addInvoice(
      payload.invoice,
      userId: user.uid,
      userName: user.name,
      defaultLocation: defaultLocation,
      autoCreateStandaloneSalesOrder: bs.autoCreateSalesOrderForStandaloneSales,
    );
    if (!mounted) return null;
    if (id == null) {
      showErrorSnackBar(
        context,
        billing.errorMessage ?? 'Failed to complete checkout',
      );
      return null;
    }

    final syncWarning = billing.errorMessage;
    if (syncWarning != null && syncWarning.isNotEmpty) {
      showInfoSnackBar(context, syncWarning);
    }

    final productProvider = context.read<ProductProvider>();
    productProvider.invalidateAnalytics();
    try {
      await productProvider.loadAnalytics();
    } catch (_) {}

    if (_printReceipt) {
      try {
        final toPrint = payload.invoice.copyWith(id: id);
        await BillingPdfService().printReceipt(toPrint, bs);
      } catch (_) {
        if (mounted) {
          showInfoSnackBar(context, 'Sale saved, but receipt print failed');
        }
      }
    }

    setState(() {
      _cart.clear();
      _selectedCustomer = null;
      _checkoutMode = FastCheckoutMode.paidNow;
      _paymentMethod = 'cash';
    });
    return invoiceNumber;
  }

  Future<void> _openCheckoutSheet() async {
    if (_cart.isEmpty) {
      showInfoSnackBar(context, 'Add at least one item');
      return;
    }
    final invoiceNumber = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: Responsive.sheetConstraints(context),
      builder: (sheetCtx) {
        var saving = false;
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final bs = context.read<BillingSettingsProvider>().settings;
            final symbol = _currencySymbol;
            final payload = buildFastPosInvoice(
              cartEntries: _cartLines
                  .map(
                    (line) => FastPosCartEntry(
                      product: line.product,
                      quantity: line.quantity,
                      unitPrice: line.unitPrice,
                      location: line.location,
                    ),
                  )
                  .toList(),
              billingSettings: bs,
              invoiceNumber: 'PREVIEW',
              now: DateTime.now(),
              userId: '',
              userName: '',
              customer: _selectedCustomer,
              mode: _checkoutMode,
              paymentMethod: _paymentMethod,
            );
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.surface(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppTheme.dividerStrongC(context),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.point_of_sale_rounded),
                            const SizedBox(width: 8),
                            Text(
                              'Checkout',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Text('$_cartItemCount items'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _CheckoutRow(
                          label: 'Subtotal',
                          value: '$symbol${_numFmt.format(payload.totals.subtotal)}',
                        ),
                        if (payload.totals.totalTax > 0)
                          _CheckoutRow(
                            label: bs.taxLabel,
                            value:
                                '$symbol${_numFmt.format(payload.totals.totalTax)}',
                          ),
                        const Divider(height: 18),
                        _CheckoutRow(
                          label: 'Grand Total',
                          value:
                              '$symbol${_numFmt.format(payload.totals.grandTotal)}',
                          bold: true,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Paid Now'),
                              selected: _checkoutMode == FastCheckoutMode.paidNow,
                              onSelected: (_) {
                                _checkoutMode = FastCheckoutMode.paidNow;
                                setSheet(() {});
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Credit'),
                              selected: _checkoutMode == FastCheckoutMode.credit,
                              onSelected: (_) {
                                _checkoutMode = FastCheckoutMode.credit;
                                setSheet(() {});
                              },
                            ),
                          ],
                        ),
                        if (_checkoutMode == FastCheckoutMode.paidNow) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final m in const [
                                ['cash', 'Cash'],
                                ['upi', 'UPI'],
                                ['card', 'Card'],
                                ['bank', 'Bank'],
                              ])
                                ChoiceChip(
                                  label: Text(m[1]),
                                  selected: _paymentMethod == m[0],
                                  onSelected: (_) {
                                    _paymentMethod = m[0];
                                    setSheet(() {});
                                  },
                                ),
                            ],
                          ),
                        ],
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Print receipt'),
                          value: _printReceipt,
                          onChanged: (value) {
                            _printReceipt = value ?? false;
                            setSheet(() {});
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final navigator = Navigator.of(sheetCtx);
                                    setSheet(() => saving = true);
                                    final inv = await _completeSale();
                                    if (!mounted) return;
                                    if (inv != null) {
                                      navigator.pop(inv);
                                    } else {
                                      setSheet(() => saving = false);
                                    }
                                  },
                            icon: saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded),
                            label: Text(
                              saving
                                  ? 'Processing...'
                                  : 'Complete Sale  •  $symbol${_numFmt.format(payload.totals.grandTotal)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted || invoiceNumber == null) return;
    await showSuccessOverlay(
      context,
      message: 'Sale saved: $invoiceNumber',
      popAfter: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user != null &&
        (!user.hasPermission(AppPermissions.useFastPos) ||
            !user.hasPermission(AppPermissions.createInvoices))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fast POS')),
        body: const Center(
          child: Text('You do not have permission to access this feature.'),
        ),
      );
    }

    final bs = context.watch<BillingSettingsProvider>().settings;
    final billing = context.watch<BillingProvider>();
    final productProvider = context.watch<ProductProvider>();
    final products = productProvider.analyticsProducts;
    final favorites = context.watch<FavoritesProvider>().ids;
    final symbol = bs.currencySymbol.isNotEmpty ? bs.currencySymbol : '₹';
    final favoriteProducts = products
        .where((p) => favorites.contains(p.id))
        .take(10)
        .toList();

    final payload = buildFastPosInvoice(
      cartEntries: _cartLines
          .map(
            (line) => FastPosCartEntry(
              product: line.product,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              location: line.location,
            ),
          )
          .toList(),
      billingSettings: bs,
      invoiceNumber: 'PREVIEW',
      now: DateTime.now(),
      userId: '',
      userName: '',
      customer: _selectedCustomer,
      mode: _checkoutMode,
      paymentMethod: _paymentMethod,
    );

    final customerDue = _selectedCustomer == null
        ? 0.0
        : billing.customerOutstanding(_selectedCustomer!.id);
    final isMobile = Responsive.isMobile(context);
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fast POS'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            onPressed: _scanAndAdd,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Search product',
            onPressed: _pickProduct,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  _SearchEntryCard(
                    busy: _isResolvingAdd,
                    enabled:
                        !(productProvider.isLoadingAnalytics && products.isEmpty),
                    onTap: _pickProduct,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickCustomer,
                          icon: const Icon(Icons.person_outline_rounded),
                          label: Text(
                            _selectedCustomer == null
                                ? 'Walk-in'
                                : _selectedCustomer!.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _scanAndAdd,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(isMobile ? 'Scan' : 'Scan Barcode'),
                      ),
                    ],
                  ),
                  if (productProvider.isLoadingAnalytics && products.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Syncing products...'),
                      ),
                    ),
                  if (!productProvider.isLoadingAnalytics && products.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'No products loaded yet. Refresh product sync.',
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                context.read<ProductProvider>().loadAnalytics();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_selectedCustomer != null && customerDue > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Outstanding: $symbol${_numFmt.format(customerDue)}',
                          style: TextStyle(
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (favoriteProducts.isNotEmpty && !(isMobile && isKeyboardOpen))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.dividerC(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick picks',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            final product = favoriteProducts[index];
                            return ActionChip(
                              avatar:
                                  const Icon(Icons.favorite_rounded, size: 16),
                              label: Text(product.name),
                              onPressed: () => _addProduct(product),
                            );
                          },
                          separatorBuilder: (_, idx) => const SizedBox(width: 8),
                          itemCount: favoriteProducts.length,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _cart.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.point_of_sale_rounded,
                      title: 'Cart is empty',
                      subtitle:
                          'Scan barcode or add products to start a fast sale.',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _cartLines.length,
                      itemBuilder: (context, index) {
                        final line = _cartLines[index];
                        return _CartItemCard(
                          line: line,
                          symbol: symbol,
                          numFmt: _numFmt,
                          isMobile: isMobile,
                          onDecrement: () => _changeQty(line, -1),
                          onIncrement: () => _changeQty(line, 1),
                          onEditQty: () => _openQtyEditor(line),
                          onEditPrice: () => _openPriceEditor(line),
                          onChangeLocation: () => _changeLineLocation(line),
                          onCommitPrice: (value) =>
                              _setUnitPrice(line, value, notify: true),
                        );
                      },
                    ),
            ),
            if (_cart.isNotEmpty)
              _CartBar(
                symbol: symbol,
                itemCount: _cartItemCount,
                grandTotal: payload.totals.grandTotal,
                numFmt: _numFmt,
                onCheckout: _openCheckoutSheet,
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchEntryCard extends StatelessWidget {
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  const _SearchEntryCard({
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(28),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: AppTheme.surface(context),
          border: Border.all(color: AppTheme.dividerC(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search products',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Tap to search by name or barcode',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  final String symbol;
  final int itemCount;
  final double grandTotal;
  final NumberFormat numFmt;
  final VoidCallback onCheckout;

  const _CartBar({
    required this.symbol,
    required this.itemCount,
    required this.grandTotal,
    required this.numFmt,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface(context),
      elevation: 12,
      child: InkWell(
        onTap: onCheckout,
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border(top: BorderSide(color: AppTheme.dividerC(context))),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_cart_rounded, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$itemCount item${itemCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        '$symbol${numFmt.format(grandTotal)}',
                        key: ValueKey(grandTotal),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onCheckout,
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Checkout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final _CartLine line;
  final String symbol;
  final NumberFormat numFmt;
  final bool isMobile;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onEditQty;
  final VoidCallback onEditPrice;
  final VoidCallback onChangeLocation;
  final ValueChanged<String> onCommitPrice;

  const _CartItemCard({
    required this.line,
    required this.symbol,
    required this.numFmt,
    required this.isMobile,
    required this.onDecrement,
    required this.onIncrement,
    required this.onEditQty,
    required this.onEditPrice,
    required this.onChangeLocation,
    required this.onCommitPrice,
  });

  Widget _locationChip(BuildContext context) {
    final available = line.product.availableAtLocation(line.location);
    return InkWell(
      onTap: onChangeLocation,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warehouse_rounded, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${line.location.isEmpty ? 'Default' : line.location} • $available',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _qtyControls(BuildContext context, {double minWidth = 56}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_rounded),
        ),
        InkWell(
          onTap: onEditQty,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: BoxConstraints(minWidth: minWidth, minHeight: 44),
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.dividerC(context)),
            ),
            child: Text(
              '${line.quantity}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: onIncrement,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.product.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _locationChip(context),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onEditPrice,
                        icon: const Icon(Icons.sell_rounded, size: 16),
                        label: Text('$symbol${numFmt.format(line.unitPrice)}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _qtyControls(context),
                      Text(
                        '$symbol${numFmt.format(line.lineTotal)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.product.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _locationChip(context),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 120,
                              child: _UnitPriceField(
                                value: line.unitPrice,
                                onCommit: onCommitPrice,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      _qtyControls(context, minWidth: 64),
                      Text(
                        '$symbol${numFmt.format(line.lineTotal)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final List<ProductModel> products;
  final String symbol;
  final NumberFormat numFmt;
  final List<String> Function(ProductModel) locationsWithStock;
  final String? Function(ProductModel, String) onAddAtLocation;

  const _ProductPickerSheet({
    required this.products,
    required this.symbol,
    required this.numFmt,
    required this.locationsWithStock,
    required this.onAddAtLocation,
  });

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  int _addedCount = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleAdd(ProductModel product, String location) {
    final err = widget.onAddAtLocation(product, location);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (err != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 2)),
      );
      return;
    }
    setState(() => _addedCount++);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added ${product.name} ($location)'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final results = q.isEmpty
        ? widget.products.take(60).toList()
        : rankedProductsByBarcodeOrName(widget.products, q, limit: 60);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.5, 0.85, 0.95],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.dividerStrongC(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Text(
                      'Add products',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (_addedCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '$_addedCount added',
                          style: TextStyle(
                            color: AppTheme.successColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search name or barcode',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          'No products found',
                          style: TextStyle(color: AppTheme.textSec(context)),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final product = results[index];
                          final locs = widget.locationsWithStock(product);
                          return _PickerProductCard(
                            product: product,
                            locations: locs,
                            symbol: widget.symbol,
                            numFmt: widget.numFmt,
                            onAdd: (loc) => _handleAdd(product, loc),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PickerProductCard extends StatelessWidget {
  final ProductModel product;
  final List<String> locations;
  final String symbol;
  final NumberFormat numFmt;
  final ValueChanged<String> onAdd;

  const _PickerProductCard({
    required this.product,
    required this.locations,
    required this.symbol,
    required this.numFmt,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final outOfStock = locations.isEmpty;
    final singleLocation = locations.length == 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (outOfStock || !singleLocation)
            ? null
            : () => onAdd(locations.first),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$symbol${numFmt.format(product.sellingPrice)} • ${product.availableQuantity} ${product.baseUnit} total',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (singleLocation)
                    Icon(Icons.add_circle_rounded,
                        color: AppTheme.primaryColor),
                ],
              ),
              if (outOfStock) ...[
                const SizedBox(height: 8),
                Text(
                  'Out of stock',
                  style: TextStyle(
                    color: AppTheme.dangerColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ] else if (!singleLocation) ...[
                const SizedBox(height: 10),
                Text(
                  'Choose location to add',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSec(context),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final loc in locations)
                      ActionChip(
                        avatar: const Icon(Icons.warehouse_rounded, size: 16),
                        label: Text(
                          '$loc • ${product.availableAtLocation(loc)}',
                        ),
                        onPressed: () => onAdd(loc),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLine {
  final ProductModel product;
  final int quantity;
  final double unitPrice;
  final String location;

  const _CartLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.location,
  });

  double get lineTotal => quantity * unitPrice;

  _CartLine copyWith({
    ProductModel? product,
    int? quantity,
    double? unitPrice,
    String? location,
  }) {
    return _CartLine(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      location: location ?? this.location,
    );
  }
}

class _CheckoutRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _CheckoutRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              fontSize: bold ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitPriceField extends StatefulWidget {
  final double value;
  final ValueChanged<String> onCommit;

  const _UnitPriceField({required this.value, required this.onCommit});

  @override
  State<_UnitPriceField> createState() => _UnitPriceFieldState();
}

class _UnitPriceFieldState extends State<_UnitPriceField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(2));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onCommit(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _UnitPriceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.value - widget.value).abs() > 0.0001 &&
        !_focusNode.hasFocus) {
      _controller.text = widget.value.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        labelText: 'Price',
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onCommit,
    );
  }
}
