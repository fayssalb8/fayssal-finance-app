import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import '../models/client.dart';
import '../models/monthly_salary_override.dart';
import '../models/sale.dart';
import '../models/time_record.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'smart_kitchen_finance.db';
  static const _dbVersion = 5;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE settings ADD COLUMN compensation_mode TEXT NOT NULL "
        "DEFAULT 'salary_bonus'",
      );
      await db.execute(
        'ALTER TABLE settings ADD COLUMN has_onboarded INTEGER NOT NULL '
        'DEFAULT 0',
      );
      await db.execute('ALTER TABLE time_records ADD COLUMN custom_rate REAL');
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE settings ADD COLUMN overtime_rate_mode TEXT NOT NULL "
        "DEFAULT 'auto'",
      );
      await db.execute(
        'ALTER TABLE settings ADD COLUMN custom_overtime_rate REAL NOT NULL '
        'DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE settings ADD COLUMN payment_target REAL NOT NULL '
        'DEFAULT 0',
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE sales ADD COLUMN order_type TEXT NOT NULL DEFAULT 'مطبخ'",
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        base_salary REAL NOT NULL DEFAULT 0,
        overtime_multiplier REAL NOT NULL DEFAULT 1.5,
        price_per_meter REAL NOT NULL DEFAULT 30000,
        work_month_start_day INTEGER NOT NULL DEFAULT 7,
        annual_leave_balance INTEGER NOT NULL DEFAULT 30,
        compensation_mode TEXT NOT NULL DEFAULT 'salary_bonus',
        has_onboarded INTEGER NOT NULL DEFAULT 0,
        overtime_rate_mode TEXT NOT NULL DEFAULT 'auto',
        custom_overtime_rate REAL NOT NULL DEFAULT 0,
        payment_target REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE monthly_salary_override (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_month TEXT NOT NULL,
        work_year INTEGER NOT NULL,
        actual_salary REAL NOT NULL,
        UNIQUE(work_month, work_year)
      )
    ''');

    await db.execute('''
      CREATE TABLE time_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        start_time TEXT,
        end_time TEXT,
        total_value REAL NOT NULL DEFAULT 0,
        days_count INTEGER NOT NULL DEFAULT 0,
        reason TEXT,
        custom_rate REAL,
        work_month TEXT NOT NULL,
        work_year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE colleagues (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        client_id INTEGER,
        order_type TEXT NOT NULL DEFAULT 'مطبخ',
        area REAL NOT NULL,
        commission_rate REAL NOT NULL,
        is_shared INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        work_month TEXT NOT NULL,
        work_year INTEGER NOT NULL,
        FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_shares (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        person_type TEXT NOT NULL,
        colleague_id INTEGER,
        share_percentage REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (colleague_id) REFERENCES colleagues(id) ON DELETE SET NULL
      )
    ''');

    await db.insert('settings', const AppSettings().toMap());
  }

  // ---------------------------------------------------------------------------
  // الإعدادات (Singleton)
  // ---------------------------------------------------------------------------

  Future<AppSettings> getSettings() async {
    final db = await database;
    final rows = await db.query('settings', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      final settings = const AppSettings();
      await db.insert('settings', settings.toMap());
      return settings;
    }
    return AppSettings.fromMap(rows.first);
  }

  Future<void> updateSettings(AppSettings settings) async {
    final db = await database;
    await db.update(
      'settings',
      settings.toMap(),
      where: 'id = ?',
      whereArgs: [settings.id],
    );
  }

  // ---------------------------------------------------------------------------
  // الراتب الفعلي الشهري
  // ---------------------------------------------------------------------------

  Future<MonthlySalaryOverride?> getSalaryOverride(
    String workMonth,
    int workYear,
  ) async {
    final db = await database;
    final rows = await db.query(
      'monthly_salary_override',
      where: 'work_month = ? AND work_year = ?',
      whereArgs: [workMonth, workYear],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MonthlySalaryOverride.fromMap(rows.first);
  }

  Future<void> saveSalaryOverride({
    required String workMonth,
    required int workYear,
    required double actualSalary,
  }) async {
    final db = await database;
    final existing = await getSalaryOverride(workMonth, workYear);
    if (existing != null) {
      await db.update(
        'monthly_salary_override',
        {'actual_salary': actualSalary},
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    } else {
      await db.insert('monthly_salary_override', {
        'work_month': workMonth,
        'work_year': workYear,
        'actual_salary': actualSalary,
      });
    }
  }

  Future<void> deleteSalaryOverride(String workMonth, int workYear) async {
    final db = await database;
    await db.delete(
      'monthly_salary_override',
      where: 'work_month = ? AND work_year = ?',
      whereArgs: [workMonth, workYear],
    );
  }

  // ---------------------------------------------------------------------------
  // سجلات الوقت (إضافات / غياب)
  // ---------------------------------------------------------------------------

  Future<int> insertTimeRecord(TimeRecord record) async {
    final db = await database;
    return db.insert('time_records', record.toMap());
  }

  Future<int> updateTimeRecord(TimeRecord record) async {
    final db = await database;
    return db.update(
      'time_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> deleteTimeRecord(int id) async {
    final db = await database;
    await db.delete('time_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TimeRecord>> getTimeRecords({
    String? workMonth,
    int? workYear,
  }) async {
    final db = await database;
    final rows = await db.query(
      'time_records',
      where: workMonth != null ? 'work_month = ? AND work_year = ?' : null,
      whereArgs: workMonth != null ? [workMonth, workYear] : null,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(TimeRecord.fromMap).toList();
  }

  /// سجلات الوقت بين تاريخين (شامل) — للتقارير.
  Future<List<TimeRecord>> getTimeRecordsBetween(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final rows = await db.query(
      'time_records',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(TimeRecord.fromMap).toList();
  }

  /// إجمالي أيام الغياب المستهلكة (لسنة عمل معينة أو كل الفترات) لحساب رصيد العطلة.
  Future<int> getTotalAbsenceDaysUsed({int? workYear}) async {
    final db = await database;
    final where = workYear != null ? 'type = ? AND work_year = ?' : 'type = ?';
    final whereArgs = workYear != null
        ? [TimeRecordType.absenceDays, workYear]
        : [TimeRecordType.absenceDays];
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(days_count), 0) AS total FROM time_records '
      'WHERE $where',
      whereArgs,
    );
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------------------
  // العملاء والزملاء
  // ---------------------------------------------------------------------------

  Future<int> insertClient(Client client) async {
    final db = await database;
    return db.insert('clients', client.toMap());
  }

  Future<int> updateClient(Client client) async {
    final db = await database;
    return db.update(
      'clients',
      client.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
  }

  Future<void> deleteClient(int id) async {
    final db = await database;
    await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query('clients', orderBy: 'name COLLATE NOCASE');
    return rows.map(Client.fromMap).toList();
  }

  Future<int> insertColleague(Colleague colleague) async {
    final db = await database;
    return db.insert('colleagues', colleague.toMap());
  }

  Future<int> updateColleague(Colleague colleague) async {
    final db = await database;
    return db.update(
      'colleagues',
      colleague.toMap(),
      where: 'id = ?',
      whereArgs: [colleague.id],
    );
  }

  Future<void> deleteColleague(int id) async {
    final db = await database;
    await db.delete('colleagues', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Colleague>> getColleagues() async {
    final db = await database;
    final rows = await db.query('colleagues', orderBy: 'name COLLATE NOCASE');
    return rows.map(Colleague.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // المبيعات
  // ---------------------------------------------------------------------------

  Future<int> insertSale(Sale sale, List<SaleShare> shares) async {
    final db = await database;
    return db.transaction((txn) async {
      final saleId = await txn.insert('sales', sale.toMap());
      for (final share in shares) {
        await txn.insert('sale_shares', {...share.toMap(), 'sale_id': saleId});
      }
      return saleId;
    });
  }

  Future<void> updateSale(Sale sale, List<SaleShare> shares) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'sales',
        sale.toMap(),
        where: 'id = ?',
        whereArgs: [sale.id],
      );
      await txn.delete(
        'sale_shares',
        where: 'sale_id = ?',
        whereArgs: [sale.id],
      );
      for (final share in shares) {
        await txn.insert('sale_shares', {...share.toMap(), 'sale_id': sale.id});
      }
    });
  }

  Future<void> deleteSale(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sale_shares', where: 'sale_id = ?', whereArgs: [id]);
      await txn.delete('sales', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Sale>> getSales({String? workMonth, int? workYear}) async {
    final db = await database;
    final rows = await db.query(
      'sales',
      where: workMonth != null ? 'work_month = ? AND work_year = ?' : null,
      whereArgs: workMonth != null ? [workMonth, workYear] : null,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Sale.fromMap).toList();
  }

  /// المبيعات بين تاريخين (شامل) — للتقارير.
  Future<List<Sale>> getSalesBetween(String startDate, String endDate) async {
    final db = await database;
    final rows = await db.query(
      'sales',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(Sale.fromMap).toList();
  }

  Future<List<SaleShare>> getSaleShares(int saleId) async {
    final db = await database;
    final rows = await db.query(
      'sale_shares',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
    return rows.map(SaleShare.fromMap).toList();
  }

  Future<Client?> getClient(int id) async {
    final db = await database;
    final rows = await db.query('clients', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  Future<Colleague?> getColleague(int id) async {
    final db = await database;
    final rows = await db.query('colleagues', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Colleague.fromMap(rows.first);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
