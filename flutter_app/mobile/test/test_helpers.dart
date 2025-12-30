import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_common/sqflite.dart' as sqflite_common;

import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/providers/inventory_provider.dart';
import 'package:mobile/providers/analytics_provider.dart';

/// Simple test Auth provider that reports a role and authenticated = true
class TestAuthProvider extends AuthProvider {
  final String roleValue;
  TestAuthProvider({this.roleValue = 'superadmin'});

  @override
  bool get isAuthenticated => true;

  @override
  String? get role => roleValue;
}

/// Minimal no-op providers used for widget tests to avoid provider not found
class TestStoreProvider extends StoreProvider {
  TestStoreProvider() : super();

  // Override initialization to avoid background network calls during tests
  @override
  Future<void> initialize() async {
    // Do not call super.initialize() which triggers backend fetches
    debugPrint('TestStoreProvider.initialize: no-op for tests');
    return;
  }

  @override
  Future<void> loadMyStores() async {
    // Provide a deterministic empty set for tests
    debugPrint('TestStoreProvider.loadMyStores: no-op for tests');
    return;
  }

  // Provide a deterministic current store for widget tests
  @override
  Map<String, dynamic>? get currentStore => {'id': 1, 'name': 'Store 1'};

  // Report initialized so UI paths that check this don't trigger background work
  @override
  bool get isInitialized => true;
}

class TestInventoryProvider extends InventoryProvider {
  TestInventoryProvider() : super();
}

class TestAnalyticsProvider extends AnalyticsProvider {
  TestAnalyticsProvider() : super();
}

/// Wrap a widget with common mock providers used across tests
Widget wrapWithDefaultProviders(Widget child,
    {AuthProvider? auth,
    StoreProvider? store,
    InventoryProvider? inventory,
    AnalyticsProvider? analytics}) {
  final a = auth ?? TestAuthProvider();
  final s = store ?? TestStoreProvider();
  final i = inventory ?? TestInventoryProvider();
  final an = analytics ?? TestAnalyticsProvider();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: a),
      ChangeNotifierProvider<StoreProvider>.value(value: s),
      ChangeNotifierProvider<InventoryProvider>.value(value: i),
      ChangeNotifierProvider<AnalyticsProvider>.value(value: an),
    ],
    child: MaterialApp(home: child),
  );
}

bool _testHelpersInitialized = false;

/// Initialize shared preferences, platform bindings and other global test state
/// Call this at the top of your test `main()` or inside `setUpAll()`.
void initializeTestHelpersOnce() {
  if (_testHelpersInitialized) return;
  // Ensure Flutter's platform bindings are available for plugin calls
  TestWidgetsFlutterBinding.ensureInitialized();
  // Provide default mock values for SharedPreferences
  SharedPreferences.setMockInitialValues({});
  // Provide a deterministic HTTP client for tests
  HttpOverrides.global = _FakeHttpOverrides();
  _testHelpersInitialized = true;
}

// Simple fake HTTP override so widget tests that attempt networking get a
// deterministic structured response instead of failing with platform errors.
class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final int _status;
  final List<int> _bodyBytes;
  _FakeHttpClientResponse(this._status, String body)
      : _bodyBytes = utf8.encode(body);

  @override
  int get statusCode => _status;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  int get contentLength => _bodyBytes.length;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final controller = StreamController<List<int>>();
    controller.add(_bodyBytes);
    controller.close();
    return controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  // The rest of the HttpClientResponse members implemented minimally for tests
  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  List<Cookie> get cookies => const [];

  @override
  String get reasonPhrase => '';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? uri, bool? followLoops]) async =>
      this;

  @override
  bool get persistentConnection => false;

  @override
  bool get isRedirect => false;

  @override
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final Uri url;
  final BytesBuilder _buffer = BytesBuilder();
  _FakeHttpClientRequest(this.url);

  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding _e) {}

  @override
  void add(List<int> data) => _buffer.add(data);

  @override
  void write(Object? obj) => add(utf8.encode(obj?.toString() ?? ''));

  @override
  Future<HttpClientResponse> close() async {
    // Provide a deterministic response based on URL path
    if (url.path.contains('/auth/token')) {
      return _FakeHttpClientResponse(
          400, '{"detail":"incorrect username or password"}');
    }
    return _FakeHttpClientResponse(400, '{"detail":"error"}');
  }

  // The rest of the members can be no-op or throw; only methods used in tests are needed
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _FakeHttpClientRequest(url);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(url);
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _FakeHttpClient();
}

// ---------- sqflite ffi and plugin helpers (test bootstrap) ----------

/// Initialize sqflite ffi and set the common databaseFactory for tests.
void initSqfliteForTests() {
  try {
    ffi.sqfliteFfiInit();
    sqflite_common.databaseFactory = ffi.databaseFactoryFfi;
  } catch (_) {
    // ignore: avoid_print
    debugPrint('sqflite ffi already initialized or not available in this env');
  }
}

/// Fake `flutter_secure_storage` for unit tests to avoid platform plugin errors.
class FakeFlutterSecureStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    required String key,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    return 'fake-token';
  }
}
