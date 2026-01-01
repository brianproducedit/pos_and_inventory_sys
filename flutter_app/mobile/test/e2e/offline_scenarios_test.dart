import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../lib/db/app_database.dart';
import '../../../lib/services/offline_auth_service.dart';
import '../../../lib/data/repositories/user_repository_v2.dart';
import '../../../lib/data/repositories/product_repository_v2.dart';
import '../../../lib/data/repositories/sale_repository_v2.dart';
import '../../../lib/data/remote/api_client.dart';

@GenerateMocks([ApiClient, FlutterSecureStorage])
import 'offline_scenarios_test.mocks.dart';

/// Tests for critical offline-first scenarios
/// Validates that the app works without internet connectivity
void main() {
  late AppDatabase database;
  late MockApiClient mockApiClient;
  late MockFlutterSecureStorage mockStorage;
  late OfflineAuthService authService;
  late UserRepository userRepository;
  late ProductRepository productRepository;
  late SaleRepository saleRepository;
  late int testStoreId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    mockApiClient = MockApiClient();
    mockStorage = MockFlutterSecureStorage();
    
    authService = OfflineAuthService(
      apiClient: mockApiClient,
      db: database,
      secureStorage: mockStorage,
    );
    
    userRepository = UserRepository(database);
    productRepository = ProductRepository(database);
    saleRepository = SaleRepository(database);

    // Create test store
    testStoreId = await database.into(database.stores).insert(
      StoresCompanion.insert(
        clientId: Value('test-store'),
        name: 'Test Store',
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('Offline Authentication', () {
    test('should create ghost user when offline', () async {
      // Simulate offline mode - API throws network error
      when(mockApiClient.login(any, any))
          .thenThrow(Exception('Network unavailable'));

      // Attempt login while offline
      final result = await authService.login('ghostuser', 'Ghost123!');

      expect(result.success, true);
      expect(result.userId, isNotNull);
      expect(result.isOffline, true);

      // Verify ghost user was created
      final user = await userRepository.getByUsername('ghostuser');
      expect(user, isNotNull);
      expect(user!.isLocalOnly, true);
      expect(user.syncStatus, SyncStatus.pending);
    });

    test('should authenticate with cached credentials when offline', () async {
      // First, login online to cache credentials
      when(mockApiClient.login('cacheduser', 'Cached123!'))
          .thenAnswer((_) async => {
                'access_token': 'token123',
                'user': {
                  'id': 100,
                  'username': 'cacheduser',
                  'full_name': 'Cached User',
                  'role': 'cashier',
                },
              });

      when(mockStorage.write(key: anyNamed('key'), value: anyNamed('value')))
          .thenAnswer((_) async => null);

      await authService.login('cacheduser', 'Cached123!');

      // Now simulate offline mode
      when(mockApiClient.login('cacheduser', 'Cached123!'))
          .thenThrow(Exception('Network unavailable'));

      // Should still be able to login with cached credentials
      final offlineResult = await authService.login('cacheduser', 'Cached123!');

      expect(offlineResult.success, true);
      expect(offlineResult.isOffline, true);
    });

    test('should reject invalid credentials when offline', () async {
      // Create cached user
      await userRepository.create(
        username: 'offlineuser',
        password: 'Correct123!',
        fullName: 'Offline User',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      // Mark user as synced to simulate cached state
      final user = await userRepository.getByUsername('offlineuser');
      await userRepository.markAsSynced(user!.id, serverId: 200);

      // Simulate offline
      when(mockApiClient.login(any, any))
          .thenThrow(Exception('Network unavailable'));

      // Try with wrong password
      final result = await authService.login('offlineuser', 'Wrong123!');

      expect(result.success, false);
      expect(result.error, contains('Invalid'));
    });
  });

  group('Offline Product Management', () {
    test('should create products while offline', () async {
      final productId = await productRepository.create(
        name: 'Offline Product',
        description: 'Created without connection',
        price: 25.00,
        stockQuantity: 100,
        storeId: testStoreId,
      );

      expect(productId, greaterThan(0));

      // Verify product exists locally
      final product = await productRepository.getById(productId);
      expect(product, isNotNull);
      expect(product!.name, 'Offline Product');
      expect(product.syncStatus, SyncStatus.pending);

      // Verify queued for sync
      final syncQueue = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('product'))
            ..where((q) => q.resourceId.equals(productId)))
          .get();
      expect(syncQueue.length, 1);
    });

    test('should update products while offline', () async {
      // Create product
      final productId = await productRepository.create(
        name: 'Original Name',
        price: 10.00,
        storeId: testStoreId,
      );

      // Update while offline
      await productRepository.update(
        productId,
        name: 'Updated Name',
        price: 15.00,
      );

      final product = await productRepository.getById(productId);
      expect(product!.name, 'Updated Name');
      expect(product.price, 15.00);
      expect(product.syncStatus, SyncStatus.pending);
    });

    test('should manage stock while offline', () async {
      final productId = await productRepository.create(
        name: 'Stock Product',
        price: 10.00,
        stockQuantity: 100,
        storeId: testStoreId,
      );

      // Adjust stock offline
      await productRepository.adjustStock(productId, -25);

      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 75);
    });

    test('should search products from local database', () async {
      await productRepository.create(
        name: 'Searchable Offline Product',
        price: 10.00,
        storeId: testStoreId,
      );

      final results = await productRepository.search('Searchable');
      expect(results.length, greaterThanOrEqualTo(1));
      expect(results.first.name, contains('Searchable'));
    });
  });

  group('Offline Sales Processing', () {
    test('should create sales while offline', () async {
      // Create cashier
      final cashierId = await userRepository.create(
        username: 'offlinecashier',
        password: 'Cashier123!',
        fullName: 'Offline Cashier',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      // Create product with stock
      final productId = await productRepository.create(
        name: 'Sale Product',
        price: 19.99,
        stockQuantity: 50,
        storeId: testStoreId,
      );

      // Create sale offline
      final saleId = await saleRepository.createSale(
        userId: cashierId,
        storeId: testStoreId,
        items: [
          SaleItemData(
            productId: productId,
            productName: 'Sale Product',
            quantity: 3,
            unitPrice: 19.99,
            subtotal: 59.97,
          ),
        ],
        totalAmount: 59.97,
        paymentMethod: 'cash',
      );

      expect(saleId, greaterThan(0));

      // Verify sale created
      final sale = await saleRepository.getById(saleId);
      expect(sale, isNotNull);
      expect(sale!.totalAmount, 59.97);
      expect(sale.syncStatus, SyncStatus.pending);

      // Verify stock deducted
      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 47); // 50 - 3

      // Verify queued for sync
      final syncQueue = await (database.select(database.syncQueue)
            ..where((q) => q.resourceType.equals('sale'))
            ..where((q) => q.resourceId.equals(saleId)))
          .get();
      expect(syncQueue.length, 1);
    });

    test('should prevent overselling when offline', () async {
      final cashierId = await userRepository.create(
        username: 'cashier2',
        password: 'Cashier123!',
        fullName: 'Cashier 2',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      final productId = await productRepository.create(
        name: 'Limited Stock',
        price: 10.00,
        stockQuantity: 5,
        storeId: testStoreId,
      );

      // Try to sell more than available
      expect(
        () => saleRepository.createSale(
          userId: cashierId,
          storeId: testStoreId,
          items: [
            SaleItemData(
              productId: productId,
              productName: 'Limited Stock',
              quantity: 10, // More than available
              unitPrice: 10.00,
              subtotal: 100.00,
            ),
          ],
          totalAmount: 100.00,
          paymentMethod: 'cash',
        ),
        throwsA(isA<Exception>()),
      );

      // Verify stock unchanged
      final product = await productRepository.getById(productId);
      expect(product!.stockQuantity, 5);
    });

    test('should generate unique transaction numbers offline', () async {
      final cashierId = await userRepository.create(
        username: 'cashier3',
        password: 'Cashier123!',
        fullName: 'Cashier 3',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      final productId = await productRepository.create(
        name: 'Transaction Product',
        price: 10.00,
        stockQuantity: 100,
        storeId: testStoreId,
      );

      // Create multiple sales
      final sale1Id = await saleRepository.createSale(
        userId: cashierId,
        storeId: testStoreId,
        items: [
          SaleItemData(
            productId: productId,
            productName: 'Transaction Product',
            quantity: 1,
            unitPrice: 10.00,
            subtotal: 10.00,
          ),
        ],
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final sale2Id = await saleRepository.createSale(
        userId: cashierId,
        storeId: testStoreId,
        items: [
          SaleItemData(
            productId: productId,
            productName: 'Transaction Product',
            quantity: 1,
            unitPrice: 10.00,
            subtotal: 10.00,
          ),
        ],
        totalAmount: 10.00,
        paymentMethod: 'cash',
      );

      final sale1 = await saleRepository.getById(sale1Id);
      final sale2 = await saleRepository.getById(sale2Id);

      expect(sale1!.transactionNumber, isNotEmpty);
      expect(sale2!.transactionNumber, isNotEmpty);
      expect(sale1.transactionNumber, isNot(sale2.transactionNumber));
    });
  });

  group('Offline Data Persistence', () {
    test('should persist all changes locally for later sync', () async {
      // Create multiple entities
      final userId = await userRepository.create(
        username: 'persistuser',
        password: 'Persist123!',
        fullName: 'Persist User',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      final productId = await productRepository.create(
        name: 'Persist Product',
        price: 20.00,
        stockQuantity: 25,
        storeId: testStoreId,
      );

      final saleId = await saleRepository.createSale(
        userId: userId,
        storeId: testStoreId,
        items: [
          SaleItemData(
            productId: productId,
            productName: 'Persist Product',
            quantity: 2,
            unitPrice: 20.00,
            subtotal: 40.00,
          ),
        ],
        totalAmount: 40.00,
        paymentMethod: 'card',
      );

      // Verify all have pending sync
      final user = await userRepository.getById(userId);
      final product = await productRepository.getById(productId);
      final sale = await saleRepository.getById(saleId);

      expect(user!.syncStatus, SyncStatus.pending);
      expect(product!.syncStatus, SyncStatus.pending);
      expect(sale!.syncStatus, SyncStatus.pending);

      // Verify all queued for sync
      final syncQueue = await database.select(database.syncQueue).get();
      expect(syncQueue.length, greaterThanOrEqualTo(3));
    });

    test('should maintain referential integrity offline', () async {
      final userId = await userRepository.create(
        username: 'refuser',
        password: 'Ref123!',
        fullName: 'Ref User',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      final productId = await productRepository.create(
        name: 'Ref Product',
        price: 15.00,
        stockQuantity: 30,
        storeId: testStoreId,
      );

      // Create sale referencing user and product
      final saleId = await saleRepository.createSale(
        userId: userId,
        storeId: testStoreId,
        items: [
          SaleItemData(
            productId: productId,
            productName: 'Ref Product',
            quantity: 1,
            unitPrice: 15.00,
            subtotal: 15.00,
          ),
        ],
        totalAmount: 15.00,
        paymentMethod: 'cash',
      );

      final sale = await saleRepository.getById(saleId);
      expect(sale!.userId, userId);
      expect(sale.storeId, testStoreId);

      // Verify sale items reference product
      final saleItems = await (database.select(database.saleItems)
            ..where((si) => si.saleId.equals(saleId)))
          .get();
      expect(saleItems.first.productId, productId);
    });
  });

  group('Offline User Management', () {
    test('should create users while offline', () async {
      final userId = await userRepository.create(
        username: 'offlineadmin',
        password: 'Admin123!',
        fullName: 'Offline Admin',
        role: UserRole.admin,
        storeId: testStoreId,
      );

      final user = await userRepository.getById(userId);
      expect(user, isNotNull);
      expect(user!.username, 'offlineadmin');
      expect(user.syncStatus, SyncStatus.pending);
    });

    test('should update user passwords while offline', () async {
      final userId = await userRepository.create(
        username: 'passuser',
        password: 'Old123!',
        fullName: 'Password User',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      await userRepository.changePassword(userId, 'New456!');

      // Verify password changed
      final isValidOld = await userRepository.validatePassword(userId, 'Old123!');
      final isValidNew = await userRepository.validatePassword(userId, 'New456!');

      expect(isValidOld, false);
      expect(isValidNew, true);
    });

    test('should manage user roles while offline', () async {
      final userId = await userRepository.create(
        username: 'roleuser',
        password: 'Role123!',
        fullName: 'Role User',
        role: UserRole.cashier,
        storeId: testStoreId,
      );

      await userRepository.update(userId, role: UserRole.admin);

      final user = await userRepository.getById(userId);
      expect(user!.role, UserRole.admin);
    });
  });

  group('Offline Query Performance', () {
    test('should efficiently query large datasets offline', () async {
      // Create many products
      for (int i = 0; i < 100; i++) {
        await productRepository.create(
          name: 'Product $i',
          price: 10.0 + i,
          stockQuantity: 50,
          storeId: testStoreId,
        );
      }

      final stopwatch = Stopwatch()..start();
      final products = await productRepository.getAll();
      stopwatch.stop();

      expect(products.length, greaterThanOrEqualTo(100));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should be fast
    });

    test('should efficiently search large datasets', () async {
      for (int i = 0; i < 50; i++) {
        await productRepository.create(
          name: 'Searchable Item $i',
          price: 10.0,
          stockQuantity: 10,
          storeId: testStoreId,
        );
      }

      final stopwatch = Stopwatch()..start();
      final results = await productRepository.search('Searchable');
      stopwatch.stop();

      expect(results.length, greaterThanOrEqualTo(50));
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}
