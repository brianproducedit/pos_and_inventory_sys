import 'package:flutter_riverpod/flutter_riverpod.dart';
import './local/database_helper.dart';
import './remote/postgres_api_service.dart';
import './repositories/product_repository.dart';
import './repositories/transaction_repository.dart';
import './repositories/sync_repository.dart';
import '../domain/models/sync_error.dart';

final syncRepositoryProvider = Provider<SyncRepository>(
    (ref) => SyncRepository(db: ref.read(databaseHelperProvider)));

final syncErrorsProvider =
    FutureProvider.autoDispose<List<SyncError>>((ref) async {
  final repo = ref.read(syncRepositoryProvider);
  return repo.getErrors();
});

final databaseHelperProvider =
    Provider<DatabaseHelper>((ref) => DatabaseHelper());
final postgresApiServiceProvider =
    Provider<PostgresApiService>((ref) => PostgresApiService());

final productRepositoryProvider = Provider<ProductRepository>((ref) =>
    ProductRepository(
        db: ref.read(databaseHelperProvider),
        api: ref.read(postgresApiServiceProvider)));
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) =>
    TransactionRepositoryImpl(
        db: ref.read(databaseHelperProvider),
        api: ref.read(postgresApiServiceProvider)));
