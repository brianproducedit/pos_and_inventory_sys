import '../local/database_helper.dart';

class StoreRepository {
  final DatabaseHelper db;

  StoreRepository({required this.db});

  Future<int> addStore(
      {required String name, String? location, bool isActive = true}) async {
    return await db.insertStore(
        name: name, location: location, isActive: isActive);
  }

  Future<List<Map<String, dynamic>>> getAllStores() async {
    return await db.getAllStores();
  }

  Future<int> updateStore(int localStoreId, Map<String, dynamic> fields) async {
    return await db.updateStore(localStoreId, fields);
  }

  Future<int> deleteStore(int localStoreId) async {
    return await db.deleteStore(localStoreId);
  }
}
