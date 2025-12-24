/// 本地操作日志服务
/// 用于本地workspace的操作日志记录

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/audit_log.dart';

class LocalAuditLogService {
  static final LocalAuditLogService _instance = LocalAuditLogService._internal();
  factory LocalAuditLogService() => _instance;
  LocalAuditLogService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  /// 记录操作日志
  /// 
  /// [transaction] 可选的事务对象，如果提供则在事务内插入日志
  /// [userId] 可选的用户ID，如果提供则跳过查询（用于事务内调用）
  /// [workspaceId] 可选的工作空间ID，如果提供则跳过查询（用于事务内调用）
  /// [username] 可选的用户名，如果提供则跳过查询（用于事务内调用）
  Future<int> logOperation({
    required OperationType operationType,
    required EntityType entityType,
    int? entityId,
    String? entityName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? changes,
    String? note,
    DatabaseExecutor? transaction,
    int? userId,
    int? workspaceId,
    String? username,
  }) async {
    try {
      // 如果提供了预获取的值，使用它们；否则查询
      final finalWorkspaceId = workspaceId ?? await _apiService.getWorkspaceId();
      final finalUsername = username ?? await _authService.getCurrentUsername();
      
      if (finalWorkspaceId == null) {
        print('未选择workspace，跳过日志记录');
        return 0;
      }
      
      if (finalUsername == null) {
        print('未登录，跳过日志记录');
        return 0;
      }
      
      // 如果在事务内，必须提供userId；否则查询
      final finalUserId = userId ?? await _dbHelper.getCurrentUserId(finalUsername);
      if (finalUserId == null) {
        print('用户不存在，跳过日志记录');
        return 0;
      }

      // 计算变更摘要（如果没有提供）
      Map<String, dynamic>? finalChanges = changes;
      if (finalChanges == null && oldData != null && newData != null) {
        finalChanges = _compareData(oldData, newData);
      }

      // 转换数据为JSON字符串
      final oldDataJson = oldData != null ? jsonEncode(oldData) : null;
      final newDataJson = newData != null ? jsonEncode(newData) : null;
      final changesJson = finalChanges != null ? jsonEncode(finalChanges) : null;

      // 获取本地时间（UTC+8）
      // DateTime.now() 返回的是本地时间，直接格式化即可
      final now = DateTime.now();
      final localTime = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      // 插入日志（使用事务对象或普通数据库连接）
      final executor = transaction ?? await _dbHelper.database;
      final id = await executor.insert('operation_logs', {
        'userId': finalUserId,
        'workspaceId': finalWorkspaceId,
        'username': finalUsername,
        'operation_type': operationType.value,
        'entity_type': entityType.value,
        'entity_id': entityId,
        'entity_name': entityName,
        'old_data': oldDataJson,
        'new_data': newDataJson,
        'changes': changesJson,
        'ip_address': null,
        'device_info': null,
        'operation_time': localTime,
        'note': note,
      });

      return id;
    } catch (e) {
      print('记录本地操作日志失败: $e');
      // 日志记录失败不应影响主业务
      return 0;
    }
  }

  /// 记录创建操作
  /// 
  /// [transaction] 可选的事务对象，如果提供则在事务内插入日志
  /// [userId] 可选的用户ID，如果提供则跳过查询（用于事务内调用）
  /// [workspaceId] 可选的工作空间ID，如果提供则跳过查询（用于事务内调用）
  /// [username] 可选的用户名，如果提供则跳过查询（用于事务内调用）
  Future<int> logCreate({
    required EntityType entityType,
    required int entityId,
    String? entityName,
    Map<String, dynamic>? newData,
    String? note,
    DatabaseExecutor? transaction,
    int? userId,
    int? workspaceId,
    String? username,
  }) async {
    return await logOperation(
      operationType: OperationType.create,
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      newData: newData,
      note: note,
      transaction: transaction,
      userId: userId,
      workspaceId: workspaceId,
      username: username,
    );
  }

  /// 记录更新操作
  /// 
  /// [transaction] 可选的事务对象，如果提供则在事务内插入日志
  /// [userId] 可选的用户ID，如果提供则跳过查询（用于事务内调用）
  /// [workspaceId] 可选的工作空间ID，如果提供则跳过查询（用于事务内调用）
  /// [username] 可选的用户名，如果提供则跳过查询（用于事务内调用）
  Future<int> logUpdate({
    required EntityType entityType,
    required int entityId,
    String? entityName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? changes,
    String? note,
    DatabaseExecutor? transaction,
    int? userId,
    int? workspaceId,
    String? username,
  }) async {
    return await logOperation(
      operationType: OperationType.update,
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      oldData: oldData,
      newData: newData,
      changes: changes,
      note: note,
      transaction: transaction,
      userId: userId,
      workspaceId: workspaceId,
      username: username,
    );
  }

  /// 记录删除操作
  /// 
  /// [transaction] 可选的事务对象，如果提供则在事务内插入日志
  /// [userId] 可选的用户ID，如果提供则跳过查询（用于事务内调用）
  /// [workspaceId] 可选的工作空间ID，如果提供则跳过查询（用于事务内调用）
  /// [username] 可选的用户名，如果提供则跳过查询（用于事务内调用）
  Future<int> logDelete({
    required EntityType entityType,
    required int entityId,
    String? entityName,
    Map<String, dynamic>? oldData,
    String? note,
    DatabaseExecutor? transaction,
    int? userId,
    int? workspaceId,
    String? username,
  }) async {
    return await logOperation(
      operationType: OperationType.delete,
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      oldData: oldData,
      note: note,
      transaction: transaction,
      userId: userId,
      workspaceId: workspaceId,
      username: username,
    );
  }

  /// 对比数据，生成变更摘要
  Map<String, dynamic> _compareData(
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) {
    final changes = <String, dynamic>{};
    
    // 找出新增和修改的字段
    newData.forEach((key, newValue) {
      final oldValue = oldData[key];
      if (oldValue != newValue) {
        changes[key] = {
          'old': oldValue,
          'new': newValue,
        };
      }
    });
    
    // 找出删除的字段
    oldData.forEach((key, oldValue) {
      if (!newData.containsKey(key)) {
        changes[key] = {
          'old': oldValue,
          'new': null,
        };
      }
    });
    
    return changes;
  }
}

