/// 进账仓库
/// 处理进账记录的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 支付方式枚举
enum PaymentMethod {
  cash('现金'),
  wechat('微信转账'),
  bankCard('银行卡');

  final String value;
  const PaymentMethod(this.value);

  static PaymentMethod fromString(String value) {
    return PaymentMethod.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

/// 进账记录模型
class Income {
  final int id;
  final int userId;
  final String incomeDate;
  final int? customerId;
  final double amount;
  final double discount;
  final int? employeeId;
  final PaymentMethod paymentMethod;
  final String? note;
  final String? createdAt;

  Income({
    required this.id,
    required this.userId,
    required this.incomeDate,
    this.customerId,
    required this.amount,
    this.discount = 0.0,
    this.employeeId,
    required this.paymentMethod,
    this.note,
    this.createdAt,
  });

  factory Income.fromJson(Map<String, dynamic> json) {
    return Income(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      incomeDate: json['incomeDate'] as String? ?? json['income_date'] as String,
      customerId: json['customerId'] as int? ?? json['customer_id'] as int?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
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
      'incomeDate': incomeDate,
      if (customerId != null) 'customerId': customerId,
      'amount': amount,
      'discount': discount,
      if (employeeId != null) 'employeeId': employeeId,
      'paymentMethod': paymentMethod.value,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  Income copyWith({
    int? id,
    int? userId,
    String? incomeDate,
    int? customerId,
    double? amount,
    double? discount,
    int? employeeId,
    PaymentMethod? paymentMethod,
    String? note,
    String? createdAt,
  }) {
    return Income(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      incomeDate: incomeDate ?? this.incomeDate,
      customerId: customerId ?? this.customerId,
      amount: amount ?? this.amount,
      discount: discount ?? this.discount,
      employeeId: employeeId ?? this.employeeId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 进账创建请求
class IncomeCreate {
  final String incomeDate;
  final int? customerId;
  final double amount; // 进账金额（必须大于0）
  final double discount; // 优惠金额
  final int? employeeId;
  final PaymentMethod paymentMethod;
  final String? note;

  IncomeCreate({
    required this.incomeDate,
    this.customerId,
    required this.amount,
    this.discount = 0.0,
    this.employeeId,
    required this.paymentMethod,
    this.note,
  }) : assert(amount > 0, '进账金额必须大于0');

  Map<String, dynamic> toJson() {
    return {
      'incomeDate': incomeDate,
      if (customerId != null) 'customerId': customerId,
      'amount': amount,
      'discount': discount,
      if (employeeId != null) 'employeeId': employeeId,
      'paymentMethod': paymentMethod.value,
      if (note != null) 'note': note,
    };
  }
}

/// 进账更新请求
class IncomeUpdate {
  final String? incomeDate;
  final int? customerId;
  final double? amount; // 进账金额（必须大于0）
  final double? discount; // 优惠金额
  final int? employeeId;
  final PaymentMethod? paymentMethod;
  final String? note;

  IncomeUpdate({
    this.incomeDate,
    this.customerId,
    this.amount,
    this.discount,
    this.employeeId,
    this.paymentMethod,
    this.note,
  }) : assert(amount == null || amount! > 0, '进账金额必须大于0');

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (incomeDate != null) json['incomeDate'] = incomeDate;
    if (customerId != null) json['customerId'] = customerId;
    if (amount != null) json['amount'] = amount;
    if (discount != null) json['discount'] = discount;
    if (employeeId != null) json['employeeId'] = employeeId;
    if (paymentMethod != null) json['paymentMethod'] = paymentMethod!.value;
    if (note != null) json['note'] = note;
    return json;
  }
}

class IncomeRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取进账记录列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（备注）
  /// [startDate] 开始日期（ISO8601格式）
  /// [endDate] 结束日期（ISO8601格式）
  /// [customerId] 客户ID筛选（null 表示不筛选，0 表示未分配客户）
  /// 
  /// 返回分页的进账记录列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Income>> getIncomes({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? customerId,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getIncomesLocal(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
      );
    } else {
      return await _getIncomesServer(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
      );
    }
  }

  /// 从服务器获取进账记录列表
  Future<PaginatedResponse<Income>> _getIncomesServer({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? customerId,
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

      if (customerId != null) {
        queryParams['customer_id'] = customerId.toString();
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/income',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Income>.fromJson(
          response.data!,
          (json) => Income.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取进账记录列表失败', e);
    }
  }

  /// 从本地数据库获取进账记录列表
  Future<PaginatedResponse<Income>> _getIncomesLocal({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? customerId,
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
        whereClause += ' AND incomeDate >= ?';
        whereArgs.add(startDate);
      }
      
      if (endDate != null) {
        whereClause += ' AND incomeDate <= ?';
        whereArgs.add(endDate);
      }
      
      if (customerId != null) {
        if (customerId == 0) {
          whereClause += ' AND (customerId IS NULL OR customerId = 0)';
        } else {
          whereClause += ' AND customerId = ?';
          whereArgs.add(customerId);
        }
      }
      
      // 获取总数
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM income WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final incomesResult = await db.query(
        'income',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Income 对象
      final incomes = incomesResult.map((row) {
        return Income(
          id: row['id'] as int,
          userId: row['userId'] as int,
          incomeDate: row['incomeDate'] as String,
          customerId: row['customerId'] as int?,
          amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
          discount: (row['discount'] as num?)?.toDouble() ?? 0.0,
          employeeId: row['employeeId'] as int?,
          paymentMethod: PaymentMethod.fromString(row['paymentMethod'] as String? ?? '现金'),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Income>(
        items: incomes,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取进账记录列表失败', e);
    }
  }

  /// 获取单个进账记录详情
  /// 
  /// [incomeId] 进账记录ID
  /// 
  /// 返回进账记录详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Income> getIncome(int incomeId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getIncomeLocal(incomeId);
    } else {
      return await _getIncomeServer(incomeId);
    }
  }

  /// 从服务器获取单个进账记录
  Future<Income> _getIncomeServer(int incomeId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/income/$incomeId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Income.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取进账记录详情失败', e);
    }
  }

  /// 从本地数据库获取单个进账记录
  Future<Income> _getIncomeLocal(int incomeId) async {
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
        'income',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [incomeId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '进账记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Income(
        id: row['id'] as int,
        userId: row['userId'] as int,
        incomeDate: row['incomeDate'] as String,
        customerId: row['customerId'] as int?,
        amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
        discount: (row['discount'] as num?)?.toDouble() ?? 0.0,
        employeeId: row['employeeId'] as int?,
        paymentMethod: PaymentMethod.fromString(row['paymentMethod'] as String? ?? '现金'),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取进账记录详情失败', e);
    }
  }

  /// 创建进账记录
  /// 
  /// [income] 进账创建请求
  /// 
  /// 返回创建的进账记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Income> createIncome(IncomeCreate income) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createIncomeLocal(income);
    } else {
      return await _createIncomeServer(income);
    }
  }

  /// 在服务器创建进账记录
  Future<Income> _createIncomeServer(IncomeCreate income) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/income',
        body: income.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Income.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建进账记录失败', e);
    }
  }

  /// 在本地数据库创建进账记录
  Future<Income> _createIncomeLocal(IncomeCreate income) async {
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
      
      // 验证客户是否存在（如果提供了 customerId）
      if (income.customerId != null) {
        final customer = await db.query(
          'customers',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [income.customerId, userId, workspaceId],
        );
        
        if (customer.isEmpty) {
          throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 验证员工是否存在（如果提供了 employeeId）
      if (income.employeeId != null) {
        final employee = await db.query(
          'employees',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [income.employeeId, userId, workspaceId],
        );
        
        if (employee.isEmpty) {
          throw ApiError(message: '员工不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 插入进账记录
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('income', {
        'userId': userId,
        'workspaceId': workspaceId,
        'incomeDate': income.incomeDate,
        'customerId': income.customerId,
        'amount': income.amount,
        'discount': income.discount,
        'employeeId': income.employeeId,
        'paymentMethod': income.paymentMethod.value,
        'note': income.note,
        'created_at': now,
      });
      
      // 返回创建的进账记录
      final createdIncome = Income(
        id: id,
        userId: userId,
        incomeDate: income.incomeDate,
        customerId: income.customerId,
        amount: income.amount,
        discount: income.discount,
        employeeId: income.employeeId,
        paymentMethod: income.paymentMethod,
        note: income.note,
        createdAt: now,
      );

      // 记录操作日志
      try {
        // 获取客户名称用于日志显示
        String customerName = '未知客户';
        if (income.customerId != null) {
          final customerResult = await db.query(
            'customers',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [income.customerId],
          );
          if (customerResult.isNotEmpty) {
            customerName = customerResult.first['name'] as String;
          }
        }
        final entityName = '$customerName (金额: ¥${income.amount})';
        await LocalAuditLogService().logCreate(
          entityType: EntityType.income,
          entityId: id,
          entityName: entityName,
          newData: {
            'id': id,
            'userId': userId,
            'incomeDate': income.incomeDate,
            'customerId': income.customerId,
            'amount': income.amount,
            'discount': income.discount,
            'employeeId': income.employeeId,
            'paymentMethod': income.paymentMethod.value,
            'note': income.note,
          },
        );
      } catch (e) {
        print('记录进账创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      return createdIncome;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('创建进账记录失败', e);
    }
  }

  /// 更新进账记录
  /// 
  /// [incomeId] 进账记录ID
  /// [update] 进账更新请求
  /// 
  /// 返回更新后的进账记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Income> updateIncome(int incomeId, IncomeUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateIncomeLocal(incomeId, update);
    } else {
      return await _updateIncomeServer(incomeId, update);
    }
  }

  /// 在服务器更新进账记录
  Future<Income> _updateIncomeServer(int incomeId, IncomeUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/income/$incomeId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Income.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新进账记录失败', e);
    }
  }

  /// 在本地数据库更新进账记录
  Future<Income> _updateIncomeLocal(int incomeId, IncomeUpdate update) async {
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
      
      // 检查进账记录是否存在
      final currentResult = await db.query(
        'income',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [incomeId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '进账记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      // 验证客户是否存在（如果更新了 customerId）
      if (update.customerId != null && update.customerId != currentResult.first['customerId']) {
        final customer = await db.query(
          'customers',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [update.customerId, userId, workspaceId],
        );
        
        if (customer.isEmpty) {
          throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
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
      if (update.incomeDate != null) updateData['incomeDate'] = update.incomeDate;
      if (update.customerId != null) updateData['customerId'] = update.customerId;
      if (update.amount != null) updateData['amount'] = update.amount;
      if (update.discount != null) updateData['discount'] = update.discount;
      if (update.employeeId != null) updateData['employeeId'] = update.employeeId;
      if (update.paymentMethod != null) updateData['paymentMethod'] = update.paymentMethod!.value;
      if (update.note != null) updateData['note'] = update.note;
      
      // 更新进账记录
      await db.update(
        'income',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [incomeId, userId, workspaceId],
      );
      
      // 返回更新后的进账记录
      final updatedResult = await db.query(
        'income',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [incomeId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedIncome = Income(
        id: row['id'] as int,
        userId: row['userId'] as int,
        incomeDate: row['incomeDate'] as String,
        customerId: row['customerId'] as int?,
        amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
        discount: (row['discount'] as num?)?.toDouble() ?? 0.0,
        employeeId: row['employeeId'] as int?,
        paymentMethod: PaymentMethod.fromString(row['paymentMethod'] as String? ?? '现金'),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );

      // 记录操作日志
      try {
        final current = currentResult.first;
        // 获取客户名称用于日志显示
        String customerName = '未知客户';
        if (updatedIncome.customerId != null) {
          final customerResult = await db.query(
            'customers',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [updatedIncome.customerId],
          );
          if (customerResult.isNotEmpty) {
            customerName = customerResult.first['name'] as String;
          }
        }
        final entityName = '$customerName (金额: ¥${updatedIncome.amount})';
        final oldData = {
          'id': current['id'],
          'userId': current['userId'],
          'incomeDate': current['incomeDate'],
          'customerId': current['customerId'],
          'amount': current['amount'],
          'discount': current['discount'],
          'employeeId': current['employeeId'],
          'paymentMethod': current['paymentMethod'],
          'note': current['note'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'incomeDate': row['incomeDate'],
          'customerId': row['customerId'],
          'amount': row['amount'],
          'discount': row['discount'],
          'employeeId': row['employeeId'],
          'paymentMethod': row['paymentMethod'],
          'note': row['note'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.income,
          entityId: incomeId,
          entityName: entityName,
          oldData: oldData,
          newData: newData,
        );
      } catch (e) {
        print('记录进账更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedIncome;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新进账记录失败', e);
    }
  }

  /// 删除进账记录
  /// 
  /// [incomeId] 进账记录ID
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteIncome(int incomeId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteIncomeLocal(incomeId);
    } else {
      return await _deleteIncomeServer(incomeId);
    }
  }

  /// 在服务器删除进账记录
  Future<void> _deleteIncomeServer(int incomeId) async {
    try {
      final response = await _apiService.delete(
        '/api/income/$incomeId',
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
      throw ApiError.unknown('删除进账记录失败', e);
    }
  }

  /// 在本地数据库删除进账记录
  Future<void> _deleteIncomeLocal(int incomeId) async {
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
      
      // 检查进账记录是否存在，并保存旧数据用于日志
      final income = await db.query(
        'income',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [incomeId, userId, workspaceId],
      );
      
      if (income.isEmpty) {
        throw ApiError(message: '进账记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final incomeRow = income.first;
      final amount = (incomeRow['amount'] as num?)?.toDouble() ?? 0.0;
      final customerId = incomeRow['customerId'] as int?;
      // 获取客户名称用于日志显示
      String customerName = '未知客户';
      if (customerId != null) {
        final customerResult = await db.query(
          'customers',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [customerId],
        );
        if (customerResult.isNotEmpty) {
          customerName = customerResult.first['name'] as String;
        }
      }
      final entityName = '$customerName (金额: ¥$amount)';
      final oldData = {
        'id': incomeRow['id'],
        'userId': incomeRow['userId'],
        'incomeDate': incomeRow['incomeDate'],
        'customerId': incomeRow['customerId'],
        'amount': incomeRow['amount'],
        'discount': incomeRow['discount'],
        'employeeId': incomeRow['employeeId'],
        'paymentMethod': incomeRow['paymentMethod'],
        'note': incomeRow['note'],
      };
      
      // 删除进账记录
      final deleted = await db.delete(
        'income',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [incomeId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除进账记录失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志
      try {
        await LocalAuditLogService().logDelete(
          entityType: EntityType.income,
          entityId: incomeId,
          entityName: entityName,
          oldData: oldData,
        );
      } catch (e) {
        print('记录进账删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除进账记录失败', e);
    }
  }
}


