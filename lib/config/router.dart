import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'motion.dart';
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
import '../widgets/deferred_screen_loader.dart';
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
import '../screens/stock/stock_hold_screen.dart';
import '../screens/stock/stock_release_screen.dart';
import '../screens/stock/hold_list_screen.dart';
import '../screens/stock/transaction_history_screen.dart';
import '../screens/excel/excel_import_screen.dart' deferred as excel_import;
import '../screens/excel/excel_export_screen.dart' deferred as excel_export;
import '../screens/excel/excel_update_screen.dart' deferred as excel_update;
import '../screens/users/user_management_screen.dart';
import '../screens/users/staff_permissions_screen.dart';
import '../screens/vendors/vendor_list_screen.dart';
import '../screens/vendors/vendor_detail_screen.dart';
import '../screens/vendors/add_edit_vendor_screen.dart';
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
import '../screens/scanner/barcode_scanner_screen.dart' deferred as scanner;
import '../screens/batches/batch_list_screen.dart';
import '../screens/batches/add_batch_screen.dart';
import '../screens/batches/expiry_alerts_screen.dart';
import '../screens/inventory/reorder_suggestions_screen.dart';
import '../screens/inventory/stock_forecast_screen.dart';
import '../screens/inventory/stock_take_list_screen.dart';
import '../screens/inventory/create_stock_take_screen.dart';
import '../screens/inventory/stock_take_count_screen.dart';
import '../screens/audit/audit_log_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/search/global_search_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/company/company_switcher_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/warehouse/warehouse_zones_screen.dart';
import '../screens/activity/activity_timeline_screen.dart';
import '../screens/help/help_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/about/about_screen.dart';
import '../screens/settings/home_customization_screen.dart';
import '../screens/settings/data_health_screen.dart';
import '../screens/settings/plan_features_screen.dart';
import '../screens/super_admin/super_admin_dashboard_screen.dart';
import '../screens/super_admin/super_admin_company_screen.dart';
import '../models/company_model.dart';
import '../screens/reports/stock_ledger_screen.dart';
import '../screens/reports/aging_screen.dart';
import '../screens/billing/payments_ledger_screen.dart';
import '../screens/billing/credit_note_screen.dart';
import '../screens/roles/role_list_screen.dart';
import '../screens/roles/role_editor_screen.dart';
import '../screens/pos/fast_pos_screen.dart' deferred as pos;

// Deferred groups — loaded on demand so they stay out of main.dart.js
// and only fetch when the user actually navigates to the feature.
import '../screens/reports/reports_screen.dart' deferred as reports;
import '../screens/reports/damage_history_screen.dart'
    deferred as reports_damage;
import '../screens/reports/profit_loss_screen.dart' deferred as reports_pl;
import '../screens/reports/abc_analysis_screen.dart' deferred as reports_abc;
import '../screens/reports/valuation_trends_screen.dart'
    deferred as reports_val;
import '../screens/reports/price_history_screen.dart' deferred as reports_price;
import '../screens/dashboard/dashboard_screen.dart' deferred as dashboard;
import '../screens/billing/invoice_list_screen.dart' deferred as billing_list;
import '../screens/billing/create_invoice_screen.dart'
    deferred as billing_create;
import '../screens/billing/invoice_detail_screen.dart'
    deferred as billing_detail;
import '../screens/billing/billing_settings_screen.dart'
    deferred as billing_settings;
import '../screens/billing/billing_reports_screen.dart'
    deferred as billing_reports;
import '../screens/billing/customer_statement_screen.dart'
    deferred as billing_cstmt;
import '../screens/billing/vendor_statement_screen.dart'
    deferred as billing_vstmt;
import '../screens/bulk/bulk_stock_in_screen.dart' deferred as bulk_in;
import '../screens/bulk/bulk_edit_screen.dart' deferred as bulk_edit;

/// A single, shared page transition for every pushed route: the incoming page
/// fades in while gently settling from a slight scale-down (0.96 -> 1) and a
/// small upward slide (12px -> 0). Kept subtle so it complements — rather than
/// competes with — each screen's own content entrance (FadeSlideIn /
/// AnimatedListItem). Honors reduce-motion by rendering the page instantly.
PageRouteBuilder _slideRoute(settings, Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: kSlideTransitionDuration,
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: kSlideTransitionCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, inner) {
            final t = curved.value;
            return Transform.translate(
              offset: Offset(0, (1 - t) * 12),
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
                child: inner,
              ),
            );
          },
          child: child,
        ),
      );
    },
  );
}

// --- Duplicate-navigation guard --------------------------------------------
// Rapid double taps — and widgets that accidentally fire a push twice — used to
// stack identical pages on top of each other, so going back "fumbled" through
// duplicate copies of the same screen. We debounce by route name + arguments:
// an identical destination requested again within this short window is ignored.
// Genuinely different destinations (or the same one a moment later) are never
// affected. Tab switches don't go through here, so they're unaffected.
String? _lastNavSignature;
DateTime? _lastNavAt;
const Duration _kDuplicateNavWindow = Duration(milliseconds: 600);

bool _isDuplicateNavigation(RouteSettings settings) {
  final signature = '${settings.name}#${settings.arguments?.hashCode ?? 0}';
  final now = DateTime.now();
  final isDuplicate =
      signature == _lastNavSignature &&
      _lastNavAt != null &&
      now.difference(_lastNavAt!) < _kDuplicateNavWindow;
  _lastNavSignature = signature;
  _lastNavAt = now;
  return isDuplicate;
}

/// An invisible, instantly self-removing route used to swallow a duplicate
/// navigation. Returning `null` from [onGenerateRoute] is unsafe (it crashes
/// `pushNamed`), so instead we push a transparent route that removes itself on
/// the next frame — the user never sees it and the current page stays put.
Route<dynamic> _noopRoute(RouteSettings settings) {
  return PageRouteBuilder(
    settings: settings,
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (ctx, _, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = ModalRoute.of(ctx);
        if (route != null) Navigator.of(ctx).removeRoute(route);
      });
      return const SizedBox.shrink();
    },
  );
}

/// Lightweight placeholder shown while a deferred library chunk is loading.
/// Uses only colors that are resolved from the current theme — no blocking work.

Route<dynamic>? onGenerateRoute(RouteSettings settings, BuildContext context) {
  // No auth guard here on purpose: [AuthWrapper] is the single global gate for
  // authentication (the app shell is only shown when signed in, and startup is
  // always routed through it via onGenerateInitialRoutes). Re-checking
  // isLoggedIn while generating each route is not only redundant, it actively
  // breaks navigation: the auth stream briefly flips currentUser to null while
  // it re-fetches user data (token refresh / cold start), and any page pushed
  // during that window would get replaced by a static Landing page that never
  // recovers -- i.e. the user gets "thrown out" mid-session.

  // Swallow accidental duplicate pushes (double taps / double-fired handlers)
  // so identical screens don't stack up and back navigation stays predictable.
  if (_isDuplicateNavigation(settings)) {
    return _noopRoute(settings);
  }

  return switch (settings.name) {
    AppRoutes.landing => MaterialPageRoute(
      builder: (_) => const LandingScreen(),
    ),
    AppRoutes.login => _slideRoute(settings, const LoginScreen()),
    AppRoutes.register => _slideRoute(settings, const RegisterScreen()),
    AppRoutes.home => MaterialPageRoute(builder: (_) => const HomeScreen()),

    // -- Products --
    AppRoutes.productList => _slideRoute(settings, const ProductListScreen()),
    AppRoutes.addProduct => _slideRoute(settings, 
      AddEditProductScreen(product: settings.arguments as ProductModel?),
    ),
    AppRoutes.editProduct => () {
      final product = settings.arguments as ProductModel?;
      return product == null
          ? _slideRoute(settings, const ProductListScreen())
          : _slideRoute(settings, AddEditProductScreen(product: product));
    }(),
    AppRoutes.productDetail => () {
      final product = settings.arguments as ProductModel?;
      return product == null
          ? _slideRoute(settings, const ProductListScreen())
          : _slideRoute(settings, ProductDetailScreen(product: product));
    }(),
    AppRoutes.categories => _slideRoute(settings, const CategoryScreen()),

    // -- Stock --
    AppRoutes.stockIn => _slideRoute(settings, 
      StockInScreen(product: settings.arguments as ProductModel?),
    ),
    AppRoutes.stockOut => _slideRoute(settings, 
      StockOutScreen(
        product: settings.arguments is ProductModel
            ? settings.arguments as ProductModel
            : null,
        holdAction: settings.arguments is HoldActionArgs
            ? settings.arguments as HoldActionArgs
            : null,
      ),
    ),
    AppRoutes.damageReport => _slideRoute(settings, 
      DamageReportScreen(product: settings.arguments as ProductModel?),
    ),
    AppRoutes.stockTransfer => _slideRoute(settings, 
      StockTransferScreen(product: settings.arguments as ProductModel?),
    ),
    AppRoutes.lowStock => _slideRoute(settings, const LowStockScreen()),
    AppRoutes.stockAdjustment => _slideRoute(settings, 
      StockAdjustmentScreen(product: settings.arguments as ProductModel?),
    ),
    AppRoutes.stockHold => _slideRoute(settings, 
      StockHoldScreen(product: settings.arguments as ProductModel?),
    ),
    AppRoutes.stockRelease => _slideRoute(settings, 
      StockReleaseScreen(
        product: settings.arguments is ProductModel
            ? settings.arguments as ProductModel
            : null,
        initialChallan: settings.arguments is HoldActionArgs
            ? (settings.arguments as HoldActionArgs).hold.challanNumber
            : null,
      ),
    ),
    AppRoutes.stockHolds => _slideRoute(settings, const HoldListScreen()),
    AppRoutes.transactionHistory => _slideRoute(settings, 
      const TransactionHistoryScreen(),
    ),

    // -- Excel --
    // Deferred: these pull in the `excel` and `file_picker` packages, which
    // are dead weight for the majority of sessions that never import a sheet.
    AppRoutes.excelImport => _slideRoute(
      settings,
      DeferredScreenLoader(
        future: excel_import.loadLibrary(),
        builder: (_) => excel_import.ExcelImportScreen(),
      ),
    ),
    AppRoutes.excelExport => _slideRoute(
      settings,
      DeferredScreenLoader(
        future: excel_export.loadLibrary(),
        builder: (_) => excel_export.ExcelExportScreen(),
      ),
    ),
    AppRoutes.excelUpdate => _slideRoute(
      settings,
      DeferredScreenLoader(
        future: excel_update.loadLibrary(),
        builder: (_) => excel_update.ExcelUpdateScreen(),
      ),
    ),

    // -- Users --
    AppRoutes.userManagement => _slideRoute(settings, const UserManagementScreen()),
    AppRoutes.staffPermissions => _slideRoute(settings, const StaffPermissionsScreen()),

    // -- Reports (deferred) --
    AppRoutes.reports => _slideRoute(settings, 
      DeferredScreenLoader(
        future: reports.loadLibrary(),
        builder: (_) => reports.ReportsScreen(),
      ),
    ),
    AppRoutes.dashboard => _slideRoute(settings, 
      DeferredScreenLoader(
        future: dashboard.loadLibrary(),
        builder: (_) => dashboard.DashboardScreen(),
      ),
    ),
    AppRoutes.damageHistory => _slideRoute(settings, 
      DeferredScreenLoader(
        future: reports_damage.loadLibrary(),
        builder: (_) => reports_damage.DamageHistoryScreen(),
      ),
    ),
    AppRoutes.profitLoss => _slideRoute(settings, 
      DeferredScreenLoader(
        future: reports_pl.loadLibrary(),
        builder: (_) => reports_pl.ProfitLossScreen(),
      ),
    ),
    AppRoutes.abcAnalysis => _slideRoute(settings, 
      DeferredScreenLoader(
        future: reports_abc.loadLibrary(),
        builder: (_) => reports_abc.AbcAnalysisScreen(),
      ),
    ),
    AppRoutes.valuationTrends => _slideRoute(settings, 
      DeferredScreenLoader(
        future: reports_val.loadLibrary(),
        builder: (_) => reports_val.ValuationTrendsScreen(),
      ),
    ),
    AppRoutes.priceHistory => _slideRoute(settings, 
      DeferredScreenLoader(
        future: reports_price.loadLibrary(),
        builder: (_) => reports_price.PriceHistoryScreen(),
      ),
    ),

    // -- Vendors --
    AppRoutes.vendors => _slideRoute(settings, const VendorListScreen()),
    AppRoutes.addVendor => _slideRoute(settings, const AddEditVendorScreen()),
    AppRoutes.editVendor => () {
      final vendor = settings.arguments as VendorModel?;
      return vendor == null
          ? _slideRoute(settings, const VendorListScreen())
          : _slideRoute(settings, AddEditVendorScreen(vendor: vendor));
    }(),
    AppRoutes.vendorDetail => () {
      final vendor = settings.arguments as VendorModel?;
      return vendor == null
          ? _slideRoute(settings, const VendorListScreen())
          : _slideRoute(settings, VendorDetailScreen(vendor: vendor));
    }(),

    // -- Legal (public) --
    AppRoutes.privacyPolicy => _slideRoute(settings, const PrivacyPolicyScreen()),
    AppRoutes.terms => _slideRoute(settings, const TermsScreen()),
    AppRoutes.support => _slideRoute(settings, const SupportScreen()),
    AppRoutes.dataDeletion => _slideRoute(settings, const DataDeletionScreen()),

    // -- Orders --
    AppRoutes.purchaseOrders => _slideRoute(settings, const PurchaseOrderListScreen()),
    AppRoutes.createPurchaseOrder => _slideRoute(settings, 
      const CreatePurchaseOrderScreen(),
    ),
    AppRoutes.purchaseOrderDetail => () {
      final poId = settings.arguments as String?;
      return poId == null
          ? _slideRoute(settings, const PurchaseOrderListScreen())
          : _slideRoute(settings, PurchaseOrderDetailScreen(orderId: poId));
    }(),
    AppRoutes.salesOrders => _slideRoute(settings, const SalesOrderListScreen()),
    AppRoutes.createSalesOrder => _slideRoute(settings, const CreateSalesOrderScreen()),
    AppRoutes.salesOrderDetail => () {
      final soId = settings.arguments as String?;
      return soId == null
          ? _slideRoute(settings, const SalesOrderListScreen())
          : _slideRoute(settings, SalesOrderDetailScreen(orderId: soId));
    }(),

    // -- Returns --
    AppRoutes.returns => _slideRoute(settings, const ReturnsListScreen()),
    AppRoutes.createReturn => _slideRoute(settings, const CreateReturnScreen()),
    AppRoutes.returnDetail => () {
      final retId = settings.arguments as String?;
      return retId == null
          ? _slideRoute(settings, const ReturnsListScreen())
          : _slideRoute(settings, ReturnDetailScreen(returnId: retId));
    }(),

    // -- Customers --
    AppRoutes.customers => _slideRoute(settings, const CustomerListScreen()),
    AppRoutes.addCustomer => _slideRoute(settings, const AddEditCustomerScreen()),
    AppRoutes.editCustomer => () {
      final customer = settings.arguments as CustomerModel?;
      return customer == null
          ? _slideRoute(settings, const CustomerListScreen())
          : _slideRoute(settings, AddEditCustomerScreen(customer: customer));
    }(),
    AppRoutes.customerDetail => () {
      final customerId = settings.arguments as String?;
      return customerId == null
          ? _slideRoute(settings, const CustomerListScreen())
          : _slideRoute(settings, CustomerDetailScreen(customerId: customerId));
    }(),

    // -- Scanner & Batches --
    AppRoutes.barcodeScanner => () {
      final scanArgs = settings.arguments;
      final captureOnly =
          scanArgs is BarcodeScannerArgs && scanArgs.captureOnly;
      // Deferred: carries the `mobile_scanner` package.
      return _slideRoute(
        settings,
        DeferredScreenLoader(
          future: scanner.loadLibrary(),
          builder: (_) => scanner.BarcodeScannerScreen(captureOnly: captureOnly),
        ),
      );
    }(),
    AppRoutes.batches => _slideRoute(settings, const BatchListScreen()),
    AppRoutes.addBatch => _slideRoute(settings, const AddBatchScreen()),
    AppRoutes.expiryAlerts => _slideRoute(settings, const ExpiryAlertsScreen()),

    // -- Inventory --
    AppRoutes.reorderSuggestions => _slideRoute(settings, 
      const ReorderSuggestionsScreen(),
    ),
    AppRoutes.stockForecast => _slideRoute(settings, const StockForecastScreen()),
    AppRoutes.stockTakes => _slideRoute(settings, const StockTakeListScreen()),
    AppRoutes.createStockTake => _slideRoute(settings, const CreateStockTakeScreen()),
    AppRoutes.stockTakeCount => () {
      final st = settings.arguments as StockTakeModel?;
      return st == null
          ? _slideRoute(settings, const StockTakeListScreen())
          : _slideRoute(settings, StockTakeCountScreen(stockTake: st));
    }(),

    // -- Audit & Notifications --
    AppRoutes.auditLog => _slideRoute(settings, const AuditLogScreen()),
    AppRoutes.notifications => _slideRoute(settings, const NotificationsScreen()),
    AppRoutes.globalSearch => _slideRoute(settings, const GlobalSearchScreen()),
    AppRoutes.activityTimeline => _slideRoute(settings, const ActivityTimelineScreen()),

    // -- Bulk (deferred) --
    AppRoutes.bulkStockIn => _slideRoute(settings, 
      DeferredScreenLoader(
        future: bulk_in.loadLibrary(),
        builder: (_) => bulk_in.BulkStockInScreen(),
      ),
    ),
    AppRoutes.bulkEdit => _slideRoute(settings, 
      DeferredScreenLoader(
        future: bulk_edit.loadLibrary(),
        builder: (_) => bulk_edit.BulkEditScreen(),
      ),
    ),

    // -- Onboarding & Company --
    AppRoutes.onboarding => _slideRoute(settings, const OnboardingScreen()),
    AppRoutes.companySwitcher => _slideRoute(settings, const CompanySwitcherScreen()),

    // -- Favorites & Warehouse --
    AppRoutes.favorites => _slideRoute(settings, const FavoritesScreen()),
    AppRoutes.warehouseZones => _slideRoute(settings, const WarehouseZonesScreen()),

    // -- Profile & Settings --
    AppRoutes.profile => _slideRoute(settings, const ProfileScreen()),
    AppRoutes.about => _slideRoute(settings, const AboutScreen()),
    AppRoutes.help => _slideRoute(settings, const HelpScreen()),
    AppRoutes.homeCustomization => _slideRoute(settings, const HomeCustomizationScreen()),
    AppRoutes.dataHealth => _slideRoute(settings, const DataHealthScreen()),
    AppRoutes.planFeatures => _slideRoute(settings, const PlanFeaturesScreen()),

    // -- Super admin (cross-tenant; gated by SuperAdminProvider + rules) --
    AppRoutes.superAdmin => _slideRoute(
      settings,
      const SuperAdminDashboardScreen(),
    ),
    AppRoutes.superAdminCompany => _slideRoute(
      settings,
      SuperAdminCompanyScreen(
        company: settings.arguments as CompanyModel,
      ),
    ),
    AppRoutes.aging => _slideRoute(settings, const AgingScreen()),
    AppRoutes.creditNote => _slideRoute(
      settings,
      CreditNoteScreen(invoice: settings.arguments as InvoiceModel),
    ),
    AppRoutes.paymentsLedger => _slideRoute(
      settings,
      const PaymentsLedgerScreen(),
    ),
    AppRoutes.stockLedger => _slideRoute(
      settings,
      StockLedgerScreen(initialProduct: settings.arguments as ProductModel?),
    ),
    AppRoutes.settings => _slideRoute(settings, 
      SettingsScreen(initialSection: settings.arguments as String?),
    ),

    // -- Roles --
    AppRoutes.roles => _slideRoute(settings, const RoleListScreen()),
    AppRoutes.roleEditor => _slideRoute(settings, 
      RoleEditorScreen(role: settings.arguments as RoleModel?),
    ),

    // -- Billing (deferred) --
    AppRoutes.invoices => _slideRoute(settings, 
      DeferredScreenLoader(
        future: billing_list.loadLibrary(),
        builder: (_) => billing_list.InvoiceListScreen(),
      ),
    ),
    AppRoutes.createInvoice => () {
      final args = settings.arguments;
      return _slideRoute(settings, 
        DeferredScreenLoader(
          future: billing_create.loadLibrary(),
          builder: (_) {
            if (args is Map<String, dynamic>) {
              return billing_create.CreateInvoiceScreen(
                salesOrderId: args['salesOrderId'] as String?,
                purchaseOrderId: args['purchaseOrderId'] as String?,
                initialType: args['type'] as InvoiceType? ?? InvoiceType.sales,
                preselectedVendorId: args['vendorId'] as String?,
                preselectedVendorName: args['vendorName'] as String?,
                preselectedCustomerId: args['customerId'] as String?,
                preselectedCustomerName: args['customerName'] as String?,
              );
            }
            return billing_create.CreateInvoiceScreen(
              salesOrderId: args is String ? args : null,
            );
          },
        ),
      );
    }(),
    AppRoutes.invoiceDetail => () {
      final invoiceId = settings.arguments as String?;
      if (invoiceId == null) {
        return _slideRoute(settings, 
          DeferredScreenLoader(
            future: billing_list.loadLibrary(),
            builder: (_) => billing_list.InvoiceListScreen(),
          ),
        );
      }
      return _slideRoute(settings, 
        DeferredScreenLoader(
          future: billing_detail.loadLibrary(),
          builder: (_) =>
              billing_detail.InvoiceDetailRouteEntry(routeArgument: invoiceId),
        ),
      );
    }(),
    AppRoutes.billingSettings => _slideRoute(settings, 
      DeferredScreenLoader(
        future: billing_settings.loadLibrary(),
        builder: (_) => billing_settings.BillingSettingsScreen(),
      ),
    ),
    AppRoutes.billingReports => _slideRoute(settings, 
      DeferredScreenLoader(
        future: billing_reports.loadLibrary(),
        builder: (_) => billing_reports.BillingReportsScreen(),
      ),
    ),
    AppRoutes.customerStatement => _slideRoute(settings, 
      DeferredScreenLoader(
        future: billing_cstmt.loadLibrary(),
        builder: (_) => billing_cstmt.CustomerStatementScreen(),
      ),
    ),
    AppRoutes.vendorStatement => _slideRoute(settings, 
      DeferredScreenLoader(
        future: billing_vstmt.loadLibrary(),
        builder: (_) => billing_vstmt.VendorStatementScreen(),
      ),
    ),
    AppRoutes.fastPos => _slideRoute(
      settings,
      DeferredScreenLoader(
        future: pos.loadLibrary(),
        builder: (_) => pos.FastPosScreen(),
      ),
    ),

    // Unknown route: keep a signed-in user inside the app (Home) rather than
    // bouncing them out to the public Landing page. Only signed-out sessions
    // fall back to Landing.
    _ => context.read<AuthProvider>().isLoggedIn
        ? MaterialPageRoute(builder: (_) => const HomeScreen())
        : MaterialPageRoute(builder: (_) => const LandingScreen()),
  };
}
