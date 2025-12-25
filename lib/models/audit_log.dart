/// 操作日志数据模型

/// 操作类型枚举
enum OperationType {
  create('CREATE'),
  update('UPDATE'),
  delete('DELETE'),
  cover('COVER');

  final String value;
  const OperationType(this.value);

  static OperationType fromString(String value) {
    return OperationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OperationType.create,
    );
  }

  String get displayName {
    switch (this) {
      case OperationType.create:
        return '创建';
      case OperationType.update:
        return '修改';
      case OperationType.delete:
        return '删除';
      case OperationType.cover:
        return '覆盖';
    }
  }
}

/// 实体类型枚举
enum EntityType {
  product('product', '产品'),
  customer('customer', '客户'),
  supplier('supplier', '供应商'),
  employee('employee', '员工'),
  purchase('purchase', '采购'),
  sale('sale', '销售'),
  return_('return', '退货'),
  income('income', '进账'),
  remittance('remittance', '汇款'),
  workspace_data('workspace_data', '全域');

  final String value;
  final String displayName;
  const EntityType(this.value, this.displayName);

  static EntityType fromString(String value) {
    return EntityType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EntityType.product,
    );
  }
}

/// 操作日志模型
class AuditLog {
  final int id;
  final int userId;
  final String username;
  final OperationType operationType;
  final EntityType entityType;
  final int? entityId;
  final String? entityName;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final Map<String, dynamic>? changes;
  final String? ipAddress;
  final String? deviceInfo;
  final String operationTime;
  final String? note;

  AuditLog({
    required this.id,
    required this.userId,
    required this.username,
    required this.operationType,
    required this.entityType,
    this.entityId,
    this.entityName,
    this.oldData,
    this.newData,
    this.changes,
    this.ipAddress,
    this.deviceInfo,
    required this.operationTime,
    this.note,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      username: json['username'] as String,
      operationType: OperationType.fromString(json['operation_type'] as String),
      entityType: EntityType.fromString(json['entity_type'] as String),
      entityId: json['entity_id'] as int? ?? json['entityId'] as int?,
      entityName: json['entity_name'] as String? ?? json['entityName'] as String?,
      oldData: json['old_data'] as Map<String, dynamic>? ?? json['oldData'] as Map<String, dynamic>?,
      newData: json['new_data'] as Map<String, dynamic>? ?? json['newData'] as Map<String, dynamic>?,
      changes: json['changes'] as Map<String, dynamic>?,
      ipAddress: json['ip_address'] as String? ?? json['ipAddress'] as String?,
      deviceInfo: json['device_info'] as String? ?? json['deviceInfo'] as String?,
      operationTime: json['operation_time'] as String? ?? json['operationTime'] as String,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'username': username,
      'operation_type': operationType.value,
      'entity_type': entityType.value,
      if (entityId != null) 'entity_id': entityId,
      if (entityName != null) 'entity_name': entityName,
      if (oldData != null) 'old_data': oldData,
      if (newData != null) 'new_data': newData,
      if (changes != null) 'changes': changes,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (deviceInfo != null) 'device_info': deviceInfo,
      'operation_time': operationTime,
      if (note != null) 'note': note,
    };
  }

  /// 格式化操作时间
  /// 注意：服务器返回的时间已经是本地时间（UTC+8），直接使用即可
  String get formattedTime {
    try {
      // 服务器返回的时间已经是 UTC+8（中国标准时间），直接显示
      // 如果时间格式正确（YYYY-MM-DD HH:MM:SS），直接返回
      String timeStr = operationTime.trim();
      
      if (timeStr.length == 19 && 
          timeStr.contains(' ') && 
          !timeStr.contains('T')) {
        // 格式正确，直接返回
        return timeStr;
      }
      
      // 如果是 ISO8601 格式，解析后格式化
      final dateTime = DateTime.parse(timeStr);
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    } catch (e) {
      // 如果解析失败，返回原始字符串
      return operationTime;
    }
  }

  /// 获取变更摘要文本
  String get changesSummary {
    if (changes == null || changes!.isEmpty) {
      return '';
    }

    final summaries = <String>[];
    changes!.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final oldValue = value['old'];
        final newValue = value['new'];
        final delta = value['delta'];

        if (delta != null) {
          // 数字字段，显示差值
          final deltaValue = delta is double ? delta : (delta as num).toDouble();
          if (deltaValue > 0) {
            summaries.add('$key: +$deltaValue');
          } else if (deltaValue < 0) {
            summaries.add('$key: $deltaValue');
          }
        } else {
          // 非数字字段，显示变更
          summaries.add('$key: ${oldValue?.toString() ?? '空'} → ${newValue?.toString() ?? '空'}');
        }
      }
    });

    return summaries.join(', ');
  }
}

/// 操作日志列表响应
class AuditLogListResponse {
  final List<AuditLog> logs;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  AuditLogListResponse({
    required this.logs,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory AuditLogListResponse.fromJson(Map<String, dynamic> json) {
    final logsJson = json['logs'] as List<dynamic>? ?? [];
    return AuditLogListResponse(
      logs: logsJson.map((item) => AuditLog.fromJson(item as Map<String, dynamic>)).toList(),
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      pageSize: json['page_size'] ?? json['pageSize'] ?? 20,
      totalPages: json['total_pages'] ?? json['totalPages'] ?? 0,
    );
  }
}

