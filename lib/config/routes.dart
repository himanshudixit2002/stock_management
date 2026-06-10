import '../models/stock_hold_model.dart';

/// Optional arguments for [AppRoutes.barcodeScanner].
class BarcodeScannerArgs {
  const BarcodeScannerArgs({this.captureOnly = false});

  /// When true, first successful scan (or manual entry on web) pops the route
  /// with the code as the result instead of searching the catalog.
  final bool captureOnly;
}

/// Arguments to deep-link a specific hold into the Stock Out or Release screen
/// (e.g. tapping Despatch/Unhold from the hold dashboard).
class HoldActionArgs {
  const HoldActionArgs({required this.hold});

  final StockHoldModel hold;
}

class AppRoutes {
  static const String landing = '/landing';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String productList = '/products';
  static const String addProduct = '/products/add';
  static const String editProduct = '/products/edit';
  static const String productDetail = '/products/detail';
  static const String categories = '/categories';
  static const String stockIn = '/stock/in';
  static const String stockOut = '/stock/out';
  static const String stockTransfer = '/stock/transfer';
  static const String damageReport = '/stock/damage';
  static const String lowStock = '/stock/low';
  static const String stockAdjustment = '/stock/adjustment';
  static const String stockHold = '/stock/hold';
  static const String stockRelease = '/stock/release';
  static const String stockHolds = '/stock/holds';
  static const String transactionHistory = '/transactions';
  static const String excelImport = '/excel/import';
  static const String excelExport = '/excel/export';
  static const String userManagement = '/users';
  static const String staffPermissions = '/settings/permissions';
  static const String reports = '/reports';
  static const String vendors = '/vendors';
  static const String addVendor = '/vendors/add';
  static const String editVendor = '/vendors/edit';
  static const String vendorDetail = '/vendors/detail';
  static const String settings = '/settings';
  static const String dashboard = '/dashboard';
  static const String damageHistory = '/reports/damage';
  static const String excelUpdate = '/excel/update';
  static const String privacyPolicy = '/legal/privacy';
  static const String terms = '/legal/terms';
  static const String support = '/legal/support';
  static const String dataDeletion = '/legal/data-deletion';
  static const String purchaseOrders = '/orders/purchase';
  static const String createPurchaseOrder = '/orders/purchase/create';
  static const String purchaseOrderDetail = '/orders/purchase/detail';
  static const String salesOrders = '/orders/sales';
  static const String createSalesOrder = '/orders/sales/create';
  static const String salesOrderDetail = '/orders/sales/detail';
  static const String returns = '/returns';
  static const String createReturn = '/returns/create';
  static const String returnDetail = '/returns/detail';
  static const String customers = '/customers';
  static const String addCustomer = '/customers/add';
  static const String editCustomer = '/customers/edit';
  static const String customerDetail = '/customers/detail';
  static const String barcodeScanner = '/scanner';
  static const String batches = '/batches';
  static const String addBatch = '/batches/add';
  static const String expiryAlerts = '/batches/expiry';
  static const String reorderSuggestions = '/reorder-suggestions';
  static const String stockForecast = '/forecast';
  static const String stockTakes = '/stock-take';
  static const String createStockTake = '/stock-take/create';
  static const String stockTakeCount = '/stock-take/count';
  static const String profitLoss = '/reports/pnl';
  static const String abcAnalysis = '/reports/abc';
  static const String valuationTrends = '/reports/valuation';
  static const String auditLog = '/audit-log';
  static const String globalSearch = '/search';
  static const String bulkStockIn = '/bulk/stock-in';
  static const String bulkEdit = '/bulk/edit';
  static const String notifications = '/notifications';
  static const String onboarding = '/onboarding';
  static const String companySwitcher = '/company-switcher';
  static const String favorites = '/favorites';
  static const String priceHistory = '/price-history';
  static const String warehouseZones = '/warehouse-zones';
  static const String profile = '/profile';
  static const String about = '/about';
  static const String activityTimeline = '/activity-timeline';
  static const String help = '/help';
  static const String homeCustomization = '/settings/home-customization';
  static const String roles = '/roles';
  static const String roleEditor = '/roles/editor';
  static const String invoices = '/billing/invoices';
  static const String createInvoice = '/billing/invoices/create';
  static const String invoiceDetail = '/billing/invoices/detail';
  static const String billingSettings = '/billing/settings';
  static const String billingReports = '/billing/reports';
  static const String customerStatement = '/billing/customer-statement';
  static const String vendorStatement = '/billing/vendor-statement';
  static const String fastPos = '/pos/fast';
}
