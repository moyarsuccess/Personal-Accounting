import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_accounting/models/category.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/models/merchant.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;
  static const String dbName = 'personal_accounting.db';

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        name TEXT,
        iconCode TEXT,
        colorCode INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE merchants(
        id TEXT PRIMARY KEY,
        name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE costs(
        id TEXT PRIMARY KEY,
        amount REAL,
        date TEXT,
        categoryId TEXT,
        merchantId TEXT,
        FOREIGN KEY (categoryId) REFERENCES categories (id),
        FOREIGN KEY (merchantId) REFERENCES merchants (id)
      )
    ''');

    // Insert Default Categories
    await _insertInitialCategories(db);
  }

  Future<void> _insertInitialCategories(Database db) async {
    final initialCategories = [
      Category(id: 'cat_groceries', name: 'Groceries', iconCode: 'shopping_cart', colorCode: 0xFF4CAF50),
      Category(id: 'cat_transport', name: 'Transport', iconCode: 'directions_car', colorCode: 0xFF2196F3),
      Category(id: 'cat_entertainment', name: 'Entertainment', iconCode: 'movie', colorCode: 0xFF9C27B0),
      Category(id: 'cat_bills', name: 'Bills', iconCode: 'receipt', colorCode: 0xFFF44336),
    ];
    for (var category in initialCategories) {
      await db.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // Categories
  Future<List<Category>> getCategories() async {
    final database = await db;
    final maps = await database.query('categories');
    return maps.map((map) => Category.fromMap(map)).toList();
  }

  Future<void> insertCategory(Category category) async {
    final database = await db;
    await database.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateCategory(Category category) async {
    final database = await db;
    await database.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }

  // Merchants
  Future<List<Merchant>> getMerchants() async {
    final database = await db;
    final maps = await database.query('merchants');
    return maps.map((map) => Merchant.fromMap(map)).toList();
  }

  Future<void> insertMerchant(Merchant merchant) async {
    final database = await db;
    await database.insert('merchants', merchant.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMerchant(Merchant merchant) async {
    final database = await db;
    await database.update('merchants', merchant.toMap(), where: 'id = ?', whereArgs: [merchant.id]);
  }

  Future<Merchant?> getMerchantByName(String name) async {
    final database = await db;
    final maps = await database.query('merchants', where: 'name = ?', whereArgs: [name], limit: 1);
    if (maps.isNotEmpty) {
      return Merchant.fromMap(maps.first);
    }
    return null;
  }

  // Costs
  Future<List<Cost>> getCosts() async {
    final database = await db;
    final maps = await database.rawQuery('''
      SELECT 
        c.id as cost_id, c.amount, c.date, c.categoryId, c.merchantId,
        cat.name as cat_name, cat.iconCode as cat_icon, cat.colorCode as cat_color,
        m.name as merchant_name
      FROM costs c 
      JOIN categories cat ON c.categoryId = cat.id 
      JOIN merchants m ON c.merchantId = m.id
      ORDER BY c.date DESC
    ''');

    return maps.map((map) {
      return Cost(
        id: map['cost_id'] as String,
        amount: map['amount'] as double,
        date: DateTime.parse(map['date'] as String),
        category: Category(
          id: map['categoryId'] as String,
          name: map['cat_name'] as String,
          iconCode: map['cat_icon'] as String,
          colorCode: map['cat_color'] as int,
        ),
        merchant: Merchant(
          id: map['merchantId'] as String,
          name: map['merchant_name'] as String,
        ),
      );
    }).toList();
  }

  Future<void> insertCost(Cost cost) async {
    final database = await db;
    await database.insert('costs', cost.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertCostsBatch(List<Cost> costs) async {
    final database = await db;
    final batch = database.batch();
    for (var cost in costs) {
      batch.insert('costs', cost.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateCost(Cost cost) async {
    final database = await db;
    await database.update('costs', cost.toMap(), where: 'id = ?', whereArgs: [cost.id]);
  }

  Future<void> deleteCost(String id) async {
    final database = await db;
    await database.delete('costs', where: 'id = ?', whereArgs: [id]);
  }
}

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(databaseServiceProvider).getCategories();
});

final merchantsProvider = FutureProvider<List<Merchant>>((ref) {
  return ref.watch(databaseServiceProvider).getMerchants();
});

final costsProvider = FutureProvider<List<Cost>>((ref) {
  return ref.watch(databaseServiceProvider).getCosts();
});
