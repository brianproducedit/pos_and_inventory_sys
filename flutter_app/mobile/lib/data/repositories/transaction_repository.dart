import '../../data/local/database_helper.dart';
import '../../data/remote/postgres_api_service.dart';
import '../../domain/models/transaction.dart';

class TransactionRepository {
  final DatabaseHelper db;
  final PostgresApiService? api;

  TransactionRepository({required this.db, this.api});

  Future<int> addTransaction({
    required String transactionNumber,
    required double totalAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
  }) async {
    return await db.insertTransaction(
      transactionNumber: transactionNumber,
      totalAmount: totalAmount,
      paymentMethod: paymentMethod,
      items: items,
    );
  }

  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final dbClient = await db.database;
    final rows = await dbClient.query('transactions');
    return rows;
  }
}
