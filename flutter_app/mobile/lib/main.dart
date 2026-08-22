import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart';
import 'package:mobile/providers/sync_provider.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/providers/data_protection_provider.dart';
import 'package:mobile/screens/audit_logs_screen.dart';
import 'package:mobile/services/time_service.dart';
import 'package:mobile/services/data_protection_service.dart';
import 'package:mobile/services/app_lifecycle_observer.dart';
import 'package:mobile/services/connectivity_monitor.dart';
import 'package:mobile/utils/smooth_page_route.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as fr;
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/inventory_provider_v2.dart';
import 'package:mobile/providers/pos_provider_v2.dart';
import 'package:mobile/providers/analytics_provider.dart';
import 'package:mobile/providers/receipts_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/settings_provider.dart';
import 'package:mobile/providers/user_profile_provider.dart';
import 'package:mobile/providers/audit_provider.dart';
import 'package:mobile/screens/cashier_management_screen.dart';
import 'package:mobile/screens/admin_management_screen.dart';
import 'package:mobile/screens/analytics_screen.dart';
import 'package:mobile/screens/analytics_events_dashboard_screen.dart';
import 'package:mobile/screens/login_screen_redesign.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/inventory_screen.dart';
import 'package:mobile/screens/pos_screen.dart';
import 'package:mobile/screens/add_product_screen.dart';
import 'package:mobile/screens/edit_product_screen.dart';
import 'package:mobile/screens/receipt_screen.dart';
import 'package:mobile/screens/sales_history_screen.dart';
import 'package:mobile/screens/store_management_screen.dart';
import 'package:mobile/screens/settings_screen.dart';
import 'package:mobile/screens/store_settings_screen.dart';
import 'package:mobile/screens/user_settings_screen.dart';
import 'package:mobile/screens/system_settings_screen.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import 'package:mobile/screens/data_protection_screen.dart';
import 'package:mobile/theme/tokens.dart';
import 'db/app_database.dart';
import 'data/remote/postgres_api_service.dart';
import 'data/remote/api_client.dart';
// V2 Offline-First Repositories
import 'data/repositories/product_repository_v2.dart' as v2;
import 'data/repositories/store_repository_v2.dart' as v2;
import 'data/repositories/user_repository_v2.dart' as v2;
import 'data/repositories/sale_repository_v2.dart' as v2;
import 'data/repositories/inventory_repository_v2.dart' as v2;
import 'data/repositories/settings_repository_v2.dart' as v2;
import 'data/repositories/analytics_repository_v2.dart' as v2;
import 'ui/admin/sync_errors_screen.dart';
import 'dart:async';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'config/demo_config.dart';
import 'data/demo/demo_seed.dart';
import 'sync/sync_background.dart';

void main() {
  // Capture Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Print to console for easier debugging
    debugPrint('FlutterError caught: ${details.exceptionAsString()}');
    if (details.stack != null) debugPrint(details.stack.toString());
  };

  // Capture uncaught asynchronous errors
  runZonedGuarded(() async {
    // Ensure Flutter bindings are initialized in the same zone as runApp
    WidgetsFlutterBinding.ensureInitialized();

    // Configure Drift runtime options
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    // Initialize data protection service FIRST (before any database operations)
    final dataProtectionService = DataProtectionService();
    try {
      await dataProtectionService.initialize();
      debugPrint('🛡️ DataProtectionService initialized');
    } catch (e) {
      debugPrint('⚠️ DataProtectionService initialization failed: $e');
    }

    // Ensure timezone database is initialized with Zimbabwe default
    try {
      await TimeService.instance.initialize();
      debugPrint('TimeService initialized to Africa/Harare');
    } catch (e) {
      debugPrint('TimeService initialization failed: $e');
    }

    // Initialize background work (Android only, skip in demo mode)
    try {
      if (Platform.isAndroid && !DemoConfig.isDemoMode) {
        // Use centralized registration helper for testability
        // Use a shorter frequency and debug mode when running in debug builds
        const freq = kDebugMode ? Duration(minutes: 15) : Duration(hours: 6);
        registerBackgroundWork(Workmanager(),
            frequency: freq, isInDebugMode: kDebugMode);
      }
    } catch (e) {
      debugPrint('WorkManager initialization failed: $e');
    }

    // Initialize connectivity monitoring for offline-first functionality
    try {
      await ConnectivityMonitor().initialize();
      debugPrint('📡 ConnectivityMonitor initialized');
    } catch (e) {
      debugPrint('⚠️ ConnectivityMonitor initialization failed: $e');
    }

    // Create the AppDatabase singleton and seed demo data if enabled
    final db = AppDatabase();
    if (DemoConfig.isDemoMode) {
      try {
        await DemoSeeder.seed(db);
      } catch (e) {
        debugPrint('⚠️ DemoSeeder failed: $e');
      }
    }

    runApp(MyApp(
      dataProtectionService: dataProtectionService,
      database: db,
    ));
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint(stack.toString());
  });
}

class MyApp extends StatelessWidget {
  final DataProtectionService dataProtectionService;
  final AppDatabase database;

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const MyApp({
    super.key, 
    required this.dataProtectionService,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    return fr.ProviderScope(
      child: MultiProvider(
        providers: [
          // Data Protection Service (passed from main)
          Provider<DataProtectionService>.value(value: dataProtectionService),

          // Data Protection Provider for UI state management
          ChangeNotifierProvider(
            create: (context) => DataProtectionProvider(
              dataProtectionService: context.read<DataProtectionService>(),
            ),
          ),

          // Core services & repositories (must be created before providers that depend on them)
          Provider(create: (_) => AuthService()),
          // Database provided from main()
          Provider<AppDatabase>.value(value: database),
          // API services
          Provider(create: (_) => PostgresApiService()),
          Provider(create: (_) => ApiClient()),

          // AuthProvider with required dependencies
          ChangeNotifierProvider(
              create: (context) => AuthProvider(
                    db: context.read<AppDatabase>(),
                    apiClient: context.read<ApiClient>(),
                  )),

          // V2 Offline-First Repositories (use Drift database)
          Provider<v2.ProductRepository>(
              create: (context) =>
                  v2.ProductRepository(context.read<AppDatabase>())),
          Provider<v2.StoreRepository>(
              create: (context) =>
                  v2.StoreRepository(context.read<AppDatabase>())),
          Provider<v2.UserRepository>(
              create: (context) =>
                  v2.UserRepository(db: context.read<AppDatabase>())),
          Provider<v2.SaleRepository>(
              create: (context) =>
                  v2.SaleRepository(context.read<AppDatabase>())),
          Provider<v2.InventoryRepository>(
              create: (context) =>
                  v2.InventoryRepository(db: context.read<AppDatabase>())),
          Provider<v2.SettingsRepository>(
              create: (context) =>
                  v2.SettingsRepository(db: context.read<AppDatabase>())),
          Provider<v2.AnalyticsRepository>(
              create: (context) =>
                  v2.AnalyticsRepository(context.read<AppDatabase>())),

          // SyncProvider must be created before providers that depend on it
          // lazy: false ensures it initializes immediately on app start
          ChangeNotifierProvider(
            create: (_) => SyncProvider(),
            lazy: false,
          ),

          // V2 UI-level providers (offline-first with Drift)
          ChangeNotifierProvider<InventoryProviderV2>(
            create: (context) => InventoryProviderV2(
              context.read<v2.ProductRepository>(),
            ),
          ),
          ChangeNotifierProvider<PosProviderV2>(
            create: (context) => PosProviderV2(
              context.read<v2.ProductRepository>(),
              context.read<v2.SaleRepository>(),
            ),
          ),

          ChangeNotifierProvider(
            create: (context) => AnalyticsProvider(
              analyticsRepository: context.read<v2.AnalyticsRepository>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (context) => ReceiptsProvider(
              saleRepository: context.read<v2.SaleRepository>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (context) => StoreProvider(
              storeRepository: context.read<v2.StoreRepository>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (context) => UserManagementProvider(
              userRepository: context.read<v2.UserRepository>(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => AuditProvider()),
          ChangeNotifierProvider(
            create: (context) => SettingsProvider(
              settingsRepository: context.read<v2.SettingsRepository>(),
            ),
          ),
          ChangeNotifierProxyProvider<AuthProvider, UserProfileProvider>(
            create: (context) =>
                UserProfileProvider(authProvider: context.read<AuthProvider>()),
            update: (context, authProvider, previous) =>
                UserProfileProvider(authProvider: authProvider),
          ),
        ],
        builder: (context, child) {
          // Wrap the entire app with a custom builder to support UI-wide features
          Widget app = Stack(
            children: [
              if (child != null) child,
              // Future: Add global toast overlays or network status indicators here
            ],
          );
          
          if (DemoConfig.isDemoMode) {
            app = Directionality(
              textDirection: TextDirection.ltr,
              child: Banner(
                message: 'DEMO',
                location: BannerLocation.topEnd,
                color: Colors.orange,
                child: app,
              ),
            );
          }
          
          return app;
        },
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'POS & Inventory',
          theme: buildLightTheme(),
          debugShowCheckedModeBanner: false,
          home: const AuthWrapper(),
          routes: {
            '/login': (context) => const LoginScreenRedesign(),
            '/login_redesign': (context) => const LoginScreenRedesign(),
            '/home': (context) => const HomeScreen(),
            '/inventory': (context) => const InventoryScreen(),
            '/pos': (context) => const PosScreen(),
            '/analytics': (context) => const AnalyticsScreen(),
            '/analytics/events': (context) =>
                const AnalyticsEventsDashboardScreen(),
            '/add_product': (context) => const AddProductScreen(),
            '/sales_history': (context) => SalesHistoryScreen(
                  saleRepository: context.read<v2.SaleRepository>(),
                ),
            '/store_management': (context) => const StoreManagementScreen(),
            '/admin_management': (context) => const AdminManagementScreen(),
            '/cashier_management': (context) => const CashierManagementScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/user_settings': (context) => const UserSettingsScreen(),
            '/store_settings': (context) => const StoreSettingsScreen(),
            '/system_settings': (context) => const SystemSettingsScreen(),
            '/user_profile': (context) => const UserProfileScreen(),
            '/audit_logs': (context) => const AuditLogsScreen(),
            '/data_protection': (context) => const DataProtectionScreen(),
            '/admin/sync-errors': (context) => const SyncErrorsScreen(),
            // Dev preview routes
            // '/components_demo': (context) => const ComponentsDemoScreen(),
          },
          onGenerateRoute: (settings) {
            final context = navigatorKey.currentContext;
            if (context == null) return null;

            if (settings.name == '/edit_product') {
              final product = settings.arguments as Map<String, dynamic>;
              return SmoothPageRoute(
                page: EditProductScreen(product: product),
              );
            }
            if (settings.name == '/receipt') {
              final saleId = settings.arguments as int;
              return SmoothPageRoute(
                page: ReceiptScreen(
                  saleId: saleId,
                  saleRepository: context.read<v2.SaleRepository>(),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    // Initialize store provider when user is authenticated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final storeProvider = Provider.of<StoreProvider>(context, listen: false);
      final userManagementProvider =
          Provider.of<UserManagementProvider>(context, listen: false);

      // Set auth provider in dependent providers for proper filtering
      storeProvider.setAuthProvider(authProvider);
      userManagementProvider.setAuthProvider(authProvider);

      if (authProvider.isAuthenticated) {
        storeProvider.initialize();
      }

      // Initialize data protection provider
      final dataProtectionProvider =
          Provider.of<DataProtectionProvider>(context, listen: false);
      dataProtectionProvider.initialize();

      // Start app lifecycle observer for data protection
      final dataProtectionService =
          Provider.of<DataProtectionService>(context, listen: false);
      _lifecycleObserver = AppLifecycleObserver(dataProtectionService);
      _lifecycleObserver.startObserving();
    });
  }

  @override
  void dispose() {
    _lifecycleObserver.stopObserving();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    return authProvider.isAuthenticated
        ? const HomeScreen()
        : const LoginScreenRedesign();
  }
}
