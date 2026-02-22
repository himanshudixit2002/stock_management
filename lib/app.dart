import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
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
import 'screens/excel/excel_import_screen.dart';
import 'screens/excel/excel_export_screen.dart';
import 'screens/users/user_management_screen.dart';
import 'screens/users/staff_permissions_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/vendors/vendor_list_screen.dart';
import 'models/product_model.dart';

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
        title: 'Stock Manager',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const AuthWrapper(),
        onGenerateRoute: (settings) {
          PageRouteBuilder slideRoute(Widget page) {
            return PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => page,
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 280),
            );
          }

          switch (settings.name) {
            case '/landing':
              return MaterialPageRoute(
                builder: (_) => const LandingScreen(),
              );
            case '/login':
              return MaterialPageRoute(
                builder: (_) => const LoginScreen(),
              );
            case '/register':
              return MaterialPageRoute(
                builder: (_) => const RegisterScreen(),
              );
            case '/home':
              return MaterialPageRoute(
                builder: (_) => const HomeScreen(),
              );
            case '/products':
              return slideRoute(const ProductListScreen());
            case '/products/add':
              return slideRoute(const AddEditProductScreen());
            case '/products/edit':
              final product = settings.arguments as ProductModel;
              return slideRoute(AddEditProductScreen(product: product));
            case '/products/detail':
              final product = settings.arguments as ProductModel;
              return slideRoute(ProductDetailScreen(product: product));
            case '/categories':
              return slideRoute(const CategoryScreen());
            case '/stock/in':
              final product = settings.arguments as ProductModel?;
              return slideRoute(StockInScreen(product: product));
            case '/stock/out':
              final product = settings.arguments as ProductModel?;
              return slideRoute(StockOutScreen(product: product));
            case '/stock/damage':
              final product = settings.arguments as ProductModel?;
              return slideRoute(DamageReportScreen(product: product));
            case '/stock/transfer':
              final product = settings.arguments as ProductModel?;
              return slideRoute(StockTransferScreen(product: product));
            case '/excel/import':
              return slideRoute(const ExcelImportScreen());
            case '/excel/export':
              return slideRoute(const ExcelExportScreen());
            case '/users':
              return slideRoute(const UserManagementScreen());
            case '/settings/permissions':
              return slideRoute(const StaffPermissionsScreen());
            case '/reports':
              return slideRoute(const ReportsScreen());
            case '/vendors':
              return slideRoute(const VendorListScreen());
            default:
              return MaterialPageRoute(
                builder: (_) => const LandingScreen(),
              );
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
  String? _initError;
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
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
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
          final companyId = authProvider.currentUser!.companyId;
          context.read<ProductProvider>().initialize(companyId: companyId);
          context.read<CategoryProvider>().initialize(companyId: companyId);
          context.read<StockProvider>().initialize(companyId: companyId);
          context.read<VendorProvider>().initialize(companyId: companyId);
          await context.read<SettingsProvider>().initialize(companyId);
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
                    'Stock Manager',
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
                const Icon(Icons.cloud_off_rounded, size: 64, color: AppTheme.dangerColor),
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
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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
      return const HomeScreen();
    } else {
      return const LandingScreen();
    }
  }
}
