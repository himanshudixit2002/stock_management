import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/routes.dart';
import '../models/product_model.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';

/// Where a notification goes when it is tapped.
///
/// Alerts carry `entityType` plus an optional `entityId`; this turns that pair
/// into a route. Summary alerts ("9 products are running low") carry only a
/// list entityType, which is why an empty id is a normal case rather than an
/// error.
class NotificationRouting {
  const NotificationRouting._();

  /// Encodes the pair the way tray payloads carry it.
  static String encodePayload(String entityType, String entityId) =>
      '$entityType|$entityId';

  /// Splits a tray payload back into its pair. Anything malformed decodes to
  /// the notification list, which is always a safe place to land.
  static (String entityType, String entityId) decodePayload(String payload) {
    final i = payload.indexOf('|');
    if (i < 0) return (payload, '');
    return (payload.substring(0, i), payload.substring(i + 1));
  }

  /// True when tapping this alert leads somewhere. Used to decide whether the
  /// row should look tappable at all.
  static bool isActionable(String entityType) =>
      _listRoute(entityType) != null ||
      _idRoute(entityType) != null ||
      entityType == 'product';

  /// Detail routes that take a bare entity id as their argument.
  static String? _idRoute(String entityType) => switch (entityType) {
    'invoice' => AppRoutes.invoiceDetail,
    'purchase_order' => AppRoutes.purchaseOrderDetail,
    'sales_order' => AppRoutes.salesOrderDetail,
    _ => null,
  };

  /// Routes that need no argument, keyed by entityType.
  static String? _listRoute(String entityType) => switch (entityType) {
    'low_stock_list' => AppRoutes.lowStock,
    'expiry_list' => AppRoutes.expiryAlerts,
    'invoice_list' => AppRoutes.invoices,
    'purchase_order_list' => AppRoutes.purchaseOrders,
    'batch' => AppRoutes.expiryAlerts,
    'notification_list' => AppRoutes.notifications,
    _ => null,
  };

  /// Navigates to whatever [entityType]/[entityId] points at.
  ///
  /// Product alerts need the full [ProductModel] because the detail route takes
  /// an object, not an id. It is looked up in the already-loaded catalog first
  /// and fetched only if that misses; if it has since been deleted, the low
  /// stock list is a more useful landing place than an error.
  static Future<void> open(
    BuildContext context, {
    required String entityType,
    required String entityId,
  }) async {
    final idRoute = _idRoute(entityType);
    if (idRoute != null && entityId.isNotEmpty) {
      Navigator.pushNamed(context, idRoute, arguments: entityId);
      return;
    }

    if (entityType == 'product' && entityId.isNotEmpty) {
      final product = await _resolveProduct(context, entityId);
      if (!context.mounted) return;
      if (product == null) {
        Navigator.pushNamed(context, AppRoutes.lowStock);
        return;
      }
      Navigator.pushNamed(
        context,
        AppRoutes.productDetail,
        arguments: product,
      );
      return;
    }

    final listRoute = _listRoute(entityType);
    if (listRoute != null) {
      Navigator.pushNamed(context, listRoute);
    }
  }

  static Future<ProductModel?> _resolveProduct(
    BuildContext context,
    String id,
  ) async {
    final loaded = context.read<ProductProvider>().allProducts;
    for (final p in loaded) {
      if (p.id == id) return p;
    }
    try {
      return await DatabaseService().getProduct(id);
    } catch (_) {
      return null;
    }
  }
}
