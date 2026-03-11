import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/vendor_model.dart';
import '../../widgets/glass_panel.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/shimmer_loading.dart';
// Vendor routes registered in app.dart onGenerateRoute

class VendorListScreen extends StatefulWidget {
  const VendorListScreen({super.key});

  @override
  State<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends State<VendorListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final vendorProvider = context.watch<VendorProvider>();
    final vendors = vendorProvider.vendors;

    final filtered = _searchQuery.isEmpty
        ? vendors
        : vendors.where((v) {
            final q = _searchQuery.toLowerCase();
            return v.name.toLowerCase().contains(q) ||
                v.contactName.toLowerCase().contains(q) ||
                v.email.toLowerCase().contains(q) ||
                v.phone.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Vendors (${vendors.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.addVendor),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: Column(
              children: [
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
                      fillColor: AppTheme.inputFillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                Expanded(
                  child: vendorProvider.isLoading
                      ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                      : filtered.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.local_shipping_outlined,
                          title: _searchQuery.isEmpty
                              ? 'No vendors added yet'
                              : 'No matching vendors',
                          subtitle: _searchQuery.isEmpty
                              ? 'Add your first vendor to get started'
                              : 'Try different search terms',
                          buttonText: _searchQuery.isEmpty
                              ? 'Add Vendor'
                              : null,
                          onButtonPressed: _searchQuery.isEmpty
                              ? () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.addVendor,
                                )
                              : null,
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            context.read<VendorProvider>().initialize(
                              companyId: context
                                  .read<AuthProvider>()
                                  .currentUser!
                                  .companyId,
                            );
                          },
                          child: ListView.separated(
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
          ),
        ),
      ),
      floatingActionButton:
          (context.watch<AuthProvider>().currentUser?.hasPermission(
                'canManageProducts',
              ) ??
              false)
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.addVendor),
              tooltip: 'Add Vendor',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Vendor'),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: AppTheme.surfaceColor,
            )
          : null,
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
        Navigator.pushNamed(context, AppRoutes.vendorDetail, arguments: vendor);
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
                    : AppTheme.textMuted.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.local_shipping_rounded,
                color: vendor.isActive
                    ? AppTheme.indigoColor
                    : AppTheme.textMuted,
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
                            color: AppTheme.textMuted.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Inactive',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textTertiary,
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
                        color: AppTheme.textTertiary,
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
                                : AppTheme.emptyStateIcon,
                          );
                        }),
                        const SizedBox(width: 8),
                      ],
                      if (vendor.leadTimeDays > 0)
                        Text(
                          '${vendor.leadTimeDays}d lead',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.iconMuted),
          ],
        ),
      ),
    );
  }
}
