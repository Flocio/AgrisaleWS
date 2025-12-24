"""
数据库连接池和并发控制管理
支持 SQLite 多连接并发访问，确保数据一致性和高可用性
"""

import sqlite3
import threading
import time
import logging
from contextlib import contextmanager
from queue import Queue, Empty
from typing import Optional, Callable, Any
from pathlib import Path
import os
import sys

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SQLiteConnectionPool:
    """
    SQLite 连接池管理器
    解决 SQLite 并发访问问题，提供连接池和重试机制
    """
    
    def __init__(
        self,
        db_path: str,
        max_connections: int = 10,
        timeout: float = 30.0,
        busy_timeout: int = 5000,  # SQLite busy timeout (毫秒)
        retry_attempts: int = 3,
        retry_delay: float = 0.1
    ):
        """
        初始化连接池
        
        Args:
            db_path: 数据库文件路径
            max_connections: 最大连接数（默认 10，适合 3-4 人并发）
            timeout: 获取连接的超时时间（秒）
            busy_timeout: SQLite busy timeout（毫秒），默认 5 秒
            retry_attempts: 重试次数
            retry_delay: 重试延迟（秒）
        """
        self.db_path = db_path
        self.max_connections = max_connections
        self.timeout = timeout
        self.busy_timeout = busy_timeout
        self.retry_attempts = retry_attempts
        self.retry_delay = retry_delay
        
        # 连接池队列
        self._pool: Queue = Queue(maxsize=max_connections)
        # 当前使用的连接数
        self._active_connections = 0
        # 线程锁
        self._lock = threading.Lock()
        # 统计信息
        self._stats = {
            'total_connections': 0,
            'active_connections': 0,
            'pool_size': 0,
            'retry_count': 0,
            'busy_errors': 0
        }
        
        # 确保数据库目录存在
        db_dir = os.path.dirname(db_path)
        if db_dir and not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)
        
        # 初始化连接池
        self._initialize_pool()
        
        # 初始化数据库结构
        self._initialize_database()
        
        logger.info(f"SQLite 连接池初始化完成: {db_path}, 最大连接数: {max_connections}")
    
    def _initialize_pool(self):
        """初始化连接池，预创建连接"""
        for _ in range(min(3, self.max_connections)):  # 预创建 3 个连接
            conn = self._create_connection()
            if conn:
                self._pool.put(conn)
                self._stats['total_connections'] += 1
    
    def _create_connection(self) -> Optional[sqlite3.Connection]:
        """
        创建新的数据库连接
        
        Returns:
            SQLite 连接对象，失败返回 None
        """
        try:
            conn = sqlite3.connect(
                self.db_path,
                timeout=self.busy_timeout / 1000.0,  # 转换为秒
                check_same_thread=False  # 允许多线程使用
            )
            
            # 配置连接
            conn.execute("PRAGMA journal_mode = WAL")  # 启用 WAL 模式，提高并发性能
            conn.execute("PRAGMA synchronous = NORMAL")  # 平衡性能和安全性
            conn.execute("PRAGMA foreign_keys = ON")  # 启用外键约束
            conn.execute(f"PRAGMA busy_timeout = {self.busy_timeout}")  # 设置 busy timeout
            
            # 设置行工厂，返回字典格式
            conn.row_factory = sqlite3.Row
            
            return conn
        except Exception as e:
            logger.error(f"创建数据库连接失败: {e}")
            return None
    
    def _initialize_database(self):
        """初始化数据库结构（如果不存在）"""
        try:
            with self.get_connection() as conn:
                # 检查数据库版本
                cursor = conn.execute("PRAGMA user_version")
                version = cursor.fetchone()[0]
                
                if version == 0:
                    # 首次创建数据库
                    logger.info("首次创建数据库，执行初始化脚本...")
                    self._create_tables(conn)
                    self._set_version(conn, 19)
                else:
                    # 升级数据库
                    logger.info(f"数据库版本: {version}, 检查是否需要升级...")
                    self._upgrade_database(conn, version, 19)
                    # 无论版本如何，都检查并修复 user_settings 表的列（兼容性修复）
                    self._ensure_user_settings_columns(conn)
        except Exception as e:
            logger.error(f"数据库初始化失败: {e}")
            raise
    
    def _create_tables(self, conn: sqlite3.Connection):
        """创建所有表"""
        # 用户表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now')),
                last_login_at TEXT
            )
        ''')
        
        # Workspace 表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS workspaces (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                description TEXT,
                ownerId INTEGER NOT NULL,
                storage_type TEXT NOT NULL CHECK(storage_type IN ('local', 'server')),
                is_shared INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (ownerId) REFERENCES users (id) ON DELETE CASCADE
            )
        ''')
        
        # Workspace 成员表（权限管理）
        conn.execute('''
            CREATE TABLE IF NOT EXISTS workspace_members (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspaceId INTEGER NOT NULL,
                userId INTEGER NOT NULL,
                role TEXT NOT NULL CHECK(role IN ('owner', 'admin', 'editor', 'viewer')),
                permissions TEXT,
                invited_by INTEGER,
                joined_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE SET NULL,
                UNIQUE(workspaceId, userId)
            )
        ''')
        
        # Workspace 邀请表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS workspace_invitations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspaceId INTEGER NOT NULL,
                email TEXT,
                userId INTEGER,
                role TEXT NOT NULL CHECK(role IN ('admin', 'editor', 'viewer')),
                token TEXT NOT NULL UNIQUE,
                invited_by INTEGER NOT NULL,
                expires_at TEXT NOT NULL,
                status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'accepted', 'rejected', 'expired')),
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE SET NULL,
                FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE CASCADE
            )
        ''')
        
        # 产品表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId INTEGER NOT NULL,
                workspaceId INTEGER,
                name TEXT NOT NULL,
                description TEXT,
                stock REAL DEFAULT 0,
                unit TEXT NOT NULL CHECK(unit IN ('斤', '公斤', '袋')),
                supplierId INTEGER,
                version INTEGER DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (supplierId) REFERENCES suppliers (id) ON DELETE SET NULL,
                UNIQUE(workspaceId, name)
            )
        ''')
        
        # 供应商表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS suppliers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId INTEGER NOT NULL,
                workspaceId INTEGER,
                name TEXT NOT NULL,
                note TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                UNIQUE(workspaceId, name)
            )
        ''')
        
        # 客户表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS customers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId INTEGER NOT NULL,
                workspaceId INTEGER,
                name TEXT NOT NULL,
                note TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                UNIQUE(workspaceId, name)
            )
        ''')
        
        # 员工表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS employees (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId INTEGER NOT NULL,
                workspaceId INTEGER,
                name TEXT NOT NULL,
                note TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                UNIQUE(workspaceId, name)
            )
        ''')
        
        # 采购表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS purchases (
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
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (supplierId) REFERENCES suppliers (id) ON DELETE SET NULL)
        ''')
        
        # 销售表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS sales (
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
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (customerId) REFERENCES customers (id) ON DELETE SET NULL)
        ''')
        
        # 退货表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS returns (
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
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (customerId) REFERENCES customers (id) ON DELETE SET NULL)
        ''')
        
        # 进账表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS income (
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
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (customerId) REFERENCES customers (id) ON DELETE SET NULL,
                FOREIGN KEY (employeeId) REFERENCES employees (id) ON DELETE SET NULL)
        ''')
        
        # 汇款表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS remittance (
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
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                FOREIGN KEY (supplierId) REFERENCES suppliers (id) ON DELETE SET NULL,
                FOREIGN KEY (employeeId) REFERENCES employees (id) ON DELETE SET NULL)
        ''')
        
        # 用户设置表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS user_settings (
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
                show_online_users INTEGER DEFAULT 1,
                notify_device_online INTEGER DEFAULT 1,
                notify_device_offline INTEGER DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE)
        ''')
        
        # 在线用户表（用于跟踪在线状态，支持多设备）
        conn.execute('''
            CREATE TABLE IF NOT EXISTS online_users (
                userId INTEGER NOT NULL,
                deviceId TEXT NOT NULL,
                username TEXT NOT NULL,
                last_heartbeat TEXT DEFAULT (datetime('now')),
                current_action TEXT,
                platform TEXT,
                device_name TEXT,
                PRIMARY KEY (userId, deviceId),
                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE)
        ''')
        
        # 操作日志表
        conn.execute('''
            CREATE TABLE IF NOT EXISTS operation_logs (
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
        ''')
        
        # 创建索引以提高查询性能
        conn.execute('CREATE INDEX IF NOT EXISTS idx_products_userId ON products(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_products_workspaceId ON products(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_suppliers_workspaceId ON suppliers(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_customers_workspaceId ON customers(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_employees_workspaceId ON employees(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_purchases_userId ON purchases(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_purchases_workspaceId ON purchases(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_sales_userId ON sales(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_sales_workspaceId ON sales(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_returns_userId ON returns(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_returns_workspaceId ON returns(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_income_userId ON income(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_income_workspaceId ON income(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_remittance_userId ON remittance(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_remittance_workspaceId ON remittance(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_userId_time ON operation_logs(userId, operation_time DESC)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_workspaceId ON operation_logs(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_entity ON operation_logs(entity_type, entity_id)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_type ON operation_logs(operation_type)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_workspace_members_workspaceId ON workspace_members(workspaceId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_workspace_members_userId ON workspace_members(userId)')
        
        conn.commit()
        logger.info("数据库表创建完成")
    
    def _set_version(self, conn: sqlite3.Connection, version: int):
        """设置数据库版本"""
        conn.execute(f"PRAGMA user_version = {version}")
        conn.commit()
    
    def _ensure_user_settings_columns(self, conn: sqlite3.Connection):
        """确保 user_settings 表有所有必需的列（兼容性修复）"""
        try:
            cursor = conn.execute("PRAGMA table_info(user_settings)")
            columns = [row[1] for row in cursor.fetchall()]
            
            if 'notify_device_online' not in columns:
                logger.info("补充添加 notify_device_online 列到 user_settings 表")
                conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_online INTEGER DEFAULT 1')
                conn.commit()
            
            if 'notify_device_offline' not in columns:
                logger.info("补充添加 notify_device_offline 列到 user_settings 表")
                conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_offline INTEGER DEFAULT 1')
                conn.commit()
        except Exception as e:
            logger.warning(f"检查 user_settings 表列时出错: {e}")
    
    def _upgrade_database(self, conn: sqlite3.Connection, old_version: int, new_version: int):
        """升级数据库结构"""
        if old_version >= new_version:
            return
        
        logger.info(f"开始数据库升级: {old_version} -> {new_version}")
        
        # 版本 5: 添加 employees, income, remittance 表
        if old_version < 5:
            logger.info("升级到版本 5: 添加 employees, income, remittance 表")
            conn.execute('''
                CREATE TABLE IF NOT EXISTS employees (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    userId INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    note TEXT,
                    created_at TEXT DEFAULT (datetime('now')),
                    updated_at TEXT DEFAULT (datetime('now')),
                    FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                    UNIQUE(userId, name)
                )
            ''')
            conn.execute('''
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
                    created_at TEXT DEFAULT (datetime('now')),
                    FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                    FOREIGN KEY (customerId) REFERENCES customers (id) ON DELETE SET NULL,
                    FOREIGN KEY (employeeId) REFERENCES employees (id) ON DELETE SET NULL)
            ''')
            conn.execute('''
                CREATE TABLE IF NOT EXISTS remittance (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    userId INTEGER NOT NULL,
                    remittanceDate TEXT NOT NULL,
                    supplierId INTEGER,
                    amount REAL NOT NULL,
                    employeeId INTEGER,
                    paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
                    note TEXT,
                    created_at TEXT DEFAULT (datetime('now')),
                    FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                    FOREIGN KEY (supplierId) REFERENCES suppliers (id) ON DELETE SET NULL,
                    FOREIGN KEY (employeeId) REFERENCES employees (id) ON DELETE SET NULL)
            ''')
        
        # 版本 11: 为 products 表添加 supplierId 字段
        if old_version < 11:
            logger.info("升级到版本 11: 为 products 表添加 supplierId 字段")
            try:
                conn.execute('ALTER TABLE products ADD COLUMN supplierId INTEGER')
            except sqlite3.OperationalError:
                # 字段可能已存在
                pass
        
        # 版本 12: 添加自动备份字段和在线用户表
        if old_version < 12:
            logger.info("升级到版本 12: 添加自动备份字段和在线用户表")
            # 检查并添加自动备份字段
            cursor = conn.execute("PRAGMA table_info(user_settings)")
            columns = [row[1] for row in cursor.fetchall()]
            
            if 'auto_backup_enabled' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_enabled INTEGER DEFAULT 0')
            if 'auto_backup_interval' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_interval INTEGER DEFAULT 15')
            if 'auto_backup_max_count' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_max_count INTEGER DEFAULT 20')
            if 'last_backup_time' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN last_backup_time TEXT')
            if 'show_online_users' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN show_online_users INTEGER DEFAULT 1')
            if 'notify_device_online' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_online INTEGER DEFAULT 1')
            if 'notify_device_offline' not in columns:
                conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_offline INTEGER DEFAULT 1')
            
            # 创建在线用户表（支持多设备）
            conn.execute('''
                CREATE TABLE IF NOT EXISTS online_users (
                    userId INTEGER NOT NULL,
                    deviceId TEXT NOT NULL,
                    username TEXT NOT NULL,
                    last_heartbeat TEXT DEFAULT (datetime('now')),
                    current_action TEXT,
                    PRIMARY KEY (userId, deviceId),
                    FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE)
            ''')
        
        # 添加版本字段和索引（如果不存在）
        try:
            conn.execute('ALTER TABLE products ADD COLUMN version INTEGER DEFAULT 1')
        except sqlite3.OperationalError:
            pass
        
        try:
            conn.execute('ALTER TABLE products ADD COLUMN created_at TEXT DEFAULT (datetime("now"))')
        except sqlite3.OperationalError:
            pass
        
        try:
            conn.execute('ALTER TABLE products ADD COLUMN updated_at TEXT DEFAULT (datetime("now"))')
        except sqlite3.OperationalError:
            pass
        
        # 版本 14: 添加 platform 字段到 online_users 表
        if old_version < 14:
            logger.info("升级到版本 14: 添加 platform 字段到 online_users 表")
            try:
                # 检查表是否存在
                cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='online_users'")
                if cursor.fetchone():
                    # 尝试添加 platform 字段
                    try:
                        conn.execute('ALTER TABLE online_users ADD COLUMN platform TEXT')
                        logger.info("已添加 platform 字段到 online_users 表")
                    except sqlite3.OperationalError:
                        # 字段可能已存在，忽略错误
                        logger.debug("platform 字段可能已存在")
            except Exception as e:
                logger.error(f"升级 online_users 表失败: {e}", exc_info=True)
                raise
        
        # 版本 15: 添加 device_name 字段到 online_users 表
        if old_version < 15:
            logger.info("升级到版本 15: 添加 device_name 字段到 online_users 表")
            try:
                # 检查表是否存在
                cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='online_users'")
                if cursor.fetchone():
                    # 尝试添加 device_name 字段
                    try:
                        conn.execute('ALTER TABLE online_users ADD COLUMN device_name TEXT')
                        logger.info("已添加 device_name 字段到 online_users 表")
                    except sqlite3.OperationalError:
                        # 字段可能已存在，忽略错误
                        logger.debug("device_name 字段可能已存在")
            except Exception as e:
                logger.error(f"升级 online_users 表失败: {e}", exc_info=True)
                raise
        
        # 版本 16: 确保 device_name 字段存在（如果从版本 15 直接升级）
        if old_version < 16:
            logger.info("升级到版本 16: 确保 device_name 字段存在")
            try:
                # 检查表是否存在
                cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='online_users'")
                if cursor.fetchone():
                    # 检查字段是否存在
                    cursor = conn.execute("PRAGMA table_info(online_users)")
                    columns = [row[1] for row in cursor.fetchall()]
                    if 'device_name' not in columns:
                        try:
                            conn.execute('ALTER TABLE online_users ADD COLUMN device_name TEXT')
                            logger.info("已添加 device_name 字段到 online_users 表")
                        except sqlite3.OperationalError:
                            logger.debug("device_name 字段可能已存在")
            except Exception as e:
                logger.error(f"升级 online_users 表失败: {e}", exc_info=True)
                raise
        
        # 版本 17: 添加操作日志表，并确保 user_settings 表有所有必需的列
        if old_version < 17:
            logger.info("升级到版本 17: 添加操作日志表，并确保 user_settings 表完整性")
            try:
                # 确保 user_settings 表有所有必需的列（兼容性修复）
                cursor = conn.execute("PRAGMA table_info(user_settings)")
                columns = [row[1] for row in cursor.fetchall()]
                
                if 'notify_device_online' not in columns:
                    logger.info("添加 notify_device_online 列到 user_settings 表")
                    conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_online INTEGER DEFAULT 1')
                
                if 'notify_device_offline' not in columns:
                    logger.info("添加 notify_device_offline 列到 user_settings 表")
                    conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_offline INTEGER DEFAULT 1')
                
                # 创建操作日志表
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS operation_logs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        userId INTEGER NOT NULL,
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
                        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
                    )
                ''')
                logger.info("已创建 operation_logs 表")
                
                # 创建索引
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_userId_time ON operation_logs(userId, operation_time DESC)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_entity ON operation_logs(entity_type, entity_id)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_type ON operation_logs(operation_type)')
                logger.info("已创建 operation_logs 表的索引")
            except Exception as e:
                logger.error(f"升级到版本 17 失败: {e}", exc_info=True)
                raise
        
        # 版本 18: 添加 Workspace 支持
        if old_version < 18:
            logger.info("升级到版本 18: 添加 Workspace 支持")
            try:
                # 创建 Workspace 相关表
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS workspaces (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        description TEXT,
                        ownerId INTEGER NOT NULL,
                        storage_type TEXT NOT NULL CHECK(storage_type IN ('local', 'server')),
                        is_shared INTEGER DEFAULT 0,
                        created_at TEXT DEFAULT (datetime('now')),
                        updated_at TEXT DEFAULT (datetime('now')),
                        FOREIGN KEY (ownerId) REFERENCES users (id) ON DELETE CASCADE
                    )
                ''')
                logger.info("已创建 workspaces 表")
                
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS workspace_members (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        workspaceId INTEGER NOT NULL,
                        userId INTEGER NOT NULL,
                        role TEXT NOT NULL CHECK(role IN ('owner', 'admin', 'editor', 'viewer')),
                        permissions TEXT,
                        invited_by INTEGER,
                        joined_at TEXT DEFAULT (datetime('now')),
                        FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                        FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE SET NULL,
                        UNIQUE(workspaceId, userId)
                    )
                ''')
                logger.info("已创建 workspace_members 表")
                
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS workspace_invitations (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        workspaceId INTEGER NOT NULL,
                        email TEXT,
                        userId INTEGER,
                        role TEXT NOT NULL CHECK(role IN ('admin', 'editor', 'viewer')),
                        token TEXT NOT NULL UNIQUE,
                        invited_by INTEGER NOT NULL,
                        expires_at TEXT NOT NULL,
                        status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'accepted', 'rejected', 'expired')),
                        created_at TEXT DEFAULT (datetime('now')),
                        FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE SET NULL,
                        FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE CASCADE
                    )
                ''')
                logger.info("已创建 workspace_invitations 表")
                
                # 为所有业务表添加 workspaceId 字段（允许 NULL，保持兼容）
                business_tables = [
                    'products', 'suppliers', 'customers', 'employees',
                    'purchases', 'sales', 'returns', 'income', 'remittance',
                    'operation_logs'
                ]
                
                for table in business_tables:
                    try:
                        cursor = conn.execute(f"PRAGMA table_info({table})")
                        columns = [row[1] for row in cursor.fetchall()]
                        
                        if 'workspaceId' not in columns:
                            logger.info(f"为 {table} 表添加 workspaceId 字段")
                            conn.execute(f'ALTER TABLE {table} ADD COLUMN workspaceId INTEGER')
                            # 注意：SQLite 不支持在 ALTER TABLE 时添加外键约束
                            # 外键约束会在下次创建表时自动添加
                    except Exception as e:
                        logger.warning(f"为 {table} 表添加 workspaceId 字段失败: {e}")
                
                # 为现有用户创建默认 workspace
                logger.info("为现有用户创建默认 workspace...")
                cursor = conn.execute("SELECT id, username FROM users")
                users = cursor.fetchall()
                
                for user_row in users:
                    user_id = user_row[0]
                    username = user_row[1]
                    
                    # 检查用户是否已有 workspace
                    cursor = conn.execute(
                        "SELECT id FROM workspaces WHERE ownerId = ? LIMIT 1",
                        (user_id,)
                    )
                    existing_workspace = cursor.fetchone()
                    
                    if not existing_workspace:
                        # 创建默认 workspace
                        cursor = conn.execute('''
                            INSERT INTO workspaces (name, ownerId, storage_type, is_shared, created_at, updated_at)
                            VALUES (?, ?, 'server', 0, datetime('now'), datetime('now'))
                        ''', (f"{username}的账本", user_id))
                        workspace_id = cursor.lastrowid
                        
                        # 将用户添加为 workspace 的 owner
                        conn.execute('''
                            INSERT INTO workspace_members (workspaceId, userId, role, joined_at)
                            VALUES (?, ?, 'owner', datetime('now'))
                        ''', (workspace_id, user_id))
                        
                        # 将用户的所有现有数据迁移到默认 workspace
                        for table in business_tables:
                            if table == 'operation_logs':
                                continue  # operation_logs 不需要迁移
                            try:
                                conn.execute(
                                    f"UPDATE {table} SET workspaceId = ? WHERE userId = ? AND workspaceId IS NULL",
                                    (workspace_id, user_id)
                                )
                            except Exception as e:
                                logger.warning(f"迁移 {table} 表数据失败: {e}")
                        
                        logger.info(f"为用户 {username} (ID: {user_id}) 创建默认 workspace (ID: {workspace_id})")
                
                # 创建索引
                conn.execute('CREATE INDEX IF NOT EXISTS idx_products_workspaceId ON products(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_suppliers_workspaceId ON suppliers(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_customers_workspaceId ON customers(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_employees_workspaceId ON employees(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_purchases_workspaceId ON purchases(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_sales_workspaceId ON sales(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_returns_workspaceId ON returns(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_income_workspaceId ON income(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_remittance_workspaceId ON remittance(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_workspaceId ON operation_logs(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_workspace_members_workspaceId ON workspace_members(workspaceId)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_workspace_members_userId ON workspace_members(userId)')
                logger.info("已创建 workspace 相关索引")
                
                conn.commit()
                logger.info("升级到版本 18 完成：Workspace 支持已添加")
            except Exception as e:
                logger.error(f"升级到版本 18 失败: {e}", exc_info=True)
                conn.rollback()
                raise
        
        # 版本 19: 修改唯一性约束从 UNIQUE(userId, name) 改为 UNIQUE(workspaceId, name)
        if old_version < 19:
            logger.info("升级到版本 19: 修改唯一性约束为 workspace 级别")
            try:
                # 需要修改的表：products, suppliers, customers, employees
                tables_to_migrate = [
                    ('products', 'supplierId'),
                    ('suppliers', None),
                    ('customers', None),
                    ('employees', None)
                ]
                
                for table_name, fk_column in tables_to_migrate:
                    logger.info(f"迁移 {table_name} 表的唯一性约束...")
                    
                    # 检查是否有workspaceId为NULL的数据
                    cursor = conn.execute(f"SELECT COUNT(*) FROM {table_name} WHERE workspaceId IS NULL")
                    null_count = cursor.fetchone()[0]
                    
                    if null_count > 0:
                        logger.warning(f"{table_name} 表中有 {null_count} 条记录的 workspaceId 为 NULL，这些记录将保留但不再允许新创建")
                    
                    # 创建新表（带新的唯一性约束）
                    if table_name == 'products':
                        conn.execute(f'''
                            CREATE TABLE {table_name}_new (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                userId INTEGER NOT NULL,
                                workspaceId INTEGER,
                                name TEXT NOT NULL,
                                description TEXT,
                                stock REAL DEFAULT 0,
                                unit TEXT NOT NULL CHECK(unit IN ('斤', '公斤', '袋')),
                                supplierId INTEGER,
                                version INTEGER DEFAULT 1,
                                created_at TEXT DEFAULT (datetime('now')),
                                updated_at TEXT DEFAULT (datetime('now')),
                                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                                FOREIGN KEY (supplierId) REFERENCES suppliers (id) ON DELETE SET NULL,
                                UNIQUE(workspaceId, name)
                            )
                        ''')
                    elif table_name == 'suppliers':
                        conn.execute(f'''
                            CREATE TABLE {table_name}_new (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                userId INTEGER NOT NULL,
                                workspaceId INTEGER,
                                name TEXT NOT NULL,
                                note TEXT,
                                created_at TEXT DEFAULT (datetime('now')),
                                updated_at TEXT DEFAULT (datetime('now')),
                                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                                UNIQUE(workspaceId, name)
                            )
                        ''')
                    elif table_name == 'customers':
                        conn.execute(f'''
                            CREATE TABLE {table_name}_new (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                userId INTEGER NOT NULL,
                                workspaceId INTEGER,
                                name TEXT NOT NULL,
                                note TEXT,
                                created_at TEXT DEFAULT (datetime('now')),
                                updated_at TEXT DEFAULT (datetime('now')),
                                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                                UNIQUE(workspaceId, name)
                            )
                        ''')
                    elif table_name == 'employees':
                        conn.execute(f'''
                            CREATE TABLE {table_name}_new (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                userId INTEGER NOT NULL,
                                workspaceId INTEGER,
                                name TEXT NOT NULL,
                                note TEXT,
                                created_at TEXT DEFAULT (datetime('now')),
                                updated_at TEXT DEFAULT (datetime('now')),
                                FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE,
                                FOREIGN KEY (workspaceId) REFERENCES workspaces (id) ON DELETE CASCADE,
                                UNIQUE(workspaceId, name)
                            )
                        ''')
                    
                    # 迁移数据：只迁移workspaceId不为NULL的数据
                    # workspaceId为NULL的旧数据将被删除（不符合新的业务逻辑：每个workspace数据完全独立）
                    conn.execute(f'''
                        INSERT INTO {table_name}_new 
                        SELECT * FROM {table_name}
                        WHERE workspaceId IS NOT NULL
                    ''')
                    
                    if null_count > 0:
                        logger.warning(f"{table_name} 表中有 {null_count} 条记录的 workspaceId 为 NULL，这些记录将被删除（不符合新的业务逻辑）")
                    
                    # 删除旧表
                    conn.execute(f'DROP TABLE {table_name}')
                    
                    # 重命名新表
                    conn.execute(f'ALTER TABLE {table_name}_new RENAME TO {table_name}')
                    
                    logger.info(f"{table_name} 表迁移完成")
                
                conn.commit()
                logger.info("升级到版本 19 完成：唯一性约束已改为 workspace 级别")
            except Exception as e:
                logger.error(f"升级到版本 19 失败: {e}", exc_info=True)
                conn.rollback()
                raise
        
        # 版本 13: 修改 online_users 表支持多设备
        if old_version < 13:
            logger.info("升级到版本 13: 修改 online_users 表支持多设备")
            try:
                # 检查表是否存在
                cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='online_users'")
                if cursor.fetchone():
                    # 删除旧表（会丢失在线状态，但这是必要的）
                    conn.execute("DROP TABLE IF EXISTS online_users")
                    logger.info("已删除旧的 online_users 表")
                
                # 创建新表（支持多设备）
                conn.execute('''
                    CREATE TABLE IF NOT EXISTS online_users (
                        userId INTEGER NOT NULL,
                        deviceId TEXT NOT NULL,
                        username TEXT NOT NULL,
                        last_heartbeat TEXT DEFAULT (datetime('now')),
                        current_action TEXT,
                        platform TEXT,
                        device_name TEXT,
                        PRIMARY KEY (userId, deviceId),
                        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE)
                ''')
                logger.info("已创建新的 online_users 表（支持多设备）")
            except Exception as e:
                logger.error(f"升级 online_users 表失败: {e}", exc_info=True)
                raise
        
        # 创建索引
        conn.execute('CREATE INDEX IF NOT EXISTS idx_products_userId ON products(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_purchases_userId ON purchases(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_sales_userId ON sales(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_returns_userId ON returns(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_income_userId ON income(userId)')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_remittance_userId ON remittance(userId)')
        
        # 确保 user_settings 表有所有必需的列（兼容性修复，防止遗漏）
        try:
            cursor = conn.execute("PRAGMA table_info(user_settings)")
            columns = [row[1] for row in cursor.fetchall()]
            
            if 'notify_device_online' not in columns:
                logger.info("补充添加 notify_device_online 列到 user_settings 表")
                conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_online INTEGER DEFAULT 1')
            
            if 'notify_device_offline' not in columns:
                logger.info("补充添加 notify_device_offline 列到 user_settings 表")
                conn.execute('ALTER TABLE user_settings ADD COLUMN notify_device_offline INTEGER DEFAULT 1')
        except Exception as e:
            logger.debug(f"检查 user_settings 表列时出错: {e}")

        # 确保操作日志表的索引存在（如果表已存在）
        try:
            cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='operation_logs'")
            if cursor.fetchone():
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_userId_time ON operation_logs(userId, operation_time DESC)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_entity ON operation_logs(entity_type, entity_id)')
                conn.execute('CREATE INDEX IF NOT EXISTS idx_logs_type ON operation_logs(operation_type)')
        except Exception as e:
            logger.debug(f"创建操作日志索引时出错（可能表不存在）: {e}")

        self._set_version(conn, new_version)
        conn.commit()
        logger.info("数据库升级完成")
    
    @contextmanager
    def get_connection(self):
        """
        获取数据库连接的上下文管理器
        自动处理连接的获取、归还和错误重试
        
        Usage:
            with pool.get_connection() as conn:
                cursor = conn.execute("SELECT * FROM users")
                results = cursor.fetchall()
        """
        conn = None
        try:
            conn = self._acquire_connection()
            yield conn
            conn.commit()  # 自动提交事务
        except sqlite3.OperationalError as e:
            if conn:
                conn.rollback()  # 回滚事务
            
            # 处理 SQLITE_BUSY 错误
            if "database is locked" in str(e).lower() or "database is locked" in str(e):
                self._stats['busy_errors'] += 1
                logger.warning(f"数据库锁定错误，将重试: {e}")
                raise DatabaseBusyError(f"数据库暂时繁忙，请稍后重试: {e}")
            else:
                logger.error(f"数据库操作错误: {e}")
                raise
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"数据库操作异常: {e}")
            raise
        finally:
            if conn:
                self._release_connection(conn)
    
    def _acquire_connection(self) -> sqlite3.Connection:
        """
        从连接池获取连接
        
        Returns:
            SQLite 连接对象
        """
        start_time = time.time()
        
        while True:
            # 尝试从池中获取连接
            try:
                conn = self._pool.get(timeout=0.1)
                with self._lock:
                    self._active_connections += 1
                    self._stats['active_connections'] = self._active_connections
                    self._stats['pool_size'] = self._pool.qsize()
                return conn
            except Empty:
                # 池中没有可用连接
                with self._lock:
                    if self._active_connections < self.max_connections:
                        # 创建新连接
                        conn = self._create_connection()
                        if conn:
                            self._active_connections += 1
                            self._stats['total_connections'] += 1
                            self._stats['active_connections'] = self._active_connections
                            return conn
                
                # 检查超时
                elapsed = time.time() - start_time
                if elapsed >= self.timeout:
                    raise ConnectionTimeoutError(
                        f"获取数据库连接超时 ({self.timeout}秒)，当前活跃连接: {self._active_connections}/{self.max_connections}"
                    )
                
                # 等待一小段时间后重试
                time.sleep(0.05)
    
    def _release_connection(self, conn: sqlite3.Connection):
        """将连接归还到连接池"""
        try:
            # 重置连接状态
            conn.rollback()  # 回滚任何未提交的事务
            
            with self._lock:
                self._active_connections -= 1
                self._stats['active_connections'] = self._active_connections
                
                # 检查连接是否仍然有效
                try:
                    conn.execute("SELECT 1")
                except sqlite3.Error:
                    # 连接已损坏，不归还到池中
                    logger.warning("检测到损坏的连接，丢弃")
                    return
                
                # 归还到池中
                try:
                    self._pool.put_nowait(conn)
                    self._stats['pool_size'] = self._pool.qsize()
                except:
                    # 池已满，关闭连接
                    conn.close()
        except Exception as e:
            logger.error(f"释放连接时出错: {e}")
            try:
                conn.close()
            except:
                pass
    
    def execute_with_retry(
        self,
        query: str,
        params: tuple = (),
        retry_attempts: Optional[int] = None
    ) -> Any:
        """
        执行 SQL 查询，带重试机制
        
        Args:
            query: SQL 查询语句
            params: 查询参数
            retry_attempts: 重试次数（默认使用类初始化时的值）
        
        Returns:
            查询结果
        """
        if retry_attempts is None:
            retry_attempts = self.retry_attempts
        
        last_error = None
        
        for attempt in range(retry_attempts):
            try:
                with self.get_connection() as conn:
                    cursor = conn.execute(query, params)
                    if query.strip().upper().startswith('SELECT'):
                        return cursor.fetchall()
                    else:
                        return cursor.rowcount
            except DatabaseBusyError as e:
                last_error = e
                self._stats['retry_count'] += 1
                if attempt < retry_attempts - 1:
                    wait_time = self.retry_delay * (2 ** attempt)  # 指数退避
                    logger.info(f"重试查询 (尝试 {attempt + 1}/{retry_attempts}): {query[:50]}...")
                    time.sleep(wait_time)
                else:
                    raise
            except Exception as e:
                logger.error(f"执行查询失败: {e}")
                raise
        
        if last_error:
            raise last_error
    
    def get_stats(self) -> dict:
        """获取连接池统计信息"""
        with self._lock:
            return {
                **self._stats,
                'pool_size': self._pool.qsize(),
                'active_connections': self._active_connections,
                'max_connections': self.max_connections
            }
    
    def close_all(self):
        """关闭所有连接"""
        logger.info("关闭所有数据库连接...")
        while not self._pool.empty():
            try:
                conn = self._pool.get_nowait()
                conn.close()
            except:
                pass
        
        with self._lock:
            self._active_connections = 0
            self._stats['active_connections'] = 0
            self._stats['pool_size'] = 0


# 全局连接池实例
_pool: Optional[SQLiteConnectionPool] = None


def _resolve_db_path(db_path: str) -> str:
    """
    解析数据库路径，确保无论server目录在何处都能正确找到data目录
    
    如果路径是相对路径，会尝试以下方式解析：
    1. 如果路径以 "server/" 开头，尝试相对于项目根目录（当前工作目录）
    2. 如果路径以 "data/" 开头，尝试相对于server目录（通过查找server模块位置）
    3. 否则，尝试相对于当前工作目录
    
    Args:
        db_path: 数据库文件路径（相对或绝对路径）
    
    Returns:
        解析后的绝对路径
    """
    # 如果是绝对路径，直接返回
    if os.path.isabs(db_path):
        return db_path
    
    # 如果路径以 "server/" 开头，尝试相对于项目根目录（当前工作目录）
    if db_path.startswith("server/"):
        abs_path = os.path.abspath(db_path)
        if os.path.exists(os.path.dirname(abs_path)) or os.path.exists(abs_path):
            return abs_path
    
    # 如果路径以 "data/" 开头，尝试相对于server目录
    if db_path.startswith("data/"):
        # 获取server模块的目录
        server_module = sys.modules.get('server')
        if server_module and hasattr(server_module, '__file__'):
            server_dir = os.path.dirname(os.path.abspath(server_module.__file__))
            abs_path = os.path.join(server_dir, db_path)
            return abs_path
    
    # 默认：相对于当前工作目录
    return os.path.abspath(db_path)


def init_database(
    db_path: str = "data/agrisalews.db",
    max_connections: int = 10,
    **kwargs
) -> SQLiteConnectionPool:
    """
    初始化全局数据库连接池
    
    Args:
        db_path: 数据库文件路径（相对路径，相对于server目录，或绝对路径）
        max_connections: 最大连接数
        **kwargs: 其他连接池参数
    
    Returns:
        连接池实例
    """
    global _pool
    if _pool is None:
        # 解析路径，确保无论server目录在何处都能正确找到
        resolved_path = _resolve_db_path(db_path)
        _pool = SQLiteConnectionPool(resolved_path, max_connections, **kwargs)
    return _pool


def get_pool() -> SQLiteConnectionPool:
    """
    获取全局连接池实例
    
    Returns:
        连接池实例
    
    Raises:
        RuntimeError: 如果连接池未初始化
    """
    if _pool is None:
        raise RuntimeError("数据库连接池未初始化，请先调用 init_database()")
    return _pool


# 自定义异常类
class DatabaseBusyError(Exception):
    """数据库繁忙错误"""
    pass


class ConnectionTimeoutError(Exception):
    """连接超时错误"""
    pass


