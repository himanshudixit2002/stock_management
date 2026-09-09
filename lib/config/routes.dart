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
  static const String stockLedger = '/reports/stock-ledger';
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
  static const String dataHealth = '/settings/data-health';
  static const String planFeatures = '/settings/plan';

  // Settings sub-pages. The Settings tab is a hub of category rows; each of
  // these is one focused page behind it. Every one accepts an optional String
  // anchor as its route argument so a settings search hit can scroll to and
  // flash the group it named.
  static const String notificationSettings = '/settings/notifications';
  static const String settingsAppearance = '/settings/appearance';
  static const String settingsFeatures = '/settings/features';
  static const String settingsCatalog = '/settings/catalog';
  static const String settingsTeam = '/settings/team';
  static const String settingsData = '/settings/data';
  static const String settingsHelp = '/settings/help';
  static const String superAdmin = '/super-admin';
  static const String superAdminCompany = '/super-admin/company';
  static const String roles = '/roles';
  static const String roleEditor = '/roles/editor';
  static const String invoices = '/billing/invoices';
  static const String createInvoice = '/billing/invoices/create';
  static const String invoiceDetail = '/billing/invoices/detail';
  static const String billingSettings = '/billing/settings';
  static const String billingReports = '/billing/reports';
  static const String paymentsLedger = '/billing/payments';
  static const String creditNote = '/billing/credit-note';
  static const String aging = '/reports/aging';
  static const String customerStatement = '/billing/customer-statement';
  static const String vendorStatement = '/billing/vendor-statement';
  static const String fastPos = '/pos/fast';

  // Manufacturing & assembly
  static const String boms = '/manufacturing/boms';
  static const String bomEditor = '/manufacturing/boms/edit';

  // Serialised units
  static const String serials = '/serials';

  // Transfer orders (multi-step, with in-transit stock)
  static const String transferOrders = '/transfers';
  static const String createTransferOrder = '/transfers/create';
  static const String transferOrderDetail = '/transfers/detail';

  // Purchase requisitions
  static const String requisitions = '/requisitions';
  static const String createRequisition = '/requisitions/create';
  static const String requisitionDetail = '/requisitions/detail';

  // Reports added alongside the existing set
  static const String taxSummary = '/reports/tax';
  static const String deadStock = '/reports/dead-stock';

  // Billing schedules
  static const String recurringInvoices = '/billing/recurring';
  static const String recurringInvoiceEditor = '/billing/recurring/edit';

  // Customer pricing
  static const String priceLists = '/pricing/lists';
  static const String priceListEditor = '/pricing/lists/edit';

  // Label printing
  static const String labelPrint = '/labels';

  // Landed costs
  static const String landedCosts = '/landed-costs';
  static const String landedCostEditor = '/landed-costs/edit';

  // Quotations (the offer before the order)
  static const String quotations = '/quotations';
  static const String quotationEditor = '/quotations/edit';
  static const String quotationDetail = '/quotations/detail';

  // Pick, pack and ship
  static const String shipments = '/shipments';
  static const String createShipment = '/shipments/create';
  static const String shipmentDetail = '/shipments/detail';

  // Operating expenses
  static const String expenses = '/expenses';
  static const String expenseEditor = '/expenses/edit';

  // Till shifts
  static const String registerSessions = '/pos/registers';
  static const String registerSessionDetail = '/pos/registers/detail';

  // Customer credit
  static const String creditControl = '/credit-control';

  // Supplier performance
  static const String vendorScorecard = '/reports/vendor-scorecard';

  // Sales commissions
  static const String commissionPlans = '/commissions/plans';
  static const String commissionPlanEditor = '/commissions/plans/edit';
  static const String commissionStatement = '/commissions/statement';

  // Budgets and variance
  static const String budgets = '/budgets';
  static const String budgetEditor = '/budgets/edit';
  static const String budgetDetail = '/budgets/detail';

  // Warranty and repairs
  static const String serviceJobs = '/service-jobs';
  static const String createServiceJob = '/service-jobs/create';
  static const String serviceJobDetail = '/service-jobs/detail';

  // Subcontracting
  static const String jobWork = '/job-work';
  static const String createJobWork = '/job-work/create';
  static const String jobWorkDetail = '/job-work/detail';
}
