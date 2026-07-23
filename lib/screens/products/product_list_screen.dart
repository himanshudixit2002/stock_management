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
import '../../widgets/provider_error_banner.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/floating_nav_padding.dart';
import '../ai/rag_chat_screen.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../config/feature_map.dart';
import '../../models/user_model.dart';
import '../../utils/responsive.dart';
import '../../widgets/permission_gate.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();
  bool _showFilters = false;
  bool _showScrollTop = false;
  Timer? _debounce;
  Timer? _loadingTimer;
  bool _loadingTooLong = false;
  bool _isDebouncing = false;
  ProductProvider? _productProvider;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(() => setState(() {}));
  }

  void _onScroll() {
    final show = _scrollController.offset > 300;
    if (show != _showScrollTop) setState(() => _showScrollTop = show);

    final provider = _productProvider;
    if (provider != null &&
        provider.hasMoreProducts &&
        !provider.isLoadingMore &&
        _scrollController.hasClients) {
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 200) {
        provider.loadMoreProducts();
      }
    }
  }

  void _startLoadingTimer() {
    _loadingTimer?.cancel();
    _loadingTooLong = false;
    _loadingTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _loadingTooLong = true);
    });
  }

  void _cancelLoadingTimer() {
    _loadingTimer?.cancel();
    if (_loadingTooLong) {
      _loadingTooLong = false;
    }
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterBottomSheet(
        onReset: () {
          context.read<ProductProvider>().clearFilters();
          _searchController.clear();
          setState(() {});
        },
      ),
    );
  }

  Widget _buildFilterButtonContent(ProductProvider productProvider) {
    final isActive = _showFilters || productProvider.activeFilterCount > 0;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.tune_rounded,
            color: isActive
                ? AppTheme.surface(context)
                : AppTheme.textSec(context),
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
                    style: TextStyle(
                      color: AppTheme.surface(context),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    _productProvider = productProvider;
    final user = context.watch<AuthProvider>().currentUser;
    final canManageProducts =
        user?.hasPermission(AppPermissions.addProducts) ?? false;
    final isMobile = Responsive.isMobile(context);
    final shortcuts = FeatureMap.entriesByCategory(
      FeatureCategory.inventory,
      user?.effectivePermissions ?? UserModel.defaultPermissions,
      placement: FeaturePlacement.tabShortcut,
    );

    return PermissionGate(
      permission: AppPermissions.viewProducts,
      featureName: 'Products',
      child: Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: Center(
            child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    pinned: true,
                    floating: true,
                    snap: true,
                    elevation: 0,
                    backgroundColor: AppTheme.surface(context),
                    surfaceTintColor: Colors.transparent,
                    automaticallyImplyLeading: true,
                    title: Text(
                      'Products (${productProvider.products.length})',
                      style: TextStyle(
                        color: AppTheme.textPri(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    actions: [
                      if (canManageProducts)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))
                            ]
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                            tooltip: 'Add Product',
                            onPressed: () => Navigator.pushNamed(context, AppRoutes.addProduct),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          ),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.sort_rounded, size: 22),
                        tooltip: 'Sort',
                        onSelected: (value) {
                          productProvider.sortProducts(value);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'name',
                            child: Text('Name (A-Z)'),
                          ),
                          const PopupMenuItem(
                            value: 'quantity',
                            child: Text('Stock (Low-High)'),
                          ),
                          const PopupMenuItem(
                            value: 'quantity_desc',
                            child: Text('Stock (High-Low)'),
                          ),
                        ],
                      ),
                      if (shortcuts.isNotEmpty)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 22),
                          tooltip: 'Shortcuts',
                          onSelected: (route) =>
                              Navigator.pushNamed(context, route),
                          itemBuilder: (context) => [
                            for (final entry in shortcuts)
                              PopupMenuItem<String>(
                                value: entry.route,
                                child: Row(
                                  children: [
                                    Icon(
                                      entry.icon,
                                      size: 18,
                                      color: AppTheme.primaryColor,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(entry.label),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size(double.infinity, 64),
                      child: Container(
                        color: AppTheme.surface(context),
                        padding: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context),
                          6,
                          Responsive.horizontalPadding(context),
                          6,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _buildSearchBar(productProvider)),
                            const SizedBox(width: 10),
                            _buildFilterButton(productProvider, isMobile),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (productProvider.errorMessage != null &&
                      productProvider.products.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context),
                          0,
                          Responsive.horizontalPadding(context),
                          8,
                        ),
                        child: ProviderErrorBanner(
                          message: productProvider.errorMessage!,
                          onDismiss: () => productProvider.clearError(),
                          onRetry: () => productProvider.refreshProducts(),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _PrimaryFilterChips(
                      productProvider: productProvider,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ActiveFilterChips(
                      onClearAll: () {
                        productProvider.clearFilters();
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  if (!isMobile && _showFilters)
                    SliverToBoxAdapter(child: const _FilterSection()),
                ];
              },
              body: RefreshIndicator(
                color: AppTheme.primaryColor,
                onRefresh: () async {
                  await productProvider.refreshProducts();
                  if (mounted) {
                    _searchController.clear();
                    setState(() {});
                  }
                },
                child: Builder(
                  builder: (context) {
                    if (productProvider.isLoading) {
                      _startLoadingTimer();
                      if (_loadingTooLong) {
                        return SingleChildScrollView(
                          physics: Responsive.scrollPhysics(context),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading is taking longer than usual...',
                                    style: TextStyle(
                                      color: AppTheme.textSec(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: () {
                                      _cancelLoadingTimer();
                                      productProvider.refreshProducts();
                                    },
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      return const ShimmerLoading(
                        itemCount: 6,
                        layout: ShimmerLayout.card,
                      );
                    }

                    _cancelLoadingTimer();

                    if (productProvider.errorMessage != null) {
                      return SingleChildScrollView(
                        physics: Responsive.scrollPhysics(context),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: EmptyStateWidget(
                            icon: Icons.cloud_off_rounded,
                            title: 'Could Not Load Products',
                            subtitle: productProvider.errorMessage!,
                            buttonText: 'Retry',
                            onButtonPressed: () {
                              productProvider.refreshProducts();
                            },
                          ),
                        ),
                      );
                    }

                    final isSearchOrDebounce =
                        productProvider.isSearching || _isDebouncing;

                    if (productProvider.products.isEmpty) {
                      if (isSearchOrDebounce) {
                        return SingleChildScrollView(
                          physics: Responsive.scrollPhysics(context),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Searching...',
                                    style: TextStyle(
                                      color: AppTheme.textSec(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // Analytics still loading — filter may find more once
                      // the full set arrives.
                      if (productProvider.hasActiveFilters &&
                          productProvider.isLoadingAnalytics) {
                        return SingleChildScrollView(
                          physics: Responsive.scrollPhysics(context),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading products...',
                                    style: TextStyle(
                                      color: AppTheme.textSec(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        physics: Responsive.scrollPhysics(context),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: EmptyStateWidget(
                            icon: Icons.inventory_2_outlined,
                            title: 'No Products Found',
                            subtitle:
                                _searchController.text.isNotEmpty ||
                                    productProvider.hasActiveFilters
                                ? 'Try different search or filters'
                                : 'Add your first product to get started',
                            buttonText: canManageProducts
                                ? 'Add Product'
                                : null,
                            onButtonPressed: canManageProducts
                                ? () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.addProduct,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }

                    return _buildProductList(context, productProvider);
                  },
                ),
              ),
            ),
          ),
        ),
        ),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: floatingNavContentInset(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            if (_showScrollTop)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FloatingActionButton.small(
                  heroTag: 'scroll_top',
                  tooltip: 'Scroll to top',
                  onPressed: () => _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  ),
                  backgroundColor: AppTheme.surface(context),
                  foregroundColor: AppTheme.primaryColor,
                  child: const Icon(Icons.arrow_upward_rounded),
                ),
              ),

          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ProductProvider productProvider) {
    final isFocused = _searchFocusNode.hasFocus;
    final hasText = _searchController.text.isNotEmpty;
    final isSearchActive =
        productProvider.isSearching || (_isDebouncing && hasText);
    final resultCount = productProvider.products.length;
    final showResultBadge = hasText && !isSearchActive && resultCount > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppTheme.inputFill(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFocused
                  ? AppTheme.primaryColor.withValues(alpha: 0.5)
                  : AppTheme.inputBorder(context),
              width: isFocused ? 1.5 : 1,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText:
                  'Search name, barcode, vendor, location… (typos OK). '
                  'Try stock:low  cat:snacks',
              hintStyle: TextStyle(
                color: AppTheme.textTer(context),
                fontSize: 14,
              ),
              filled: false,
              border: InputBorder.none,
              prefixIcon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: isSearchActive
                    ? const SizedBox(
                        key: ValueKey('searching'),
                        width: 48,
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.search_rounded,
                        key: ValueKey(isFocused),
                        color: isFocused
                            ? AppTheme.primaryColor
                            : AppTheme.textTer(context),
                      ),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showResultBadge)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$resultCount',
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (hasText)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _debounce?.cancel();
                        _isDebouncing = false;
                        productProvider.search('');
                        setState(() {});
                      },
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (value) {
              _debounce?.cancel();
              setState(() => _isDebouncing = value.isNotEmpty);
              _debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) setState(() => _isDebouncing = false);
                productProvider.search(value);
              });
            },
          ),
        ),
        // Subtle progress bar visible during search
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: isSearchActive ? 2 : 0,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: isSearchActive
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.primaryColor,
                    backgroundColor: Color(0x1A007AFF),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildFilterButton(ProductProvider productProvider, bool isMobile) {
    final isActive = _showFilters || productProvider.activeFilterCount > 0;
    void onTap() {
      if (isMobile) {
        _openFilterSheet(context);
      } else {
        setState(() => _showFilters = !_showFilters);
      }
    }

    if (isActive) {
      return Material(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: _buildFilterButtonContent(productProvider),
        ),
      );
    }
    return GlassPanel(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: _buildFilterButtonContent(productProvider),
      ),
    );
  }

  static const _animateFirstN = 15;

  Widget _buildProductList(
    BuildContext context,
    ProductProvider productProvider,
  ) {
    final gridColumns = Responsive.gridColumns(context);
    final hPad = Responsive.horizontalPadding(context);
    final productCount = productProvider.products.length;
    final showLoadMore =
        productProvider.hasMoreProducts && !productProvider.isInSearchMode;
    final itemCount = productCount + (showLoadMore ? 1 : 0);

    Widget buildCard(int index) {
      final product = productProvider.products[index];
      final card = ProductCard(
        product: product,
        useGridPadding: gridColumns > 1,
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.productDetail,
          arguments: product,
        ),
        onStockIn: gridColumns > 1
            ? null
            : () => Navigator.pushNamed(
                context,
                AppRoutes.stockIn,
                arguments: product,
              ),
        onStockOut: gridColumns > 1
            ? null
            : () => Navigator.pushNamed(
                context,
                AppRoutes.stockOut,
                arguments: product,
              ),
      );
      if (index < _animateFirstN) {
        return AnimatedListItem(index: index, child: card);
      }
      return card;
    }

    Widget? buildLoadMore(int index) {
      if (index != productCount) return null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: productProvider.isLoadingMore
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton.icon(
                  onPressed: productProvider.loadMoreProducts,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('Load more products'),
                ),
        ),
      );
    }

    if (gridColumns > 1) {
      return GridView.builder(
        controller: _scrollController,
        physics: Responsive.scrollPhysics(context),
        addAutomaticKeepAlives: false,
        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, floatingNavContentInset(context)),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: gridColumns >= 4 ? 3.5 : 3.2,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final loadMore = buildLoadMore(index);
          if (loadMore != null) return loadMore;
          return buildCard(index);
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: Responsive.scrollPhysics(context),
      addAutomaticKeepAlives: false,
      padding: EdgeInsets.only(top: 4, bottom: floatingNavContentInset(context)),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final loadMore = buildLoadMore(index);
        if (loadMore != null) return loadMore;
        return buildCard(index);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Primary inline filter chips: Category + Stock Status (always visible)
// ---------------------------------------------------------------------------
class _PrimaryFilterChips extends StatelessWidget {
  final ProductProvider productProvider;
  const _PrimaryFilterChips({required this.productProvider});

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final isWide = Responsive.isWide(context);

    final children = <Widget>[
      _FilterChipItem(
        label: 'All categories',
        isSelected: productProvider.selectedCategoryId == null,
        onTap: () => productProvider.filterByCategory(null),
      ),
      ...categoryProvider.categories.map((category) {
        return _FilterChipItem(
          label: category.name,
          isSelected: productProvider.selectedCategoryId == category.id,
          onTap: () => productProvider.filterByCategory(
            productProvider.selectedCategoryId == category.id
                ? null
                : category.id,
          ),
        );
      }),
      _FilterChipItem(
        label: 'All status',
        isSelected: productProvider.selectedStockStatus == null,
        onTap: () => productProvider.filterByStockStatus(null),
      ),
      _FilterChipItem(
        label: 'In Stock',
        isSelected: productProvider.selectedStockStatus == 'in_stock',
        onTap: () => productProvider.filterByStockStatus(
          productProvider.selectedStockStatus == 'in_stock' ? null : 'in_stock',
        ),
        dotColor: AppTheme.stockGood,
      ),
      _FilterChipItem(
        label: 'Low Stock',
        isSelected: productProvider.selectedStockStatus == 'low_stock',
        onTap: () => productProvider.filterByStockStatus(
          productProvider.selectedStockStatus == 'low_stock'
              ? null
              : 'low_stock',
        ),
        dotColor: AppTheme.stockLow,
      ),
      _FilterChipItem(
        label: 'Out of Stock',
        isSelected: productProvider.selectedStockStatus == 'out_of_stock',
        onTap: () => productProvider.filterByStockStatus(
          productProvider.selectedStockStatus == 'out_of_stock'
              ? null
              : 'out_of_stock',
        ),
        dotColor: AppTheme.stockOut,
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        4,
        Responsive.horizontalPadding(context),
        4,
      ),
      child: isWide
          ? Wrap(spacing: 6, runSpacing: 6, children: children)
          : SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: children,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active filter chips row (shown when secondary filters from "More" are active)
// ---------------------------------------------------------------------------
class _ActiveFilterChips extends StatelessWidget {
  final VoidCallback onClearAll;
  const _ActiveFilterChips({required this.onClearAll});

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();

    final chips = <_ActiveChipData>[];
    if (productProvider.selectedCompany != null) {
      chips.add(
        _ActiveChipData(
          label: productProvider.selectedCompany!,
          icon: Icons.business_rounded,
          onRemove: () => productProvider.filterByCompany(null),
        ),
      );
    }
    if (productProvider.selectedSize != null) {
      chips.add(
        _ActiveChipData(
          label: productProvider.selectedSize!,
          icon: Icons.straighten_rounded,
          onRemove: () => productProvider.filterBySize(null),
        ),
      );
    }
    if (productProvider.selectedLocation != null) {
      chips.add(
        _ActiveChipData(
          label: productProvider.selectedLocation!,
          icon: Icons.location_on_outlined,
          onRemove: () => productProvider.filterByLocation(null),
        ),
      );
    }
    if (productProvider.selectedVendorId != null) {
      chips.add(
        _ActiveChipData(
          label: 'Vendor',
          icon: Icons.storefront_rounded,
          onRemove: () => productProvider.filterByVendor(null),
        ),
      );
    }
    if (productProvider.filterStartDate != null) {
      chips.add(
        _ActiveChipData(
          label: 'Date range',
          icon: Icons.date_range_rounded,
          onRemove: () => productProvider.filterByDateRange(null, null),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        4,
        Responsive.horizontalPadding(context),
        4,
      ),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...chips.map(
                    (chip) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _ActiveFilterTag(data: chip),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${productProvider.products.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSec(context),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.dangerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChipData {
  final String label;
  final IconData icon;
  final VoidCallback onRemove;
  const _ActiveChipData({
    required this.label,
    required this.icon,
    required this.onRemove,
  });
}

class _ActiveFilterTag extends StatelessWidget {
  final _ActiveChipData data;
  const _ActiveFilterTag({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 14, color: AppTheme.primaryColor),
          const SizedBox(width: 4),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: data.onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: AppTheme.primaryColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bottom sheet (mobile)
// ---------------------------------------------------------------------------
class _FilterBottomSheet extends StatelessWidget {
  final VoidCallback onReset;
  const _FilterBottomSheet({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.emptyIcon(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'More Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPri(context),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        onReset();
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Reset All',
                        style: TextStyle(
                          color: AppTheme.dangerColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: const _FilterContent(),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Consumer<ProductProvider>(
                    builder: (context, pp, _) {
                      final count = pp.products.length;
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            pp.hasActiveFilters
                                ? 'Show $count Result${count == 1 ? '' : 's'}'
                                : 'Show Results',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline filter section (wide screens)
// ---------------------------------------------------------------------------
bool _isLastNDays(ProductProvider provider, int days) {
  if (provider.filterStartDate == null) return false;
  final end = DateTime.now();
  final start = end.subtract(Duration(days: days));
  return provider.filterStartDate!.difference(start).inDays.abs() < 2;
}

class _FilterSection extends StatelessWidget {
  const _FilterSection();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.4;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
      ),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: const SingleChildScrollView(child: _FilterContent()),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared filter content (used by both inline and bottom sheet)
// ---------------------------------------------------------------------------
class _FilterContent extends StatelessWidget {
  const _FilterContent();

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final isWide = Responsive.isWide(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // More filters: Date, Company, Size, Location, Vendor (Category + Stock in primary chips)
        const _FilterLabel(label: 'Added Date'),
        const SizedBox(height: 6),
        _FilterChipGroup(
          isWide: isWide,
          children: [
            _FilterChipItem(
              label: 'All',
              isSelected: productProvider.filterStartDate == null,
              onTap: () => productProvider.filterByDateRange(null, null),
            ),
            _FilterChipItem(
              label: 'Last 7 days',
              isSelected:
                  productProvider.filterStartDate != null &&
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
              isSelected:
                  productProvider.filterStartDate != null &&
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

        const SizedBox(height: 12),

        // Company filter
        Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            final companies = settings.companies.isNotEmpty
                ? settings.companies
                : productProvider.availableCompaniesFromProducts;
            if (companies.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const _FilterLabel(label: 'Company'),
                const SizedBox(height: 6),
                _FilterChipGroup(
                  isWide: isWide,
                  children: [
                    _FilterChipItem(
                      label: 'All',
                      isSelected: productProvider.selectedCompany == null,
                      onTap: () => productProvider.filterByCompany(null),
                    ),
                    ...companies.map(
                      (c) => _FilterChipItem(
                        label: c,
                        isSelected: productProvider.selectedCompany == c,
                        onTap: () => productProvider.filterByCompany(
                          productProvider.selectedCompany == c ? null : c,
                        ),
                        icon: Icons.business_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),

        // Size filter
        Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            final sizes = settings.sizes.isNotEmpty
                ? settings.sizes
                : productProvider.availableSizesFromProducts;
            if (sizes.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const _FilterLabel(label: 'Sub-Category'),
                const SizedBox(height: 6),
                _FilterChipGroup(
                  isWide: isWide,
                  children: [
                    _FilterChipItem(
                      label: 'All',
                      isSelected: productProvider.selectedSize == null,
                      onTap: () => productProvider.filterBySize(null),
                    ),
                    ...sizes.map(
                      (s) => _FilterChipItem(
                        label: s,
                        isSelected: productProvider.selectedSize == s,
                        onTap: () => productProvider.filterBySize(
                          productProvider.selectedSize == s ? null : s,
                        ),
                        icon: Icons.straighten_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 12),

        // Location filter
        Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            final locations = settings.locations.isNotEmpty
                ? settings.locations
                : productProvider.availableLocationsFromProducts;
            if (locations.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FilterLabel(label: 'Location'),
                const SizedBox(height: 6),
                _FilterChipGroup(
                  isWide: isWide,
                  children: [
                    _FilterChipItem(
                      label: 'All',
                      isSelected: productProvider.selectedLocation == null,
                      onTap: () => productProvider.filterByLocation(null),
                    ),
                    ...locations.map((loc) {
                      return _FilterChipItem(
                        label: loc,
                        isSelected: productProvider.selectedLocation == loc,
                        onTap: () => productProvider.filterByLocation(
                          productProvider.selectedLocation == loc ? null : loc,
                        ),
                        icon: Icons.location_on_outlined,
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            );
          },
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
                _FilterChipGroup(
                  isWide: isWide,
                  children: [
                    _FilterChipItem(
                      label: 'All',
                      isSelected: productProvider.selectedVendorId == null,
                      onTap: () => productProvider.filterByVendor(null),
                    ),
                    ...activeVendors.map(
                      (v) => _FilterChipItem(
                        label: v.name,
                        isSelected: productProvider.selectedVendorId == v.id,
                        onTap: () => productProvider.filterByVendor(
                          productProvider.selectedVendorId == v.id
                              ? null
                              : v.id,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip group: Wrap on wide, horizontal scroll on mobile
// ---------------------------------------------------------------------------
class _FilterChipGroup extends StatelessWidget {
  final List<Widget> children;
  final bool isWide;
  const _FilterChipGroup({required this.children, required this.isWide});

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      return Wrap(spacing: 10, runSpacing: 10, children: children);
    }

    return SizedBox(
      height: 42,
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white,
            Colors.white,
            Colors.white,
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.0, 0.85, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 20),
          children: children,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter label
// ---------------------------------------------------------------------------
class _FilterLabel extends StatelessWidget {
  final String label;
  const _FilterLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSec(context),
        letterSpacing: 0.5,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip item with scale animation
// ---------------------------------------------------------------------------
class _FilterChipItem extends StatefulWidget {
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
  State<_FilterChipItem> createState() => _FilterChipItemState();
}

class _FilterChipItemState extends State<_FilterChipItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppTheme.primaryColor
                  : AppTheme.inputFill(context),
              borderRadius: BorderRadius.circular(10),
              border: widget.isSelected
                  ? null
                  : Border.all(color: AppTheme.inputBorder(context)),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.dotColor != null && !widget.isSelected) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (widget.icon != null && !widget.isSelected) ...[
                  Icon(widget.icon, size: 14, color: AppTheme.textSec(context)),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isSelected
                        ? AppTheme.surface(context)
                        : AppTheme.textPri(context),
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                if (widget.isSelected) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppTheme.surface(context).withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
