import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/empty_state_widget.dart';
import '../../config/app_navigation.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final allProducts = context.watch<ProductProvider>().allProducts;
    final favoriteIds = context.watch<FavoritesProvider>().ids;
    final favorites = allProducts
        .where((p) => favoriteIds.contains(p.id))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.star_rounded,
          color: AppTheme.warningColor,
          title: 'Favorites',
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: favorites.isEmpty
            ? const EmptyStateWidget(
                icon: Icons.star_outline_rounded,
                title: 'No Favorites Yet',
                subtitle:
                    'Star products for quick access. They will appear here.',
              )
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.contentMaxWidth(context),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.all(
                      Responsive.horizontalPadding(context),
                    ),
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final product = favorites[index];
                      return _FavoriteProductCard(
                        product: product,
                        onUnfavorite: () {
                          context.read<FavoritesProvider>().toggle(product.id);
                        },
                        onTap: () => context.pushAppRoute(AppRoutes.productDetail,
                          extra: product,
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

class _FavoriteProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onUnfavorite;
  final VoidCallback onTap;

  const _FavoriteProductCard({
    required this.product,
    required this.onUnfavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stockColor = AppTheme.getStockColor(
      product.quantity,
      threshold: product.lowStockThreshold,
    );
    final stockLabel = AppTheme.getStockLabel(
      product.quantity,
      threshold: product.lowStockThreshold,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        useContentVariant: true,
        borderRadius: 16,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          onTap: onTap,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: stockColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              color: stockColor,
              size: 22,
            ),
          ),
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: stockColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$stockLabel • ${product.quantity} ${product.unit}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: stockColor,
                  ),
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.star_rounded,
              color: AppTheme.warningColor,
            ),
            onPressed: onUnfavorite,
            tooltip: 'Remove from favorites',
          ),
        ),
      ),
    );
  }
}