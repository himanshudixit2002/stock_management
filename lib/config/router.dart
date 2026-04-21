import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'routes.dart';
import '../models/product_model.dart';
import '../models/vendor_model.dart';
import '../models/customer_model.dart';
import '../models/stock_take_model.dart';
import '../models/invoice_model.dart';
import '../models/role_model.dart';
import '../screens/landing_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home_screen.dart';
import '../screens/products/add_edit_product_screen.dart';
import '../screens/products/product_detail_screen.dart';
import '../screens/products/product_list_screen.dart';
import '../screens/categories/category_screen.dart';
import '../screens/stock/stock_in_screen.dart';
import '../screens/stock/stock_out_screen.dart';
import '../screens/stock/damage_report_screen.dart';
import '../screens/stock/stock_transfer_screen.dart';
import '../screens/stock/low_stock_screen.dart';
import '../screens/stock/stock_adjustment_screen.dart';
import '../screens/stock/transaction_history_screen.dart';
import '../screens/excel/excel_import_screen.dart';
import '../screens/excel/excel_export_screen.dart';
import '../screens/excel/excel_update_screen.dart';
import '../screens/users/user_management_screen.dart';
import '../screens/users/staff_permissions_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/vendors/vendor_list_screen.dart';
import '../screens/vendors/vendor_detail_screen.dart';
import '../screens/vendors/add_edit_vendor_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/reports/damage_history_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/legal/support_screen.dart';
import '../screens/legal/data_deletion_screen.dart';
import '../screens/orders/purchase_order_list_screen.dart';
import '../screens/orders/create_purchase_order_screen.dart';
import '../screens/orders/purchase_order_detail_screen.dart';
import '../screens/orders/sales_order_list_screen.dart';
import '../screens/orders/create_sales_order_screen.dart';
import '../screens/orders/sales_order_detail_screen.dart';
import '../screens/returns/returns_list_screen.dart';
import '../screens/returns/create_return_screen.dart';
import '../screens/returns/return_detail_screen.dart';
import '../screens/customers/customer_list_screen.dart';
import '../screens/customers/add_edit_customer_screen.dart';
import '../screens/customers/customer_detail_screen.dart';
import '../screens/scanner/barcode_scanner_screen.dart';
import '../screens/batches/batch_list_screen.dart';
import '../screens/batches/add_batch_screen.dart';
import '../screens/batches/expiry_alerts_screen.dart';
import '../screens/inventory/reorder_suggestions_screen.dart';
import '../screens/inventory/stock_forecast_screen.dart';
import '../screens/inventory/stock_take_list_screen.dart';
import '../screens/inventory/create_stock_take_screen.dart';
import '../screens/inventory/stock_take_count_screen.dart';
import '../screens/reports/profit_loss_screen.dart';
import '../screens/reports/abc_analysis_screen.dart';
import '../screens/reports/valuation_trends_screen.dart';
import '../screens/audit/audit_log_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/search/global_search_screen.dart';
import '../screens/bulk/bulk_stock_in_screen.dart';
import '../screens/bulk/bulk_edit_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/company/company_switcher_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/reports/price_history_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/warehouse/warehouse_zones_screen.dart';
import '../screens/activity/activity_timeline_screen.dart';
import '../screens/help/help_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/about/about_screen.dart';
import '../screens/settings/home_customization_screen.dart';
import '../screens/roles/role_list_screen.dart';
import '../screens/roles/role_editor_screen.dart';
import '../screens/billing/invoice_list_screen.dart';
import '../screens/billing/create_invoice_screen.dart';
import '../screens/billing/invoice_detail_screen.dart';
import '../screens/billing/billing_settings_screen.dart';
import '../screens/billing/billing_reports_screen.dart';
import '../screens/billing/customer_statement_screen.dart';
import '../screens/billing/vendor_statement_screen.dart';

const _kPublicRoutes = {
  AppRoutes.landing,
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.privacyPolicy,
  AppRoutes.terms,
  AppRoutes.support,
  AppRoutes.dataDeletion,
};

PageRouteBuilder _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
  );
}

Route<dynamic>? onGenerateRoute(
  RouteSettings settings,
  BuildContext context,
) {
  final isProtected = !_kPublicRoutes.contains(settings.name);
  if (isProtected && !context.read<AuthProvider>().isLoggedIn) {
    return MaterialPageRoute(builder: (_) => const LandingScreen());
  }

  return switch (settings.name) {
    AppRoutes.landing =>
      MaterialPageRoute(builder: (_) => const LandingScreen()),
    AppRoutes.login =>
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    AppRoutes.register =>
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    AppRoutes.home =>
      MaterialPageRoute(builder: (_) => const HomeScreen()),

    // -- Products --
    AppRoutes.productList => _slideRoute(const ProductListScreen()),
    AppRoutes.addProduct => _slideRoute(
        AddEditProductScreen(product: settings.arguments as ProductModel?)),
    AppRoutes.editProduct => () {
        final product = settings.arguments as ProductModel?;
        return product == null
            ? _slideRoute(const ProductListScreen())
            : _slideRoute(AddEditProductScreen(product: product));
      }(),
    AppRoutes.productDetail => () {
        final product = settings.arguments as ProductModel?;
        return product == null
            ? _slideRoute(const ProductListScreen())
            : _slideRoute(ProductDetailScreen(product: product));
      }(),
    AppRoutes.categories => _slideRoute(const CategoryScreen()),

    // -- Stock --
    AppRoutes.stockIn =>
      _slideRoute(StockInScreen(product: settings.arguments as ProductModel?)),
    AppRoutes.stockOut =>
      _slideRoute(StockOutScreen(product: settings.arguments as ProductModel?)),
    AppRoutes.damageReport => _slideRoute(
        DamageReportScreen(product: settings.arguments as ProductModel?)),
    AppRoutes.stockTransfer => _slideRoute(
        StockTransferScreen(product: settings.arguments as ProductModel?)),
    AppRoutes.lowStock => _slideRoute(const LowStockScreen()),
    AppRoutes.stockAdjustment => _slideRoute(
        StockAdjustmentScreen(product: settings.arguments as ProductModel?)),
    AppRoutes.transactionHistory =>
      _slideRoute(const TransactionHistoryScreen()),

    // -- Excel --
    AppRoutes.excelImport => _slideRoute(const ExcelImportScreen()),
    AppRoutes.excelExport => _slideRoute(const ExcelExportScreen()),
    AppRoutes.excelUpdate => _slideRoute(const ExcelUpdateScreen()),

    // -- Users --
    AppRoutes.userManagement => _slideRoute(const UserManagementScreen()),
    AppRoutes.staffPermissions => _slideRoute(const StaffPermissionsScreen()),

    // -- Reports --
    AppRoutes.reports => _slideRoute(const ReportsScreen()),
    AppRoutes.dashboard => _slideRoute(const DashboardScreen()),
    AppRoutes.damageHistory => _slideRoute(const DamageHistoryScreen()),
    AppRoutes.profitLoss => _slideRoute(const ProfitLossScreen()),
    AppRoutes.abcAnalysis => _slideRoute(const AbcAnalysisScreen()),
    AppRoutes.valuationTrends => _slideRoute(const ValuationTrendsScreen()),
    AppRoutes.priceHistory => _slideRoute(const PriceHistoryScreen()),

    // -- Vendors --
    AppRoutes.vendors => _slideRoute(const VendorListScreen()),
    AppRoutes.addVendor => _slideRoute(const AddEditVendorScreen()),
    AppRoutes.editVendor => () {
        final vendor = settings.arguments as VendorModel?;
        return vendor == null
            ? _slideRoute(const VendorListScreen())
            : _slideRoute(AddEditVendorScreen(vendor: vendor));
      }(),
    AppRoutes.vendorDetail => () {
        final vendor = settings.arguments as VendorModel?;
        return vendor == null
            ? _slideRoute(const VendorListScreen())
            : _slideRoute(VendorDetailScreen(vendor: vendor));
      }(),

    // -- Legal (public) --
    AppRoutes.privacyPolicy => _slideRoute(const PrivacyPolicyScreen()),
    AppRoutes.terms => _slideRoute(const TermsScreen()),
    AppRoutes.support => _slideRoute(const SupportScreen()),
    AppRoutes.dataDeletion => _slideRoute(const DataDeletionScreen()),

    // -- Orders --
    AppRoutes.purchaseOrders =>
      _slideRoute(const PurchaseOrderListScreen()),
    AppRoutes.createPurchaseOrder =>
      _slideRoute(const CreatePurchaseOrderScreen()),
    AppRoutes.purchaseOrderDetail => () {
        final poId = settings.arguments as String?;
        return poId == null
            ? _slideRoute(const PurchaseOrderListScreen())
            : _slideRoute(PurchaseOrderDetailScreen(orderId: poId));
      }(),
    AppRoutes.salesOrders => _slideRoute(const SalesOrderListScreen()),
    AppRoutes.createSalesOrder =>
      _slideRoute(const CreateSalesOrderScreen()),
    AppRoutes.salesOrderDetail => () {
        final soId = settings.arguments as String?;
        return soId == null
            ? _slideRoute(const SalesOrderListScreen())
            : _slideRoute(SalesOrderDetailScreen(orderId: soId));
      }(),

    // -- Returns --
    AppRoutes.returns => _slideRoute(const ReturnsListScreen()),
    AppRoutes.createReturn => _slideRoute(const CreateReturnScreen()),
    AppRoutes.returnDetail => () {
        final retId = settings.arguments as String?;
        return retId == null
            ? _slideRoute(const ReturnsListScreen())
            : _slideRoute(ReturnDetailScreen(returnId: retId));
      }(),

    // -- Customers --
    AppRoutes.customers => _slideRoute(const CustomerListScreen()),
    AppRoutes.addCustomer => _slideRoute(const AddEditCustomerScreen()),
    AppRoutes.editCustomer => () {
        final customer = settings.arguments as CustomerModel?;
        return customer == null
            ? _slideRoute(const CustomerListScreen())
            : _slideRoute(AddEditCustomerScreen(customer: customer));
      }(),
    AppRoutes.customerDetail => () {
        final customerId = settings.arguments as String?;
        return customerId == null
            ? _slideRoute(const CustomerListScreen())
            : _slideRoute(CustomerDetailScreen(customerId: customerId));
      }(),

    // -- Scanner & Batches --
    AppRoutes.barcodeScanner => () {
        final scanArgs = settings.arguments;
        final captureOnly =
            scanArgs is BarcodeScannerArgs && scanArgs.captureOnly;
        return _slideRoute(BarcodeScannerScreen(captureOnly: captureOnly));
      }(),
    AppRoutes.batches => _slideRoute(const BatchListScreen()),
    AppRoutes.addBatch => _slideRoute(const AddBatchScreen()),
    AppRoutes.expiryAlerts => _slideRoute(const ExpiryAlertsScreen()),

    // -- Inventory --
    AppRoutes.reorderSuggestions =>
      _slideRoute(const ReorderSuggestionsScreen()),
    AppRoutes.stockForecast => _slideRoute(const StockForecastScreen()),
    AppRoutes.stockTakes => _slideRoute(const StockTakeListScreen()),
    AppRoutes.createStockTake => _slideRoute(const CreateStockTakeScreen()),
    AppRoutes.stockTakeCount => () {
        final st = settings.arguments as StockTakeModel?;
        return st == null
            ? _slideRoute(const StockTakeListScreen())
            : _slideRoute(StockTakeCountScreen(stockTake: st));
      }(),

    // -- Audit & Notifications --
    AppRoutes.auditLog => _slideRoute(const AuditLogScreen()),
    AppRoutes.notifications => _slideRoute(const NotificationsScreen()),
    AppRoutes.globalSearch => _slideRoute(const GlobalSearchScreen()),
    AppRoutes.activityTimeline => _slideRoute(const ActivityTimelineScreen()),

    // -- Bulk --
    AppRoutes.bulkStockIn => _slideRoute(const BulkStockInScreen()),
    AppRoutes.bulkEdit => _slideRoute(const BulkEditScreen()),

    // -- Onboarding & Company --
    AppRoutes.onboarding => _slideRoute(const OnboardingScreen()),
    AppRoutes.companySwitcher => _slideRoute(const CompanySwitcherScreen()),

    // -- Favorites & Warehouse --
    AppRoutes.favorites => _slideRoute(const FavoritesScreen()),
    AppRoutes.warehouseZones => _slideRoute(const WarehouseZonesScreen()),

    // -- Profile & Settings --
    AppRoutes.profile => _slideRoute(const ProfileScreen()),
    AppRoutes.about => _slideRoute(const AboutScreen()),
    AppRoutes.help => _slideRoute(const HelpScreen()),
    AppRoutes.homeCustomization =>
      _slideRoute(const HomeCustomizationScreen()),
    AppRoutes.settings => _slideRoute(
        SettingsScreen(initialSection: settings.arguments as String?)),

    // -- Roles --
    AppRoutes.roles => _slideRoute(const RoleListScreen()),
    AppRoutes.roleEditor =>
      _slideRoute(RoleEditorScreen(role: settings.arguments as RoleModel?)),

    // -- Billing --
    AppRoutes.invoices => _slideRoute(const InvoiceListScreen()),
    AppRoutes.createInvoice => () {
        final args = settings.arguments;
        if (args is Map<String, dynamic>) {
          return _slideRoute(CreateInvoiceScreen(
            salesOrderId: args['salesOrderId'] as String?,
            purchaseOrderId: args['purchaseOrderId'] as String?,
            initialType:
                args['type'] as InvoiceType? ?? InvoiceType.sales,
            preselectedVendorId: args['vendorId'] as String?,
            preselectedVendorName: args['vendorName'] as String?,
            preselectedCustomerId: args['customerId'] as String?,
            preselectedCustomerName: args['customerName'] as String?,
          ));
        }
        return _slideRoute(CreateInvoiceScreen(
          salesOrderId: args is String ? args : null,
        ));
      }(),
    AppRoutes.invoiceDetail => () {
        final invoiceId = settings.arguments as String?;
        return invoiceId == null
            ? _slideRoute(const InvoiceListScreen())
            : _slideRoute(
                InvoiceDetailRouteEntry(routeArgument: invoiceId));
      }(),
    AppRoutes.billingSettings => _slideRoute(const BillingSettingsScreen()),
    AppRoutes.billingReports => _slideRoute(const BillingReportsScreen()),
    AppRoutes.customerStatement =>
      _slideRoute(const CustomerStatementScreen()),
    AppRoutes.vendorStatement =>
      _slideRoute(const VendorStatementScreen()),

    _ => MaterialPageRoute(builder: (_) => const LandingScreen()),
  };
}
