import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/routes.dart';
import 'config/router.dart' as app_router;
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
import 'providers/connectivity_provider.dart';
import 'screens/landing_screen.dart';
import 'screens/home_screen.dart';
import 'firebase_options.dart';
import 'utils/html_splash.dart';

/// App-wide scroll behavior tuned for a soft, "cloudy" feel that is identical
/// on every platform: iOS-style bouncy overscroll everywhere (mobile, web and
/// desktop), drag support for all pointer kinds, and no Android glow (the
/// bounce already conveys the edge, so the glow would feel inconsistent).
class SoftScrollBehavior extends MaterialScrollBehavior {
  const SoftScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
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
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) => MaterialApp(
          title: 'SmartShelfKart',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          scrollBehavior: const SoftScrollBehavior(),
          debugShowCheckedModeBanner: false,
          home: const AuthWrapper(),
          onGenerateRoute: (settings) =>
              app_router.onGenerateRoute(settings, context),
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
      // Keep the HTML splash visible until [_initialized] — hiding it on the
      // first frame exposed a duplicate Flutter loading screen underneath.
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
          if (kIsWeb) {
            // On web, show the app shell immediately. Provider data loads in
            // the background -- home screen already handles partial/empty data.
            setState(() => _initialized = true);
            _scheduleHideHtmlSplash();
            await _initializeProviders(authProvider.currentUser!.companyId);
          } else {
            await _initializeProviders(authProvider.currentUser!.companyId);
          }
        }
      } else if (authProvider.currentUser == null) {
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

      await settingsProvider
          .initialize(companyId)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              settingsProvider.setWarning(
                'Settings loaded slowly — some data may be stale.',
              );
            },
          );

      if (!mounted) return;

      await productProvider
          .initialize(companyId: companyId)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              productProvider.setWarning(
                'Products loaded slowly — pull to refresh for latest data.',
              );
            },
          );

      if (mounted) {
        await context.read<HomeCustomizationProvider>().setCompanyId(companyId);
      }
      if (mounted) {
        final uid = context.read<AuthProvider>().currentUser?.uid ?? '';
        await context.read<FavoritesProvider>().initialize(
          companyId: companyId,
          uid: uid,
        );
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
        // Matches [web/index.html] body gradient so the handoff is invisible
        // once the HTML overlay is removed (no second branded loading page).
        return const Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.85, -1),
                end: Alignment(0.85, 1),
                colors: [
                  Color(0xFF00695C),
                  Color(0xFF00897B),
                  Color(0xFF26A69A),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
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
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Lottie.asset('assets/lottie/lottie_logo.json'),
                  ),
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
      if (authProvider.sessionExpired) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          authProvider.clearSessionExpired();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your session has expired. Please sign in again.'),
              duration: Duration(seconds: 4),
            ),
          );
        });
      }
      return const LandingScreen();
    }
  }
}
