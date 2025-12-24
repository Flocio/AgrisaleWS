/// 供应商仓库
/// 处理供应商的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 供应商模型
class Supplier {
  final int id;
  final int userId;
  final String name;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  Supplier({
    required this.id,
    required this.userId,
    required this.name,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
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

  Supplier copyWith({
    int? id,
    int? userId,
    String? name,
    String? note,
    String? createdAt,
    String? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 供应商创建请求
class SupplierCreate {
  final String name;
  final String? note;

  SupplierCreate({
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

/// 供应商更新请求
class SupplierUpdate {
  final String? name;
  final String? note;

  SupplierUpdate({
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

class SupplierRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取供应商列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（供应商名称或备注）
  /// 
  /// 返回分页的供应商列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Supplier>> getSuppliers({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getSuppliersLocal(page: page, pageSize: pageSize, search: search);
    } else {
      return await _getSuppliersServer(page: page, pageSize: pageSize, search: search);
    }
  }

  /// 从服务器获取供应商列表
  Future<PaginatedResponse<Supplier>> _getSuppliersServer({
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
        '/api/suppliers',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Supplier>.fromJson(
          response.data!,
          (json) => Supplier.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取供应商列表失败', e);
    }
  }

  /// 从本地数据库获取供应商列表
  Future<PaginatedResponse<Supplier>> _getSuppliersLocal({
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
        'SELECT COUNT(*) as count FROM suppliers WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final suppliersResult = await db.query(
        'suppliers',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Supplier 对象
      final suppliers = suppliersResult.map((row) {
        return Supplier(
          id: row['id'] as int,
          userId: row['userId'] as int,
          name: row['name'] as String,
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
          updatedAt: row['updated_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Supplier>(
        items: suppliers,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取供应商列表失败', e);
    }
  }

  /// 获取所有供应商（不分页，用于下拉选择等场景）
  /// 
  /// 返回所有供应商列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<List<Supplier>> getAllSuppliers() async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getAllSuppliersLocal();
    } else {
      return await _getAllSuppliersServer();
    }
  }

  /// 从服务器获取所有供应商
  Future<List<Supplier>> _getAllSuppliersServer() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/suppliers/all',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final suppliersJson = response.data!['suppliers'] as List<dynamic>? ?? [];
        return suppliersJson
            .map((json) => Supplier.fromJson(json as Map<String, dynamic>))
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
      throw ApiError.unknown('获取供应商列表失败', e);
    }
  }

  /// 从本地数据库获取所有供应商
  Future<List<Supplier>> _getAllSuppliersLocal() async {
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
      
      final suppliersResult = await db.query(
        'suppliers',
        where: 'userId = ? AND workspaceId = ?',
        whereArgs: [userId, workspaceId],
        orderBy: 'name ASC',
      );
      
      return suppliersResult.map((row) {
        return Supplier(
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
      throw ApiError.unknown('获取供应商列表失败', e);
    }
  }

  /// 获取单个供应商详情
  /// 
  /// [supplierId] 供应商ID
  /// 
  /// 返回供应商详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Supplier> getSupplier(int supplierId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getSupplierLocal(supplierId);
    } else {
      return await _getSupplierServer(supplierId);
    }
  }

  /// 从服务器获取单个供应商
  Future<Supplier> _getSupplierServer(int supplierId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/suppliers/$supplierId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Supplier.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取供应商详情失败', e);
    }
  }

  /// 从本地数据库获取单个供应商
  Future<Supplier> _getSupplierLocal(int supplierId) async {
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
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [supplierId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Supplier(
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
      throw ApiError.unknown('获取供应商详情失败', e);
    }
  }

  /// 创建供应商
  /// 
  /// [supplier] 供应商创建请求
  /// 
  /// 返回创建的供应商
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Supplier> createSupplier(SupplierCreate supplier) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createSupplierLocal(supplier);
    } else {
      return await _createSupplierServer(supplier);
    }
  }

  /// 在服务器创建供应商
  Future<Supplier> _createSupplierServer(SupplierCreate supplier) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/suppliers',
        body: supplier.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Supplier.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建供应商失败', e);
    }
  }

  /// 在本地数据库创建供应商
  Future<Supplier> _createSupplierLocal(SupplierCreate supplier) async {
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
      
      // 检查供应商名称是否已存在（同一 workspace 下）
      final existing = await db.query(
        'suppliers',
        where: 'userId = ? AND workspaceId = ? AND name = ?',
        whereArgs: [userId, workspaceId, supplier.name],
      );
      
      if (existing.isNotEmpty) {
        throw ApiError(message: '供应商名称已存在', errorCode: 'DUPLICATE');
      }
      
      // 插入供应商
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('suppliers', {
        'userId': userId,
        'workspaceId': workspaceId,
        'name': supplier.name,
        'note': supplier.note,
        'created_at': now,
        'updated_at': now,
      });
      
      // 返回创建的供应商
      final createdSupplier = Supplier(
        id: id,
        userId: userId,
        name: supplier.name,
        note: supplier.note,
        createdAt: now,
        updatedAt: now,
      );

      // 记录操作日志
      try {
        await LocalAuditLogService().logCreate(
          entityType: EntityType.supplier,
          entityId: id,
          entityName: supplier.name,
          newData: {
            'id': id,
            'userId': userId,
            'name': supplier.name,
            'note': supplier.note,
          },
        );
      } catch (e) {
        print('记录供应商创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      return createdSupplier;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('创建供应商失败', e);
    }
  }

  /// 更新供应商
  /// 
  /// [supplierId] 供应商ID
  /// [update] 供应商更新请求
  /// 
  /// 返回更新后的供应商
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Supplier> updateSupplier(int supplierId, SupplierUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateSupplierLocal(supplierId, update);
    } else {
      return await _updateSupplierServer(supplierId, update);
    }
  }

  /// 在服务器更新供应商
  Future<Supplier> _updateSupplierServer(int supplierId, SupplierUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/suppliers/$supplierId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Supplier.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新供应商失败', e);
    }
  }

  /// 在本地数据库更新供应商
  Future<Supplier> _updateSupplierLocal(int supplierId, SupplierUpdate update) async {
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
      
      // 检查供应商是否存在
      final currentResult = await db.query(
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [supplierId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      // 如果更新了名称，检查是否与其他供应商重名
      if (update.name != null && update.name != currentResult.first['name']) {
        final existing = await db.query(
          'suppliers',
          where: 'userId = ? AND workspaceId = ? AND name = ? AND id != ?',
          whereArgs: [userId, workspaceId, update.name, supplierId],
        );
        
        if (existing.isNotEmpty) {
          throw ApiError(message: '供应商名称已存在', errorCode: 'DUPLICATE');
        }
      }
      
      // 构建更新数据
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (update.name != null) updateData['name'] = update.name;
      if (update.note != null) updateData['note'] = update.note;
      
      // 更新供应商
      await db.update(
        'suppliers',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [supplierId, userId, workspaceId],
      );
      
      // 返回更新后的供应商
      final updatedResult = await db.query(
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [supplierId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedSupplier = Supplier(
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
          entityType: EntityType.supplier,
          entityId: supplierId,
          entityName: updatedSupplier.name,
          oldData: oldData,
          newData: newData,
        );
      } catch (e) {
        print('记录供应商更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedSupplier;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新供应商失败', e);
    }
  }

  /// 删除供应商
  /// 
  /// [supplierId] 供应商ID
  /// 
  /// 注意：删除供应商不会删除相关的采购、汇款记录，这些记录的 supplierId 会被设置为 NULL
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteSupplier(int supplierId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteSupplierLocal(supplierId);
    } else {
      return await _deleteSupplierServer(supplierId);
    }
  }

  /// 在服务器删除供应商
  Future<void> _deleteSupplierServer(int supplierId) async {
    try {
      final response = await _apiService.delete(
        '/api/suppliers/$supplierId',
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
      throw ApiError.unknown('删除供应商失败', e);
    }
  }

  /// 在本地数据库删除供应商
  Future<void> _deleteSupplierLocal(int supplierId) async {
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
      
      // 检查供应商是否存在，并保存旧数据用于日志
      final supplier = await db.query(
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [supplierId, userId, workspaceId],
      );
      
      if (supplier.isEmpty) {
        throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final supplierRow = supplier.first;
      final supplierName = supplierRow['name'] as String;
      final oldData = {
        'id': supplierRow['id'],
        'userId': supplierRow['userId'],
        'name': supplierRow['name'],
        'note': supplierRow['note'],
      };
      
      // 删除供应商（注意：相关记录的 supplierId 会被设置为 NULL，由数据库外键约束处理）
      final deleted = await db.delete(
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [supplierId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除供应商失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志
      try {
        await LocalAuditLogService().logDelete(
          entityType: EntityType.supplier,
          entityId: supplierId,
          entityName: supplierName,
          oldData: oldData,
        );
      } catch (e) {
        print('记录供应商删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除供应商失败', e);
    }
  }

  /// 搜索所有供应商（不分页，用于下拉选择等场景）
  /// 
  /// [search] 搜索关键词
  /// 
  /// 返回匹配的供应商列表（最多 50 条）
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<List<Supplier>> searchAllSuppliers(String search) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _searchAllSuppliersLocal(search);
    } else {
      return await _searchAllSuppliersServer(search);
    }
  }

  /// 在服务器搜索所有供应商
  Future<List<Supplier>> _searchAllSuppliersServer(String search) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/suppliers/search/all',
        queryParameters: {'search': search},
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final suppliersJson = response.data!['suppliers'] as List<dynamic>? ?? [];
        return suppliersJson
            .map((json) => Supplier.fromJson(json as Map<String, dynamic>))
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
      throw ApiError.unknown('搜索供应商失败', e);
    }
  }

  /// 在本地数据库搜索所有供应商
  Future<List<Supplier>> _searchAllSuppliersLocal(String search) async {
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
      
      final suppliersResult = await db.query(
        'suppliers',
        where: 'userId = ? AND workspaceId = ? AND (name LIKE ? OR note LIKE ?)',
        whereArgs: [userId, workspaceId, '%$search%', '%$search%'],
        orderBy: 'name ASC',
        limit: 50,
      );
      
      return suppliersResult.map((row) {
        return Supplier(
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
      throw ApiError.unknown('搜索供应商失败', e);
    }
  }
}


