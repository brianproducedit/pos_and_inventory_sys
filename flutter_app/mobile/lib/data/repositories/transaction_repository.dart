import 'package:flutter/foundation.dart';

import '../../data/local/database_helper.dart';
import '../../data/remote/postgres_api_service.dart';
import '../../domain/models/transaction.dart';

abstract class TransactionRepository {
  final DatabaseHelper db;
  final PostgresApiService? api;

  TransactionRepository({required this.db, this.api});

  Future<int> addTransaction({
    required String transactionNumber,
    required double totalAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
    int? storeId,
    int? userId,
  });

  Future<List<Transaction>> getAllTransactions({int? storeId});

  Future<Map<String, dynamic>?> getTransaction(int transactionId);
}

class TransactionRepositoryImpl implements TransactionRepository {
  @override
  final DatabaseHelper db;
  @override
  final PostgresApiService? api;

  TransactionRepositoryImpl({required this.db, this.api});

  @override
  Future<int> addTransaction({
    required String transactionNumber,
    required double totalAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
    int? storeId,
    int? userId,
  }) async {
    try {
      return await db.insertTransaction(
        transactionNumber: transactionNumber,
        totalAmount: totalAmount,
        paymentMethod: paymentMethod,
        items: items,
        storeId: storeId,
        userId: userId,
      );
    } catch (e) {
      // Handle database_closed exception gracefully
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database_closed') ||
          errorMessage.contains('database') &&
              errorMessage.contains('closed')) {
        debugPrint(
            'TransactionRepository.addTransaction: Database closed, returning -1');
        return -1; // Return -1 to indicate failure
      }
      rethrow;
    }
  }

  @override
  Future<List<Transaction>> getAllTransactions({int? storeId}) async {
    try {
      final dbClient = await db.database;

      // Filter by store_id if provided, otherwise return all (for admins in "All Stores" view)
      List<Map<String, dynamic>> rows;
      if (storeId != null && storeId > 0) {
        rows = await dbClient
            .query('transactions', where: 'store_id = ?', whereArgs: [storeId]);
      } else {
        rows = await dbClient.query('transactions');
      }

      return rows.map((row) => Transaction.fromMap(row)).toList();
    } catch (e) {
      // Handle database_closed exception gracefully
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database_closed') ||
          errorMessage.contains('database') &&
              errorMessage.contains('closed')) {
        debugPrint(
            'TransactionRepository.getAllTransactions: Database closed, returning empty list');
        return [];
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> getTransaction(int transactionId) async {
    try {
      final dbClient = await db.database;

      // Get transaction
      final txRows = await dbClient.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );

      if (txRows.isEmpty) return null;

      final transaction = txRows.first;

      // Get transaction items with product names
      final itemRows = await dbClient.rawQuery('''
      SELECT ti.*, p.name as product_name, p.sku
      FROM transaction_items ti
      LEFT JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''', [transactionId]);

      // Convert to receipt format
      final items = itemRows
          .map((item) => {
                'product_name': item['product_name'] ?? 'Unknown Product',
                'quantity': item['quantity'],
                'unit_price': item['price'],
                'product_id': item['product_id'],
              })
          .toList();

      // Get current store info
      final storeRows = await dbClient.query('stores', limit: 1);
      final store = storeRows.isNotEmpty
          ? {
              'id': storeRows.first['id'],
              'name': storeRows.first['name'] ?? 'Store',
              'location': storeRows.first['location'] ?? '',
            }
          : null;

      // Get current user info
      final userRows = await dbClient.query('users', limit: 1);
      final cashier = userRows.isNotEmpty
          ? {
              'id': userRows.first['server_id'],
              'username': userRows.first['email'] ?? 'Unknown',
              'full_name': userRows.first['name'] ?? 'Unknown Cashier',
            }
          : null;

      return {
        'id': transaction['id'],
        'sale_id': transaction['id'], // For compatibility
        'transaction_number': transaction['transaction_number'],
        'total_amount': transaction['total_amount'],
        'payment_method': transaction['payment_method'],
        'created_at': DateTime.fromMillisecondsSinceEpoch(
                transaction['created_at'] as int)
            .toIso8601String(),
        'items': items,
        'store': store,
        'cashier': cashier,
        'is_offline': true, // Mark as offline-generated
      };
    } catch (e) {
      // Handle database_closed exception gracefully
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('database_closed') ||
          errorMessage.contains('database') &&
              errorMessage.contains('closed')) {
        debugPrint(
            'TransactionRepository.getTransaction: Database closed, returning null');
        return null;
      }
      rethrow;
    }
  }
}
