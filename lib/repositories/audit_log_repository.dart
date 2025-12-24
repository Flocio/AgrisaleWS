/// 操作日志仓库
/// 处理操作日志的查询功能

import 'dart:convert';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../database_helper.dart';

class AuditLogRepository {
  final ApiService _apiService = ApiService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AuthService _authService = AuthService();

  /// 获取操作日志列表
  /// 
  /// [page] 页码（从1开始）
  /// [pageSize] 每页数量
  /// [operationType] 操作类型筛选（CREATE/UPDATE/DELETE）
  /// [entityType] 实体类型筛选
  /// [startTime] 开始时间（ISO8601格式）
  /// [endTime] 结束时间（ISO8601格式）
  /// [search] 搜索关键词（实体名称、备注）
  Future<PaginatedResponse<AuditLog>> getAuditLogs({
    int page = 1,
    int pageSize = 20,
    String? operationType,
    String? entityType,
    String? startTime,
    String? endTime,
    String? search,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getAuditLogsLocal(
        page: page,
        pageSize: pageSize,
        operationType: operationType,
        entityType: entityType,
        startTime: startTime,
        endTime: endTime,
        search: search,
      );
    } else {
      return await _getAuditLogsServer(
        page: page,
        pageSize: pageSize,
        operationType: operationType,
        entityType: entityType,
        startTime: startTime,
        endTime: endTime,
        search: search,
      );
    }
  }

  /// 从服务器获取操作日志列表
  Future<PaginatedResponse<AuditLog>> _getAuditLogsServer({
    int page = 1,
    int pageSize = 20,
    String? operationType,
    String? entityType,
    String? startTime,
    String? endTime,
    String? search,
  }) async {
    try {
      // 构建查询参数
      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      if (operationType != null && operationType.isNotEmpty) {
        queryParams['operation_type'] = operationType;
      }

      if (entityType != null && entityType.isNotEmpty) {
        queryParams['entity_type'] = entityType;
      }

      if (startTime != null && startTime.isNotEmpty) {
        queryParams['start_time'] = startTime;
      }

      if (endTime != null && endTime.isNotEmpty) {
        queryParams['end_time'] = endTime;
      }

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      // 发送请求
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/audit-logs',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final listResponse = AuditLogListResponse.fromJson(response.data!);

        return PaginatedResponse<AuditLog>(
          items: listResponse.logs,
          total: listResponse.total,
          page: listResponse.page,
          pageSize: listResponse.pageSize,
          totalPages: listResponse.totalPages,
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
      throw ApiError.unknown('获取操作日志失败', e);
    }
  }

  /// 从本地数据库获取操作日志列表
  Future<PaginatedResponse<AuditLog>> _getAuditLogsLocal({
    int page = 1,
    int pageSize = 20,
    String? operationType,
    String? entityType,
    String? startTime,
    String? endTime,
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

      // 构建WHERE条件
      final whereConditions = <String>['userId = ?', 'workspaceId = ?'];
      final whereArgs = <dynamic>[userId, workspaceId];

      if (operationType != null && operationType.isNotEmpty) {
        whereConditions.add('operation_type = ?');
        whereArgs.add(operationType);
      }

      if (entityType != null && entityType.isNotEmpty) {
        whereConditions.add('entity_type = ?');
        whereArgs.add(entityType);
      }

      if (startTime != null && startTime.isNotEmpty) {
        // 转换ISO8601格式为SQLite datetime格式
        final startDateTime = startTime.replaceAll('T', ' ').substring(0, 19);
        whereConditions.add('operation_time >= ?');
        whereArgs.add(startDateTime);
      }

      if (endTime != null && endTime.isNotEmpty) {
        // 转换ISO8601格式为SQLite datetime格式
        final endDateTime = endTime.replaceAll('T', ' ').substring(0, 19);
        whereConditions.add('operation_time <= ?');
        whereArgs.add(endDateTime);
      }

      if (search != null && search.isNotEmpty) {
        whereConditions.add('(entity_name LIKE ? OR note LIKE ?)');
        whereArgs.add('%$search%');
        whereArgs.add('%$search%');
      }

      final whereClause = whereConditions.join(' AND ');

      // 获取总数
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM operation_logs WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;

      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final logsResult = await db.query(
        'operation_logs',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'operation_time DESC',
        limit: pageSize,
        offset: offset,
      );

      // 转换为AuditLog对象
      final logs = logsResult.map((row) {
        return AuditLog(
          id: row['id'] as int,
          userId: row['userId'] as int,
          username: row['username'] as String,
          operationType: OperationType.fromString(row['operation_type'] as String),
          entityType: EntityType.fromString(row['entity_type'] as String),
          entityId: row['entity_id'] as int?,
          entityName: row['entity_name'] as String?,
          oldData: row['old_data'] != null 
              ? jsonDecode(row['old_data'] as String) as Map<String, dynamic>
              : null,
          newData: row['new_data'] != null
              ? jsonDecode(row['new_data'] as String) as Map<String, dynamic>
              : null,
          changes: row['changes'] != null
              ? jsonDecode(row['changes'] as String) as Map<String, dynamic>
              : null,
          ipAddress: row['ip_address'] as String?,
          deviceInfo: row['device_info'] as String?,
          operationTime: row['operation_time'] as String,
          note: row['note'] as String?,
        );
      }).toList();

      final totalPages = (total / pageSize).ceil();

      return PaginatedResponse<AuditLog>(
        items: logs,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: totalPages,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取操作日志失败', e);
    }
  }

  /// 获取操作日志详情
  /// 
  /// [logId] 日志ID
  Future<AuditLog> getAuditLogDetail(int logId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getAuditLogDetailLocal(logId);
    } else {
      return await _getAuditLogDetailServer(logId);
    }
  }

  /// 从服务器获取操作日志详情
  Future<AuditLog> _getAuditLogDetailServer(int logId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/audit-logs/$logId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return AuditLog.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取操作日志详情失败', e);
    }
  }

  /// 从本地数据库获取操作日志详情
  Future<AuditLog> _getAuditLogDetailLocal(int logId) async {
    try {
      final db = await _dbHelper.database;
      final workspaceId = await _apiService.getWorkspaceId();
      
      if (workspaceId == null) {
        throw ApiError(message: '未选择 Workspace');
      }

      final result = await db.query(
        'operation_logs',
        where: 'id = ? AND workspaceId = ?',
        whereArgs: [logId, workspaceId],
      );

      if (result.isEmpty) {
        throw ApiError(message: '日志不存在', errorCode: 'NOT_FOUND');
      }

      final row = result.first;
      return AuditLog(
        id: row['id'] as int,
        userId: row['userId'] as int,
        username: row['username'] as String,
        operationType: OperationType.fromString(row['operation_type'] as String),
        entityType: EntityType.fromString(row['entity_type'] as String),
        entityId: row['entity_id'] as int?,
        entityName: row['entity_name'] as String?,
        oldData: row['old_data'] != null 
            ? jsonDecode(row['old_data'] as String) as Map<String, dynamic>
            : null,
        newData: row['new_data'] != null
            ? jsonDecode(row['new_data'] as String) as Map<String, dynamic>
            : null,
        changes: row['changes'] != null
            ? jsonDecode(row['changes'] as String) as Map<String, dynamic>
            : null,
        ipAddress: row['ip_address'] as String?,
        deviceInfo: row['device_info'] as String?,
        operationTime: row['operation_time'] as String,
        note: row['note'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取操作日志详情失败', e);
    }
  }
}

