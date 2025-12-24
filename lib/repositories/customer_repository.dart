/// 客户仓库
/// 处理客户的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 客户模型
class Customer {
  final int id;
  final int userId;
  final String name;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  Customer({
    required this.id,
    required this.userId,
    required this.name,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      name: json['name'] as String,
      note: json['note'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  Customer copyWith({
    int? id,
    int? userId,
    String? name,
    String? note,
    String? createdAt,
    String? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 客户创建请求
class CustomerCreate {
  final String name;
  final String? note;

  CustomerCreate({
    required this.name,
    this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (note != null) 'note': note,
    };
  }
}

/// 客户更新请求
class CustomerUpdate {
  final String? name;
  final String? note;

  CustomerUpdate({
    this.name,
    this.note,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (name != null) json['name'] = name;
    if (note != null) json['note'] = note;
    return json;
  }
}

class CustomerRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取客户列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（客户名称或备注）
  /// 
  /// 返回分页的客户列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Customer>> getCustomers({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getCustomersLocal(page: page, pageSize: pageSize, search: search);
    } else {
      return await _getCustomersServer(page: page, pageSize: pageSize, search: search);
    }
  }

  /// 从服务器获取客户列表
  Future<PaginatedResponse<Customer>> _getCustomersServer({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/customers',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Customer>.fromJson(
          response.data!,
          (json) => Customer.fromJson(json as Map<String, dynamic>),
        );
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取客户列表失败', e);
    }
  }

  /// 从本地数据库获取客户列表
  Future<PaginatedResponse<Customer>> _getCustomersLocal({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      // 构建查询条件
      var whereClause = 'userId = ? AND workspaceId = ?';
      var whereArgs = <dynamic>[userId, workspaceId];
      
      if (search != null && search.isNotEmpty) {
        whereClause += ' AND (name LIKE ? OR note LIKE ?)';
        whereArgs.add('%$search%');
        whereArgs.add('%$search%');
      }
      
      // 获取总数
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final customersResult = await db.query(
        'customers',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Customer 对象
      final customers = customersResult.map((row) {
        return Customer(
          id: row['id'] as int,
          userId: row['userId'] as int,
          name: row['name'] as String,
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
          updatedAt: row['updated_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Customer>(
        items: customers,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取客户列表失败', e);
    }
  }

  /// 获取所有客户（不分页，用于下拉选择等场景）
  /// 
  /// 返回所有客户列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<List<Customer>> getAllCustomers() async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getAllCustomersLocal();
    } else {
      return await _getAllCustomersServer();
    }
  }

  /// 从服务器获取所有客户
  Future<List<Customer>> _getAllCustomersServer() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/customers/all',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final customersJson = response.data!['customers'] as List<dynamic>? ?? [];
        return customersJson
            .map((json) => Customer.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取客户列表失败', e);
    }
  }

  /// 从本地数据库获取所有客户
  Future<List<Customer>> _getAllCustomersLocal() async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      final customersResult = await db.query(
        'customers',
        where: 'userId = ? AND workspaceId = ?',
        whereArgs: [userId, workspaceId],
        orderBy: 'name ASC',
      );
      
      return customersResult.map((row) {
        return Customer(
          id: row['id'] as int,
          userId: row['userId'] as int,
          name: row['name'] as String,
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
          updatedAt: row['updated_at'] as String?,
        );
      }).toList();
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取客户列表失败', e);
    }
  }

  /// 获取单个客户详情
  /// 
  /// [customerId] 客户ID
  /// 
  /// 返回客户详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Customer> getCustomer(int customerId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getCustomerLocal(customerId);
    } else {
      return await _getCustomerServer(customerId);
    }
  }

  /// 从服务器获取单个客户
  Future<Customer> _getCustomerServer(int customerId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/customers/$customerId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Customer.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取客户详情失败', e);
    }
  }

  /// 从本地数据库获取单个客户
  Future<Customer> _getCustomerLocal(int customerId) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      final result = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [customerId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Customer(
        id: row['id'] as int,
        userId: row['userId'] as int,
        name: row['name'] as String,
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
        updatedAt: row['updated_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取客户详情失败', e);
    }
  }

  /// 创建客户
  /// 
  /// [customer] 客户创建请求
  /// 
  /// 返回创建的客户
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Customer> createCustomer(CustomerCreate customer) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createCustomerLocal(customer);
    } else {
      return await _createCustomerServer(customer);
    }
  }

  /// 在服务器创建客户
  Future<Customer> _createCustomerServer(CustomerCreate customer) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/customers',
        body: customer.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Customer.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建客户失败', e);
    }
  }

  /// 在本地数据库创建客户
  Future<Customer> _createCustomerLocal(CustomerCreate customer) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      // 检查客户名称是否已存在（同一 workspace 下）
      final existing = await db.query(
        'customers',
        where: 'userId = ? AND workspaceId = ? AND name = ?',
        whereArgs: [userId, workspaceId, customer.name],
      );
      
      if (existing.isNotEmpty) {
        throw ApiError(message: '客户名称已存在', errorCode: 'DUPLICATE');
      }
      
      // 插入客户
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('customers', {
        'userId': userId,
        'workspaceId': workspaceId,
        'name': customer.name,
        'note': customer.note,
        'created_at': now,
        'updated_at': now,
      });
      
      // 返回创建的客户
      final createdCustomer = Customer(
        id: id,
        userId: userId,
        name: customer.name,
        note: customer.note,
        createdAt: now,
        updatedAt: now,
      );

      // 记录操作日志
      try {
        await LocalAuditLogService().logCreate(
          entityType: EntityType.customer,
          entityId: id,
          entityName: customer.name,
          newData: {
            'id': id,
            'userId': userId,
            'name': customer.name,
            'note': customer.note,
          },
        );
      } catch (e) {
        print('记录客户创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      return createdCustomer;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('创建客户失败', e);
    }
  }

  /// 更新客户
  /// 
  /// [customerId] 客户ID
  /// [update] 客户更新请求
  /// 
  /// 返回更新后的客户
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Customer> updateCustomer(int customerId, CustomerUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateCustomerLocal(customerId, update);
    } else {
      return await _updateCustomerServer(customerId, update);
    }
  }

  /// 在服务器更新客户
  Future<Customer> _updateCustomerServer(int customerId, CustomerUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/customers/$customerId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Customer.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新客户失败', e);
    }
  }

  /// 在本地数据库更新客户
  Future<Customer> _updateCustomerLocal(int customerId, CustomerUpdate update) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      // 检查客户是否存在
      final currentResult = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [customerId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      // 如果更新了名称，检查是否与其他客户重名
      if (update.name != null && update.name != currentResult.first['name']) {
        final existing = await db.query(
          'customers',
          where: 'userId = ? AND workspaceId = ? AND name = ? AND id != ?',
          whereArgs: [userId, workspaceId, update.name, customerId],
        );
        
        if (existing.isNotEmpty) {
          throw ApiError(message: '客户名称已存在', errorCode: 'DUPLICATE');
        }
      }
      
      // 构建更新数据
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (update.name != null) updateData['name'] = update.name;
      if (update.note != null) updateData['note'] = update.note;
      
      // 更新客户
      await db.update(
        'customers',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [customerId, userId, workspaceId],
      );
      
      // 返回更新后的客户
      final updatedResult = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [customerId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedCustomer = Customer(
        id: row['id'] as int,
        userId: row['userId'] as int,
        name: row['name'] as String,
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
        updatedAt: row['updated_at'] as String?,
      );

      // 记录操作日志
      try {
        final current = currentResult.first;
        final oldData = {
          'id': current['id'],
          'userId': current['userId'],
          'name': current['name'],
          'note': current['note'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'name': row['name'],
          'note': row['note'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.customer,
          entityId: customerId,
          entityName: updatedCustomer.name,
          oldData: oldData,
          newData: newData,
        );
      } catch (e) {
        print('记录客户更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedCustomer;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新客户失败', e);
    }
  }

  /// 删除客户
  /// 
  /// [customerId] 客户ID
  /// 
  /// 注意：删除客户不会删除相关的销售、退货、进账记录，这些记录的 customerId 会被设置为 NULL
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteCustomer(int customerId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteCustomerLocal(customerId);
    } else {
      return await _deleteCustomerServer(customerId);
    }
  }

  /// 在服务器删除客户
  Future<void> _deleteCustomerServer(int customerId) async {
    try {
      final response = await _apiService.delete(
        '/api/customers/$customerId',
        fromJsonT: (json) => json,
      );

      if (!response.isSuccess) {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('删除客户失败', e);
    }
  }

  /// 在本地数据库删除客户
  Future<void> _deleteCustomerLocal(int customerId) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      // 检查客户是否存在，并保存旧数据用于日志
      final customer = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [customerId, userId, workspaceId],
      );
      
      if (customer.isEmpty) {
        throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final customerRow = customer.first;
      final customerName = customerRow['name'] as String;
      final oldData = {
        'id': customerRow['id'],
        'userId': customerRow['userId'],
        'name': customerRow['name'],
        'note': customerRow['note'],
      };
      
      // 删除客户（注意：相关记录的 customerId 会被设置为 NULL，由数据库外键约束处理）
      final deleted = await db.delete(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [customerId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除客户失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志
      try {
        await LocalAuditLogService().logDelete(
          entityType: EntityType.customer,
          entityId: customerId,
          entityName: customerName,
          oldData: oldData,
        );
      } catch (e) {
        print('记录客户删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除客户失败', e);
    }
  }

  /// 搜索所有客户（不分页，用于下拉选择等场景）
  /// 
  /// [search] 搜索关键词
  /// 
  /// 返回匹配的客户列表（最多 50 条）
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<List<Customer>> searchAllCustomers(String search) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _searchAllCustomersLocal(search);
    } else {
      return await _searchAllCustomersServer(search);
    }
  }

  /// 在服务器搜索所有客户
  Future<List<Customer>> _searchAllCustomersServer(String search) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/customers/search/all',
        queryParameters: {'search': search},
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final customersJson = response.data!['customers'] as List<dynamic>? ?? [];
        return customersJson
            .map((json) => Customer.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('搜索客户失败', e);
    }
  }

  /// 在本地数据库搜索所有客户
  Future<List<Customer>> _searchAllCustomersLocal(String search) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      final username = await _authService.getCurrentUsername();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }
      
      if (username == null) {
        throw ApiError(message: '未登录');
      }
      
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      final customersResult = await db.query(
        'customers',
        where: 'userId = ? AND workspaceId = ? AND (name LIKE ? OR note LIKE ?)',
        whereArgs: [userId, workspaceId, '%$search%', '%$search%'],
        orderBy: 'name ASC',
        limit: 50,
      );
      
      return customersResult.map((row) {
        return Customer(
          id: row['id'] as int,
          userId: row['userId'] as int,
          name: row['name'] as String,
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
          updatedAt: row['updated_at'] as String?,
        );
      }).toList();
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('搜索客户失败', e);
    }
  }
}


