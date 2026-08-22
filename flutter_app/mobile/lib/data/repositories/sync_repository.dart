import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import '../../domain/models/sync_error.dart';
import '../sync/sync_database_helper.dart';
import '../remote/postgres_api_service.dart';
import '../../db/app_database.dart'
    show
        AppDatabase,
        ProductsCompanion,
        SaleItemsCompanion,
        SalesCompanion,
        StoresCompanion,
        SyncMetaCompanion,
        SyncQueueCompanion,
        SyncStatus,
        UserRole,
        UsersCompanion,
        cleanupDuplicateStores;

/// Enhanced sync repository providing complex sync operations
/// that were previously implemented with raw SQL in PostgresSyncService.
/// This repository handles batch operations, FK resolution, and complex transactions.
class SyncRepository {
  final SyncDatabaseHelper _dbHelper;
  final AppDatabase _db;

  SyncRepository({required SyncDatabaseHelper dbHelper})
      : _dbHelper = dbHelper,
        _db = dbHelper.driftDatabase;

  Future<List<SyncError>> getErrors({int limit = 100}) async {
    final rows = await _dbHelper.getSyncErrors(limit: limit);
    return rows.map((r) => SyncError.fromMap(r)).toList();
  }

  Future<void> clearError(int id) async => _dbHelper.clearSyncError(id);

  Future<void> clearErrorsForQueue(int queueId) async =>
      _dbHelper.clearErrorsForQueue(queueId);

  /// Re-enqueue a failed queue item (reset retry_count + status='pending') and clear errors
  Future<void> reenqueueQueueItem(int queueId) async =>
      _dbHelper.reenqueueQueueItem(queueId);

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH SYNC OPERATIONS (Replacing syncPendingChangesBatch)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get pending sync items with sequence filtering for batch operations
  Future<List<Map<String, dynamic>>> getPendingSyncItemsForBatch(
      {int limit = 100, int lastPushedSeq = 0}) async {
    final items = await _dbHelper.getPendingSyncItems(limit: limit);

    // Assign client sequences to items that don't have them
    final itemsNeedingSeq = items.where((item) {
      final clientSeq = item['client_seq'] as int? ?? 0;
      return clientSeq == 0;
    }).toList();

    if (itemsNeedingSeq.isNotEmpty) {
      debugPrint(
          'getPendingSyncItemsForBatch: Assigning sequences to ${itemsNeedingSeq.length} items');
      await assignClientSequences(itemsNeedingSeq, lastPushedSeq);
      // Re-fetch items after sequence assignment
      final updatedItems = await _dbHelper.getPendingSyncItems(limit: limit);
      return updatedItems.where((item) {
        final clientSeq = item['client_seq'] as int? ?? 0;
        return clientSeq > lastPushedSeq;
      }).toList();
    }

    // Filter items with client_seq > lastPushedSeq
    return items.where((item) {
      final clientSeq = item['client_seq'] as int? ?? 0;
      return clientSeq > lastPushedSeq;
    }).toList();
  }

  /// Assign client sequence numbers to pending items within a transaction
  Future<List<Map<String, dynamic>>> assignClientSequences(
    List<Map<String, dynamic>> items,
    int lastPushedSeq,
  ) async {
    final filteredItems = <Map<String, dynamic>>[];
    int maxSeq = lastPushedSeq;

    await _db.transaction(() async {
      // Get current last_client_seq
      final seqRows = await (_db.select(_db.syncMeta)
            ..where((m) => m.key.equals('last_client_seq')))
          .get();
      int lastSeq = 0;
      if (seqRows.isNotEmpty) {
        lastSeq = int.tryParse(seqRows.first.value ?? '') ?? 0;
      }

      for (final item in items) {
        final queueId = item['id'] as int;
        int clientSeq = item['client_seq'] as int? ?? 0;

        // Assign new seq if needed
        if (clientSeq == 0 || clientSeq <= lastPushedSeq) {
          lastSeq += 1;
          clientSeq = lastSeq;
          await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueId)))
              .write(SyncQueueCompanion(clientSeq: Value(clientSeq)));
        }

        // Include if seq > lastPushedSeq
        if (clientSeq > lastPushedSeq) {
          filteredItems.add({...item, 'client_seq': clientSeq});
          if (clientSeq > maxSeq) maxSeq = clientSeq;
        }
      }

      // Update last_client_seq
      if (lastSeq > 0) {
        await _db.into(_db.syncMeta).insertOnConflictUpdate(
              SyncMetaCompanion.insert(
                key: 'last_client_seq',
                value: Value(lastSeq.toString()),
              ),
            );
      }
    });

    return filteredItems;
  }

  /// Resolve foreign key mappings for batch sync operations
  /// Maps local IDs to server IDs for products, stores, users in transaction items
  Future<Map<String, dynamic>> resolveBatchSyncData(
    Map<String, dynamic> item,
  ) async {
    final tableName = item['table_name'] as String;
    final rowId = item['row_id'] as int;
    final payloadJson = item['payload_json'] as String;
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

    switch (tableName) {
      case 'products':
        return await _resolveProductSyncData(rowId, payload);
      case 'stores':
        return await _resolveStoreSyncData(rowId, payload);
      case 'users':
        return await _resolveUserSyncData(rowId, payload);
      case 'sales':
        return await _resolveSaleSyncData(rowId, payload);
      default:
        return payload;
    }
  }

  /// Resolve product sync data with store_id mapping
  Future<Map<String, dynamic>> _resolveProductSyncData(
    int rowId,
    Map<String, dynamic> payload,
  ) async {
    final product = await (_db.select(_db.products)
          ..where((p) => p.id.equals(rowId)))
        .getSingleOrNull();

    if (product == null) return payload;

    final data = payload['data'] as Map<String, dynamic>? ??
        {
          'name': product.name,
          'sku': product.sku,
          'price': product.price,
          'stock_quantity': product.stockQuantity,
          'store_id': product.storeId,
        };

    // Map local store_id to server store_id
    final localStoreId = data['store_id'] as int?;
    if (localStoreId != null) {
      final store = await (_db.select(_db.stores)
            ..where((s) => s.id.equals(localStoreId)))
          .getSingleOrNull();
      if (store?.serverId != null) {
        data['store_id'] = store!.serverId;
      } else {
        // Store not synced yet - defer product sync by throwing exception
        // This will be caught and the item will be retried later
        throw Exception(
            'Product $rowId references unsynced store $localStoreId - deferring sync');
      }
    }

    return data;
  }

  /// Resolve store sync data (stores don't have FK dependencies)
  Future<Map<String, dynamic>> _resolveStoreSyncData(
    int rowId,
    Map<String, dynamic> payload,
  ) async {
    final store = await (_db.select(_db.stores)
          ..where((s) => s.id.equals(rowId)))
        .getSingleOrNull();

    if (store == null) return payload;

    return payload['data'] as Map<String, dynamic>? ??
        {
          'name': store.name,
          'location': store.location,
        };
  }

  /// Resolve user sync data with store_id mapping
  Future<Map<String, dynamic>> _resolveUserSyncData(
    int rowId,
    Map<String, dynamic> payload,
  ) async {
    final user = await (_db.select(_db.users)..where((u) => u.id.equals(rowId)))
        .getSingleOrNull();

    if (user == null) return payload;

    final data = payload['data'] as Map<String, dynamic>? ??
        {
          'username': user.username,
          'full_name': user.fullName,
          'role': user.role.name,
          'store_id': user.storeId,
          'is_active': user.isActive,
        };

    // Map local store_id to server store_id
    final localStoreId = data['store_id'] as int?;
    if (localStoreId != null) {
      final store = await (_db.select(_db.stores)
            ..where((s) => s.id.equals(localStoreId)))
          .getSingleOrNull();
      if (store?.serverId != null) {
        data['store_id'] = store!.serverId;
      } else {
        // Store not synced yet - defer user sync
        throw Exception('User $rowId references unsynced store $localStoreId');
      }
    }

    return data;
  }

  /// Resolve sale sync data with complex FK mappings for items
  Future<Map<String, dynamic>> _resolveSaleSyncData(
    int rowId,
    Map<String, dynamic> payload,
  ) async {
    final sale = await (_db.select(_db.sales)..where((s) => s.id.equals(rowId)))
        .getSingleOrNull();

    if (sale == null) return payload;

    // Get sale items with product mappings
    final saleItems = await (_db.select(_db.saleItems)
          ..where((si) => si.saleId.equals(rowId)))
        .get();

    final items = <Map<String, dynamic>>[];
    for (final item in saleItems) {
      final product = await (_db.select(_db.products)
            ..where((p) => p.id.equals(item.productId)))
          .getSingleOrNull();

      if (product == null) {
        throw Exception(
            'Sale $rowId references non-existent product ${item.productId}');
      }

      int? productRef;
      if (product.serverId != null) {
        productRef = product.serverId;
      } else {
        // Product not synced - check if it's in current batch
        // For now, we'll defer this sale
        throw Exception(
            'Sale $rowId references unsynced product ${item.productId}');
      }

      items.add({
        'product_id': productRef,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total_price': item.totalPrice,
      });
    }

    // Map store_id and user_id to server IDs
    int? serverStoreId;
    int? serverUserId;

    final store = await (_db.select(_db.stores)
          ..where((s) => s.id.equals(sale.storeId)))
        .getSingleOrNull();
    serverStoreId = store!.serverId;

    final user = await (_db.select(_db.users)
          ..where((u) => u.id.equals(sale.userId)))
        .getSingleOrNull();
    serverUserId = user!.serverId;

    return {
      'transaction_number': sale.transactionNumber,
      'total_amount': sale.totalAmount,
      'payment_method': sale.paymentMethod,
      'store_id': serverStoreId,
      'user_id': serverUserId,
      'items': items,
    };
  }

  /// Apply batch sync results (id_map, conflicts, applied) atomically
  Future<void> applyBatchSyncResults({
    required Map<String, dynamic> idMap,
    required List<dynamic> conflicts,
    required List<dynamic> applied,
  }) async {
    await _db.transaction(() async {
      // Apply id_map: update local rows and mark queue items synced
      for (final entry in idMap.entries) {
        final tempId = entry.key;
        final serverId = entry.value as int;
        await _applyIdMapping(tempId, serverId);
      }

      // Handle applied changes
      for (final appliedItem in applied) {
        await _applyServerChange(appliedItem as Map<String, dynamic>);
      }

      // Handle conflicts
      for (final conflict in conflicts) {
        await _handleSyncConflict(conflict as Map<String, dynamic>);
      }
    });
  }

  /// Apply ID mapping from server response
  Future<void> _applyIdMapping(String tempId, int serverId) async {
    // Find queue item by temp_id
    final queueItem = await (_db.select(_db.syncQueue)
          ..where((q) => q.clientTempId.equals(tempId)))
        .getSingleOrNull();

    if (queueItem == null) return;

    final resourceType = queueItem.resourceType;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Update the appropriate table with server_id
    switch (resourceType) {
      case 'product':
        await (_db.update(_db.products)
              ..where((p) => p.clientId.equals(tempId)))
            .write(ProductsCompanion(
          serverId: Value(serverId),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        ));
        break;
      case 'store':
        await (_db.update(_db.stores)..where((s) => s.clientId.equals(tempId)))
            .write(StoresCompanion(
          serverId: Value(serverId),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        ));
        break;
      case 'user':
        await (_db.update(_db.users)..where((u) => u.clientId.equals(tempId)))
            .write(UsersCompanion(
          serverId: Value(serverId),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        ));
        break;
      case 'transaction':
      case 'sale':
        await (_db.update(_db.sales)..where((s) => s.clientId.equals(tempId)))
            .write(SalesCompanion(
          serverId: Value(serverId),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        ));
        break;
    }

    // Mark queue item as synced
    await (_db.update(_db.syncQueue)..where((q) => q.id.equals(queueItem.id)))
        .write(const SyncQueueCompanion(status: Value('synced')));
  }

  /// Apply a server change from the 'applied' list
  Future<void> _applyServerChange(Map<String, dynamic> change) async {
    final resource = change['resource_type'] as String?;
    final id = change['id'] as int?;
    final data = change['data'] as Map<String, dynamic>?;

    if (resource == null || id == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    switch (resource) {
      case 'product':
        await _applyProductServerChange(id, data, now);
        break;
      case 'store':
        await _applyStoreServerChange(id, data, now);
        break;
      case 'user':
        await _applyUserServerChange(id, data, now);
        break;
      case 'transaction':
      case 'sale':
        await _applySaleServerChange(id, data, now);
        break;
    }
  }

  Future<void> _applyProductServerChange(
      int serverId, Map<String, dynamic>? data, int now) async {
    final updateFields = <String, Object>{
      'sync_status': 'synced',
      'last_updated_at': now,
    };

    if (data != null) {
      // Map server store_id to local store_id
      if (data.containsKey('store_id')) {
        final serverStoreId = data['store_id'] as int?;
        if (serverStoreId != null) {
          final store = await (_db.select(_db.stores)
                ..where((s) => s.serverId.equals(serverStoreId)))
              .getSingleOrNull();
          if (store != null) {
            updateFields['store_id'] = store.id;
          }
        }
      }

      // Apply other fields
      if (data.containsKey('name')) updateFields['name'] = data['name'];
      if (data.containsKey('sku')) updateFields['sku'] = data['sku'];
      if (data.containsKey('price')) updateFields['price'] = data['price'];
      if (data.containsKey('stock_quantity')) {
        updateFields['stock_quantity'] = data['stock_quantity'];
      }
    }

    // This would need raw SQL access - we'll handle this in the next phase
    // For now, this is a placeholder showing the structure
  }

  Future<void> _applyStoreServerChange(
      int serverId, Map<String, dynamic>? data, int now) async {
    // Similar structure to product changes
  }

  Future<void> _applyUserServerChange(
      int serverId, Map<String, dynamic>? data, int now) async {
    // Similar structure to product changes
  }

  Future<void> _applySaleServerChange(
      int serverId, Map<String, dynamic>? data, int now) async {
    // Similar structure to product changes
  }

  /// Handle sync conflicts
  Future<void> _handleSyncConflict(Map<String, dynamic> conflict) async {
    // Implementation for handling conflicts
    // This will increment retry counts and mark items for manual resolution if needed
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIAL SYNC OPERATIONS (Replacing performInitialSync)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apply initial sync data from server
  Future<void> applyInitialSyncData({
    required List<Map<String, dynamic>> stores,
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      // Sync stores first (no dependencies)
      await _syncStoresInitial(stores, now);

      // Sync users (depend on stores)
      await _syncUsersInitial(users, now);

      // Sync products (depend on stores)
      await _syncProductsInitial(products, now);

      // Sync transactions (depend on products, users, stores)
      await _syncTransactionsInitial(transactions, now);
    });
  }

  Future<void> _syncStoresInitial(
      List<Map<String, dynamic>> stores, int now) async {
    for (final store in stores) {
      final serverId = store['id'] as int;
      final existing = await (_db.select(_db.stores)
            ..where((s) => s.serverId.equals(serverId)))
          .getSingleOrNull();

      final storeData = StoresCompanion.insert(
        serverId: Value(serverId),
        name: store['name'] as String,
        location: Value(store['location'] as String?),
        isActive: Value((store['is_active'] as bool?) ?? true),
        createdAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        syncStatus: const Value(SyncStatus.synced),
      );

      if (existing == null) {
        await _db.into(_db.stores).insert(storeData);
      } else {
        await (_db.update(_db.stores)..where((s) => s.id.equals(existing.id)))
            .write(storeData);
      }
    }
  }

  Future<void> _syncUsersInitial(
      List<Map<String, dynamic>> users, int now) async {
    for (final user in users) {
      final serverId = user['id'] as int;
      final username = user['username'] as String;

      // Find existing user by server_id or username
      var existing = await (_db.select(_db.users)
            ..where((u) => u.serverId.equals(serverId)))
          .getSingleOrNull();

      existing ??= await (_db.select(_db.users)
            ..where((u) => u.username.equals(username)))
          .getSingleOrNull();

      // Map server store_id to local store_id
      int? localStoreId;
      final serverStoreId = user['store_id'] as int?;
      if (serverStoreId != null) {
        final store = await (_db.select(_db.stores)
              ..where((s) => s.serverId.equals(serverStoreId)))
            .getSingleOrNull();
        localStoreId = store?.id;
      }

      final userData = UsersCompanion.insert(
        serverId: Value(serverId),
        username: username,
        passwordHash: user['password_hash'] as String? ??
            '', // Default empty hash for initial sync (passwords not synced for security)
        fullName: Value(user['full_name'] as String?),
        role: UserRole.values.firstWhere(
          (r) => r.name == (user['role'] as String? ?? 'cashier'),
          orElse: () => UserRole.cashier,
        ),
        storeId: Value(localStoreId),
        isActive: Value((user['is_active'] as bool?) ?? true),
        createdAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        syncStatus: const Value(SyncStatus.synced),
        isLocalOnly: const Value(false), // Server users are not local-only
      );

      if (existing == null) {
        await _db.into(_db.users).insert(userData);
      } else {
        await (_db.update(_db.users)..where((u) => u.id.equals(existing!.id)))
            .write(userData);
      }
    }
  }

  Future<void> _syncProductsInitial(
      List<Map<String, dynamic>> products, int now) async {
    for (final product in products) {
      final serverId = product['id'] as int;

      // Map server store_id to local store_id
      int? localStoreId;
      final serverStoreId = product['store_id'] as int?;
      if (serverStoreId != null) {
        final store = await (_db.select(_db.stores)
              ..where((s) => s.serverId.equals(serverStoreId)))
            .getSingleOrNull();
        if (store == null) continue; // Skip if store not found
        localStoreId = store.id;
      }

      final existing = await (_db.select(_db.products)
            ..where((p) => p.serverId.equals(serverId)))
          .getSingleOrNull();

      final productData = ProductsCompanion.insert(
        serverId: Value(serverId),
        storeId: localStoreId!, // Required field, should not be null
        name: product['name'] as String,
        sku: Value(product['sku'] as String?),
        price: Value((product['price'] as num).toDouble()),
        stockQuantity: Value(product['stock_quantity'] as int? ?? 0),
        isActive: Value((product['is_active'] as bool?) ?? true),
        createdAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        syncStatus: const Value(SyncStatus.synced),
      );

      if (existing == null) {
        await _db.into(_db.products).insert(productData);
      } else {
        await (_db.update(_db.products)..where((p) => p.id.equals(existing.id)))
            .write(productData);
      }
    }
  }

  Future<void> _syncTransactionsInitial(
      List<Map<String, dynamic>> transactions, int now) async {
    for (final transaction in transactions) {
      final serverId = transaction['id'] as int;

      // Map server store_id to local store_id
      int? localStoreId;
      final serverStoreId = transaction['store_id'] as int?;
      if (serverStoreId != null) {
        final store = await (_db.select(_db.stores)
              ..where((s) => s.serverId.equals(serverStoreId)))
            .getSingleOrNull();
        if (store == null) continue; // Skip if store not found
        localStoreId = store.id;
      }

      // Map server user_id to local user_id
      int? localUserId;
      final serverUserId = transaction['user_id'] as int?;
      if (serverUserId != null) {
        final user = await (_db.select(_db.users)
              ..where((u) => u.serverId.equals(serverUserId)))
            .getSingleOrNull();
        localUserId = user?.id;
      }

      final existing = await (_db.select(_db.sales)
            ..where((s) => s.serverId.equals(serverId)))
          .getSingleOrNull();

      final resolvedTxnNum =
          (transaction['transaction_number'] as String?) ?? 'sales#$serverId';

      final saleData = SalesCompanion.insert(
        serverId: Value(serverId),
        transactionNumber: resolvedTxnNum,
        totalAmount: (transaction['total_amount'] as num).toDouble(),
        paymentMethod: transaction['payment_method'] as String? ?? 'cash',
        paymentReference: Value(transaction['payment_reference'] as String?),
        status: Value(transaction['status'] as String? ?? 'completed'),
        storeId: localStoreId!,
        userId: localUserId!,
        createdAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
        syncStatus: const Value(SyncStatus.synced),
      );

      int saleId;
      if (existing == null) {
        saleId = await _db.into(_db.sales).insert(saleData);
      } else {
        saleId = existing.id;
        await (_db.update(_db.sales)..where((s) => s.id.equals(saleId)))
            .write(saleData);
      }

      // Insert sale items
      final items = transaction['items'] as List?;
      if (items != null) {
        for (final item in items) {
          final itemData = item as Map<String, dynamic>;
          final serverProductId = itemData['product_id'] as int;

          // Map server product_id to local product_id
          final product = await (_db.select(_db.products)
                ..where((p) => p.serverId.equals(serverProductId)))
              .getSingleOrNull();

          if (product == null) continue; // Skip if product not found

          await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
                saleId: saleId,
                productId: product.id,
                quantity: itemData['quantity'] as int,
                unitPrice: (itemData['unit_price'] as num).toDouble(),
                totalPrice: (itemData['total_price'] as num).toDouble(),
                syncStatus: const Value(SyncStatus.synced),
              ));
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PULL SYNC OPERATIONS (Replacing pullChangesSinceSeq)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apply pull sync changes from server
  Future<void> applyPullChanges(List<Map<String, dynamic>> changes) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction(() async {
      for (final change in changes) {
        await _applyPullChange(change, now);
      }
    });
  }

  Future<void> _applyPullChange(Map<String, dynamic> change, int now) async {
    final entityType = change['entity_type'] as String?;
    final entityId = change['entity_id']?.toString();
    final op = change['operation'] as String?;
    final payload = change['payload'] as Map<String, dynamic>? ?? {};

    switch (entityType) {
      case 'product':
        await _applyPullProductChange(op, entityId, payload, now);
        break;
      case 'store':
        await _applyPullStoreChange(op, entityId, payload, now);
        break;
      case 'user':
        await _applyPullUserChange(op, entityId, payload, now);
        break;
      case 'transaction':
        await _applyPullTransactionChange(op, entityId, payload, now);
        break;
    }
  }

  Future<void> _applyPullProductChange(String? op, String? entityId,
      Map<String, dynamic> payload, int now) async {
    final serverId = int.tryParse(entityId ?? '');
    if (serverId == null) return;

    if (op == 'delete') {
      await (_db.delete(_db.products)
            ..where((p) => p.serverId.equals(serverId)))
          .go();
      return;
    }

    final data = payload['data'] as Map<String, dynamic>? ?? {};
    final existing = await (_db.select(_db.products)
          ..where((p) => p.serverId.equals(serverId)))
        .getSingleOrNull();

    // Map server store_id to local store_id
    int? localStoreId;
    final serverStoreId = data['store_id'] as int?;
    if (serverStoreId != null) {
      final store = await (_db.select(_db.stores)
            ..where((s) => s.serverId.equals(serverStoreId)))
          .getSingleOrNull();
      localStoreId = store?.id;
    }

    // Skip if required data is missing
    if (localStoreId == null || data['name'] == null) {
      debugPrint(
          'Skipping product update - missing required data: storeId=$localStoreId, name=${data['name']}');
      return;
    }

    final productData = ProductsCompanion(
      serverId: Value(serverId),
      storeId: Value(localStoreId),
      name: Value(data['name'] as String),
      sku: data['sku'] != null
          ? Value(data['sku'] as String)
          : const Value.absent(),
      price: data['price'] != null
          ? Value((data['price'] as num).toDouble())
          : const Value.absent(),
      stockQuantity: data['stock_quantity'] != null
          ? Value(data['stock_quantity'] as int)
          : const Value.absent(),
      syncStatus: const Value(SyncStatus.synced),
      lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
    );

    if (existing == null) {
      // Check for duplicate by name/store before inserting
      final duplicate = await (_db.select(_db.products)
            ..where((p) => p.name.equals(data['name'] as String))
            ..where((p) => p.storeId.equals(localStoreId!)))
          .getSingleOrNull();
      if (duplicate != null) {
        // Update existing instead of creating duplicate
        await (_db.update(_db.products)
              ..where((p) => p.id.equals(duplicate.id)))
            .write(productData);
        return;
      }
      await _db.into(_db.products).insert(ProductsCompanion.insert(
            serverId: Value(serverId),
            storeId: localStoreId,
            name: data['name'] as String,
            sku: Value(data['sku'] as String?),
            price: Value((data['price'] as num?)?.toDouble() ?? 0.0),
            stockQuantity: Value(data['stock_quantity'] as int? ?? 0),
            syncStatus: const Value(SyncStatus.synced),
            lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
            createdAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
          ));
    } else {
      await (_db.update(_db.products)..where((p) => p.id.equals(existing.id)))
          .write(productData);
    }
  }

  Future<void> _applyPullStoreChange(String? op, String? entityId,
      Map<String, dynamic> payload, int now) async {
    final serverId = int.tryParse(entityId ?? '');
    if (serverId == null) return;

    if (op == 'delete') {
      await (_db.delete(_db.stores)..where((s) => s.serverId.equals(serverId)))
          .go();
      return;
    }

    final data = payload['data'] as Map<String, dynamic>? ?? {};

    // Skip if required data is missing
    if (data['name'] == null) {
      debugPrint(
          'Skipping store update - missing required data: name=${data['name']}');
      return;
    }

    final existing = await (_db.select(_db.stores)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();

    final storeData = StoresCompanion(
      serverId: Value(serverId),
      name: Value(data['name'] as String),
      location: data['location'] != null
          ? Value(data['location'] as String)
          : const Value.absent(),
      isActive: Value(data['is_active'] as bool? ?? true),
      lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
      syncStatus: const Value(SyncStatus.synced),
    );

    if (existing == null) {
      await _db.into(_db.stores).insert(storeData);
    } else {
      await (_db.update(_db.stores)..where((s) => s.id.equals(existing.id)))
          .write(storeData);
    }
  }

  Future<void> _applyPullUserChange(String? op, String? entityId,
      Map<String, dynamic> payload, int now) async {
    final serverId = int.tryParse(entityId ?? '');
    if (serverId == null) return;

    if (op == 'delete') {
      await (_db.delete(_db.users)..where((u) => u.serverId.equals(serverId)))
          .go();
      return;
    }

    final data = payload['data'] as Map<String, dynamic>? ?? {};

    // Skip if required data is missing
    if (data['username'] == null) {
      debugPrint(
          'Skipping user update - missing required data: username=${data['username']}');
      return;
    }

    final existing = await (_db.select(_db.users)
          ..where((u) => u.serverId.equals(serverId)))
        .getSingleOrNull();

    // Map server store_id to local store_id
    int? localStoreId;
    final serverStoreId = data['store_id'] as int?;
    if (serverStoreId != null) {
      final store = await (_db.select(_db.stores)
            ..where((s) => s.serverId.equals(serverStoreId)))
          .getSingleOrNull();
      localStoreId = store?.id;
    }

    final userData = UsersCompanion(
      serverId: Value(serverId),
      username: Value(data['username'] as String),
      passwordHash: Value(data['password_hash'] as String? ?? ''),
      fullName: data['full_name'] != null
          ? Value(data['full_name'] as String)
          : const Value.absent(),
      role: Value(UserRole.values.firstWhere(
        (r) => r.name == (data['role'] as String? ?? 'cashier'),
        orElse: () => UserRole.cashier,
      )),
      storeId:
          localStoreId != null ? Value(localStoreId) : const Value.absent(),
      isActive: Value(data['is_active'] as bool? ?? true),
      lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
      syncStatus: const Value(SyncStatus.synced),
    );

    if (existing == null) {
      await _db.into(_db.users).insert(userData);
    } else {
      await (_db.update(_db.users)..where((u) => u.id.equals(existing.id)))
          .write(userData);
    }
  }

  Future<void> _applyPullTransactionChange(String? op, String? entityId,
      Map<String, dynamic> payload, int now) async {
    final serverId = int.tryParse(entityId ?? '');
    if (serverId == null) return;

    if (op == 'delete') {
      // Delete sale items first, then sale
      final sale = await (_db.select(_db.sales)
            ..where((s) => s.serverId.equals(serverId)))
          .getSingleOrNull();
      if (sale != null) {
        await (_db.delete(_db.saleItems)
              ..where((si) => si.saleId.equals(sale.id)))
            .go();
        await (_db.delete(_db.sales)..where((s) => s.id.equals(sale.id))).go();
      }
      return;
    }

    final data = payload['data'] as Map<String, dynamic>? ?? {};

    final existing = await (_db.select(_db.sales)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();

    // Map server store_id to local store_id
    int? localStoreId;
    final serverStoreId = data['store_id'] as int?;
    if (serverStoreId != null) {
      final store = await (_db.select(_db.stores)
            ..where((s) => s.serverId.equals(serverStoreId)))
          .getSingleOrNull();
      localStoreId = store?.id;
    }

    // Map server user_id to local user_id
    int? localUserId;
    final serverUserId = data['user_id'] as int?;
    if (serverUserId != null) {
      final user = await (_db.select(_db.users)
            ..where((u) => u.serverId.equals(serverUserId)))
          .getSingleOrNull();
      localUserId = user?.id;
    }

    // Skip if required data is missing
    if (data['total_amount'] == null ||
        localStoreId == null ||
        localUserId == null) {
      debugPrint(
          'Skipping transaction update - missing required data: total_amount=${data['total_amount']}, storeId=$localStoreId, userId=$localUserId');
      return;
    }

    final saleData = SalesCompanion(
      serverId: Value(serverId),
      transactionNumber:
          Value(data['transaction_number'] as String? ?? 'sales#$serverId'),
      totalAmount: Value((data['total_amount'] as num).toDouble()),
      paymentMethod: data['payment_method'] != null
          ? Value(data['payment_method'] as String)
          : const Value.absent(),
      status: Value(data['status'] as String? ?? 'completed'),
      storeId: Value(localStoreId),
      userId: Value(localUserId),
      lastUpdatedAt: Value(DateTime.fromMillisecondsSinceEpoch(now)),
      syncStatus: const Value(SyncStatus.synced),
    );

    int saleId;
    if (existing == null) {
      saleId = await _db.into(_db.sales).insert(saleData);
    } else {
      saleId = existing.id;
      await (_db.update(_db.sales)..where((s) => s.id.equals(saleId)))
          .write(saleData);
    }

    // Handle sale items if provided
    final items = data['items'] as List?;
    if (items != null) {
      // Clear existing items first
      await (_db.delete(_db.saleItems)..where((si) => si.saleId.equals(saleId)))
          .go();

      for (final item in items) {
        final itemData = item as Map<String, dynamic>;
        final serverProductId = itemData['product_id'] as int;

        // Map server product_id to local product_id
        final product = await (_db.select(_db.products)
              ..where((p) => p.serverId.equals(serverProductId)))
            .getSingleOrNull();

        if (product == null) continue; // Skip if product not found

        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
              saleId: saleId,
              productId: product.id,
              quantity: itemData['quantity'] as int,
              unitPrice: (itemData['unit_price'] as num).toDouble(),
              totalPrice: (itemData['total_price'] as num).toDouble(),
              syncStatus: const Value(SyncStatus.synced),
            ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS (Supporting pullChangesSinceSeq)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get total count of stores
  Future<int> getStoreCount() async {
    final count = await _db.stores.count().getSingle();
    return count;
  }

  /// Get count of stores that have been synced with server (have server_id)
  Future<int> getSyncedStoreCount() async {
    final result = await (_db.selectOnly(_db.stores)
          ..addColumns([_db.stores.id.count()])
          ..where(_db.stores.serverId.isNotNull()))
        .getSingle();
    return result.read(_db.stores.id.count())!;
  }

  /// Get the last server sequence number
  Future<int> getLastServerSeq() async {
    return await _dbHelper.getLastServerSeq();
  }

  /// Set the last server sequence number
  Future<void> setLastServerSeq(int seq) async {
    return await _dbHelper.setLastServerSeq(seq);
  }

  /// Clean up orphaned products that have never been synced
  Future<int> cleanupOrphanedProducts({int maxAgeMs = 86400000}) async {
    return await _dbHelper.cleanupOrphanedProducts(maxAgeMs: maxAgeMs);
  }

  /// Clean up duplicate products by SKU and store
  Future<int> cleanupDuplicateProducts() async {
    return await _dbHelper.cleanupDuplicateProducts();
  }

  /// Clean up duplicate users by username
  Future<int> cleanupDuplicateUsers() async {
    return await _dbHelper.cleanupDuplicateUsers();
  }

  /// Clean up orphaned sync queue items
  Future<int> cleanupOrphanedSyncQueue() async {
    return await _dbHelper.cleanupOrphanedSyncQueue();
  }

  /// Clean up duplicate stores
  Future<int> cleanupDuplicateStoresInDb() async {
    return await cleanupDuplicateStores(_db);
  }

  /// Process batch sync data - push pending changes to server
  Future<bool> processBatchSyncData({
    required String token,
    required PostgresApiService api,
    int limit = 100,
  }) async {
    // Get the last pushed sequence to filter items correctly
    final lastPushedSeqRows = await (_db.select(_db.syncMeta)
          ..where((m) => m.key.equals('last_pushed_seq')))
        .get();
    final lastPushedSeq = lastPushedSeqRows.isNotEmpty
        ? int.tryParse(lastPushedSeqRows.first.value ?? '0') ?? 0
        : 0;

    debugPrint('processBatchSyncData: Last pushed seq = $lastPushedSeq');

    final pendingItems = await getPendingSyncItemsForBatch(
        limit: limit, lastPushedSeq: lastPushedSeq);
    if (pendingItems.isEmpty) {
      debugPrint('processBatchSyncData: No pending items to sync');
      return false;
    }

    debugPrint(
        'processBatchSyncData: Processing ${pendingItems.length} pending items');

    // Debug: Log all pending items
    for (final item in pendingItems) {
      debugPrint(
          'processBatchSyncData: Pending item: id=${item['id']}, client_seq=${item['client_seq']}, payload=${item['payload']}');
    }

    final changes = <Map<String, dynamic>>[];
    final validItems = <Map<String, dynamic>>[];
    
    for (final item in pendingItems) {
      final rawPayload = item['payload'] as String?;
      debugPrint(
          'processBatchSyncData: Raw payload for item ${item['id']}: $rawPayload');

      if (rawPayload == null || rawPayload.isEmpty) {
        debugPrint(
            'processBatchSyncData: Skipping item ${item['id']} - empty payload');
        continue;
      }

      final payload = jsonDecode(rawPayload) as Map<String, dynamic>;
      
      try {
        // Resolve foreign key mappings (e.g., local store_id -> server store_id)
        final resolvedPayload = await resolveBatchSyncData(
          item['table_name'] as String,
          item['row_id'] as int,
          payload,
        );
        
        final change = {
          'resource_type': resolvedPayload['resource_type'],
          'operation': resolvedPayload['operation'],
          if (resolvedPayload.containsKey('temp_id')) 'temp_id': resolvedPayload['temp_id'],
          if (resolvedPayload.containsKey('id')) 'id': resolvedPayload['id'],
          'data': resolvedPayload['data'] ?? {},
        };
        changes.add(change);
        validItems.add(item);
        debugPrint('processBatchSyncData: Converted change: $change');
      } catch (e) {
        debugPrint('processBatchSyncData: Failed to resolve item ${item['id']}: $e');
        // Mark this item as failed for retry later
        await _markQueueItemsFailed([item['id'] as int], e.toString());
        // Continue with other items
      }
    }

    debugPrint(
        'processBatchSyncData: Sending ${changes.length} changes to server');

    try {
      // Push changes to server
      debugPrint('processBatchSyncData: Calling api.pushChangesBatch...');
      final response = await api.pushChangesBatch(changes, token: token);
      debugPrint('processBatchSyncData: Push response: $response');
      debugPrint(
          'processBatchSyncData: Push successful, applied: ${response['applied']?.length ?? 0}, conflicts: ${response['conflicts']?.length ?? 0}');

      // Mark items as synced
      final queueIds = validItems.map((item) => item['id'] as int).toList();
      debugPrint(
          'processBatchSyncData: Marking ${queueIds.length} items as synced: $queueIds');
      await _markQueueItemsSynced(queueIds);

      // Update last pushed sequence
      final maxSeq = validItems
          .map((item) => item['client_seq'] as int? ?? 0)
          .reduce((a, b) => a > b ? a : b);
      debugPrint('processBatchSyncData: Updating last pushed seq to $maxSeq');
      await _updateLastPushedSeq(maxSeq);

      return true;
    } catch (e, stackTrace) {
      debugPrint('processBatchSyncData: Push failed: $e');
      debugPrint('processBatchSyncData: Stack trace: $stackTrace');
      // Mark successfully resolved items as failed for retry
      final queueIds = validItems.map((item) => item['id'] as int).toList();
      debugPrint(
          'processBatchSyncData: Marking ${queueIds.length} items as failed: $queueIds');
      await _markQueueItemsFailed(queueIds, e.toString());
      return false;
    }
  }

  /// Mark queue items as synced
  Future<void> _markQueueItemsSynced(List<int> queueIds) async {
    for (final id in queueIds) {
      await (_db.update(_db.syncQueue)..where((q) => q.id.equals(id)))
          .write(const SyncQueueCompanion(status: Value('synced')));
    }
  }

  /// Update the last pushed sequence
  Future<void> _updateLastPushedSeq(int seq) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: 'last_pushed_seq',
            value: Value(seq.toString()),
          ),
        );
  }

  /// Mark queue items as failed with error
  Future<void> _markQueueItemsFailed(List<int> queueIds, String error) async {
    for (final id in queueIds) {
      await (_db.update(_db.syncQueue)..where((q) => q.id.equals(id)))
          .write(SyncQueueCompanion(
        status: const Value('failed'),
        errorMessage: Value(error),
      ));
    }
  }
}
