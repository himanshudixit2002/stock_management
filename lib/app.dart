import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/routes.dart';
import 'models/invoice_model.dart';
import 'config/theme.dart';
import 'utils/error_helpers.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/category_provider.dart';
import 'providers/stock_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vendor_provider.dart';
import 'providers/purchase_order_provider.dart';
import 'providers/sales_order_provider.dart';
import 'providers/return_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/batch_provider.dart';
import 'providers/stock_take_provider.dart';
import 'providers/audit_log_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/price_history_provider.dart';
import 'providers/warehouse_zone_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/home_customization_provider.dart';
import 'providers/billing_provider.dart';
import 'providers/billing_settings_provider.dart';
import 'providers/role_provider.dart';
import 'screens/landing_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/products/add_edit_product_screen.dart';
import 'screens/products/product_detail_screen.dart';
import 'screens/products/product_list_screen.dart';
import 'screens/categories/category_screen.dart';
import 'screens/stock/stock_in_screen.dart';
import 'screens/stock/stock_out_screen.dart';
import 'screens/stock/damage_report_screen.dart';
import 'screens/stock/stock_transfer_screen.dart';
import 'screens/stock/low_stock_screen.dart';
import 'screens/stock/stock_adjustment_screen.dart';
import 'screens/stock/transaction_history_screen.dart';
import 'screens/excel/excel_import_screen.dart';
import 'screens/excel/excel_export_screen.dart';
import 'screens/excel/excel_update_screen.dart';
import 'screens/users/user_management_screen.dart';
import 'screens/users/staff_permissions_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/vendors/vendor_list_screen.dart';
import 'screens/vendors/vendor_detail_screen.dart';
import 'screens/vendors/add_edit_vendor_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/reports/damage_history_screen.dart';
import 'screens/legal/privacy_policy_screen.dart';
import 'screens/legal/terms_screen.dart';
import 'screens/legal/support_screen.dart';
import 'screens/legal/data_deletion_screen.dart';
import 'screens/orders/purchase_order_list_screen.dart';
import 'screens/orders/create_purchase_order_screen.dart';
import 'screens/orders/purchase_order_detail_screen.dart';
import 'screens/orders/sales_order_list_screen.dart';
import 'screens/orders/create_sales_order_screen.dart';
import 'screens/orders/sales_order_detail_screen.dart';
import 'screens/returns/returns_list_screen.dart';
import 'screens/returns/create_return_screen.dart';
import 'screens/returns/return_detail_screen.dart';
import 'screens/customers/customer_list_screen.dart';
import 'screens/customers/add_edit_customer_screen.dart';
import 'screens/customers/customer_detail_screen.dart';
import 'screens/scanner/barcode_scanner_screen.dart';
import 'screens/batches/batch_list_screen.dart';
import 'screens/batches/add_batch_screen.dart';
import 'screens/batches/expiry_alerts_screen.dart';
import 'screens/inventory/reorder_suggestions_screen.dart';
import 'screens/inventory/stock_forecast_screen.dart';
import 'screens/inventory/stock_take_list_screen.dart';
import 'screens/inventory/create_stock_take_screen.dart';
import 'screens/inventory/stock_take_count_screen.dart';
import 'screens/reports/profit_loss_screen.dart';
import 'screens/reports/abc_analysis_screen.dart';
import 'screens/reports/valuation_trends_screen.dart';
import 'screens/audit/audit_log_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/search/global_search_screen.dart';
import 'screens/bulk/bulk_stock_in_screen.dart';
import 'screens/bulk/bulk_edit_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/company/company_switcher_screen.dart';
import 'screens/favorites/favorites_screen.dart';
import 'screens/reports/price_history_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/warehouse/warehouse_zones_screen.dart';
import 'screens/activity/activity_timeline_screen.dart';
import 'screens/help/help_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/about/about_screen.dart';
import 'screens/settings/home_customization_screen.dart';
import 'screens/roles/role_list_screen.dart';
import 'screens/roles/role_editor_screen.dart';
import 'models/role_model.dart';
import 'screens/billing/invoice_list_screen.dart';
import 'screens/billing/create_invoice_screen.dart';
import 'screens/billing/invoice_detail_screen.dart';
import 'screens/billing/billing_settings_screen.dart';
import 'screens/billing/billing_reports_screen.dart';
import 'screens/billing/customer_statement_screen.dart';
import 'screens/billing/vendor_statement_screen.dart';
import 'models/product_model.dart';
import 'models/vendor_model.dart';
import 'models/customer_model.dart';
import 'models/stock_take_model.dart';
import 'firebase_options.dart';
import 'utils/html_splash.dart';

class _WebScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class StockManagementApp extends StatelessWidget {
  const StockManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => StockProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => VendorProvider()),
        ChangeNotifierProvider(create: (_) => PurchaseOrderProvider()),
        ChangeNotifierProvider(create: (_) => SalesOrderProvider()),
        ChangeNotifierProvider(create: (_) => ReturnProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => BatchProvider()),
        ChangeNotifierProvider(create: (_) => StockTakeProvider()),
        ChangeNotifierProvider(create: (_) => AuditLogProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => PriceHistoryProvider()),
        ChangeNotifierProvider(create: (_) => WarehouseZoneProvider()),
        ChangeNotifierProvider(create: (_) => HomeCustomizationProvider()),
        ChangeNotifierProvider(create: (_) => BillingProvider()),
        ChangeNotifierProvider(create: (_) => BillingSettingsProvider()),
        ChangeNotifierProvider(create: (_) => RoleProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) => MaterialApp(
          title: 'SmartShelfKart',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          scrollBehavior: _WebScrollBehavior(),
          debugShowCheckedModeBanner: false,
          home: const AuthWrapper(),
          onGenerateRoute: (settings) {
            PageRouteBuilder slideRoute(Widget page) {
              return PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => page,
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      );
                    },
                transitionDuration: const Duration(milliseconds: 280),
              );
            }

            switch (settings.name) {
              case AppRoutes.landing:
                return MaterialPageRoute(builder: (_) => const LandingScreen());
              case AppRoutes.login:
                return MaterialPageRoute(builder: (_) => const LoginScreen());
              case AppRoutes.register:
                return MaterialPageRoute(
                  builder: (_) => const RegisterScreen(),
                );
              case AppRoutes.home:
                return MaterialPageRoute(builder: (_) => const HomeScreen());
              case AppRoutes.productList:
                return slideRoute(const ProductListScreen());
              case AppRoutes.addProduct:
                final template = settings.arguments as ProductModel?;
                return slideRoute(AddEditProductScreen(product: template));
              case AppRoutes.editProduct:
                final product = settings.arguments as ProductModel?;
                if (product == null)
                  return slideRoute(const ProductListScreen());
                return slideRoute(AddEditProductScreen(product: product));
              case AppRoutes.productDetail:
                final product = settings.arguments as ProductModel?;
                if (product == null)
                  return slideRoute(const ProductListScreen());
                return slideRoute(ProductDetailScreen(product: product));
              case AppRoutes.categories:
                return slideRoute(const CategoryScreen());
              case AppRoutes.stockIn:
                final product = settings.arguments as ProductModel?;
                return slideRoute(StockInScreen(product: product));
              case AppRoutes.stockOut:
                final product = settings.arguments as ProductModel?;
                return slideRoute(StockOutScreen(product: product));
              case AppRoutes.damageReport:
                final product = settings.arguments as ProductModel?;
                return slideRoute(DamageReportScreen(product: product));
              case AppRoutes.stockTransfer:
                final product = settings.arguments as ProductModel?;
                return slideRoute(StockTransferScreen(product: product));
              case AppRoutes.lowStock:
                return slideRoute(const LowStockScreen());
              case AppRoutes.stockAdjustment:
                final product = settings.arguments as ProductModel?;
                return slideRoute(StockAdjustmentScreen(product: product));
              case AppRoutes.transactionHistory:
                return slideRoute(const TransactionHistoryScreen());
              case AppRoutes.excelImport:
                return slideRoute(const ExcelImportScreen());
              case AppRoutes.excelExport:
                return slideRoute(const ExcelExportScreen());
              case AppRoutes.excelUpdate:
                return slideRoute(const ExcelUpdateScreen());
              case AppRoutes.userManagement:
                return slideRoute(const UserManagementScreen());
              case AppRoutes.staffPermissions:
                return slideRoute(const StaffPermissionsScreen());
              case AppRoutes.reports:
                return slideRoute(const ReportsScreen());
              case AppRoutes.vendors:
                return slideRoute(const VendorListScreen());
              case AppRoutes.addVendor:
                return slideRoute(const AddEditVendorScreen());
              case AppRoutes.editVendor:
                final vendor = settings.arguments as VendorModel?;
                if (vendor == null) return slideRoute(const VendorListScreen());
                return slideRoute(AddEditVendorScreen(vendor: vendor));
              case AppRoutes.vendorDetail:
                final vendor = settings.arguments as VendorModel?;
                if (vendor == null) return slideRoute(const VendorListScreen());
                return slideRoute(VendorDetailScreen(vendor: vendor));
              case AppRoutes.dashboard:
                return slideRoute(const DashboardScreen());
              case AppRoutes.damageHistory:
                return slideRoute(const DamageHistoryScreen());
              case AppRoutes.privacyPolicy:
                return slideRoute(const PrivacyPolicyScreen());
              case AppRoutes.terms:
                return slideRoute(const TermsScreen());
              case AppRoutes.support:
                return slideRoute(const SupportScreen());
              case AppRoutes.dataDeletion:
                return slideRoute(const DataDeletionScreen());
              case AppRoutes.purchaseOrders:
                return slideRoute(const PurchaseOrderListScreen());
              case AppRoutes.createPurchaseOrder:
                return slideRoute(const CreatePurchaseOrderScreen());
              case AppRoutes.purchaseOrderDetail:
                final poId = settings.arguments as String?;
                if (poId == null)
                  return slideRoute(const PurchaseOrderListScreen());
                return slideRoute(PurchaseOrderDetailScreen(orderId: poId));
              case AppRoutes.salesOrders:
                return slideRoute(const SalesOrderListScreen());
              case AppRoutes.createSalesOrder:
                return slideRoute(const CreateSalesOrderScreen());
              case AppRoutes.salesOrderDetail:
                final soId = settings.arguments as String?;
                if (soId == null)
                  return slideRoute(const SalesOrderListScreen());
                return slideRoute(SalesOrderDetailScreen(orderId: soId));
              case AppRoutes.returns:
                return slideRoute(const ReturnsListScreen());
              case AppRoutes.createReturn:
                return slideRoute(const CreateReturnScreen());
              case AppRoutes.returnDetail:
                final retId = settings.arguments as String?;
                if (retId == null) return slideRoute(const ReturnsListScreen());
                return slideRoute(ReturnDetailScreen(returnId: retId));
              case AppRoutes.customers:
                return slideRoute(const CustomerListScreen());
              case AppRoutes.addCustomer:
                return slideRoute(const AddEditCustomerScreen());
              case AppRoutes.editCustomer:
                final customer = settings.arguments as CustomerModel?;
                if (customer == null)
                  return slideRoute(const CustomerListScreen());
                return slideRoute(AddEditCustomerScreen(customer: customer));
              case AppRoutes.customerDetail:
                final customerId = settings.arguments as String?;
                if (customerId == null)
                  return slideRoute(const CustomerListScreen());
                return slideRoute(CustomerDetailScreen(customerId: customerId));
              case AppRoutes.barcodeScanner:
                final scanArgs = settings.arguments;
                final captureOnly =
                    scanArgs is BarcodeScannerArgs && scanArgs.captureOnly;
                return slideRoute(
                  BarcodeScannerScreen(captureOnly: captureOnly),
                );
              case AppRoutes.batches:
                return slideRoute(const BatchListScreen());
              case AppRoutes.addBatch:
                return slideRoute(const AddBatchScreen());
              case AppRoutes.expiryAlerts:
                return slideRoute(const ExpiryAlertsScreen());
              case AppRoutes.reorderSuggestions:
                return slideRoute(const ReorderSuggestionsScreen());
              case AppRoutes.stockForecast:
                return slideRoute(const StockForecastScreen());
              case AppRoutes.stockTakes:
                return slideRoute(const StockTakeListScreen());
              case AppRoutes.createStockTake:
                return slideRoute(const CreateStockTakeScreen());
              case AppRoutes.stockTakeCount:
                final st = settings.arguments as StockTakeModel?;
                if (st == null) return slideRoute(const StockTakeListScreen());
                return slideRoute(StockTakeCountScreen(stockTake: st));
              case AppRoutes.profitLoss:
                return slideRoute(const ProfitLossScreen());
              case AppRoutes.abcAnalysis:
                return slideRoute(const AbcAnalysisScreen());
              case AppRoutes.valuationTrends:
                return slideRoute(const ValuationTrendsScreen());
              case AppRoutes.auditLog:
                return slideRoute(const AuditLogScreen());
              case AppRoutes.notifications:
                return slideRoute(const NotificationsScreen());
              case AppRoutes.globalSearch:
                return slideRoute(const GlobalSearchScreen());
              case AppRoutes.bulkStockIn:
                return slideRoute(const BulkStockInScreen());
              case AppRoutes.bulkEdit:
                return slideRoute(const BulkEditScreen());
              case AppRoutes.onboarding:
                return slideRoute(const OnboardingScreen());
              case AppRoutes.companySwitcher:
                return slideRoute(const CompanySwitcherScreen());
              case AppRoutes.favorites:
                return slideRoute(const FavoritesScreen());
              case AppRoutes.priceHistory:
                return slideRoute(const PriceHistoryScreen());
              case AppRoutes.warehouseZones:
                return slideRoute(const WarehouseZonesScreen());
              case AppRoutes.profile:
                return slideRoute(const ProfileScreen());
              case AppRoutes.about:
                return slideRoute(const AboutScreen());
              case AppRoutes.activityTimeline:
                return slideRoute(const ActivityTimelineScreen());
              case AppRoutes.help:
                return slideRoute(const HelpScreen());
              case AppRoutes.homeCustomization:
                return slideRoute(const HomeCustomizationScreen());
              case AppRoutes.roles:
                return slideRoute(const RoleListScreen());
              case AppRoutes.roleEditor:
                final role = settings.arguments as RoleModel?;
                return slideRoute(RoleEditorScreen(role: role));
              case AppRoutes.invoices:
                return slideRoute(const InvoiceListScreen());
              case AppRoutes.createInvoice:
                final args = settings.arguments;
                if (args is Map<String, dynamic>) {
                  return slideRoute(
                    CreateInvoiceScreen(
                      salesOrderId: args['salesOrderId'] as String?,
                      purchaseOrderId: args['purchaseOrderId'] as String?,
                      initialType:
                          args['type'] as InvoiceType? ?? InvoiceType.sales,
                      preselectedVendorId: args['vendorId'] as String?,
                      preselectedVendorName: args['vendorName'] as String?,
                      preselectedCustomerId: args['customerId'] as String?,
                      preselectedCustomerName: args['customerName'] as String?,
                    ),
                  );
                }
                return slideRoute(
                  CreateInvoiceScreen(
                    salesOrderId: args is String ? args : null,
                  ),
                );
              case AppRoutes.invoiceDetail:
                final invoiceId = settings.arguments as String?;
                if (invoiceId == null)
                  return slideRoute(const InvoiceListScreen());
                return slideRoute(
                  InvoiceDetailRouteEntry(routeArgument: invoiceId),
                );
              case AppRoutes.billingSettings:
                return slideRoute(const BillingSettingsScreen());
              case AppRoutes.billingReports:
                return slideRoute(const BillingReportsScreen());
              case AppRoutes.customerStatement:
                return slideRoute(const CustomerStatementScreen());
              case AppRoutes.vendorStatement:
                return slideRoute(const VendorStatementScreen());
              case AppRoutes.settings:
                final section = settings.arguments as String?;
                return slideRoute(SettingsScreen(initialSection: section));
              default:
                return MaterialPageRoute(builder: (_) => const LandingScreen());
            }
          },
        ),
      ),
    );
  }
}

/// Wrapper that checks if user is logged in and initializes providers
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;
  bool _providersInitializing = false;
  bool _onboardingChecked = false;
  String? _initError;
  String? _providerInitError;
  String? _activeCompanyId;
  /// Last company id that completed [_initializeProviders] successfully; drives rebind vs auth.
  String? _providersBoundCompanyId;
  bool _companyRebindPending = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    if (!kIsWeb) {
      _animController.forward();
    }
    if (kIsWeb) {
      _bootstrapWebFirebase();
    } else {
      _initializeApp();
    }
  }

  /// On web, [main] defers [Firebase.initializeApp] so the first frame can paint
  /// before Firebase completes. [AuthProvider] must not be read until this finishes.
  Future<void> _bootstrapWebFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _initialized = true;
        });
        _scheduleHideHtmlSplash();
      }
      return;
    }
    if (mounted) {
      _initializeApp();
    }
  }

  void _scheduleHideHtmlSplash() {
    if (!kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hideHtmlLoadingSplash();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _initError = null;
      });
      final authProvider = context.read<AuthProvider>();
      await authProvider.initialize();

      if (authProvider.isLoggedIn && authProvider.currentUser != null) {
        if (mounted) {
          await _initializeProviders(authProvider.currentUser!.companyId);
        }
      } else if (authProvider.currentUser == null) {
        // Auth account exists but user doc is missing — sign out gracefully
        await authProvider.logout();
      }

      if (mounted) {
        setState(() {
          _initialized = true;
        });
        _scheduleHideHtmlSplash();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _initialized = true;
        });
        _scheduleHideHtmlSplash();
      }
    }
  }

  void _resetAllProviders() {
    _onboardingChecked = false;
    context.read<SettingsProvider>().reset();
    context.read<CategoryProvider>().reset();
    context.read<StockProvider>().reset();
    context.read<VendorProvider>().reset();
    context.read<ProductProvider>().reset();
    context.read<PurchaseOrderProvider>().reset();
    context.read<SalesOrderProvider>().reset();
    context.read<ReturnProvider>().reset();
    context.read<CustomerProvider>().reset();
    context.read<BatchProvider>().reset();
    context.read<StockTakeProvider>().reset();
    context.read<AuditLogProvider>().reset();
    context.read<NotificationProvider>().reset();
    context.read<PriceHistoryProvider>().reset();
    context.read<WarehouseZoneProvider>().reset();
    context.read<BillingProvider>().reset();
    context.read<BillingSettingsProvider>().reset();
    context.read<RoleProvider>().reset();
    context.read<FavoritesProvider>().reset();
    context.read<HomeCustomizationProvider>().reset();
    _providersInitializing = false;
  }

  Future<void> _initializeProviders(String companyId) async {
    if (_providersInitializing) return;
    _providersInitializing = true;
    if (mounted) setState(() => _providerInitError = null);
    try {
      final catProvider = context.read<CategoryProvider>();
      final stockProvider = context.read<StockProvider>();
      final vendorProvider = context.read<VendorProvider>();
      final settingsProvider = context.read<SettingsProvider>();
      final productProvider = context.read<ProductProvider>();

      catProvider.initialize(companyId: companyId);
      stockProvider.initialize(companyId: companyId);
      vendorProvider.initialize(companyId: companyId);
      context.read<PurchaseOrderProvider>().initialize(companyId: companyId);
      context.read<SalesOrderProvider>().initialize(companyId: companyId);
      context.read<ReturnProvider>().initialize(companyId: companyId);
      context.read<CustomerProvider>().initialize(companyId: companyId);
      context.read<BatchProvider>().initialize(companyId: companyId);
      context.read<StockTakeProvider>().initialize(companyId: companyId);
      context.read<AuditLogProvider>().initialize(companyId: companyId);
      context.read<NotificationProvider>().initialize(companyId: companyId);
      context.read<PriceHistoryProvider>().initialize(companyId: companyId);
      context.read<WarehouseZoneProvider>().initialize(companyId: companyId);
      context.read<BillingProvider>().initialize(companyId: companyId);
      context.read<BillingSettingsProvider>().initialize(companyId);
      context.read<RoleProvider>().initialize(companyId: companyId);

      // Attach RoleProvider to AuthProvider for permission resolution
      final authProvider = context.read<AuthProvider>();
      final roleProvider = context.read<RoleProvider>();
      authProvider.attachRoleProvider(roleProvider);

      // Ensure RBAC roles exist and legacy users are migrated
      await authProvider.ensureRbacReady();

      // Settings must load before products for location/company/sub-category lists.
      await settingsProvider
          .initialize(companyId)
          .timeout(const Duration(seconds: 15), onTimeout: () {});

      if (!mounted) return;

      // ProductProvider.initialize loads a first page then starts analytics
      // in the background. Don't let a slow first-page fetch block the whole
      // app — the home screen handles partial/empty data gracefully.
      await productProvider
          .initialize(companyId: companyId)
          .timeout(const Duration(seconds: 20), onTimeout: () {});

      if (mounted) {
        await context
            .read<HomeCustomizationProvider>()
            .setCompanyId(companyId);
      }
      if (mounted) {
        setState(() {
          _providersBoundCompanyId = companyId;
          _activeCompanyId = companyId;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _providerInitError = friendlyError(
            e,
            fallback: 'Could not load data. Please try again.',
          ),
        );
      }
    } finally {
      _providersInitializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      if (kIsWeb) {
        return const Scaffold(
          backgroundColor: Color(0xFF00897B),
          body: SizedBox.expand(),
        );
      }
      return Scaffold(
        body: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('logo.png', width: 100, height: 100),
                  const SizedBox(height: 20),
                  const Text(
                    'SmartShelfKart',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Simple Inventory Management',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: AppTheme.dangerColor,
                ),
                const SizedBox(height: 20),
                Text(
                  'Connection Error',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPri(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not connect to the server.\nPlease check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textTer(context),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _initialized = false;
                      _initError = null;
                    });
                    if (kIsWeb && Firebase.apps.isEmpty) {
                      _bootstrapWebFirebase();
                    } else {
                      _initializeApp();
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isLoggedIn) {
      final currentCompanyId = authProvider.currentUser!.companyId;
      final settings = context.read<SettingsProvider>();

      final needsRebind = _providersBoundCompanyId != currentCompanyId;

      if (needsRebind) {
        if (_providerInitError != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 64,
                      color: AppTheme.dangerColor,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Could Not Load Data',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPri(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _providerInitError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textTer(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _providerInitError = null);
                        _initializeProviders(currentCompanyId).catchError((e) {
                          if (mounted) {
                            setState(
                              () => _providerInitError = friendlyError(
                                e,
                                fallback: 'Could not load data.',
                              ),
                            );
                          }
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!_companyRebindPending) {
          _companyRebindPending = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            _resetAllProviders();
            try {
              await _initializeProviders(currentCompanyId);
            } finally {
              if (mounted) {
                setState(() {
                  _companyRebindPending = false;
                });
              }
            }
          });
        }

        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('logo.png', width: 100, height: 100),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      _activeCompanyId = currentCompanyId;

      if (!_onboardingChecked) {
        _onboardingChecked = true;
        final categories = context.read<CategoryProvider>().categories;
        if (settings.locations.isEmpty && categories.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final prefs = await SharedPreferences.getInstance();
            final key = 'onboarding_completed_$currentCompanyId';
            if (prefs.getBool(key) != true) {
              if (mounted) {
                Navigator.pushNamed(context, AppRoutes.onboarding);
              }
            }
          });
        }
      }

      return const HomeScreen();
    } else {
      if (_providersBoundCompanyId != null || _activeCompanyId != null) {
        _providersBoundCompanyId = null;
        _activeCompanyId = null;
        _providerInitError = null;
        _onboardingChecked = false;
        _providersInitializing = false;
        _companyRebindPending = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resetAllProviders();
        });
      }
      return const LandingScreen();
    }
  }
}
