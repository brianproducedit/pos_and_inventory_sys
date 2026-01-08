import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import './remote/postgres_api_service.dart';
import './repositories/sync_repository.dart';
import './sync/sync_database_helper.dart';
import '../domain/models/sync_error.dart';

// App database provider (single Drift database)
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

// Sync database helper wraps AppDatabase for sync operations
final syncDatabaseHelperProvider = Provider<SyncDatabaseHelper>(
    (ref) => SyncDatabaseHelper(ref.read(appDatabaseProvider)));

final syncRepositoryProvider = Provider<SyncRepository>(
    (ref) => SyncRepository(dbHelper: ref.read(syncDatabaseHelperProvider)));

final syncErrorsProvider =
    FutureProvider.autoDispose<List<SyncError>>((ref) async {
  final repo = ref.read(syncRepositoryProvider);
  return repo.getErrors();
});

final postgresApiServiceProvider =
    Provider<PostgresApiService>((ref) => PostgresApiService());

// V1 repositories removed - using V2 providers in main.dart instead
