import 'package:mobile/services/time_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:mobile/models/database_models.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'pos_inventory.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE stores(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        location TEXT,
        created_by INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        store_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        stock_quantity INTEGER DEFAULT 0,
        store_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL,
        store_id INTEGER NOT NULL,
        total_amount REAL NOT NULL,
        payment_method TEXT,
        paynow_reference TEXT,
        status TEXT DEFAULT 'completed',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory_logs(
        id INTEGER PRIMARY KEY,
        product_id INTEGER NOT NULL,
        quantity_change INTEGER NOT NULL,
        reason TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  // CRUD methods for each model
  Future<List<Product>> getProducts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('products');
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  Future<void> insertProduct(Product product) async {
    final db = await database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSampleData() async {
    final db = await database;
    // Insert sample store
    await db.insert('stores', {
      'id': 1,
      'name': 'Main Store',
      'location': 'Harare',
      'created_by': 1,
      'created_at': TimeService.instance.nowIsoString(),
      'updated_at': TimeService.instance.nowIsoString(),
    });

    // Insert sample user
    await db.insert('users', {
      'id': 1,
      'username': 'admin',
      'password_hash': 'hashed_password', // In real app, hash properly
      'role': 'superadmin',
      'store_id': 1,
      'created_at': TimeService.instance.nowIsoString(),
      'updated_at': TimeService.instance.nowIsoString(),
    });

    // Insert sample products
    final products = [
      Product(
          id: 1,
          name: 'Bread',
          description: 'Fresh white bread',
          price: 2.50,
          stockQuantity: 50,
          storeId: 1,
          createdAt: TimeService.instance.now(),
          updatedAt: TimeService.instance.now()),
      Product(
          id: 2,
          name: 'Milk',
          description: 'Fresh cow milk',
          price: 1.20,
          stockQuantity: 30,
          storeId: 1,
          createdAt: TimeService.instance.now(),
          updatedAt: TimeService.instance.now()),
      Product(
          id: 3,
          name: 'Eggs',
          description: 'Dozen eggs',
          price: 3.00,
          stockQuantity: 20,
          storeId: 1,
          createdAt: TimeService.instance.now(),
          updatedAt: TimeService.instance.now()),
      Product(
          id: 4,
          name: 'Sugar',
          description: 'White sugar 1kg',
          price: 2.00,
          stockQuantity: 40,
          storeId: 1,
          createdAt: TimeService.instance.now(),
          updatedAt: TimeService.instance.now()),
      Product(
          id: 5,
          name: 'Rice',
          description: 'Long grain rice 1kg',
          price: 4.50,
          stockQuantity: 25,
          storeId: 1,
          createdAt: TimeService.instance.now(),
          updatedAt: TimeService.instance.now()),
    ];

    for (final product in products) {
      await db.insert('products', product.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // Add more methods as needed
}
