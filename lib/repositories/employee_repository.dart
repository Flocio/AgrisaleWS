/// 员工仓库
/// 处理员工的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 员工模型
class Employee {
  final int id;
  final int userId;
  final String name;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  Employee({
    required this.id,
    required this.userId,
    required this.name,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
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

  Employee copyWith({
    int? id,
    int? userId,
    String? name,
    String? note,
    String? createdAt,
    String? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 员工创建请求
class EmployeeCreate {
  final String name;
  final String? note;

  EmployeeCreate({
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

/// 员工更新请求
class EmployeeUpdate {
  final String? name;
  final String? note;

  EmployeeUpdate({
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

class EmployeeRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取员工列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（员工名称或备注）
  /// 
  /// 返回分页的员工列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Employee>> getEmployees({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getEmployeesLocal(page: page, pageSize: pageSize, search: search);
    } else {
      return await _getEmployeesServer(page: page, pageSize: pageSize, search: search);
    }
  }

  /// 从服务器获取员工列表
  Future<PaginatedResponse<Employee>> _getEmployeesServer({
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
        '/api/employees',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Employee>.fromJson(
          response.data!,
          (json) => Employee.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取员工列表失败', e);
    }
  }

  /// 从本地数据库获取员工列表
  Future<PaginatedResponse<Employee>> _getEmployeesLocal({
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
        'SELECT COUNT(*) as count FROM employees WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final employeesResult = await db.query(
        'employees',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Employee 对象
      final employees = employeesResult.map((row) {
        return Employee(
          id: row['id'] as int,
          userId: row['userId'] as int,
          name: row['name'] as String,
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
          updatedAt: row['updated_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Employee>(
        items: employees,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取员工列表失败', e);
    }
  }

  /// 获取所有员工（不分页，用于下拉选择等场景）
  /// 
  /// 返回所有员工列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<List<Employee>> getAllEmployees() async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getAllEmployeesLocal();
    } else {
      return await _getAllEmployeesServer();
    }
  }

  /// 从服务器获取所有员工
  Future<List<Employee>> _getAllEmployeesServer() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/employees/all',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final employeesJson = response.data!['employees'] as List<dynamic>? ?? [];
        return employeesJson
            .map((json) => Employee.fromJson(json as Map<String, dynamic>))
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
      throw ApiError.unknown('获取员工列表失败', e);
    }
  }

  /// 从本地数据库获取所有员工
  Future<List<Employee>> _getAllEmployeesLocal() async {
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
      
      final employeesResult = await db.query(
        'employees',
        where: 'userId = ? AND workspaceId = ?',
        whereArgs: [userId, workspaceId],
        orderBy: 'name ASC',
      );
      
      return employeesResult.map((row) {
        return Employee(
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
      throw ApiError.unknown('获取员工列表失败', e);
    }
  }

  /// 获取单个员工详情
  /// 
  /// [employeeId] 员工ID
  /// 
  /// 返回员工详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Employee> getEmployee(int employeeId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getEmployeeLocal(employeeId);
    } else {
      return await _getEmployeeServer(employeeId);
    }
  }

  /// 从服务器获取单个员工
  Future<Employee> _getEmployeeServer(int employeeId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/employees/$employeeId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Employee.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取员工详情失败', e);
    }
  }

  /// 从本地数据库获取单个员工
  Future<Employee> _getEmployeeLocal(int employeeId) async {
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
        'employees',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [employeeId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '员工不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Employee(
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
      throw ApiError.unknown('获取员工详情失败', e);
    }
  }

  /// 创建员工
  /// 
  /// [employee] 员工创建请求
  /// 
  /// 返回创建的员工
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Employee> createEmployee(EmployeeCreate employee) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createEmployeeLocal(employee);
    } else {
      return await _createEmployeeServer(employee);
    }
  }

  /// 在服务器创建员工
  Future<Employee> _createEmployeeServer(EmployeeCreate employee) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/employees',
        body: employee.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Employee.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建员工失败', e);
    }
  }

  /// 在本地数据库创建员工
  Future<Employee> _createEmployeeLocal(EmployeeCreate employee) async {
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
      
      // 检查员工名称是否已存在（同一 workspace 下）
      final existing = await db.query(
        'employees',
        where: 'userId = ? AND workspaceId = ? AND name = ?',
        whereArgs: [userId, workspaceId, employee.name],
      );
      
      if (existing.isNotEmpty) {
        throw ApiError(message: '员工名称已存在', errorCode: 'DUPLICATE');
      }
      
      // 插入员工
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('employees', {
        'userId': userId,
        'workspaceId': workspaceId,
        'name': employee.name,
        'note': employee.note,
        'created_at': now,
        'updated_at': now,
      });
      
      // 返回创建的员工
      final createdEmployee = Employee(
        id: id,
        userId: userId,
        name: employee.name,
        note: employee.note,
        createdAt: now,
        updatedAt: now,
      );

      // 记录操作日志
      try {
        await LocalAuditLogService().logCreate(
          entityType: EntityType.employee,
          entityId: id,
          entityName: employee.name,
          newData: {
            'id': id,
            'userId': userId,
            'name': employee.name,
            'note': employee.note,
          },
        );
      } catch (e) {
        print('记录员工创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      return createdEmployee;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('创建员工失败', e);
    }
  }

  /// 更新员工
  /// 
  /// [employeeId] 员工ID
  /// [update] 员工更新请求
  /// 
  /// 返回更新后的员工
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Employee> updateEmployee(int employeeId, EmployeeUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateEmployeeLocal(employeeId, update);
    } else {
      return await _updateEmployeeServer(employeeId, update);
    }
  }

  /// 在服务器更新员工
  Future<Employee> _updateEmployeeServer(int employeeId, EmployeeUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/employees/$employeeId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Employee.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新员工失败', e);
    }
  }

  /// 在本地数据库更新员工
  Future<Employee> _updateEmployeeLocal(int employeeId, EmployeeUpdate update) async {
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
      
      // 检查员工是否存在
      final currentResult = await db.query(
        'employees',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [employeeId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '员工不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      // 如果更新了名称，检查是否与其他员工重名
      if (update.name != null && update.name != currentResult.first['name']) {
        final existing = await db.query(
          'employees',
          where: 'userId = ? AND workspaceId = ? AND name = ? AND id != ?',
          whereArgs: [userId, workspaceId, update.name, employeeId],
        );
        
        if (existing.isNotEmpty) {
          throw ApiError(message: '员工名称已存在', errorCode: 'DUPLICATE');
        }
      }
      
      // 构建更新数据
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (update.name != null) updateData['name'] = update.name;
      if (update.note != null) updateData['note'] = update.note;
      
      // 更新员工
      await db.update(
        'employees',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [employeeId, userId, workspaceId],
      );
      
      // 返回更新后的员工
      final updatedResult = await db.query(
        'employees',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [employeeId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedEmployee = Employee(
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
          entityType: EntityType.employee,
          entityId: employeeId,
          entityName: updatedEmployee.name,
          oldData: oldData,
          newData: newData,
        );
      } catch (e) {
        print('记录员工更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedEmployee;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新员工失败', e);
    }
  }

  /// 删除员工
  /// 
  /// [employeeId] 员工ID
  /// 
  /// 注意：删除员工不会删除相关的进账、汇款记录，这些记录的 employeeId 会被设置为 NULL
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteEmployee(int employeeId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteEmployeeLocal(employeeId);
    } else {
      return await _deleteEmployeeServer(employeeId);
    }
  }

  /// 在服务器删除员工
  Future<void> _deleteEmployeeServer(int employeeId) async {
    try {
      final response = await _apiService.delete(
        '/api/employees/$employeeId',
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
      throw ApiError.unknown('删除员工失败', e);
    }
  }

  /// 在本地数据库删除员工
  Future<void> _deleteEmployeeLocal(int employeeId) async {
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
      
      // 检查员工是否存在，并保存旧数据用于日志
      final employee = await db.query(
        'employees',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [employeeId, userId, workspaceId],
      );
      
      if (employee.isEmpty) {
        throw ApiError(message: '员工不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final employeeRow = employee.first;
      final employeeName = employeeRow['name'] as String;
      final oldData = {
        'id': employeeRow['id'],
        'userId': employeeRow['userId'],
        'name': employeeRow['name'],
        'note': employeeRow['note'],
      };
      
      // 删除员工（注意：相关记录的 employeeId 会被设置为 NULL，由数据库外键约束处理）
      final deleted = await db.delete(
        'employees',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [employeeId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除员工失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志
      try {
        await LocalAuditLogService().logDelete(
          entityType: EntityType.employee,
          entityId: employeeId,
          entityName: employeeName,
          oldData: oldData,
        );
      } catch (e) {
        print('记录员工删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除员工失败', e);
    }
  }

  /// 搜索所有员工（不分页，用于下拉选择等场景）
  /// 
  /// [search] 搜索关键词
  /// 
  /// 返回匹配的员工列表（最多 50 条）
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<List<Employee>> searchAllEmployees(String search) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _searchAllEmployeesLocal(search);
    } else {
      return await _searchAllEmployeesServer(search);
    }
  }

  /// 在服务器搜索所有员工
  Future<List<Employee>> _searchAllEmployeesServer(String search) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/employees/search/all',
        queryParameters: {'search': search},
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final employeesJson = response.data!['employees'] as List<dynamic>? ?? [];
        return employeesJson
            .map((json) => Employee.fromJson(json as Map<String, dynamic>))
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
      throw ApiError.unknown('搜索员工失败', e);
    }
  }

  /// 在本地数据库搜索所有员工
  Future<List<Employee>> _searchAllEmployeesLocal(String search) async {
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
      
      final employeesResult = await db.query(
        'employees',
        where: 'userId = ? AND workspaceId = ? AND (name LIKE ? OR note LIKE ?)',
        whereArgs: [userId, workspaceId, '%$search%', '%$search%'],
        orderBy: 'name ASC',
        limit: 50,
      );
      
      return employeesResult.map((row) {
        return Employee(
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
      throw ApiError.unknown('搜索员工失败', e);
    }
  }
}


