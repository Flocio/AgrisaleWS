// lib/database_helper.dart
//
// 本地数据库管理
// 用途：
// 1. 本地 workspace（storage_type='local'）的业务数据存储
// 2. 备份恢复功能（restoreBackup）
// 3. 向后兼容（迁移期间）
//
// 注意：
// - 服务器 workspace（storage_type='server'）的数据存储在服务器，通过 API 访问
// - 本地 workspace 的数据完全存储在客户端本地数据库
// - 所有业务表都包含 workspaceId 字段，用于数据隔离

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // 注意：databaseFactory 应该在 main.dart 中初始化，这里不再重复设置
    // 这样可以避免多次设置导致的 sqflite warning
    
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面平台使用应用数据目录
      final appDocumentsDirectory = await getApplicationDocumentsDirectory();
      path = join(appDocumentsDirectory.path, 'agrisalews', 'agriculture_management.db');
      
      // 确保目录存在
      final directory = Directory(dirname(path));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } else {
      // 移动平台使用默认数据库路径
      path = join(await getDatabasesPath(), 'agriculture_management.db');
    }
    
    return await openDatabase(
      path,
      version: 15, // 更新版本号 - 添加 operation_logs 表支持本地 workspace 日志
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    // 用户表（保留用于向后兼容，实际用户数据在服务器）
    await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      password TEXT NOT NULL
    )
  ''');
    
    // Workspace 表（用于存储本地 workspace 信息）
    await db.execute('''
    CREATE TABLE workspaces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      ownerId INTEGER NOT NULL,
      storage_type TEXT NOT NULL CHECK(storage_type IN ('local', 'server')),
      is_shared INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (ownerId) REFERENCES users (id)
    )
  ''');
    
    // 产品表（支持 workspaceId，用于本地存储）
    await db.execute('''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      name TEXT NOT NULL,
      description TEXT,
      stock REAL,
      unit TEXT NOT NULL CHECK(unit IN ('斤', '公斤', '袋')),
      supplierId INTEGER,
      version INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (supplierId) REFERENCES suppliers (id),
      UNIQUE(userId, workspaceId, name)
    )
  ''');
    
    // 供应商表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      name TEXT NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      UNIQUE(userId, workspaceId, name)
    )
  ''');
    
    // 客户表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      name TEXT NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      UNIQUE(userId, workspaceId, name)
    )
  ''');
    
    // 员工表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      name TEXT NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      UNIQUE(userId, workspaceId, name)
    )
  ''');
    
    // 进账表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE income (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      incomeDate TEXT NOT NULL,
      customerId INTEGER,
      amount REAL NOT NULL,
      discount REAL DEFAULT 0,
      employeeId INTEGER,
      paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (customerId) REFERENCES customers (id),
      FOREIGN KEY (employeeId) REFERENCES employees (id)
    )
  ''');
    
    // 汇款表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE remittance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      remittanceDate TEXT NOT NULL,
      supplierId INTEGER,
      amount REAL NOT NULL,
      employeeId INTEGER,
      paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (supplierId) REFERENCES suppliers (id),
      FOREIGN KEY (employeeId) REFERENCES employees (id)
    )
  ''');
    
    // 采购表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      productName TEXT NOT NULL,
      quantity REAL NOT NULL,
      purchaseDate TEXT,
      supplierId INTEGER,
      totalPurchasePrice REAL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (supplierId) REFERENCES suppliers (id)
    )
  ''');

    // 销售表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      productName TEXT NOT NULL,
      quantity REAL NOT NULL,
      customerId INTEGER,
      saleDate TEXT,
      totalSalePrice REAL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (customerId) REFERENCES customers (id)
    )
  ''');

    // 退货表（支持 workspaceId）
    await db.execute('''
    CREATE TABLE returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      workspaceId INTEGER,
      productName TEXT NOT NULL,
      quantity REAL NOT NULL,
      customerId INTEGER,
      returnDate TEXT,
      totalReturnPrice REAL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (customerId) REFERENCES customers (id)
    )
  ''');

    // 创建用户设置表，存储每个用户的个人设置
    await db.execute('''
    CREATE TABLE user_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL UNIQUE,
      deepseek_api_key TEXT,
      deepseek_model TEXT DEFAULT 'deepseek-chat',
      deepseek_temperature REAL DEFAULT 0.7,
      deepseek_max_tokens INTEGER DEFAULT 2000,
      dark_mode INTEGER DEFAULT 0,
      auto_backup_enabled INTEGER DEFAULT 0,
      auto_backup_interval INTEGER DEFAULT 15,
      auto_backup_max_count INTEGER DEFAULT 20,
      last_backup_time TEXT,
      FOREIGN KEY (userId) REFERENCES users (id)
    )
  ''');

    // 操作日志表（支持 workspaceId，用于本地 workspace）
    await db.execute('''
      CREATE TABLE operation_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        workspaceId INTEGER,
        username TEXT NOT NULL,
        operation_type TEXT NOT NULL CHECK(operation_type IN ('CREATE', 'UPDATE', 'DELETE')),
        entity_type TEXT NOT NULL,
        entity_id INTEGER,
        entity_name TEXT,
        old_data TEXT,
        new_data TEXT,
        changes TEXT,
        ip_address TEXT,
        device_info TEXT,
        operation_time TEXT DEFAULT (datetime('now')),
        note TEXT,
        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
        FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE SET NULL
      )
    ''');
    
    // 创建索引以提高查询性能
    await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_logs_workspaceId ON operation_logs(workspaceId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_logs_userId ON operation_logs(userId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_logs_operation_time ON operation_logs(operation_time)');
    
    // 不再插入初始用户数据，让用户自己注册
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('数据库升级: 从版本 $oldVersion 到版本 $newVersion');
    
    // 渐进式升级，根据旧版本逐步升级
    if (oldVersion < 5) {
      // 从版本1-4升级到5：添加employees, income, remittance表
      print('升级到版本5: 添加employees, income, remittance表');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS employees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          name TEXT NOT NULL,
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id),
          UNIQUE(userId, name)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS income (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          incomeDate TEXT NOT NULL,
          customerId INTEGER,
          amount REAL NOT NULL,
          discount REAL DEFAULT 0,
          employeeId INTEGER,
          paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id),
          FOREIGN KEY (customerId) REFERENCES customers (id),
          FOREIGN KEY (employeeId) REFERENCES employees (id)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS remittance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          remittanceDate TEXT NOT NULL,
          supplierId INTEGER,
          amount REAL NOT NULL,
          employeeId INTEGER,
          paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id),
          FOREIGN KEY (supplierId) REFERENCES suppliers (id),
          FOREIGN KEY (employeeId) REFERENCES employees (id)
        )
      ''');
    }
    
    if (oldVersion < 11) {
      // 从版本10或更早升级到11：为products表添加supplierId字段
      print('升级到版本11: 为products表添加supplierId字段');
      
      // 检查products表是否已存在supplierId列
      final tableInfo = await db.rawQuery('PRAGMA table_info(products)');
      final hasSupplierIdColumn = tableInfo.any((column) => column['name'] == 'supplierId');
      
      if (!hasSupplierIdColumn) {
        // 添加supplierId列，默认值为NULL（未分配供应商）
        await db.execute('ALTER TABLE products ADD COLUMN supplierId INTEGER');
        print('✓ 已为products表添加supplierId列，现有产品的供应商设为未分配');
      } else {
        print('✓ products表已包含supplierId列，跳过');
      }
    }
    
    // 无论版本如何，都检查并添加缺失的自动备份字段（修复可能的不完整升级）
    // 这样可以确保即使升级过程中出现问题，也能修复
    final tableInfo = await db.rawQuery('PRAGMA table_info(user_settings)');
    final columnNames = tableInfo.map((col) => col['name'] as String).toList();
    
    bool hasChanges = false;
    
    if (!columnNames.contains('auto_backup_enabled')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_enabled INTEGER DEFAULT 0');
      print('✓ 已添加 auto_backup_enabled 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_interval')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_interval INTEGER DEFAULT 15');
      print('✓ 已添加 auto_backup_interval 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_max_count')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_max_count INTEGER DEFAULT 20');
      print('✓ 已添加 auto_backup_max_count 列');
      hasChanges = true;
    }
    if (!columnNames.contains('last_backup_time')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN last_backup_time TEXT');
      print('✓ 已添加 last_backup_time 列');
      hasChanges = true;
    }
    
    if (!hasChanges && oldVersion < 12) {
      print('✓ user_settings表已包含所有自动备份字段');
    }
    
    if (oldVersion < 13) {
      // 从版本12升级到13：添加 workspaceId 支持本地存储
      print('升级到版本13: 添加 workspaceId 支持本地存储');
      
      // 为所有业务表添加 workspaceId 字段
      final businessTables = [
        'products',
        'suppliers',
        'customers',
        'employees',
        'purchases',
        'sales',
        'returns',
        'income',
        'remittance',
      ];
      
      for (final tableName in businessTables) {
        // 检查表是否存在 workspaceId 列
        final tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
        final hasWorkspaceIdColumn = tableInfo.any((column) => column['name'] == 'workspaceId');
        
        if (!hasWorkspaceIdColumn) {
          await db.execute('ALTER TABLE $tableName ADD COLUMN workspaceId INTEGER');
          print('✓ 已为 $tableName 表添加 workspaceId 列');
        }
      }
      
      // 为 products 表添加 version 字段（用于乐观锁）
      final productsTableInfo = await db.rawQuery('PRAGMA table_info(products)');
      final hasVersionColumn = productsTableInfo.any((column) => column['name'] == 'version');
      if (!hasVersionColumn) {
        await db.execute('ALTER TABLE products ADD COLUMN version INTEGER DEFAULT 1');
        print('✓ 已为 products 表添加 version 列');
      }
      
      // 为所有业务表添加 created_at 和 updated_at 字段
      for (final tableName in businessTables) {
        final tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
        final columnNames = tableInfo.map((col) => col['name'] as String).toList();
        
        if (!columnNames.contains('created_at')) {
          await db.execute('ALTER TABLE $tableName ADD COLUMN created_at TEXT DEFAULT (datetime(\'now\'))');
          print('✓ 已为 $tableName 表添加 created_at 列');
        }
        
        if (!columnNames.contains('updated_at') && tableName != 'purchases' && tableName != 'sales' && tableName != 'returns' && tableName != 'income' && tableName != 'remittance') {
          // 只有基础信息表需要 updated_at，业务记录表不需要
          await db.execute('ALTER TABLE $tableName ADD COLUMN updated_at TEXT DEFAULT (datetime(\'now\'))');
          print('✓ 已为 $tableName 表添加 updated_at 列');
        }
      }
      
      // 注意：由于 SQLite 的限制，无法直接修改 UNIQUE 约束
      // 现有的 UNIQUE(userId, name) 约束仍然有效
      // 在实际使用中，需要通过应用层逻辑确保 (userId, workspaceId, name) 的唯一性
      print('✓ 升级到版本13完成：已添加 workspaceId 支持');
    }
    
    if (oldVersion < 14) {
      // 从版本13升级到14：添加 workspaces 表用于存储本地 workspace 信息
      print('升级到版本14: 添加 workspaces 表');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workspaces (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          ownerId INTEGER NOT NULL,
          storage_type TEXT NOT NULL CHECK(storage_type IN ('local', 'server')),
          is_shared INTEGER DEFAULT 0,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now')),
          FOREIGN KEY (ownerId) REFERENCES users (id)
        )
      ''');
      print('✓ 升级到版本14完成：已添加 workspaces 表');
    }
    
    if (oldVersion < 15) {
      // 从版本14升级到15：添加 operation_logs 表用于存储本地 workspace 的操作日志
      print('升级到版本15: 添加 operation_logs 表');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS operation_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          workspaceId INTEGER,
          username TEXT NOT NULL,
          operation_type TEXT NOT NULL CHECK(operation_type IN ('CREATE', 'UPDATE', 'DELETE', 'COVER')),
          entity_type TEXT NOT NULL,
          entity_id INTEGER,
          entity_name TEXT,
          old_data TEXT,
          new_data TEXT,
          changes TEXT,
          ip_address TEXT,
          device_info TEXT,
          operation_time TEXT DEFAULT (datetime('now')),
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
          FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE SET NULL
        )
      ''');
      
      // 创建索引以提高查询性能
      await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_logs_workspaceId ON operation_logs(workspaceId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_logs_userId ON operation_logs(userId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_logs_operation_time ON operation_logs(operation_time)');
      
      print('✓ 升级到版本15完成：已添加 operation_logs 表');
    }
    
    print('数据库升级完成！所有数据已保留。');
  }

  // 获取当前用户ID的辅助方法
  Future<int?> getCurrentUserId(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      columns: ['id'],
      where: 'username = ?',
      whereArgs: [username],
    );
    
    if (result.isNotEmpty) {
      return result.first['id'] as int;
    }
    return null;
  }

  /// 确保 workspaces 表存在（如果不存在则创建）
  /// 用于修复数据库升级问题
  Future<void> ensureWorkspacesTableExists() async {
    final db = await database;
    try {
      await db.rawQuery('SELECT 1 FROM workspaces LIMIT 1');
    } catch (e) {
      // 表不存在，创建它
      print('workspaces 表不存在，正在创建...');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS workspaces (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          ownerId INTEGER NOT NULL,
          storage_type TEXT NOT NULL CHECK(storage_type IN ('local', 'server')),
          is_shared INTEGER DEFAULT 0,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now')),
          FOREIGN KEY (ownerId) REFERENCES users (id)
        )
      ''');
      print('✓ workspaces 表已创建');
    }
  }

  // 创建用户设置记录
  Future<void> createUserSettings(int userId) async {
    final db = await database;
    await db.insert('user_settings', {
      'userId': userId,
    });
  }
}