import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'utils/error_helpers.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/category_provider.dart';
import 'providers/stock_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vendor_provider.dart';
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
import 'models/product_model.dart';
import 'models/vendor_model.dart';

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
      ],
      child: MaterialApp(
        title: 'Smart Inventory',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
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
              return MaterialPageRoute(builder: (_) => const RegisterScreen());
            case AppRoutes.home:
              return MaterialPageRoute(builder: (_) => const HomeScreen());
            case AppRoutes.productList:
              return slideRoute(const ProductListScreen());
            case AppRoutes.addProduct:
              return slideRoute(const AddEditProductScreen());
            case AppRoutes.editProduct:
              final product = settings.arguments as ProductModel?;
              if (product == null) return slideRoute(const ProductListScreen());
              return slideRoute(AddEditProductScreen(product: product));
            case AppRoutes.productDetail:
              final product = settings.arguments as ProductModel?;
              if (product == null) return slideRoute(const ProductListScreen());
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
            default:
              return MaterialPageRoute(builder: (_) => const LandingScreen());
          }
        },
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
  String? _initError;
  String? _providerInitError;
  String? _activeCompanyId;
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
    _animController.forward();
    _initializeApp();
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
          _activeCompanyId = authProvider.currentUser!.companyId;
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _initialized = true;
        });
      }
    }
  }

  void _resetAllProviders() {
    context.read<SettingsProvider>().reset();
    context.read<CategoryProvider>().reset();
    context.read<StockProvider>().reset();
    context.read<VendorProvider>().reset();
    context.read<ProductProvider>().reset();
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

      // Settings must load before products for location/company/size lists.
      await settingsProvider.initialize(companyId).timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );

      if (!mounted) return;

      // ProductProvider.initialize loads a first page then starts analytics
      // in the background. Don't let a slow first-page fetch block the whole
      // app — the home screen handles partial/empty data gracefully.
      await productProvider.initialize(
        companyId: companyId,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
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
                    'Smart Inventory',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Simple Inventory Management',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
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
                const Text(
                  'Connection Error',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not connect to the server.\nPlease check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _initialized = false;
                      _initError = null;
                    });
                    _initializeApp();
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
      final settings = context.watch<SettingsProvider>();

      final companyChanged = _activeCompanyId != null &&
          _activeCompanyId != currentCompanyId;
      final needsInit = !settings.isInitialized || companyChanged;

      if (needsInit) {
        if (companyChanged) {
          _resetAllProviders();
        }
        _activeCompanyId = currentCompanyId;
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
                    const Text(
                      'Could Not Load Data',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _providerInitError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textTertiary,
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
      return const HomeScreen();
    } else {
      if (_activeCompanyId != null) {
        _resetAllProviders();
        _activeCompanyId = null;
      }
      return const LandingScreen();
    }
  }
}
