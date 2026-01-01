import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/data/local/database_helper.dart';
import 'package:mobile/data/repositories/transaction_repository.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransactionRepository', () {
    late DatabaseHelper db;
    late TransactionRepository repo;

    setUp(() async {
      initSqfliteForTests();
      await DatabaseHelper.initTestDb();
      db = DatabaseHelper();
      repo = TransactionRepositoryImpl(db: db, api: null as dynamic);
    });

    tearDown(() async {
      try {
        final d = await db.database;
        await d.delete('sync_queue');
        await d.delete('transaction_items');
        await d.delete('transactions');
        await DatabaseHelper.resetTestDb();
      } catch (_) {}
    });

    test('addTransaction writes transaction and enqueues sync item', () async {
      final txId = await repo.addTransaction(
        transactionNumber: 'TX-001',
        totalAmount: 25.50,
        paymentMethod: 'cash',
        items: [
          {'product_id': 1, 'quantity': 1, 'price': 10.0},
          {'product_id': 2, 'quantity': 1, 'price': 15.5},
        ],
      );

      expect(txId, greaterThan(0));
      final d = await db.database;
      final txs =
          await d.query('transactions', where: 'id = ?', whereArgs: [txId]);
      expect(txs, isNotEmpty);

      final queue =
          await d.query('sync_queue', where: 'row_id = ?', whereArgs: [txId]);
      expect(queue, isNotEmpty);
      final q = queue.first;
      expect(q['table_name'], equals('transactions'));
      expect(q['action'], equals('CREATE'));
    });
  });
}
