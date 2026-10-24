import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/feature_map.dart';
import '../../config/feature_visibility.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../utils/responsive.dart';
import '../../utils/invoice_search.dart';
import '../../utils/product_search.dart';
import '../../models/vendor_model.dart';
import '../../models/customer_model.dart';
import '../../models/invoice_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/billing_provider.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/animations.dart';
import '../../utils/currency.dart';
import '../../utils/debouncer.dart';
import '../../utils/date_formats.dart';

enum _SearchCategory { all, products, customers, vendors, invoices, features }

/// What the signed-in user may search. Vendors and customers used to be listed
/// to everyone, including people whose role cannot open either list, and
/// vendors showed with the Vendors switch off.
class _SearchAccess {
  _SearchAccess(FeatureVisibility vis)
    : products = vis.has(AppPermissions.viewProducts),
      customers = vis.has(AppPermissions.viewCustomers),
      vendors = vis.gates.vendors && vis.has(AppPermissions.viewVendors),
      invoices = vis.gates.billing && vis.has(AppPermissions.viewInvoices);

  final bool products;
  final bool customers;
  final bool vendors;
  final bool invoices;

  bool allows(_SearchCategory c) => switch (c) {
    _SearchCategory.all || _SearchCategory.features => true,
    _SearchCategory.products => products,
    _SearchCategory.customers => customers,
    _SearchCategory.vendors => vendors,
    _SearchCategory.invoices => invoices,
  };

  /// "products, customers and features", for the hint and empty state.
  String describe() {
    final parts = [
      if (products) 'products',
      if (customers) 'customers',
      if (vendors) 'vendors',
      if (invoices) 'invoices',
      'features',
    ];
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _searchController = TextEditingController();
  final _searchDebounce = Debouncer();
  String _query = '';
  final List<String> _recentSearches = [];
  _SearchCategory _selectedCategory = _SearchCategory.all;

  List<RankedProductSearchItem> _productResults = [];
  ProductProvider? _productProviderRef;
  bool _hadFullProductCatalog = false;
  List<VendorModel> _vendorResults = [];
  List<CustomerModel> _customerResults = [];
  List<InvoiceModel> _invoiceResults = [];
  List<FeatureEntry> _featureResults = [];

  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;

  bool _hasFilteredResults() {
    switch (_selectedCategory) {
      case _SearchCategory.all:
        return _productResults.isNotEmpty ||
            _vendorResults.isNotEmpty ||
            _customerResults.isNotEmpty ||
            _invoiceResults.isNotEmpty ||
            _featureResults.isNotEmpty;
      case _SearchCategory.products:
        return _productResults.isNotEmpty;
      case _SearchCategory.vendors:
        return _vendorResults.isNotEmpty;
      case _SearchCategory.customers:
        return _customerResults.isNotEmpty;
      case _SearchCategory.invoices:
        return _invoiceResults.isNotEmpty;
      case _SearchCategory.features:
        return _featureResults.isNotEmpty;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pp = context.read<ProductProvider>();
      _productProviderRef = pp;
      pp.addListener(_onProductCatalogChanged);
      _hadFullProductCatalog = pp.isAnalyticsLoaded;
      if (!pp.isAnalyticsLoaded && !pp.isLoadingAnalytics) {
        pp.loadAnalytics();
      }
    });
  }

  void _onProductCatalogChanged() {
    if (!mounted) return;
    final pp = _productProviderRef ?? context.read<ProductProvider>();
    final full = pp.isAnalyticsLoaded;
    if (full && !_hadFullProductCatalog && _query.isNotEmpty) {
      _hadFullProductCatalog = true;
      _performSearch(_query);
    } else if (!full) {
      _hadFullProductCatalog = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = _SearchAccess(FeatureVisibility.read(context));
    if (!access.allows(_selectedCategory)) {
      setState(() => _selectedCategory = _SearchCategory.all);
    }
  }

  @override
  void dispose() {
    _productProviderRef?.removeListener(_onProductCatalogChanged);
    _searchController.dispose();
    _searchDebounce.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentSearchesKey);
    if (list != null && mounted) {
      setState(
        () => _recentSearches
          ..clear()
          ..addAll(list),
      );
    }
  }

  Future<void> _saveRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
  }

  void _onSearchChanged(String value) {
    _searchDebounce.run(() => _performSearch(value.trim()));
  }

  void _performSearch(String query) {
    setState(() => _query = query);

    if (query.isEmpty) {
      setState(() {
        _productResults = [];
        _vendorResults = [];
        _customerResults = [];
        _invoiceResults = [];
        _featureResults = [];
      });
      return;
    }

    final lower = query.toLowerCase();
    final vis = FeatureVisibility.read(context);
    final access = _SearchAccess(vis);
    final productProvider = context.read<ProductProvider>();
    final catalog = productProvider.isAnalyticsLoaded
        ? productProvider.analyticsProducts
        : productProvider.allProducts;
    final productLimit = _selectedCategory == _SearchCategory.products
        ? 100
        : 24;
    final vendors = context.read<VendorProvider>().vendors;
    final customers = context.read<CustomerProvider>().customers;

    setState(() {
      _productResults = access.products
          ? searchProductsRanked(catalog, query, limit: productLimit)
          : [];

      _vendorResults = access.vendors
          ? vendors
                .where((v) => v.name.toLowerCase().contains(lower))
                .take(10)
                .toList()
          : [];

      _customerResults = access.customers
          ? customers
                .where(
                  (c) =>
                      c.name.toLowerCase().contains(lower) ||
                      c.email.toLowerCase().contains(lower) ||
                      c.phone.toLowerCase().contains(lower),
                )
                .take(10)
                .toList()
          : [];

      if (access.invoices) {
        final billing = context.read<BillingProvider>();
        _invoiceResults = billing.invoices
            .where((i) => invoiceMatchesSearch(i, query))
            .take(15)
            .toList();
      } else {
        _invoiceResults = [];
      }

      _featureResults = vis.searchFeatures(
        query,
        limit: _selectedCategory == _SearchCategory.features ? 30 : 4,
      );
    });
  }

  void _onRecentTap(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _performSearch(query);
  }

  void _addToRecentSearches(String query) {
    if (query.isEmpty) return;
    setState(() {
      _recentSearches.remove(query);
      _recentSearches.insert(0, query);
      while (_recentSearches.length > _maxRecentSearches) {
        _recentSearches.removeLast();
      }
    });
    _saveRecentSearches();
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final access = _SearchAccess(FeatureVisibility.watch(context));
    final searchHint = 'Search ${access.describe()}…';

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: searchHint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: _onSearchChanged,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Container(
            decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_query.isNotEmpty) ...[
                  _buildCategoryTabs(access),
                  if (access.products && !productProvider.isAnalyticsLoaded)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        Responsive.horizontalPadding(context),
                        0,
                        Responsive.horizontalPadding(context),
                        8,
                      ),
                      child: Text(
                        'Showing matches from inventory loaded so far. Full catalog is still loading.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ),
                ],
                Expanded(
                  child: _query.isEmpty
                      ? _buildRecentSearches(access)
                      : _buildResults(access),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSearches(_SearchAccess access) {
    if (_recentSearches.isEmpty) {
      final what = access.describe();
      return EmptyStateWidget(
        icon: Icons.search_rounded,
        title: 'Search Everything',
        subtitle: access.products
            ? 'Find $what. For products, try a name, barcode or location, '
                  'or filters like stock:low or cat:snacks.'
            : 'Find $what by name.',
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 16,
      ),
      children: [
        Row(
          children: [
            Icon(
              Icons.history_rounded,
              size: 18,
              color: AppTheme.textSec(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Recent Searches',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSec(context),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() => _recentSearches.clear());
                _saveRecentSearches();
              },
              child: const Text('Clear', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _recentSearches.map((q) {
            return ActionChip(
              avatar: Icon(
                Icons.history_rounded,
                size: 16,
                color: AppTheme.textSec(context),
              ),
              label: Text(q),
              onPressed: () => _onRecentTap(q),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryTabs(_SearchAccess access) {
    final categories = _SearchCategory.values.where(access.allows).toList();
    // The selected chip's label sat in light teal on a pale teal fill, about
    // 1.4:1; the darker shade reads in light mode and the lighter in dark.
    final selectedFg = AppTheme.isDark(context)
        ? AppTheme.primaryLight
        : AppTheme.primaryDark;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: categories.map((cat) {
            final isSelected = _selectedCategory == cat;
            final label = switch (cat) {
              _SearchCategory.all => 'All',
              _SearchCategory.products => 'Products',
              _SearchCategory.vendors => 'Vendors',
              _SearchCategory.customers => 'Customers',
              _SearchCategory.invoices => 'Invoices',
              _SearchCategory.features => 'Features',
            };
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? selectedFg
                        : AppTheme.textPri(context),
                  ),
                ),
                selected: isSelected,
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.16),
                backgroundColor: AppTheme.card(context),
                checkmarkColor: selectedFg,
                side: BorderSide(
                  color: isSelected
                      ? Colors.transparent
                      : AppTheme.dividerC(context),
                ),
                onSelected: (_) {
                  setState(() => _selectedCategory = cat);
                  if (_query.isNotEmpty) _performSearch(_query);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildResults(_SearchAccess access) {
    if (!_hasFilteredResults()) {
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No Results',
        subtitle: access.products
            ? 'No matches for "$_query". Try other words, or filters: '
                  'stock:out, stock:low, cat:name, company:name, loc:name, '
                  'vendor:name.'
            : 'No matches for "$_query". Try other words.',
      );
    }

    final showFeatures =
        _selectedCategory == _SearchCategory.all ||
        _selectedCategory == _SearchCategory.features;
    final showProducts =
        _selectedCategory == _SearchCategory.all ||
        _selectedCategory == _SearchCategory.products;
    final showVendors =
        _selectedCategory == _SearchCategory.all ||
        _selectedCategory == _SearchCategory.vendors;
    final showCustomers =
        _selectedCategory == _SearchCategory.all ||
        _selectedCategory == _SearchCategory.customers;
    final showInvoices =
        _selectedCategory == _SearchCategory.all ||
        _selectedCategory == _SearchCategory.invoices;

    // Build results with a running stagger index so every tile (across all
    // sections) fades + slides in sequentially.
    var staggerIndex = 0;
    Widget staggered(Widget child) =>
        FadeSlideIn(index: staggerIndex++, child: child);

    final children = <Widget>[];
    // Features first: there are only a few, and someone typing "ledger" or
    // "ageing" is looking for the screen, not a product.
    if (showFeatures && _featureResults.isNotEmpty) {
      children.add(
        staggered(
          _sectionHeader(
            Icons.apps_rounded,
            'Features',
            _featureResults.length,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.addAll(
        _featureResults.map((e) => staggered(_buildFeatureTile(e))),
      );
      children.add(const SizedBox(height: 16));
    }
    if (showProducts && _productResults.isNotEmpty) {
      children.add(
        staggered(
          _sectionHeader(
            Icons.inventory_2_rounded,
            'Products',
            _productResults.length,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.addAll(_productResults.map((p) => staggered(_buildProductTile(p))));
      children.add(const SizedBox(height: 16));
    }
    if (showVendors && _vendorResults.isNotEmpty) {
      children.add(
        staggered(
          _sectionHeader(
            Icons.local_shipping_rounded,
            'Vendors',
            _vendorResults.length,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.addAll(_vendorResults.map((v) => staggered(_buildVendorTile(v))));
      children.add(const SizedBox(height: 16));
    }
    if (showCustomers && _customerResults.isNotEmpty) {
      children.add(
        staggered(
          _sectionHeader(
            Icons.people_rounded,
            'Customers',
            _customerResults.length,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.addAll(
        _customerResults.map((c) => staggered(_buildCustomerTile(c))),
      );
      children.add(const SizedBox(height: 16));
    }
    if (showInvoices && _invoiceResults.isNotEmpty) {
      children.add(
        staggered(
          _sectionHeader(
            Icons.receipt_long_rounded,
            'Invoices',
            _invoiceResults.length,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.addAll(_invoiceResults.map((i) => staggered(_buildInvoiceTile(i))));
    }

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 16,
      ),
      children: children,
    );
  }

  /// Builds a [Text.rich] that highlights every case-insensitive occurrence of
  /// [query] within [text] using [AppTheme.primaryColor]. Falls back to a plain
  /// [Text] when there is no match.
  Widget _highlightedText(
    String text,
    String query, {
    required TextStyle baseStyle,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var idx = lowerText.indexOf(lowerQuery);
    if (idx < 0) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }
    final highlightStyle = baseStyle.copyWith(
      color: AppTheme.primaryColor,
      fontWeight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    var start = 0;
    while (idx >= 0) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + lowerQuery.length),
          style: highlightStyle,
        ),
      );
      start = idx + lowerQuery.length;
      idx = lowerText.indexOf(lowerQuery, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  Widget _sectionHeader(IconData icon, String title, int count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(
          '$title ($count)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPri(context),
          ),
        ),
      ],
    );
  }

  Widget _buildProductTile(RankedProductSearchItem item) {
    final product = item.product;
    final stockColor = AppTheme.getStockColor(
      product.quantity,
      threshold: product.lowStockThreshold,
    );
    final baseLine =
        '${product.categoryName.isNotEmpty ? product.categoryName : "—"} • ${product.quantity} ${product.unit}';
    final subtitle = item.matchHint != null
        ? '$baseLine · ${item.matchHint}'
        : baseLine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 14,
        child: ListTile(
          onTap: () {
            _addToRecentSearches(_query);
            Navigator.pushNamed(
              context,
              AppRoutes.productDetail,
              arguments: product,
            );
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: stockColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.inventory_2_rounded, color: stockColor, size: 20),
          ),
          title: _highlightedText(
            product.name,
            _query,
            baseStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textPri(context),
            ),
          ),
          subtitle: _highlightedText(
            subtitle,
            _query,
            baseStyle: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile(FeatureEntry entry) {
    final color = FeatureMap.categoryColor(entry.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 14,
        child: ListTile(
          onTap: () {
            _addToRecentSearches(_query);
            Navigator.pushNamed(context, entry.route);
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(entry.icon, color: color, size: 20),
          ),
          title: _highlightedText(
            entry.label,
            _query,
            baseStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textPri(context),
            ),
          ),
          subtitle: _highlightedText(
            entry.subtitle,
            _query,
            baseStyle: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }

  Widget _buildVendorTile(VendorModel vendor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 14,
        child: ListTile(
          onTap: () {
            _addToRecentSearches(_query);
            Navigator.pushNamed(
              context,
              AppRoutes.vendorDetail,
              arguments: vendor,
            );
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: AppTheme.infoColor,
              size: 20,
            ),
          ),
          title: _highlightedText(
            vendor.name,
            _query,
            baseStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textPri(context),
            ),
          ),
          subtitle: _highlightedText(
            vendor.phone.isNotEmpty ? vendor.phone : vendor.email,
            _query,
            baseStyle: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceTile(InvoiceModel invoice) {
    final dateFmt = AppDates.day;
    final symUse = Money.symbolOf(context, listen: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 14,
        child: ListTile(
          onTap: () {
            _addToRecentSearches(_query);
            Navigator.pushNamed(
              context,
              AppRoutes.invoiceDetail,
              arguments: invoice.id,
            );
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              invoice.isPurchase
                  ? Icons.shopping_bag_rounded
                  : Icons.receipt_long_rounded,
              color: AppTheme.primaryColor,
              size: 20,
            ),
          ),
          title: _highlightedText(
            invoice.invoiceNumber,
            _query,
            baseStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textPri(context),
            ),
          ),
          subtitle: _highlightedText(
            '${invoice.partyName.isNotEmpty ? invoice.partyName : "—"} • ${dateFmt.format(invoice.invoiceDate)} • $symUse${Money.number(invoice.grandTotal)}',
            _query,
            baseStyle: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerTile(CustomerModel customer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 14,
        child: ListTile(
          onTap: () {
            _addToRecentSearches(_query);
            Navigator.pushNamed(
              context,
              AppRoutes.customerDetail,
              arguments: customer.id,
            );
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.indigoColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppTheme.indigoColor,
              size: 20,
            ),
          ),
          title: _highlightedText(
            customer.name,
            _query,
            baseStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppTheme.textPri(context),
            ),
          ),
          subtitle: _highlightedText(
            customer.phone.isNotEmpty ? customer.phone : customer.email,
            _query,
            baseStyle: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.textSec(context),
          ),
        ),
      ),
    );
  }
}
