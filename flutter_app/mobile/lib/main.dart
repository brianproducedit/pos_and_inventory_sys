import 'package:flutter/material.dart';
import 'package:mobile/providers/user_management_provider.dart';
import 'package:mobile/screens/audit_logs_screen.dart';
import 'package:mobile/services/time_service.dart';
import 'package:provider/provider.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/database_service.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/pos_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';
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
import 'package:mobile/theme/tokens.dart';
import 'db/app_database.dart';
import 'ui/sync_demo.dart';
import 'dart:async';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
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
    // Ensure timezone database is initialized with Zimbabwe default
    try {
      await TimeService.instance.initialize();
      debugPrint('TimeService initialized to Africa/Harare');
    } catch (e) {
      debugPrint('TimeService initialization failed: $e');
    }

    // Initialize background work (Android only)
    try {
      if (Platform.isAndroid) {
        // Use centralized registration helper for testability
        registerBackgroundWork(Workmanager());
      }
    } catch (e) {
      debugPrint('WorkManager initialization failed: $e');
    }

    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint(stack.toString());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => StoreProvider()),
        ChangeNotifierProvider(create: (_) => UserManagementProvider()),
        ChangeNotifierProvider(create: (_) => AuditProvider()),
        ChangeNotifierProxyProvider<AuthProvider, SettingsProvider>(
          create: (context) =>
              SettingsProvider(authProvider: context.read<AuthProvider>()),
          update: (context, authProvider, previous) =>
              SettingsProvider(authProvider: authProvider),
        ),
        ChangeNotifierProxyProvider<AuthProvider, UserProfileProvider>(
          create: (context) =>
              UserProfileProvider(authProvider: context.read<AuthProvider>()),
          update: (context, authProvider, previous) =>
              UserProfileProvider(authProvider: authProvider),
        ),
        Provider(create: (_) => AuthService()),
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => AppDatabase()),
      ],
      child: MaterialApp(
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
          '/sales_history': (context) => const SalesHistoryScreen(),
          '/store_management': (context) => const StoreManagementScreen(),
          '/admin_management': (context) => const AdminManagementScreen(),
          '/cashier_management': (context) => const CashierManagementScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/user_settings': (context) => const UserSettingsScreen(),
          '/store_settings': (context) => const StoreSettingsScreen(),
          '/system_settings': (context) => const SystemSettingsScreen(),
          '/user_profile': (context) => const UserProfileScreen(),
          '/audit_logs': (context) => const AuditLogsScreen(),
          '/sync_demo': (context) => const SyncDemoScreen(),
          // Dev preview routes
          // '/components_demo': (context) => const ComponentsDemoScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/edit_product') {
            final product = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => EditProductScreen(product: product),
            );
          }
          if (settings.name == '/receipt') {
            final saleId = settings.arguments as int;
            return MaterialPageRoute(
              builder: (context) => ReceiptScreen(saleId: saleId),
            );
          }
          return null;
        },
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
  @override
  void initState() {
    super.initState();
    // Initialize store provider when user is authenticated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        final storeProvider =
            Provider.of<StoreProvider>(context, listen: false);
        storeProvider.initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    return authProvider.isAuthenticated
        ? const HomeScreen()
        : const LoginScreenRedesign();
  }
}
