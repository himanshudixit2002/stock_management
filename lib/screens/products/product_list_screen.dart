import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showFilters = false;
  bool _showScrollTop = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _scrollController.offset > 300;
    if (show != _showScrollTop) setState(() => _showScrollTop = show);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final isAdmin = context.watch<AuthProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Products (${productProvider.products.length})'),
          ],
        ),
        automaticallyImplyLeading: true,
        actions: [
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.inputFillColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.sort_rounded, size: 20),
            ),
            tooltip: 'Sort',
            onSelected: (value) {
              productProvider.sortProducts(value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'name', child: Text('Name (A-Z)')),
              const PopupMenuItem(
                  value: 'quantity',
                  child: Text('Stock (Low-High)')),
              const PopupMenuItem(
                  value: 'quantity_desc',
                  child: Text('Stock (High-Low)')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
          child: Column(
        children: [
          // Search bar + filter toggle
          Padding(
            padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 8, Responsive.horizontalPadding(context), 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 20),
                              onPressed: () {
                                _searchController.clear();
                                productProvider.search('');
                              },
                            )
                          : null,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      _debounce?.cancel();
                      _debounce = Timer(
                          const Duration(milliseconds: 300), () {
                        productProvider.search(value);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Filter button with badge
                Material(
                  color: _showFilters ||
                          productProvider.activeFilterCount > 0
                      ? AppTheme.primaryColor
                      : AppTheme.inputFillColor,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      setState(() => _showFilters = !_showFilters);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _showFilters ||
                                  productProvider.activeFilterCount > 0
                              ? AppTheme.primaryColor
                              : AppTheme.inputBorderColor,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            color: _showFilters ||
                                    productProvider.activeFilterCount > 0
                                ? Colors.white
                                : AppTheme.textSecondary,
                            size: 22,
                          ),
                          if (productProvider.activeFilterCount > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${productProvider.activeFilterCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expandable filter section with smooth animation
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child: _showFilters
                ? _FilterSection(
                    key: const ValueKey('filters'),
                    productProvider: productProvider,
                    categoryProvider: categoryProvider,
                  )
                : const SizedBox.shrink(),
          ),

          // Results count
          if (productProvider.hasActiveFilters)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '${productProvider.products.length} results',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        productProvider.clearFilters();
                        _searchController.clear();
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Text(
                          'Clear all',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Product list with pull-to-refresh
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                productProvider.initialize(companyId: productProvider.companyId);
              },
              child: productProvider.isLoading
                ? const ShimmerLoading(itemCount: 6, layout: ShimmerLayout.card)
                : productProvider.products.isEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: EmptyStateWidget(
                            icon: Icons.inventory_2_outlined,
                            title: 'No Products Found',
                            subtitle: _searchController.text.isNotEmpty ||
                                    productProvider.hasActiveFilters
                                ? 'Try different search or filters'
                                : 'Add your first product to get started',
                            buttonText: isAdmin ? 'Add Product' : null,
                            onButtonPressed: isAdmin
                                ? () => Navigator.pushNamed(
                                    context, '/products/add')
                                : null,
                          ),
                        ),
                      )
                    : _buildProductList(context, productProvider),
            ),
          ),
        ],
      ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showScrollTop)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.small(
                heroTag: 'scroll_top',
                onPressed: () => _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryColor,
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          if (isAdmin)
            FloatingActionButton(
              heroTag: 'add_product',
              onPressed: () =>
                  Navigator.pushNamed(context, '/products/add'),
              tooltip: 'Add Product',
              child: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }

  Widget _buildProductList(BuildContext context, ProductProvider productProvider) {
    final gridColumns = Responsive.gridColumns(context);
    final hPad = Responsive.horizontalPadding(context);

    Widget buildCard(int index) {
      final product = productProvider.products[index];
      return AnimatedListItem(
        index: index,
        child: ProductCard(
          product: product,
          useGridPadding: gridColumns > 1,
          onTap: () => Navigator.pushNamed(context, '/products/detail', arguments: product),
          onStockIn: () => Navigator.pushNamed(context, '/stock/in', arguments: product),
          onStockOut: () => Navigator.pushNamed(context, '/stock/out', arguments: product),
        ),
      );
    }

    if (gridColumns > 1) {
      return GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 90),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
        ),
        itemCount: productProvider.products.length,
        itemBuilder: (context, index) => buildCard(index),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 90),
      itemCount: productProvider.products.length,
      itemBuilder: (context, index) => buildCard(index),
    );
  }
}

bool _isLastNDays(ProductProvider provider, int days) {
  if (provider.filterStartDate == null) return false;
  final end = DateTime.now();
  final start = end.subtract(Duration(days: days));
  return provider.filterStartDate!.difference(start).inDays.abs() < 2;
}

class _FilterSection extends StatelessWidget {
  final ProductProvider productProvider;
  final CategoryProvider categoryProvider;

  const _FilterSection({
    super.key,
    required this.productProvider,
    required this.categoryProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range filter
          const _FilterLabel(label: 'Added Date'),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChipItem(
                  label: 'All',
                  isSelected: productProvider.filterStartDate == null,
                  onTap: () =>
                      productProvider.filterByDateRange(null, null),
                ),
                _FilterChipItem(
                  label: 'Last 7 days',
                  isSelected: productProvider.filterStartDate != null &&
                      _isLastNDays(productProvider, 7),
                  onTap: () {
                    final end = DateTime.now();
                    productProvider.filterByDateRange(
                      end.subtract(const Duration(days: 7)),
                      end,
                    );
                  },
                ),
                _FilterChipItem(
                  label: 'Last 30 days',
                  isSelected: productProvider.filterStartDate != null &&
                      _isLastNDays(productProvider, 30),
                  onTap: () {
                    final end = DateTime.now();
                    productProvider.filterByDateRange(
                      end.subtract(const Duration(days: 30)),
                      end,
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Category filter
          const _FilterLabel(label: 'Category'),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChipItem(
                  label: 'All',
                  isSelected:
                      productProvider.selectedCategoryId == null,
                  onTap: () =>
                      productProvider.filterByCategory(null),
                ),
                ...categoryProvider.topLevelCategories.map((category) {
                  return _FilterChipItem(
                    label: category.name,
                    isSelected: productProvider.selectedCategoryId ==
                        category.id,
                    onTap: () => productProvider.filterByCategory(
                      productProvider.selectedCategoryId ==
                              category.id
                          ? null
                          : category.id,
                    ),
                  );
                }),
              ],
            ),
          ),

          // Subcategory filter (shown when a category is selected and has subcategories)
          if (productProvider.selectedCategoryId != null) ...[
            Builder(builder: (context) {
              final subcats = categoryProvider
                  .getSubcategoriesOf(productProvider.selectedCategoryId!);
              if (subcats.isEmpty) return const SizedBox.shrink();
              final useWrap = subcats.length > 6;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const _FilterLabel(label: 'Subcategory'),
                      const SizedBox(width: 6),
                      Text('(${subcats.length})',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (useWrap)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _CompactFilterChip(
                          label: 'All',
                          isSelected: productProvider.selectedSubcategoryId == null,
                          onTap: () => productProvider.filterBySubcategory(null),
                        ),
                        ...subcats.map((sub) => _CompactFilterChip(
                          label: sub.name,
                          isSelected: productProvider.selectedSubcategoryId == sub.id,
                          onTap: () => productProvider.filterBySubcategory(
                            productProvider.selectedSubcategoryId == sub.id
                                ? null
                                : sub.id,
                          ),
                        )),
                      ],
                    )
                  else
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _FilterChipItem(
                            label: 'All',
                            isSelected: productProvider.selectedSubcategoryId == null,
                            onTap: () => productProvider.filterBySubcategory(null),
                          ),
                          ...subcats.map((sub) => _FilterChipItem(
                            label: sub.name,
                            isSelected: productProvider.selectedSubcategoryId == sub.id,
                            onTap: () => productProvider.filterBySubcategory(
                              productProvider.selectedSubcategoryId == sub.id
                                  ? null
                                  : sub.id,
                            ),
                          )),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ],

          const SizedBox(height: 10),

          // Location filter
          if (productProvider.availableLocations.isNotEmpty) ...[
            const _FilterLabel(label: 'Location'),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChipItem(
                    label: 'All',
                    isSelected:
                        productProvider.selectedLocation == null,
                    onTap: () =>
                        productProvider.filterByLocation(null),
                  ),
                  ...productProvider.availableLocations.map((loc) {
                    return _FilterChipItem(
                      label: loc,
                      isSelected:
                          productProvider.selectedLocation == loc,
                      onTap: () =>
                          productProvider.filterByLocation(
                        productProvider.selectedLocation == loc
                            ? null
                            : loc,
                      ),
                      icon: Icons.location_on_outlined,
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Stock status filter
          const _FilterLabel(label: 'Stock Status'),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChipItem(
                  label: 'All',
                  isSelected:
                      productProvider.selectedStockStatus == null,
                  onTap: () =>
                      productProvider.filterByStockStatus(null),
                ),
                _FilterChipItem(
                  label: 'In Stock',
                  isSelected: productProvider.selectedStockStatus ==
                      'in_stock',
                  onTap: () =>
                      productProvider.filterByStockStatus(
                    productProvider.selectedStockStatus == 'in_stock'
                        ? null
                        : 'in_stock',
                  ),
                  dotColor: AppTheme.stockGood,
                ),
                _FilterChipItem(
                  label: 'Low Stock',
                  isSelected: productProvider.selectedStockStatus ==
                      'low_stock',
                  onTap: () =>
                      productProvider.filterByStockStatus(
                    productProvider.selectedStockStatus == 'low_stock'
                        ? null
                        : 'low_stock',
                  ),
                  dotColor: AppTheme.stockLow,
                ),
                _FilterChipItem(
                  label: 'Out of Stock',
                  isSelected: productProvider.selectedStockStatus ==
                      'out_of_stock',
                  onTap: () =>
                      productProvider.filterByStockStatus(
                    productProvider.selectedStockStatus ==
                            'out_of_stock'
                        ? null
                        : 'out_of_stock',
                  ),
                  dotColor: AppTheme.stockOut,
                ),
              ],
            ),
          ),

          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              if (!settings.vendorsEnabled) return const SizedBox.shrink();
              final vendorProvider = context.watch<VendorProvider>();
              final activeVendors = vendorProvider.activeVendors;
              if (activeVendors.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  const _FilterLabel(label: 'Vendor'),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterChipItem(
                          label: 'All',
                          isSelected: productProvider.selectedVendorId == null,
                          onTap: () => productProvider.filterByVendor(null),
                        ),
                        ...activeVendors.map((v) => _FilterChipItem(
                              label: v.name,
                              isSelected: productProvider.selectedVendorId == v.id,
                              onTap: () => productProvider.filterByVendor(
                                productProvider.selectedVendorId == v.id
                                    ? null
                                    : v.id,
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String label;
  const _FilterLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _FilterChipItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dotColor;

  const _FilterChipItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor
                  : const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? null
                  : Border.all(color: AppTheme.inputBorderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null && !isSelected) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (icon != null && !isSelected) ...[
                  Icon(icon, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor
                : const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? null
                : Border.all(color: AppTheme.inputBorderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
