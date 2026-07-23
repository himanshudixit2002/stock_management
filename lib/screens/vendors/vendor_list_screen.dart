import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/vendor_model.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/provider_error_banner.dart';
import '../../config/app_navigation.dart';
// Vendor routes registered in app.dart onGenerateRoute

enum _VendorSort {
  nameAsc,
  nameDesc,
  ratingHigh,
  ratingLow,
  leadShort,
  leadLong,
}

enum _StatusFilter { all, activeOnly, inactiveOnly }

class VendorListScreen extends StatefulWidget {
  const VendorListScreen({super.key});

  @override
  State<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends State<VendorListScreen> {
  String _searchQuery = '';
  _VendorSort _sort = _VendorSort.nameAsc;
  _StatusFilter _statusFilter = _StatusFilter.all;
  int _minRating = 0;
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final show = _scrollController.offset > 500;
      if (show != _showScrollToTop && mounted) {
        setState(() => _showScrollToTop = show);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _statusFilter != _StatusFilter.all || _minRating > 0;

  List<VendorModel> _applyFiltersAndSort(List<VendorModel> vendors) {
    var result = vendors.where((v) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!v.name.toLowerCase().contains(q) &&
            !v.contactName.toLowerCase().contains(q) &&
            !v.email.toLowerCase().contains(q) &&
            !v.phone.contains(q)) {
          return false;
        }
      }
      if (_statusFilter == _StatusFilter.activeOnly && !v.isActive) {
        return false;
      }
      if (_statusFilter == _StatusFilter.inactiveOnly && v.isActive) {
        return false;
      }
      if (_minRating > 0 && v.rating < _minRating) return false;
      return true;
    }).toList();

    result.sort(
      (a, b) => switch (_sort) {
        _VendorSort.nameAsc => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _VendorSort.nameDesc => b.name.toLowerCase().compareTo(
          a.name.toLowerCase(),
        ),
        _VendorSort.ratingHigh => b.rating.compareTo(a.rating),
        _VendorSort.ratingLow => a.rating.compareTo(b.rating),
        _VendorSort.leadShort => a.leadTimeDays.compareTo(b.leadTimeDays),
        _VendorSort.leadLong => b.leadTimeDays.compareTo(a.leadTimeDays),
      },
    );

    return result;
  }

  void _showFilterSheet() {
    var tempStatus = _statusFilter;
    var tempRating = _minRating;

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: AppTheme.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.dividerC(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Filter Vendors',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                        const Spacer(),
                        if (tempStatus != _StatusFilter.all || tempRating > 0)
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                tempStatus = _StatusFilter.all;
                                tempRating = 0;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _FilterToggle(
                          label: 'All',
                          selected: tempStatus == _StatusFilter.all,
                          onTap: () => setSheetState(
                            () => tempStatus = _StatusFilter.all,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterToggle(
                          label: 'Active',
                          selected: tempStatus == _StatusFilter.activeOnly,
                          onTap: () => setSheetState(
                            () => tempStatus = _StatusFilter.activeOnly,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterToggle(
                          label: 'Inactive',
                          selected: tempStatus == _StatusFilter.inactiveOnly,
                          onTap: () => setSheetState(
                            () => tempStatus = _StatusFilter.inactiveOnly,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Minimum Rating',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(5, (i) {
                        final star = i + 1;
                        final active = star <= tempRating;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              tempRating = tempRating == star ? 0 : star;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              active
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 32,
                              color: active
                                  ? AppTheme.warningColor
                                  : AppTheme.iconMute(context),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (tempRating > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '$tempRating star${tempRating > 1 ? 's' : ''} & above',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _statusFilter = tempStatus;
                            _minRating = tempRating;
                          });
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewVendors,
      featureName: 'Vendors',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    final vendorProvider = context.watch<VendorProvider>();
    final vendors = vendorProvider.vendors;
    final filtered = _applyFiltersAndSort(vendors);

    return AppScreenScaffold(
      icon: Icons.store_rounded,
      title: 'Vendors (${vendors.length})',
      actions: [
        PopupMenuButton<_VendorSort>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort',
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            _sortMenuItem(_VendorSort.nameAsc, 'Name A–Z'),
            _sortMenuItem(_VendorSort.nameDesc, 'Name Z–A'),
            const PopupMenuDivider(),
            _sortMenuItem(_VendorSort.ratingHigh, 'Rating: High to Low'),
            _sortMenuItem(_VendorSort.ratingLow, 'Rating: Low to High'),
            const PopupMenuDivider(),
            _sortMenuItem(_VendorSort.leadShort, 'Lead Time: Shortest'),
            _sortMenuItem(_VendorSort.leadLong, 'Lead Time: Longest'),
          ],
        ),
        IconButton(
          icon: Badge(
            isLabelVisible: _hasActiveFilters,
            smallSize: 8,
            child: const Icon(Icons.filter_list_rounded),
          ),
          tooltip: 'Filter',
          onPressed: _showFilterSheet,
        ),
        if (user?.hasPermission(AppPermissions.addVendors) ?? false)
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.pushAppRoute(AppRoutes.addVendor),
          ),
      ],
      body: Column(
              children: [
                if (vendorProvider.errorMessage != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Responsive.horizontalPadding(context),
                      8,
                      Responsive.horizontalPadding(context),
                      0,
                    ),
                    child: ProviderErrorBanner(
                      message: vendorProvider.errorMessage!,
                      onDismiss: () =>
                          context.read<VendorProvider>().clearError(),
                      onRetry: () => context.read<VendorProvider>().initialize(
                        companyId: context
                            .read<AuthProvider>()
                            .currentUser!
                            .companyId,
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    12,
                    Responsive.horizontalPadding(context),
                    8,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search vendors...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppTheme.inputFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                if (_hasActiveFilters || _sort != _VendorSort.nameAsc)
                  _ActiveFilterChips(
                    statusFilter: _statusFilter,
                    minRating: _minRating,
                    sort: _sort,
                    onClearStatus: () =>
                        setState(() => _statusFilter = _StatusFilter.all),
                    onClearRating: () => setState(() => _minRating = 0),
                    onClearSort: () =>
                        setState(() => _sort = _VendorSort.nameAsc),
                    onClearAll: () => setState(() {
                      _statusFilter = _StatusFilter.all;
                      _minRating = 0;
                      _sort = _VendorSort.nameAsc;
                    }),
                  ),
                Expanded(
                  child: vendorProvider.isLoading
                      ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                      : filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.local_shipping_outlined,
                          title: _searchQuery.isEmpty && !_hasActiveFilters
                              ? 'No vendors added yet'
                              : 'No matching vendors',
                          subtitle: _searchQuery.isEmpty && !_hasActiveFilters
                              ? 'Add your first vendor to get started'
                              : 'Try different search terms or filters',
                          buttonText:
                              _searchQuery.isEmpty &&
                                  !_hasActiveFilters &&
                                  (user?.hasPermission(
                                        AppPermissions.addVendors,
                                      ) ??
                                      false)
                              ? 'Add Vendor'
                              : null,
                          onButtonPressed:
                              _searchQuery.isEmpty &&
                                  !_hasActiveFilters &&
                                  (user?.hasPermission(
                                        AppPermissions.addVendors,
                                      ) ??
                                      false)
                              ? () => context.pushAppRoute(AppRoutes.addVendor)
                              : null,
                        )
                      : RefreshIndicator(
                          color: AppTheme.primaryColor,
                          onRefresh: () async {
                            context.read<VendorProvider>().initialize(
                              companyId: context
                                  .read<AuthProvider>()
                                  .currentUser!
                                  .companyId,
                            );
                          },
                          child: Responsive.listGridColumns(context) > 1
                              ? GridView.builder(
                                  controller: _scrollController,
                                  padding: EdgeInsets.all(
                                    Responsive.horizontalPadding(context),
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            Responsive.listGridColumns(context),
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 0,
                                        mainAxisExtent:
                                            Responsive.listGridColumns(
                                                  context,
                                                ) >=
                                                3
                                            ? 110
                                            : 100,
                                      ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final vendor = filtered[index];
                                    return AnimatedListItem(
                                      index: index,
                                      child: _VendorCard(vendor: vendor),
                                    );
                                  },
                                )
                              : ListView.separated(
                                  controller: _scrollController,
                                  padding: EdgeInsets.all(
                                    Responsive.horizontalPadding(context),
                                  ),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, index) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final vendor = filtered[index];
                                    return AnimatedListItem(
                                      index: index,
                                      child: _VendorCard(vendor: vendor),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _showScrollToTop ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: FloatingActionButton.small(
              heroTag: 'scrollTop',
              onPressed: () => _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              ),
              backgroundColor: AppTheme.surface(context),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          if (user?.hasPermission(AppPermissions.addVendors) ?? false) ...[
            const SizedBox(height: 8),
            FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.addVendor),
              tooltip: 'Add Vendor',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Vendor'),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: AppTheme.surface(context),
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuEntry<_VendorSort> _sortMenuItem(_VendorSort value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_sort == value)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.check_rounded,
                size: 18,
                color: AppTheme.primaryColor,
              ),
            ),
          Text(label),
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final _StatusFilter statusFilter;
  final int minRating;
  final _VendorSort sort;
  final VoidCallback onClearStatus;
  final VoidCallback onClearRating;
  final VoidCallback onClearSort;
  final VoidCallback onClearAll;

  const _ActiveFilterChips({
    required this.statusFilter,
    required this.minRating,
    required this.sort,
    required this.onClearStatus,
    required this.onClearRating,
    required this.onClearSort,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (statusFilter == _StatusFilter.activeOnly) {
      chips.add(_chip(context, 'Active only', onClearStatus));
    } else if (statusFilter == _StatusFilter.inactiveOnly) {
      chips.add(_chip(context, 'Inactive only', onClearStatus));
    }

    if (minRating > 0) {
      chips.add(
        _chip(
          context,
          '≥ $minRating star${minRating > 1 ? 's' : ''}',
          onClearRating,
        ),
      );
    }

    if (sort != _VendorSort.nameAsc) {
      final label = switch (sort) {
        _VendorSort.nameDesc => 'Name Z–A',
        _VendorSort.ratingHigh => 'Rating ↑',
        _VendorSort.ratingLow => 'Rating ↓',
        _VendorSort.leadShort => 'Lead ↑',
        _VendorSort.leadLong => 'Lead ↓',
        _ => '',
      };
      chips.add(_chip(context, label, onClearSort));
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
      ),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
            if (chips.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: GestureDetector(
                  onTap: onClearAll,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
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

  Widget _chip(BuildContext context, String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      labelStyle: TextStyle(color: AppTheme.primaryColor),
      deleteIconColor: AppTheme.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : AppTheme.inputFill(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primaryColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? AppTheme.primaryColor
                  : AppTheme.textSec(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  final VendorModel vendor;
  const _VendorCard({required this.vendor});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushAppRoute(AppRoutes.vendorDetail, extra: vendor);
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: vendor.isActive
                    ? AppTheme.indigoColor.withValues(alpha: 0.1)
                    : AppTheme.textMute(context).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.local_shipping_rounded,
                color: vendor.isActive
                    ? AppTheme.indigoColor
                    : AppTheme.textMute(context),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vendor.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!vendor.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.textMute(
                              context,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Inactive',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textTer(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (vendor.contactName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      vendor.contactName,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textTer(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (vendor.rating > 0) ...[
                        ...List.generate(5, (i) {
                          return Icon(
                            i < vendor.rating.round()
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 14,
                            color: i < vendor.rating.round()
                                ? AppTheme.warningColor
                                : AppTheme.emptyIcon(context),
                          );
                        }),
                        const SizedBox(width: 8),
                      ],
                      if (vendor.leadTimeDays > 0)
                        Text(
                          '${vendor.leadTimeDays}d lead',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTer(context),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.iconMute(context),
            ),
          ],
        ),
      ),
    );
  }
}
