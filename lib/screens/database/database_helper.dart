
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;


  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'milk_management.db');

    _database = await openDatabase(
      path,
      version: 4,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );

    return _database!;
  }


  Future<void> _createDatabase(
      Database db,
      int version,
      ) async {
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mobile TEXT NOT NULL,
        address TEXT NOT NULL DEFAULT '',
        milk_type TEXT NOT NULL DEFAULT 'cow',
        rate REAL NOT NULL DEFAULT 0,
        morning_quantity REAL NOT NULL DEFAULT 0,
        start_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE milk_entries (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        delivered INTEGER NOT NULL DEFAULT 0,
        rate REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id)
          REFERENCES customers (id),
        UNIQUE (customer_id, entry_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        payment_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL DEFAULT 'cash',
        reference TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id)
          REFERENCES customers (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE bills (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        billing_month TEXT NOT NULL,
        milk_amount REAL NOT NULL DEFAULT 0,
        previous_due REAL NOT NULL DEFAULT 0,
        payments_received REAL NOT NULL DEFAULT 0,
        service_charge REAL NOT NULL DEFAULT 60,
        final_balance REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'unpaid',
        created_at TEXT NOT NULL,
        UNIQUE (customer_id, billing_month),
        FOREIGN KEY (customer_id)
          REFERENCES customers (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE delivery_pauses (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (customer_id)
          REFERENCES customers (id)
      )
    ''');

    await _createCustomerProducts(db);

    await _createMilkRates(db);

    await db.execute(
      'CREATE INDEX idx_milk_date ON milk_entries(entry_date)',
    );

    await db.execute(
      'CREATE INDEX idx_payment_customer ON payments(customer_id)',
    );
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createMilkRates(db);
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE bills ADD COLUMN service_charge REAL NOT NULL DEFAULT 60');
      await db.rawUpdate("""
        UPDATE bills
        SET final_balance = final_balance + 60,
            status = CASE WHEN final_balance + 60 > 0 THEN 'unpaid' ELSE 'paid' END
      """);
    }
    if (oldVersion < 4) await _createCustomerProducts(db);
  }

  Future<void> _createCustomerProducts(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE customer_daily_products (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        UNIQUE (customer_id, entry_date, product_name)
      )
    ''');
    await db.execute('CREATE INDEX idx_customer_products_date ON customer_daily_products(entry_date, customer_id)');
  }

  Future<List<Map<String, Object?>>> getCustomerDailyProducts(String customerId, String date) async {
    final db = await database;
    return db.query('customer_daily_products', where: 'customer_id = ? AND entry_date = ?', whereArgs: [customerId, date], orderBy: 'product_name');
  }

  Future<void> saveCustomerDailyProduct(Map<String, Object?> product) async {
    final db = await database;
    await db.insert('customer_daily_products', product, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveCustomerDailyProducts(List<Map<String, Object?>> products, String customerId, String date) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('customer_daily_products', where: 'customer_id = ? AND entry_date = ?', whereArgs: [customerId, date]);
      for (final product in products) {
        await txn.insert('customer_daily_products', product, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> _createMilkRates(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE milk_rates (
        milk_type TEXT PRIMARY KEY,
        rate REAL NOT NULL
      )
    ''');
    await db.insert('milk_rates', {'milk_type': 'cow', 'rate': 60});
    await db.insert('milk_rates', {'milk_type': 'standard', 'rate': 65});
    await db.insert('milk_rates', {'milk_type': 'full_cream', 'rate': 70});
    // Existing buffalo customers are grouped with the standard milk rate.
    await db.update('customers', {'milk_type': 'standard'}, where: 'milk_type = ?', whereArgs: ['buffalo']);
    await db.rawUpdate('''
      UPDATE customers SET rate = CASE milk_type
        WHEN 'cow' THEN 60 WHEN 'standard' THEN 65 WHEN 'full_cream' THEN 70 ELSE rate END
    ''');
  }

  Future<Map<String, double>> getMilkRates() async {
    final db = await database;
    final rows = await db.query('milk_rates');
    return {for (final row in rows) row['milk_type'] as String: (row['rate'] as num).toDouble()};
  }

  Future<void> saveMilkRates(Map<String, double> rates) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in rates.entries) {
        await txn.insert('milk_rates', {'milk_type': entry.key, 'rate': entry.value}, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.update('customers', {'rate': entry.value}, where: 'milk_type = ?', whereArgs: [entry.key]);
      }
    });
  }

  // Add a new customer.
  Future<void> addCustomer(
      Map<String, Object?> customer,
      ) async {
    final db = await database;

    await db.insert(
      'customers',
      customer,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Get all customers, including inactive customers.
  Future<List<Map<String, Object?>>> getCustomers({
    bool activeOnly = true,
  }) async {
    final db = await database;

    return db.query(
      'customers',
      where: activeOnly ? 'is_active = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  // Update customer details.
  Future<int> updateCustomer(
      String id,
      Map<String, Object?> values,
      ) async {
    final db = await database;

    return db.update(
      'customers',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Deactivate a customer without deleting history.
  Future<int> deactivateCustomer(String id) async {
    final db = await database;

    return db.update(
      'customers',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Save or update the delivery for a customer and date.
  Future<void> saveMilkEntry(
      Map<String, Object?> entry,
      ) async {
    final db = await database;

    await db.insert(
      'milk_entries',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all milk entries for a particular date.
  Future<List<Map<String, Object?>>> getMilkEntries(
      String date,
      ) async {
    final db = await database;

    return db.query(
      'milk_entries',
      where: 'entry_date = ?',
      whereArgs: [date],
      orderBy: 'customer_id',
    );
  }

  // Calculate total delivered milk for a date.
  Future<double> getDailyMilkTotal(String date) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS total
      FROM milk_entries
      WHERE entry_date = ? AND delivered = 1
      ''',
      [date],
    );

    return (result.first['total'] as num).toDouble();
  }

  // Record a customer payment.
  Future<void> addPayment(
      Map<String, Object?> payment,
      ) async {
    final db = await database;

    await db.insert(
      'payments',
      payment,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Get payment history for a customer.
  Future<List<Map<String, Object?>>> getPayments(
      String customerId,
      ) async {
    final db = await database;

    return db.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'payment_date DESC',
    );
  }
}
