/// 汇款仓库
/// 处理汇款记录的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';
import 'income_repository.dart'; // 复用 PaymentMethod 枚举

/// 汇款记录模型
class Remittance {
  final int id;
  final int userId;
  final String remittanceDate;
  final int? supplierId;
  final double amount;
  final int? employeeId;
  final PaymentMethod paymentMethod;
  final String? note;
  final String? createdAt;

  Remittance({
    required this.id,
    required this.userId,
    required this.remittanceDate,
    this.supplierId,
    required this.amount,
    this.employeeId,
    required this.paymentMethod,
    this.note,
    this.createdAt,
  });

  factory Remittance.fromJson(Map<String, dynamic> json) {
    return Remittance(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      remittanceDate: json['remittanceDate'] as String? ?? json['remittance_date'] as String,
      supplierId: json['supplierId'] as int? ?? json['supplier_id'] as int?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      employeeId: json['employeeId'] as int? ?? json['employee_id'] as int?,
      paymentMethod: PaymentMethod.fromString(
        json['paymentMethod'] as String? ?? json['payment_method'] as String? ?? '现金',
      ),
      note: json['note'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'remittanceDate': remittanceDate,
      if (supplierId != null) 'supplierId': supplierId,
      'amount': amount,
      if (employeeId != null) 'employeeId': employeeId,
      'paymentMethod': paymentMethod.value,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  Remittance copyWith({
    int? id,
    int? userId,
    String? remittanceDate,
    int? supplierId,
    double? amount,
    int? employeeId,
    PaymentMethod? paymentMethod,
    String? note,
    String? createdAt,
  }) {
    return Remittance(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      remittanceDate: remittanceDate ?? this.remittanceDate,
      supplierId: supplierId ?? this.supplierId,
      amount: amount ?? this.amount,
      employeeId: employeeId ?? this.employeeId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 汇款创建请求
class RemittanceCreate {
  final String remittanceDate;
  final int? supplierId;
  final double amount; // 汇款金额（必须大于0）
  final int? employeeId;
  final PaymentMethod paymentMethod;
  final String? note;

  RemittanceCreate({
    required this.remittanceDate,
    this.supplierId,
    required this.amount,
    this.employeeId,
    required this.paymentMethod,
    this.note,
  }) : assert(amount > 0, '汇款金额必须大于0');

  Map<String, dynamic> toJson() {
    return {
      'remittanceDate': remittanceDate,
      if (supplierId != null) 'supplierId': supplierId,
      'amount': amount,
      if (employeeId != null) 'employeeId': employeeId,
      'paymentMethod': paymentMethod.value,
      if (note != null) 'note': note,
    };
  }
}

/// 汇款更新请求
class RemittanceUpdate {
  final String? remittanceDate;
  final int? supplierId;
  final double? amount; // 汇款金额（必须大于0）
  final int? employeeId;
  final PaymentMethod? paymentMethod;
  final String? note;

  RemittanceUpdate({
    this.remittanceDate,
    this.supplierId,
    this.amount,
    this.employeeId,
    this.paymentMethod,
    this.note,
  }) : assert(amount == null || amount! > 0, '汇款金额必须大于0');

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (remittanceDate != null) json['remittanceDate'] = remittanceDate;
    if (supplierId != null) json['supplierId'] = supplierId;
    if (amount != null) json['amount'] = amount;
    if (employeeId != null) json['employeeId'] = employeeId;
    if (paymentMethod != null) json['paymentMethod'] = paymentMethod!.value;
    if (note != null) json['note'] = note;
    return json;
  }
}

class RemittanceRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取汇款记录列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（备注）
  /// [startDate] 开始日期（ISO8601格式）
  /// [endDate] 结束日期（ISO8601格式）
  /// [supplierId] 供应商ID筛选（null 表示不筛选，0 表示未分配供应商）
  /// 
  /// 返回分页的汇款记录列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Remittance>> getRemittances({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? supplierId,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getRemittancesLocal(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        supplierId: supplierId,
      );
    } else {
      return await _getRemittancesServer(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        supplierId: supplierId,
      );
    }
  }

  /// 从服务器获取汇款记录列表
  Future<PaginatedResponse<Remittance>> _getRemittancesServer({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? supplierId,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      if (startDate != null) {
        queryParams['start_date'] = startDate;
      }

      if (endDate != null) {
        queryParams['end_date'] = endDate;
      }

      if (supplierId != null) {
        queryParams['supplier_id'] = supplierId.toString();
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/remittance',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Remittance>.fromJson(
          response.data!,
          (json) => Remittance.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取汇款记录列表失败', e);
    }
  }

  /// 从本地数据库获取汇款记录列表
  Future<PaginatedResponse<Remittance>> _getRemittancesLocal({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? supplierId,
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
        whereClause += ' AND note LIKE ?';
        whereArgs.add('%$search%');
      }
      
      if (startDate != null) {
        whereClause += ' AND remittanceDate >= ?';
        whereArgs.add(startDate);
      }
      
      if (endDate != null) {
        whereClause += ' AND remittanceDate <= ?';
        whereArgs.add(endDate);
      }
      
      if (supplierId != null) {
        if (supplierId == 0) {
          whereClause += ' AND (supplierId IS NULL OR supplierId = 0)';
        } else {
          whereClause += ' AND supplierId = ?';
          whereArgs.add(supplierId);
        }
      }
      
      // 获取总数
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM remittance WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final remittancesResult = await db.query(
        'remittance',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Remittance 对象
      final remittances = remittancesResult.map((row) {
        return Remittance(
          id: row['id'] as int,
          userId: row['userId'] as int,
          remittanceDate: row['remittanceDate'] as String,
          supplierId: row['supplierId'] as int?,
          amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
          employeeId: row['employeeId'] as int?,
          paymentMethod: PaymentMethod.fromString(row['paymentMethod'] as String? ?? '现金'),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Remittance>(
        items: remittances,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取汇款记录列表失败', e);
    }
  }

  /// 获取单个汇款记录详情
  /// 
  /// [remittanceId] 汇款记录ID
  /// 
  /// 返回汇款记录详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Remittance> getRemittance(int remittanceId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getRemittanceLocal(remittanceId);
    } else {
      return await _getRemittanceServer(remittanceId);
    }
  }

  /// 从服务器获取单个汇款记录
  Future<Remittance> _getRemittanceServer(int remittanceId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/remittance/$remittanceId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Remittance.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取汇款记录详情失败', e);
    }
  }

  /// 从本地数据库获取单个汇款记录
  Future<Remittance> _getRemittanceLocal(int remittanceId) async {
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
        'remittance',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [remittanceId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '汇款记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Remittance(
        id: row['id'] as int,
        userId: row['userId'] as int,
        remittanceDate: row['remittanceDate'] as String,
        supplierId: row['supplierId'] as int?,
        amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
        employeeId: row['employeeId'] as int?,
        paymentMethod: PaymentMethod.fromString(row['paymentMethod'] as String? ?? '现金'),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取汇款记录详情失败', e);
    }
  }

  /// 创建汇款记录
  /// 
  /// [remittance] 汇款创建请求
  /// 
  /// 返回创建的汇款记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Remittance> createRemittance(RemittanceCreate remittance) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createRemittanceLocal(remittance);
    } else {
      return await _createRemittanceServer(remittance);
    }
  }

  /// 在服务器创建汇款记录
  Future<Remittance> _createRemittanceServer(RemittanceCreate remittance) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/remittance',
        body: remittance.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Remittance.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建汇款记录失败', e);
    }
  }

  /// 在本地数据库创建汇款记录
  Future<Remittance> _createRemittanceLocal(RemittanceCreate remittance) async {
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
      
      // 验证供应商是否存在（如果提供了 supplierId）
      if (remittance.supplierId != null && remittance.supplierId != 0) {
        final supplier = await db.query(
          'suppliers',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [remittance.supplierId, userId, workspaceId],
        );
        
        if (supplier.isEmpty) {
          throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 验证员工是否存在（如果提供了 employeeId）
      if (remittance.employeeId != null) {
        final employee = await db.query(
          'employees',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [remittance.employeeId, userId, workspaceId],
        );
        
        if (employee.isEmpty) {
          throw ApiError(message: '员工不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 插入汇款记录
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('remittance', {
        'userId': userId,
        'workspaceId': workspaceId,
        'remittanceDate': remittance.remittanceDate,
        'supplierId': remittance.supplierId == 0 ? null : remittance.supplierId,
        'amount': remittance.amount,
        'employeeId': remittance.employeeId,
        'paymentMethod': remittance.paymentMethod.value,
        'note': remittance.note,
        'created_at': now,
      });
      
      // 返回创建的汇款记录
      final createdRemittance = Remittance(
        id: id,
        userId: userId,
        remittanceDate: remittance.remittanceDate,
        supplierId: remittance.supplierId == 0 ? null : remittance.supplierId,
        amount: remittance.amount,
        employeeId: remittance.employeeId,
        paymentMethod: remittance.paymentMethod,
        note: remittance.note,
        createdAt: now,
      );

      // 记录操作日志
      try {
        final entityName = '汇款记录 (金额: ¥${remittance.amount})';
        await LocalAuditLogService().logCreate(
          entityType: EntityType.remittance,
          entityId: id,
          entityName: entityName,
          newData: {
            'id': id,
            'userId': userId,
            'remittanceDate': remittance.remittanceDate,
            'supplierId': remittance.supplierId == 0 ? null : remittance.supplierId,
            'amount': remittance.amount,
            'employeeId': remittance.employeeId,
            'paymentMethod': remittance.paymentMethod.value,
            'note': remittance.note,
          },
        );
      } catch (e) {
        print('记录汇款创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      return createdRemittance;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('创建汇款记录失败', e);
    }
  }

  /// 更新汇款记录
  /// 
  /// [remittanceId] 汇款记录ID
  /// [update] 汇款更新请求
  /// 
  /// 返回更新后的汇款记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Remittance> updateRemittance(int remittanceId, RemittanceUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateRemittanceLocal(remittanceId, update);
    } else {
      return await _updateRemittanceServer(remittanceId, update);
    }
  }

  /// 在服务器更新汇款记录
  Future<Remittance> _updateRemittanceServer(int remittanceId, RemittanceUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/remittance/$remittanceId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Remittance.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新汇款记录失败', e);
    }
  }

  /// 在本地数据库更新汇款记录
  Future<Remittance> _updateRemittanceLocal(int remittanceId, RemittanceUpdate update) async {
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
      
      // 检查汇款记录是否存在
      final currentResult = await db.query(
        'remittance',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [remittanceId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '汇款记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      // 验证供应商是否存在（如果更新了 supplierId）
      if (update.supplierId != null && update.supplierId != currentResult.first['supplierId'] && update.supplierId != 0) {
        final supplier = await db.query(
          'suppliers',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [update.supplierId, userId, workspaceId],
        );
        
        if (supplier.isEmpty) {
          throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 验证员工是否存在（如果更新了 employeeId）
      if (update.employeeId != null && update.employeeId != currentResult.first['employeeId']) {
        final employee = await db.query(
          'employees',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [update.employeeId, userId, workspaceId],
        );
        
        if (employee.isEmpty) {
          throw ApiError(message: '员工不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 构建更新数据
      final updateData = <String, dynamic>{};
      if (update.remittanceDate != null) updateData['remittanceDate'] = update.remittanceDate;
      if (update.supplierId != null) updateData['supplierId'] = update.supplierId == 0 ? null : update.supplierId;
      if (update.amount != null) updateData['amount'] = update.amount;
      if (update.employeeId != null) updateData['employeeId'] = update.employeeId;
      if (update.paymentMethod != null) updateData['paymentMethod'] = update.paymentMethod!.value;
      if (update.note != null) updateData['note'] = update.note;
      
      // 更新汇款记录
      await db.update(
        'remittance',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [remittanceId, userId, workspaceId],
      );
      
      // 返回更新后的汇款记录
      final updatedResult = await db.query(
        'remittance',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [remittanceId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedRemittance = Remittance(
        id: row['id'] as int,
        userId: row['userId'] as int,
        remittanceDate: row['remittanceDate'] as String,
        supplierId: row['supplierId'] as int?,
        amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
        employeeId: row['employeeId'] as int?,
        paymentMethod: PaymentMethod.fromString(row['paymentMethod'] as String? ?? '现金'),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );

      // 记录操作日志
      try {
        final current = currentResult.first;
        final entityName = '汇款记录 (金额: ¥${updatedRemittance.amount})';
        final oldData = {
          'id': current['id'],
          'userId': current['userId'],
          'remittanceDate': current['remittanceDate'],
          'supplierId': current['supplierId'],
          'amount': current['amount'],
          'employeeId': current['employeeId'],
          'paymentMethod': current['paymentMethod'],
          'note': current['note'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'remittanceDate': row['remittanceDate'],
          'supplierId': row['supplierId'],
          'amount': row['amount'],
          'employeeId': row['employeeId'],
          'paymentMethod': row['paymentMethod'],
          'note': row['note'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.remittance,
          entityId: remittanceId,
          entityName: entityName,
          oldData: oldData,
          newData: newData,
        );
      } catch (e) {
        print('记录汇款更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedRemittance;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新汇款记录失败', e);
    }
  }

  /// 删除汇款记录
  /// 
  /// [remittanceId] 汇款记录ID
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteRemittance(int remittanceId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteRemittanceLocal(remittanceId);
    } else {
      return await _deleteRemittanceServer(remittanceId);
    }
  }

  /// 在服务器删除汇款记录
  Future<void> _deleteRemittanceServer(int remittanceId) async {
    try {
      final response = await _apiService.delete(
        '/api/remittance/$remittanceId',
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
      throw ApiError.unknown('删除汇款记录失败', e);
    }
  }

  /// 在本地数据库删除汇款记录
  Future<void> _deleteRemittanceLocal(int remittanceId) async {
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
      
      // 检查汇款记录是否存在，并保存旧数据用于日志
      final remittance = await db.query(
        'remittance',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [remittanceId, userId, workspaceId],
      );
      
      if (remittance.isEmpty) {
        throw ApiError(message: '汇款记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final remittanceRow = remittance.first;
      final amount = (remittanceRow['amount'] as num?)?.toDouble() ?? 0.0;
      final entityName = '汇款记录 (金额: ¥$amount)';
      final oldData = {
        'id': remittanceRow['id'],
        'userId': remittanceRow['userId'],
        'remittanceDate': remittanceRow['remittanceDate'],
        'supplierId': remittanceRow['supplierId'],
        'amount': remittanceRow['amount'],
        'employeeId': remittanceRow['employeeId'],
        'paymentMethod': remittanceRow['paymentMethod'],
        'note': remittanceRow['note'],
      };
      
      // 删除汇款记录
      final deleted = await db.delete(
        'remittance',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [remittanceId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除汇款记录失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志
      try {
        await LocalAuditLogService().logDelete(
          entityType: EntityType.remittance,
          entityId: remittanceId,
          entityName: entityName,
          oldData: oldData,
        );
      } catch (e) {
        print('记录汇款删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除汇款记录失败', e);
    }
  }
}


