import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../../db/app_database.dart';

class DemoSeeder {
  static final _uuid = const Uuid();

  /// Hashes a password the same way OfflineAuthService does.
  static String _hashPassword(String password, String username) {
    final bytes = utf8.encode(password + username.toLowerCase());
    return sha256.convert(bytes).toString();
  }

  /// Seeds the local database with demo data if it's empty.
  static Future<void> seed(AppDatabase db) async {
    final userCount = await db.select(db.users).get();
    if (userCount.isNotEmpty) {
      return; // Already seeded or has real data
    }

    print('Seeding demo data into local Drift database...');

    // 1. Users
    final users = [
      UsersCompanion.insert(
        clientId: Value(_uuid.v4()),
        username: 'demo',
        passwordHash: _hashPassword('demo123', 'demo'),
        fullName: const Value('Demo Cashier'),
        role: UserRole.cashier,
        isLocalOnly: const Value(true),
        syncStatus: const Value(SyncStatus.synced),
      ),
      UsersCompanion.insert(
        clientId: Value(_uuid.v4()),
        username: 'admin',
        passwordHash: _hashPassword('demo123', 'admin'),
        fullName: const Value('Demo Admin'),
        role: UserRole.admin,
        isLocalOnly: const Value(true),
        syncStatus: const Value(SyncStatus.synced),
      ),
      UsersCompanion.insert(
        clientId: Value(_uuid.v4()),
        username: 'superadmin',
        passwordHash: _hashPassword('demo123', 'superadmin'),
        fullName: const Value('Demo Superadmin'),
        role: UserRole.superadmin,
        isLocalOnly: const Value(true),
        syncStatus: const Value(SyncStatus.synced),
      ),
    ];

    for (var u in users) {
      await db.into(db.users).insert(u);
    }

    // Fetch the inserted superadmin to associate stores/sales
    final adminUser = await (db.select(db.users)
          ..where((u) => u.username.equals('superadmin')))
        .getSingle();

    // 2. Stores
    final storeIdMap = <String, int>{};
    final stores = [
      StoresCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Harare CBD',
        location: const Value('First Street, Harare'),
        syncStatus: const Value(SyncStatus.synced),
      ),
      StoresCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Avondale',
        location: const Value('Avondale Shopping Centre'),
        syncStatus: const Value(SyncStatus.synced),
      ),
    ];

    for (var s in stores) {
      final id = await db.into(db.stores).insert(s);
      storeIdMap[s.name.value] = id;
    }
    
    final harareId = storeIdMap['Harare CBD']!;

    // Make superadmin belong to Harare (or admin)
    await (db.update(db.users)..where((u) => u.username.equals('admin')))
        .write(UsersCompanion(storeId: Value(harareId)));
    await (db.update(db.users)..where((u) => u.username.equals('demo')))
        .write(UsersCompanion(storeId: Value(harareId)));

    // 3. Products
    final products = [
      ProductsCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Coca-Cola 500ml',
        sku: const Value('COCA-500'),
        price: const Value(1.50),
        stockQuantity: const Value(120),
        storeId: harareId,
        syncStatus: const Value(SyncStatus.synced),
      ),
      ProductsCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Lays Salted 30g',
        sku: const Value('LAYS-30G'),
        price: const Value(0.80),
        stockQuantity: const Value(85),
        storeId: harareId,
        syncStatus: const Value(SyncStatus.synced),
      ),
      ProductsCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Econet Airtime \$1',
        sku: const Value('ECO-1USD'),
        price: const Value(1.00),
        stockQuantity: const Value(500),
        storeId: harareId,
        syncStatus: const Value(SyncStatus.synced),
      ),
      ProductsCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Mazoe Orange Crush 2L',
        sku: const Value('MAZ-OR-2L'),
        price: const Value(4.50),
        stockQuantity: const Value(45),
        storeId: harareId,
        syncStatus: const Value(SyncStatus.synced),
      ),
      ProductsCompanion.insert(
        clientId: Value(_uuid.v4()),
        name: 'Bakers Inscore Bread',
        sku: const Value('BREAD-INS'),
        price: const Value(1.00),
        stockQuantity: const Value(30),
        storeId: harareId,
        syncStatus: const Value(SyncStatus.synced),
      ),
    ];

    final productIds = <int>[];
    for (var p in products) {
      final id = await db.into(db.products).insert(p);
      productIds.add(id);
    }

    // 4. Sales & SaleItems
    final now = DateTime.now();
    for (int i = 0; i < 15; i++) {
      final saleDate = now.subtract(Duration(days: i % 5, hours: i));
      
      final saleId = await db.into(db.sales).insert(SalesCompanion.insert(
        clientId: Value(_uuid.v4()),
        transactionNumber: 'TXN-DEMO-${1000 + i}',
        userId: adminUser.id,
        storeId: harareId,
        totalAmount: 2.50, // Will update
        paymentMethod: i % 3 == 0 ? 'card' : 'cash',
        createdAt: Value(saleDate),
        syncStatus: const Value(SyncStatus.synced),
      ));

      // Add a couple of items per sale
      double totalAmount = 0;
      final numItems = (i % 3) + 1;
      for (int j = 0; j < numItems; j++) {
        final prodId = productIds[(i + j) % productIds.length];
        // Fetch product to get price
        final p = await (db.select(db.products)..where((p) => p.id.equals(prodId))).getSingle();
        final qty = (j % 2) + 1;
        final itemTotal = p.price * qty;
        totalAmount += itemTotal;

        await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
          clientId: Value(_uuid.v4()),
          saleId: saleId,
          productId: prodId,
          quantity: qty,
          unitPrice: p.price,
          totalPrice: itemTotal,
          syncStatus: const Value(SyncStatus.synced),
        ));
      }

      await (db.update(db.sales)..where((s) => s.id.equals(saleId)))
          .write(SalesCompanion(totalAmount: Value(totalAmount)));
    }

    print('Demo data seeding completed.');
  }
}
