import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../db/app_database.dart';
import '../data/remote/api_client.dart';
import '../models/sync_conflict.dart' as models;

/// Background sync worker - handles pushing and pulling changes
/// NOTE: This worker runs in background isolates (WorkManager) which have
/// separate memory from the main app. The static lock below only prevents
/// concurrent syncs within the same isolate. Database-level protection
/// (WAL mode + busy_timeout) handles cross-isolate concurrency.
class SyncWorker {
  final AppDatabase db;
  final ApiClient apiClient;
  final FlutterSecureStorage secureStorage;
  final models.ConflictManager conflictManager;

  /// Static lock to prevent concurrent sync operations within this isolate.
  /// Note: This lock is NOT shared with the main app's PostgresSyncService
  /// because they run in different isolates. Database-level WAL mode and
  /// busy_timeout provide cross-isolate concurrency protection.
  static bool _isSyncing = false;
  static DateTime? _lockAcquiredAt;

  SyncWorker({
    required this.db,
    required this.apiClient,
    FlutterSecureStorage? storage,
    models.ConflictManager? conflictManager,
  })  : secureStorage = storage ?? const FlutterSecureStorage(),
        conflictManager = conflictManager ?? models.ConflictManager();

  /// Execute database operations with automatic retry on database_closed errors
  Future<R> _withDatabaseRetry<R>(Future<R> Function() operation) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        return await operation();
      } on DriftWrappedException catch (e) {
        if (e.toString().contains('database_closed') &&
            retryCount < maxRetries - 1) {
          retryCount++;
          debugPrint(
              '🔁 SyncWorker: Database closed error (attempt $retryCount/$maxRetries), retrying...');
          // Wait a bit before retrying
          await Future.delayed(Duration(milliseconds: 100 * retryCount));
          // Force database reconnection by closing and reopening
          try {
            await db.close();
            // The database will be reopened on next access
          } catch (closeError) {
            debugPrint(
                '⚠️ SyncWorker: Error closing DB during retry: $closeError');
          }
          continue;
        }
        rethrow;
      } catch (e) {
        // For non-database errors, don't retry
        rethrow;
      }
    }

    throw Exception(
        'Failed to execute database operation after $maxRetries attempts');
  }

  /// Check if sync is in progress
  static bool get isSyncing => _isSyncing;

  /// Trigger a sync operation
  Future<void> triggerSync() async {
    if (_isSyncing) {
      final lockInfo =
          _lockAcquiredAt != null ? ' (locked since $_lockAcquiredAt)' : '';
      debugPrint('SyncWorker: Sync already in progress$lockInfo, skipping');
      return;
    }

    _isSyncing = true;
    _lockAcquiredAt = DateTime.now();
    debugPrint(
        'SyncWorker: Starting sync (lock acquired at $_lockAcquiredAt)...');

    try {
      // 1. Push local changes to server
      await _pushChanges();

      // 2. Pull server changes
      await _pullChanges();

      debugPrint('SyncWorker: Sync completed successfully');
    } catch (e) {
      debugPrint('SyncWorker: Sync failed: $e');
    } finally {
      final duration = _lockAcquiredAt != null
          ? DateTime.now().difference(_lockAcquiredAt!).inMilliseconds
          : 0;
      debugPrint('SyncWorker: Releasing lock (held for ${duration}ms)');
      _isSyncing = false;
      _lockAcquiredAt = null;
    }
  }

  /// Pull changes from server and apply to local database
  Future<void> _pullChanges() async {
    return await _withDatabaseRetry(() async {
      debugPrint('SyncWorker: Pulling changes from server...');

      final token = await secureStorage.read(key: 'access_token');
      if (token == null) {
        debugPrint('SyncWorker: No auth token, skipping pull');
        return;
      }

      try {
        // Get last sync timestamp from metadata
        final lastSyncMeta = await (db.select(db.syncMeta)
              ..where((m) => m.key.equals('last_pull_sync')))
            .getSingleOrNull();

        DateTime? lastSyncTime;
        if (lastSyncMeta != null && lastSyncMeta.value != null) {
          lastSyncTime = DateTime.parse(lastSyncMeta.value!);
        }

        // Fetch changes from server
        final response = await apiClient.pullChanges(
          token: token,
          lastSyncTime: lastSyncTime,
        );

        final changes = response['changes'] as List<dynamic>?;
        if (changes == null || changes.isEmpty) {
          debugPrint('SyncWorker: No server changes to pull');
          return;
        }

        debugPrint('SyncWorker: Pulling ${changes.length} changes from server');

        // Apply changes to local database
        for (final change in changes) {
          final changeMap = change as Map<String, dynamic>;
          await _applyServerChange(changeMap);
        }

        // Update last sync timestamp
        final now = DateTime.now();
        await db.into(db.syncMeta).insertOnConflictUpdate(
              SyncMetaCompanion.insert(
                key: 'last_pull_sync',
                value: Value(now.toIso8601String()),
              ),
            );

        debugPrint(
            'SyncWorker: Successfully pulled and applied server changes');
      } catch (e) {
        debugPrint('SyncWorker: Failed to pull changes: $e');
        rethrow;
      }
    });
  }

  /// Apply a single change from server to local database
  Future<void> _applyServerChange(Map<String, dynamic> change) async {
    final resourceType = change['resource_type'] as String?;
    final operation = change['operation'] as String?;
    final data = change['data'] as Map<String, dynamic>?;

    if (resourceType == null || operation == null || data == null) {
      debugPrint('SyncWorker: Invalid change format, skipping');
      return;
    }

    debugPrint('SyncWorker: Applying $operation on $resourceType');

    try {
      switch (resourceType) {
        case 'user':
          await _applyUserChange(operation, data);
          break;
        case 'product':
          await _applyProductChange(operation, data);
          break;
        case 'sale':
          await _applySaleChange(operation, data);
          break;
        case 'store':
          await _applyStoreChange(operation, data);
          break;
        default:
          debugPrint('SyncWorker: Unknown resource type: $resourceType');
      }
    } catch (e) {
      debugPrint('SyncWorker: Failed to apply change: $e');
      // Continue with other changes even if one fails
    }
  }

  /// Apply user change from server
  Future<void> _applyUserChange(
      String operation, Map<String, dynamic> data) async {
    final serverId = data['id'] as int?;
    if (serverId == null) return;

    if (operation == 'delete') {
      // Delete user by server ID
      await (db.delete(db.users)..where((u) => u.serverId.equals(serverId)))
          .go();
      return;
    }

    // Check if user already exists locally
    final existingUser = await (db.select(db.users)
          ..where((u) => u.serverId.equals(serverId)))
        .getSingleOrNull();

    final serverUpdatedAt =
        DateTime.tryParse(data['updated_at'] as String? ?? '');

    if (existingUser != null) {
      // Check for conflicts
      if (existingUser.syncStatus == SyncStatus.pending) {
        debugPrint(
            'SyncWorker: Conflict detected for user $serverId - local changes pending');

        // Create conflict record for manual resolution
        final conflict = models.SyncConflict(
          resourceType: 'user',
          localId: existingUser.id,
          serverId: serverId,
          clientId: existingUser.clientId,
          localData: {
            'username': existingUser.username,
            'full_name': existingUser.fullName,
            'role': existingUser.role,
            'store_id': existingUser.storeId,
            'is_active': existingUser.isActive,
          },
          serverData: data,
          localUpdatedAt: existingUser.lastUpdatedAt,
          serverUpdatedAt: serverUpdatedAt ?? DateTime.now(),
          detectedAt: DateTime.now(),
        );

        conflictManager.addConflict(conflict);

        // Mark as conflict in database
        await (db.update(db.users)..where((u) => u.id.equals(existingUser.id)))
            .write(const UsersCompanion(
          syncStatus: Value(SyncStatus.conflict),
        ));
        return;
      }

      // Update existing user if server version is newer
      if (serverUpdatedAt != null &&
          serverUpdatedAt.isAfter(existingUser.lastUpdatedAt)) {
        await (db.update(db.users)..where((u) => u.id.equals(existingUser.id)))
            .write(UsersCompanion(
          username: Value(data['username'] as String),
          fullName: Value(data['full_name'] as String? ?? ''),
          role: Value(_parseUserRole(data['role'] as String)),
          storeId: Value(data['store_id'] as int?),
          isActive: Value(data['is_active'] as bool? ?? true),
          passwordHash: data['password_hash'] != null
              ? Value(data['password_hash'] as String)
              : const Value.absent(),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(serverUpdatedAt),
        ));
      }
    } else {
      // Insert new user from server
      await db.into(db.users).insert(
            UsersCompanion.insert(
              serverId: Value(serverId),
              clientId: Value(data['client_id'] as String? ?? ''),
              username: data['username'] as String,
              fullName: Value(data['full_name'] as String?),
              role: _parseUserRole(data['role'] as String),
              storeId: Value(data['store_id'] as int?),
              isActive: Value(data['is_active'] as bool? ?? true),
              passwordHash: data['password_hash'] as String? ?? '',
              syncStatus: const Value(SyncStatus.synced),
              isLocalOnly: const Value(false),
              lastUpdatedAt: Value(serverUpdatedAt ?? DateTime.now()),
            ),
          );
    }
  }

  /// Apply product change from server
  Future<void> _applyProductChange(
      String operation, Map<String, dynamic> data) async {
    final serverId = data['id'] as int?;
    if (serverId == null) return;

    if (operation == 'delete') {
      await (db.delete(db.products)..where((p) => p.serverId.equals(serverId)))
          .go();
      return;
    }

    final existingProduct = await (db.select(db.products)
          ..where((p) => p.serverId.equals(serverId)))
        .getSingleOrNull();

    final serverUpdatedAt =
        DateTime.tryParse(data['updated_at'] as String? ?? '');

    if (existingProduct != null) {
      if (existingProduct.syncStatus == SyncStatus.pending) {
        debugPrint('SyncWorker: Conflict detected for product $serverId');

        // Create conflict record
        final conflict = models.SyncConflict(
          resourceType: 'product',
          localId: existingProduct.id,
          serverId: serverId,
          clientId: existingProduct.clientId,
          localData: {
            'name': existingProduct.name,
            'sku': existingProduct.sku,
            'description': existingProduct.description,
            'price': existingProduct.price,
            'stock_quantity': existingProduct.stockQuantity,
          },
          serverData: data,
          localUpdatedAt: existingProduct.lastUpdatedAt,
          serverUpdatedAt: serverUpdatedAt ?? DateTime.now(),
          detectedAt: DateTime.now(),
        );

        conflictManager.addConflict(conflict);

        await (db.update(db.products)
              ..where((p) => p.id.equals(existingProduct.id)))
            .write(const ProductsCompanion(
                syncStatus: Value(SyncStatus.conflict)));
        return;
      }

      if (serverUpdatedAt != null &&
          serverUpdatedAt.isAfter(existingProduct.lastUpdatedAt)) {
        await (db.update(db.products)
              ..where((p) => p.id.equals(existingProduct.id)))
            .write(ProductsCompanion(
          name: Value(data['name'] as String),
          sku: Value(data['sku'] as String?),
          description: Value(data['description'] as String?),
          price: Value(data['price'] as double? ?? 0.0),
          stockQuantity: Value(data['stock_quantity'] as int? ?? 0),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(serverUpdatedAt),
        ));
      }
    } else {
      // Before inserting, check if a product with same name and store already exists
      // This handles cases where raw SQL inserts are not visible to Drift
      final name = data['name'] as String;
      final storeId = data['store_id'] as int;
      final existingByName = await (db.select(db.products)
            ..where((p) => p.name.equals(name))
            ..where((p) => p.storeId.equals(storeId)))
          .getSingleOrNull();

      if (existingByName != null) {
        // Update existing product instead of creating duplicate
        await (db.update(db.products)
              ..where((p) => p.id.equals(existingByName.id)))
            .write(ProductsCompanion(
          serverId: Value(serverId),
          clientId: Value(data['client_id'] as String? ?? ''),
          name: Value(name),
          sku: Value(data['sku'] as String?),
          description: Value(data['description'] as String?),
          price: Value(data['price'] as double? ?? 0.0),
          stockQuantity: Value(data['stock_quantity'] as int? ?? 0),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(serverUpdatedAt ?? DateTime.now()),
        ));
      } else {
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                serverId: Value(serverId),
                clientId: Value(data['client_id'] as String? ?? ''),
                name: data['name'] as String,
                sku: Value(data['sku'] as String?),
                description: Value(data['description'] as String?),
                price: Value(data['price'] as double? ?? 0.0),
                stockQuantity: Value(data['stock_quantity'] as int? ?? 0),
                storeId: data['store_id'] as int,
                syncStatus: const Value(SyncStatus.synced),
                lastUpdatedAt: Value(serverUpdatedAt ?? DateTime.now()),
              ),
            );
      }
    }
  }

  /// Apply sale change from server
  Future<void> _applySaleChange(
      String operation, Map<String, dynamic> data) async {
    final serverId = data['id'] as int?;
    if (serverId == null) return;

    if (operation == 'delete') {
      await (db.delete(db.sales)..where((s) => s.serverId.equals(serverId)))
          .go();
      return;
    }

    final existingSale = await (db.select(db.sales)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();

    if (existingSale == null) {
      // Insert new sale from server
      final serverUpdatedAt =
          DateTime.tryParse(data['updated_at'] as String? ?? '') ??
              DateTime.now();

      await db.into(db.sales).insert(
            SalesCompanion.insert(
              serverId: Value(serverId),
              clientId: Value(data['client_id'] as String? ?? ''),
              transactionNumber: data['transaction_number'] as String,
              totalAmount: data['total_amount'] as double? ?? 0.0,
              paymentMethod: data['payment_method'] as String? ?? 'cash',
              userId: data['user_id'] as int,
              storeId: data['store_id'] as int,
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(serverUpdatedAt),
            ),
          );
    }
  }

  /// Apply store change from server
  Future<void> _applyStoreChange(
      String operation, Map<String, dynamic> data) async {
    final serverId = data['id'] as int?;
    if (serverId == null) return;

    if (operation == 'delete') {
      await (db.delete(db.stores)..where((s) => s.serverId.equals(serverId)))
          .go();
      return;
    }

    final existingStore = await (db.select(db.stores)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();

    final serverUpdatedAt =
        DateTime.tryParse(data['updated_at'] as String? ?? '');

    if (existingStore != null) {
      if (serverUpdatedAt != null &&
          serverUpdatedAt.isAfter(existingStore.lastUpdatedAt)) {
        await (db.update(db.stores)
              ..where((s) => s.id.equals(existingStore.id)))
            .write(StoresCompanion(
          name: Value(data['name'] as String),
          location: Value(data['location'] as String?),
          isActive: Value(data['is_active'] as bool? ?? true),
          syncStatus: const Value(SyncStatus.synced),
          lastUpdatedAt: Value(serverUpdatedAt),
        ));
      }
    } else {
      await db.into(db.stores).insert(
            StoresCompanion.insert(
              serverId: Value(serverId),
              clientId: Value(data['client_id'] as String? ?? ''),
              name: data['name'] as String,
              location: Value(data['location'] as String?),
              isActive: Value(data['is_active'] as bool? ?? true),
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(serverUpdatedAt ?? DateTime.now()),
            ),
          );
    }
  }

  /// Push pending local changes to server
  /// Push local changes to server
  Future<void> _pushChanges() async {
    return await _withDatabaseRetry(() async {
      // Get pending items from sync queue, respecting exponential backoff
      final now = DateTime.now();

      // Get all pending items
      final allPendingItems = await (db.select(db.syncQueue)
            ..where((q) => q.status.equals('pending'))
            ..orderBy([(q) => OrderingTerm.asc(q.createdAt)])
            ..limit(100))
          .get();

      if (allPendingItems.isEmpty) {
        debugPrint('SyncWorker: No pending changes to push');
        return;
      }

      // Filter out items that are in exponential backoff period
      final pendingItems = <SyncQueueData>[];
      for (final item in allPendingItems) {
        // Check if this item has a retry schedule
        final retryMeta = await (db.select(db.syncMeta)
              ..where((m) => m.key.equals('next_retry_${item.id}')))
            .getSingleOrNull();

        if (retryMeta != null) {
          final nextRetryTime = DateTime.parse(retryMeta.value!);
          if (now.isBefore(nextRetryTime)) {
            // Still in backoff period, skip for now
            debugPrint('SyncWorker: Item ${item.id} in backoff, skipping until '
                '${nextRetryTime.toLocal()}');
            continue;
          } else {
            // Backoff period expired, remove the metadata
            await (db.delete(db.syncMeta)
                  ..where((m) => m.key.equals('next_retry_${item.id}')))
                .go();
          }
        }

        pendingItems.add(item);
      }

      if (pendingItems.isEmpty) {
        debugPrint('SyncWorker: All pending items are in backoff period');
        return;
      }

      debugPrint('SyncWorker: Pushing ${pendingItems.length} changes...');

      for (final item in pendingItems) {
        try {
          await _processSyncItem(item);
        } catch (e) {
          debugPrint('SyncWorker: Failed to sync item ${item.id}: $e');
          // Update retry count with exponential backoff
          await _markSyncItemFailed(item, e.toString());
        }
      }
    });
  }

  /// Process a single sync queue item
  Future<void> _processSyncItem(SyncQueueData item) async {
    return await _withDatabaseRetry(() async {
      // Mark as processing
      await (db.update(db.syncQueue)..where((q) => q.id.equals(item.id)))
          .write(SyncQueueCompanion(
        status: const Value('processing'),
        lastAttemptAt: Value(DateTime.now()),
      ));

      final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;

      switch (item.resourceType) {
        case 'user':
          await _syncUser(item, payload);
          break;
        case 'product':
          await _syncProduct(item, payload);
          break;
        case 'sale':
          await _syncSale(item, payload);
          break;
        case 'store':
          await _syncStore(item, payload);
          break;
        default:
          throw UnsupportedError('Unknown resource type: ${item.resourceType}');
      }

      // Mark as completed and remove from queue
      await (db.delete(db.syncQueue)..where((q) => q.id.equals(item.id))).go();
    });
  }

  /// Sync user changes
  Future<void> _syncUser(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing user: ${item.operation}');

    // Get auth token
    final token = await secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('No auth token available for sync');
    }

    if (item.operation == 'create') {
      // Create user on server
      if (item.clientTempId != null) {
        final localUser = await (db.select(db.users)
              ..where((u) => u.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localUser != null) {
          try {
            // Send user data to server
            final serverUser = await apiClient.createUser(
              token: token,
              userData: payload,
            );

            // Update local user with server ID
            await (db.update(db.users)..where((u) => u.id.equals(localUser.id)))
                .write(UsersCompanion(
              serverId: Value(serverUser['id'] as int),
              syncStatus: const Value(SyncStatus.synced),
              isLocalOnly: const Value(false),
              lastUpdatedAt: Value(DateTime.now()),
            ));

            print(
                'SyncWorker: User created on server, id: ${serverUser['id']}');
          } catch (e) {
            print('SyncWorker: Failed to create user on server: $e');
            rethrow;
          }
        }
      }
    } else if (item.operation == 'update') {
      // Update existing user on server
      final userId = payload['id'] as int?;
      if (userId != null) {
        try {
          // Check if it's a password change
          if (payload['action'] == 'change_password') {
            // Handle password change - remove action field before sending
            final updateData = Map<String, dynamic>.from(payload);
            updateData.remove('action');
            updateData.remove('id');
            updateData.remove('client_id');

            await apiClient.updateUser(
              token: token,
              userId: userId,
              userData: updateData,
            );
          } else {
            // Regular user update
            final updateData = Map<String, dynamic>.from(payload);
            updateData.remove('id');
            updateData.remove('client_id');

            await apiClient.updateUser(
              token: token,
              userId: userId,
              userData: updateData,
            );
          }

          // Update local sync status
          final localUser = await (db.select(db.users)
                ..where((u) => u.serverId.equals(userId)))
              .getSingleOrNull();

          if (localUser != null) {
            await (db.update(db.users)..where((u) => u.id.equals(localUser.id)))
                .write(UsersCompanion(
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));
          }

          print('SyncWorker: User updated on server, id: $userId');
        } catch (e) {
          print('SyncWorker: Failed to update user on server: $e');
          rethrow;
        }
      }
    }
  }

  /// Sync product changes
  Future<void> _syncProduct(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing product: ${item.operation}');

    final token = await secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('No auth token available for sync');
    }

    if (item.operation == 'create') {
      // Create product on server
      if (item.clientTempId != null) {
        final localProduct = await (db.select(db.products)
              ..where((p) => p.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localProduct != null) {
          try {
            final serverProduct = await apiClient.createProduct(
              token: token,
              productData: payload,
            );

            await (db.update(db.products)
                  ..where((p) => p.id.equals(localProduct.id)))
                .write(ProductsCompanion(
              serverId: Value(serverProduct['id'] as int),
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));

            print(
                'SyncWorker: Product created on server, id: ${serverProduct['id']}');
          } catch (e) {
            print('SyncWorker: Failed to create product on server: $e');
            rethrow;
          }
        }
      }
    } else if (item.operation == 'update') {
      // Update product on server
      final productId = payload['id'] as int?;
      if (productId != null) {
        try {
          final updateData = Map<String, dynamic>.from(payload);
          updateData.remove('id');
          updateData.remove('client_id');

          await apiClient.updateProduct(
            token: token,
            productId: productId,
            productData: updateData,
          );

          final localProduct = await (db.select(db.products)
                ..where((p) => p.serverId.equals(productId)))
              .getSingleOrNull();

          if (localProduct != null) {
            await (db.update(db.products)
                  ..where((p) => p.id.equals(localProduct.id)))
                .write(ProductsCompanion(
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));
          }

          print('SyncWorker: Product updated on server, id: $productId');
        } catch (e) {
          print('SyncWorker: Failed to update product on server: $e');
          rethrow;
        }
      }
    }
  }

  /// Sync sale changes
  Future<void> _syncSale(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing sale: ${item.operation}');

    final token = await secureStorage.read(key: 'access_token');
    if (token == null) {
      throw Exception('No auth token available for sync');
    }

    if (item.operation == 'create') {
      // Create sale on server
      if (item.clientTempId != null) {
        final localSale = await (db.select(db.sales)
              ..where((s) => s.clientId.equals(item.clientTempId!)))
            .getSingleOrNull();

        if (localSale != null) {
          try {
            final serverSale = await apiClient.createSale(
              token: token,
              saleData: payload,
            );

            // Update sale with server ID
            await (db.update(db.sales)..where((s) => s.id.equals(localSale.id)))
                .write(SalesCompanion(
              serverId: Value(serverSale['id'] as int),
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));

            // Update sale items sync status
            final saleItems = await (db.select(db.saleItems)
                  ..where((si) => si.saleId.equals(localSale.id)))
                .get();

            for (final saleItem in saleItems) {
              await (db.update(db.saleItems)
                    ..where((si) => si.id.equals(saleItem.id)))
                  .write(const SaleItemsCompanion(
                syncStatus: Value(SyncStatus.synced),
              ));
            }

            print(
                'SyncWorker: Sale created on server, id: ${serverSale['id']}');
          } catch (e) {
            print('SyncWorker: Failed to create sale on server: $e');
            rethrow;
          }
        }
      }
    }
  }

  /// Sync store changes
  Future<void> _syncStore(
      SyncQueueData item, Map<String, dynamic> payload) async {
    print('SyncWorker: Syncing store: ${item.operation}');

    // Phase 3 store sync is backend-dependent. Implement a safe no-op handler
    // that applies server-provided IDs locally when present and otherwise
    // defers authoritative changes to the server-side sync implementation.
    try {
      final op = item.operation;

      if (op == 'create') {
        // If server returned an id in the payload (id or server_id), apply it locally
        final serverId = payload['id'] as int? ?? payload['server_id'] as int?;
        if (serverId != null && item.clientTempId != null) {
          final localStore = await (db.select(db.stores)
                ..where((s) => s.clientId.equals(item.clientTempId!)))
              .getSingleOrNull();
          if (localStore != null) {
            await (db.update(db.stores)
                  ..where((s) => s.id.equals(localStore.id)))
                .write(StoresCompanion(
              serverId: Value(serverId),
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));
            print(
                'SyncWorker: Applied server id $serverId to local store ${localStore.id}');
          }
        }
      } else if (op == 'update') {
        // If update includes server id, mark store as synced locally
        final serverId = payload['id'] as int? ?? payload['server_id'] as int?;
        if (serverId != null) {
          final localStore = await (db.select(db.stores)
                ..where((s) => s.serverId.equals(serverId)))
              .getSingleOrNull();
          if (localStore != null) {
            await (db.update(db.stores)
                  ..where((s) => s.id.equals(localStore.id)))
                .write(StoresCompanion(
              syncStatus: const Value(SyncStatus.synced),
              lastUpdatedAt: Value(DateTime.now()),
            ));
            print(
                'SyncWorker: Marked local store ${localStore.id} as synced for server id $serverId');
          }
        }
      } else if (op == 'delete') {
        // Hard delete may be represented by payload.local_id or payload.id
        final localId = payload['local_id'] as int? ?? payload['id'] as int?;
        if (localId != null) {
          await (db.delete(db.stores)..where((s) => s.id.equals(localId))).go();
          print(
              'SyncWorker: Deleted local store id $localId as per server delete');
        }
      }

      // No exception -> processed successfully (queue removal handled by caller)
    } catch (e) {
      print('SyncWorker: Failed to process store sync item: $e');
      rethrow;
    }
  }

  /// Mark sync item as failed with exponential backoff
  Future<void> _markSyncItemFailed(SyncQueueData item, String error) async {
    return await _withDatabaseRetry(() async {
      final newRetryCount = item.retryCount + 1;
      const maxRetries = 5;

      // Calculate exponential backoff delay
      // Base delay: 30 seconds, doubled for each retry
      // Retry 1: 30s, Retry 2: 60s, Retry 3: 120s, Retry 4: 240s, Retry 5: 480s
      const baseDelaySeconds = 30;
      final backoffMultiplier = 1 << (newRetryCount - 1); // 2^(retry-1)
      final delaySeconds = baseDelaySeconds * backoffMultiplier;
      final nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds));

      final newStatus = newRetryCount >= maxRetries ? 'failed' : 'pending';

      await (db.update(db.syncQueue)..where((q) => q.id.equals(item.id)))
          .write(SyncQueueCompanion(
        retryCount: Value(newRetryCount),
        lastAttemptAt: Value(DateTime.now()),
        status: Value(newStatus),
        errorMessage: Value(error),
      ));

      if (newStatus == 'failed') {
        print('SyncWorker: Item ${item.id} marked as permanently failed after '
            '$newRetryCount attempts');
      } else {
        // Store next retry time in metadata for exponential backoff
        await db.into(db.syncMeta).insertOnConflictUpdate(
              SyncMetaCompanion.insert(
                key: 'next_retry_${item.id}',
                value: Value(nextRetryAt.toIso8601String()),
              ),
            );

        print('SyncWorker: Item ${item.id} will retry in ${delaySeconds}s '
            '(attempt $newRetryCount of $maxRetries, error: $error)');
      }
    });
  }

  /// Get sync queue status
  Future<SyncQueueStatus> getQueueStatus() async {
    return await _withDatabaseRetry(() async {
      final pending = await (db.select(db.syncQueue)
            ..where((q) => q.status.equals('pending')))
          .get();

      final processing = await (db.select(db.syncQueue)
            ..where((q) => q.status.equals('processing')))
          .get();

      final failed = await (db.select(db.syncQueue)
            ..where((q) => q.status.equals('failed')))
          .get();

      return SyncQueueStatus(
        pendingCount: pending.length,
        processingCount: processing.length,
        failedCount: failed.length,
      );
    });
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    return await _withDatabaseRetry(() async {
      final lastItem = await (db.select(db.syncQueue)
            ..orderBy([(q) => OrderingTerm.desc(q.lastAttemptAt)])
            ..limit(1))
          .getSingleOrNull();

      return lastItem?.lastAttemptAt;
    });
  }
}

/// Sync queue status information
class SyncQueueStatus {
  final int pendingCount;
  final int processingCount;
  final int failedCount;

  SyncQueueStatus({
    required this.pendingCount,
    required this.processingCount,
    required this.failedCount,
  });

  bool get hasPending => pendingCount > 0;
  bool get hasFailures => failedCount > 0;
  bool get isSyncing => processingCount > 0;
  int get totalUnsynced => pendingCount + failedCount;
}

/// Helper function to parse UserRole from string
UserRole _parseUserRole(String role) {
  switch (role.toLowerCase()) {
    case 'admin':
      return UserRole.admin;
    case 'cashier':
      return UserRole.cashier;
    default:
      return UserRole.cashier; // Default to cashier for unknown roles
  }
}
