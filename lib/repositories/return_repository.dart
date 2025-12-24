/// 退货仓库
/// 处理退货记录的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 退货记录模型
class Return {
  final int id;
  final int userId;
  final String productName;
  final double quantity; // 退货数量（必须大于0）
  final int? customerId;
  final String? returnDate;
  final double? totalReturnPrice;
  final String? note;
  final String? createdAt;

  Return({
    required this.id,
    required this.userId,
    required this.productName,
    required this.quantity,
    this.customerId,
    this.returnDate,
    this.totalReturnPrice,
    this.note,
    this.createdAt,
  });

  factory Return.fromJson(Map<String, dynamic> json) {
    return Return(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      productName: json['productName'] as String? ?? json['product_name'] as String,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      customerId: json['customerId'] as int? ?? json['customer_id'] as int?,
      returnDate: json['returnDate'] as String? ?? json['return_date'] as String?,
      totalReturnPrice: (json['totalReturnPrice'] as num?)?.toDouble() ??
          (json['total_return_price'] as num?)?.toDouble(),
      note: json['note'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'productName': productName,
      'quantity': quantity,
      if (customerId != null) 'customerId': customerId,
      if (returnDate != null) 'returnDate': returnDate,
      if (totalReturnPrice != null) 'totalReturnPrice': totalReturnPrice,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  Return copyWith({
    int? id,
    int? userId,
    String? productName,
    double? quantity,
    int? customerId,
    String? returnDate,
    double? totalReturnPrice,
    String? note,
    String? createdAt,
  }) {
    return Return(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      customerId: customerId ?? this.customerId,
      returnDate: returnDate ?? this.returnDate,
      totalReturnPrice: totalReturnPrice ?? this.totalReturnPrice,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 退货创建请求
class ReturnCreate {
  final String productName;
  final double quantity; // 退货数量（必须大于0）
  final int? customerId;
  final String? returnDate;
  final double? totalReturnPrice;
  final String? note;

  ReturnCreate({
    required this.productName,
    required this.quantity,
    this.customerId,
    this.returnDate,
    this.totalReturnPrice,
    this.note,
  }) : assert(quantity > 0, '退货数量必须大于0');

  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
      'quantity': quantity,
      if (customerId != null) 'customerId': customerId,
      if (returnDate != null) 'returnDate': returnDate,
      if (totalReturnPrice != null) 'totalReturnPrice': totalReturnPrice,
      if (note != null) 'note': note,
    };
  }
}

/// 退货更新请求
class ReturnUpdate {
  final String? productName;
  final double? quantity; // 退货数量（必须大于0）
  final int? customerId;
  final String? returnDate;
  final double? totalReturnPrice;
  final String? note;

  ReturnUpdate({
    this.productName,
    this.quantity,
    this.customerId,
    this.returnDate,
    this.totalReturnPrice,
    this.note,
  }) : assert(quantity == null || quantity! > 0, '退货数量必须大于0');

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (productName != null) json['productName'] = productName;
    if (quantity != null) json['quantity'] = quantity;
    if (customerId != null) json['customerId'] = customerId;
    if (returnDate != null) json['returnDate'] = returnDate;
    if (totalReturnPrice != null) json['totalReturnPrice'] = totalReturnPrice;
    if (note != null) json['note'] = note;
    return json;
  }
}

class ReturnRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取退货记录列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（产品名称）
  /// [startDate] 开始日期（ISO8601格式）
  /// [endDate] 结束日期（ISO8601格式）
  /// [customerId] 客户ID筛选（null 表示不筛选，0 表示未分配客户）
  /// 
  /// 返回分页的退货记录列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Return>> getReturns({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? customerId,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getReturnsLocal(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
      );
    } else {
      return await _getReturnsServer(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
      );
    }
  }

  /// 从服务器获取退货记录列表
  Future<PaginatedResponse<Return>> _getReturnsServer({
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
        '/api/returns',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Return>.fromJson(
          response.data!,
          (json) => Return.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取退货记录列表失败', e);
    }
  }

  /// 从本地数据库获取退货记录列表
  Future<PaginatedResponse<Return>> _getReturnsLocal({
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
        whereClause += ' AND productName LIKE ?';
        whereArgs.add('%$search%');
      }
      
      if (startDate != null) {
        whereClause += ' AND returnDate >= ?';
        whereArgs.add(startDate);
      }
      
      if (endDate != null) {
        whereClause += ' AND returnDate <= ?';
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
        'SELECT COUNT(*) as count FROM returns WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final returnsResult = await db.query(
        'returns',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Return 对象
      final returns = returnsResult.map((row) {
        return Return(
          id: row['id'] as int,
          userId: row['userId'] as int,
          productName: row['productName'] as String,
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
          customerId: row['customerId'] as int?,
          returnDate: row['returnDate'] as String?,
          totalReturnPrice: (row['totalReturnPrice'] as num?)?.toDouble(),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Return>(
        items: returns,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取退货记录列表失败', e);
    }
  }

  /// 获取单个退货记录详情
  /// 
  /// [returnId] 退货记录ID
  /// 
  /// 返回退货记录详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Return> getReturn(int returnId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getReturnLocal(returnId);
    } else {
      return await _getReturnServer(returnId);
    }
  }

  /// 从服务器获取单个退货记录
  Future<Return> _getReturnServer(int returnId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/returns/$returnId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Return.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取退货记录详情失败', e);
    }
  }

  /// 从本地数据库获取单个退货记录
  Future<Return> _getReturnLocal(int returnId) async {
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
        'returns',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [returnId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '退货记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Return(
        id: row['id'] as int,
        userId: row['userId'] as int,
        productName: row['productName'] as String,
        quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        customerId: row['customerId'] as int?,
        returnDate: row['returnDate'] as String?,
        totalReturnPrice: (row['totalReturnPrice'] as num?)?.toDouble(),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取退货记录详情失败', e);
    }
  }

  /// 创建退货记录
  /// 
  /// [returnRecord] 退货创建请求
  /// 
  /// 注意：退货时会自动增加产品库存（退货数量必须大于0）
  /// 
  /// 返回创建的退货记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Return> createReturn(ReturnCreate returnRecord) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createReturnLocal(returnRecord);
    } else {
      return await _createReturnServer(returnRecord);
    }
  }

  /// 在服务器创建退货记录
  Future<Return> _createReturnServer(ReturnCreate returnRecord) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/returns',
        body: returnRecord.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Return.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建退货记录失败', e);
    }
  }

  /// 在本地数据库创建退货记录（需要处理库存更新）
  Future<Return> _createReturnLocal(ReturnCreate returnRecord) async {
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
    if (returnRecord.customerId != null) {
      final customer = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [returnRecord.customerId, userId, workspaceId],
      );
      
      if (customer.isEmpty) {
        throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
    }
    
    // 查找产品
    final products = await db.query(
      'products',
      where: 'userId = ? AND workspaceId = ? AND name = ?',
      whereArgs: [userId, workspaceId, returnRecord.productName],
    );
    
    if (products.isEmpty) {
      throw ApiError(message: '产品不存在: ${returnRecord.productName}', errorCode: 'NOT_FOUND');
    }
    
    final product = products.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final currentVersion = product['version'] as int;
    
    // 使用事务确保数据一致性
    return await db.transaction((txn) async {
      // 增加产品库存（退货增加库存）
      await txn.update(
        'products',
        {
          'stock': currentStock + returnRecord.quantity,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [product['id'], userId, workspaceId, currentVersion],
      );
      
      // 插入退货记录
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('returns', {
        'userId': userId,
        'workspaceId': workspaceId,
        'productName': returnRecord.productName,
        'quantity': returnRecord.quantity,
        'customerId': returnRecord.customerId,
        'returnDate': returnRecord.returnDate ?? now,
        'totalReturnPrice': returnRecord.totalReturnPrice,
        'note': returnRecord.note,
        'created_at': now,
      });
      
      // 记录操作日志（在事务内）
      try {
        final entityName = '${returnRecord.productName} (数量: ${returnRecord.quantity})';
        await LocalAuditLogService().logCreate(
          entityType: EntityType.return_,
          entityId: id,
          entityName: entityName,
          newData: {
            'id': id,
            'userId': userId,
            'productName': returnRecord.productName,
            'quantity': returnRecord.quantity,
            'customerId': returnRecord.customerId,
            'returnDate': returnRecord.returnDate ?? now,
            'totalReturnPrice': returnRecord.totalReturnPrice,
            'note': returnRecord.note,
          },
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录退货创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      // 返回创建的退货记录
      return Return(
        id: id,
        userId: userId,
        productName: returnRecord.productName,
        quantity: returnRecord.quantity,
        customerId: returnRecord.customerId,
        returnDate: returnRecord.returnDate ?? now,
        totalReturnPrice: returnRecord.totalReturnPrice,
        note: returnRecord.note,
        createdAt: now,
      );
    });
  }

  /// 更新退货记录
  /// 
  /// [returnId] 退货记录ID
  /// [update] 退货更新请求
  /// 
  /// 注意：更新时会计算库存变化差值并更新产品库存
  /// - 如果新数量 > 旧数量，需要增加更多库存
  /// - 如果新数量 < 旧数量，需要减少库存（需检查库存是否足够）
  /// 
  /// 返回更新后的退货记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Return> updateReturn(int returnId, ReturnUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateReturnLocal(returnId, update);
    } else {
      return await _updateReturnServer(returnId, update);
    }
  }

  /// 在服务器更新退货记录
  Future<Return> _updateReturnServer(int returnId, ReturnUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/returns/$returnId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Return.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError catch (e) {
      // 如果是库存不足错误，提供更友好的错误信息
      if (e.statusCode == 400 && e.message.contains('库存不足')) {
        throw ApiError(
          message: e.message,
          errorCode: 'INSUFFICIENT_STOCK',
          statusCode: 400,
        );
      }
      // 如果是版本冲突
      if (e.statusCode == 409) {
        throw ApiError(
          message: '产品库存已被其他操作修改，请刷新后重试',
          errorCode: 'VERSION_CONFLICT',
          statusCode: 409,
        );
      }
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新退货记录失败', e);
    }
  }

  /// 在本地数据库更新退货记录（需要处理库存更新）
  Future<Return> _updateReturnLocal(int returnId, ReturnUpdate update) async {
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
    
    // 获取当前退货记录
    final currentReturnResult = await db.query(
      'returns',
      where: 'id = ? AND userId = ? AND workspaceId = ?',
      whereArgs: [returnId, userId, workspaceId],
    );
    
    if (currentReturnResult.isEmpty) {
      throw ApiError(message: '退货记录不存在或无权限访问', errorCode: 'NOT_FOUND');
    }
    
    final currentReturn = currentReturnResult.first;
    final oldQuantity = (currentReturn['quantity'] as num?)?.toDouble() ?? 0.0;
    final productName = update.productName ?? currentReturn['productName'] as String;
    
    // 验证客户是否存在（如果更新了 customerId）
    if (update.customerId != null && update.customerId != currentReturn['customerId']) {
      final customer = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [update.customerId, userId, workspaceId],
      );
      
      if (customer.isEmpty) {
        throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
    }
    
    // 如果更新了数量，需要处理库存变化
    if (update.quantity != null && update.quantity != oldQuantity) {
      // 查找产品
      final products = await db.query(
        'products',
        where: 'userId = ? AND workspaceId = ? AND name = ?',
        whereArgs: [userId, workspaceId, productName],
      );
      
      if (products.isEmpty) {
        throw ApiError(message: '产品不存在: $productName', errorCode: 'NOT_FOUND');
      }
      
      final product = products.first;
      final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
      final currentVersion = product['version'] as int;
      // 数量差值：新数量 - 旧数量（如果新数量更大，需要增加更多库存；如果新数量更小，需要减少库存）
      final quantityDiff = update.quantity! - oldQuantity;
      
      // 如果数量减少（quantityDiff < 0），检查库存是否足够减少
      if (quantityDiff < 0 && currentStock < -quantityDiff) {
        throw ApiError(
          message: '库存不足，当前库存：$currentStock，需要减少：${-quantityDiff}',
          errorCode: 'INSUFFICIENT_STOCK',
          statusCode: 400,
        );
      }
      
      // 使用事务确保数据一致性
      return await db.transaction((txn) async {
        // 更新产品库存（数量增加则增加库存，数量减少则减少库存）
        await txn.update(
          'products',
          {
            'stock': currentStock + quantityDiff,
            'version': currentVersion + 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
          whereArgs: [product['id'], userId, workspaceId, currentVersion],
        );
        
        // 更新退货记录
        final updateData = <String, dynamic>{};
        if (update.productName != null) updateData['productName'] = update.productName;
        if (update.quantity != null) updateData['quantity'] = update.quantity;
        if (update.customerId != null) updateData['customerId'] = update.customerId;
        if (update.returnDate != null) updateData['returnDate'] = update.returnDate;
        if (update.totalReturnPrice != null) updateData['totalReturnPrice'] = update.totalReturnPrice;
        if (update.note != null) updateData['note'] = update.note;
        
        await txn.update(
          'returns',
          updateData,
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [returnId, userId, workspaceId],
        );
        
        // 返回更新后的退货记录
        final updatedResult = await txn.query(
          'returns',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [returnId, userId, workspaceId],
        );
        
        final row = updatedResult.first;
        
        // 记录操作日志（在事务内）
        try {
          final entityName = '${row['productName']} (数量: ${row['quantity']})';
          final oldData = {
            'id': currentReturn['id'],
            'userId': currentReturn['userId'],
            'productName': currentReturn['productName'],
            'quantity': currentReturn['quantity'],
            'customerId': currentReturn['customerId'],
            'returnDate': currentReturn['returnDate'],
            'totalReturnPrice': currentReturn['totalReturnPrice'],
            'note': currentReturn['note'],
          };
          final newData = {
            'id': row['id'],
            'userId': row['userId'],
            'productName': row['productName'],
            'quantity': row['quantity'],
            'customerId': row['customerId'],
            'returnDate': row['returnDate'],
            'totalReturnPrice': row['totalReturnPrice'],
            'note': row['note'],
          };
          await LocalAuditLogService().logUpdate(
            entityType: EntityType.return_,
            entityId: returnId,
            entityName: entityName,
            oldData: oldData,
            newData: newData,
            transaction: txn,
            userId: userId,
            workspaceId: workspaceId,
            username: username,
          );
        } catch (e) {
          print('记录退货更新日志失败: $e');
          // 日志记录失败不影响业务
        }

        return Return(
          id: row['id'] as int,
          userId: row['userId'] as int,
          productName: row['productName'] as String,
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
          customerId: row['customerId'] as int?,
          returnDate: row['returnDate'] as String?,
          totalReturnPrice: (row['totalReturnPrice'] as num?)?.toDouble(),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      });
    } else {
      // 如果没有更新数量，直接更新退货记录
      final updateData = <String, dynamic>{};
      if (update.productName != null) updateData['productName'] = update.productName;
      if (update.customerId != null) updateData['customerId'] = update.customerId;
      if (update.returnDate != null) updateData['returnDate'] = update.returnDate;
      if (update.totalReturnPrice != null) updateData['totalReturnPrice'] = update.totalReturnPrice;
      if (update.note != null) updateData['note'] = update.note;
      
      await db.update(
        'returns',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [returnId, userId, workspaceId],
      );
      
      // 返回更新后的退货记录
      final updatedResult = await db.query(
        'returns',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [returnId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedReturn = Return(
        id: row['id'] as int,
        userId: row['userId'] as int,
        productName: row['productName'] as String,
        quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        customerId: row['customerId'] as int?,
        returnDate: row['returnDate'] as String?,
        totalReturnPrice: (row['totalReturnPrice'] as num?)?.toDouble(),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );

      // 记录操作日志
      try {
        final entityName = '${updatedReturn.productName} (数量: ${updatedReturn.quantity})';
        final oldData = {
          'id': currentReturn['id'],
          'userId': currentReturn['userId'],
          'productName': currentReturn['productName'],
          'quantity': currentReturn['quantity'],
          'customerId': currentReturn['customerId'],
          'returnDate': currentReturn['returnDate'],
          'totalReturnPrice': currentReturn['totalReturnPrice'],
          'note': currentReturn['note'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'productName': row['productName'],
          'quantity': row['quantity'],
          'customerId': row['customerId'],
          'returnDate': row['returnDate'],
          'totalReturnPrice': row['totalReturnPrice'],
          'note': row['note'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.return_,
          entityId: returnId,
          entityName: entityName,
          oldData: oldData,
          newData: newData,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录退货更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedReturn;
    }
  }

  /// 删除退货记录
  /// 
  /// [returnId] 退货记录ID
  /// 
  /// 注意：删除时会自动减少产品库存（因为退货被撤销）
  /// 需要检查删除后库存不能为负
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteReturn(int returnId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteReturnLocal(returnId);
    } else {
      return await _deleteReturnServer(returnId);
    }
  }

  /// 在服务器删除退货记录
  Future<void> _deleteReturnServer(int returnId) async {
    try {
      final response = await _apiService.delete(
        '/api/returns/$returnId',
        fromJsonT: (json) => json,
      );

      if (!response.isSuccess) {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError catch (e) {
      // 如果是库存不足错误
      if (e.statusCode == 400 && e.message.contains('库存不足')) {
        throw ApiError(
          message: e.message,
          errorCode: 'INSUFFICIENT_STOCK',
          statusCode: 400,
        );
      }
      // 如果是版本冲突
      if (e.statusCode == 409) {
        throw ApiError(
          message: '产品库存已被其他操作修改，请刷新后重试',
          errorCode: 'VERSION_CONFLICT',
          statusCode: 409,
        );
      }
      rethrow;
    } catch (e) {
      throw ApiError.unknown('删除退货记录失败', e);
    }
  }

  /// 在本地数据库删除退货记录（需要减少库存）
  Future<void> _deleteReturnLocal(int returnId) async {
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
    
    // 获取当前退货记录
    final returnResult = await db.query(
      'returns',
      where: 'id = ? AND userId = ? AND workspaceId = ?',
      whereArgs: [returnId, userId, workspaceId],
    );
    
    if (returnResult.isEmpty) {
      throw ApiError(message: '退货记录不存在或无权限访问', errorCode: 'NOT_FOUND');
    }
    
    final returnRecord = returnResult.first;
    final productName = returnRecord['productName'] as String;
    final quantity = (returnRecord['quantity'] as num?)?.toDouble() ?? 0.0;
    
    // 查找产品
    final products = await db.query(
      'products',
      where: 'userId = ? AND workspaceId = ? AND name = ?',
      whereArgs: [userId, workspaceId, productName],
    );
    
    if (products.isEmpty) {
      // 产品不存在，仍然删除退货记录（可能是产品已被删除）
      await db.delete(
        'returns',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [returnId, userId, workspaceId],
      );
      return;
    }
    
    final product = products.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final currentVersion = product['version'] as int;
    
    // 检查删除后库存是否足够（不能为负）
    if (currentStock < quantity) {
      throw ApiError(
        message: '库存不足，当前库存：$currentStock，需要减少：$quantity',
        errorCode: 'INSUFFICIENT_STOCK',
        statusCode: 400,
      );
    }
    
    // 使用事务确保数据一致性
    await db.transaction((txn) async {
      // 减少产品库存（删除退货记录，撤销退货）
      await txn.update(
        'products',
        {
          'stock': currentStock - quantity,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [product['id'], userId, workspaceId, currentVersion],
      );
      
      // 删除退货记录
      final deleted = await txn.delete(
        'returns',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [returnId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除退货记录失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志（在事务内）
      try {
        final entityName = '$productName (数量: $quantity)';
        final oldData = {
          'id': returnRecord['id'],
          'userId': returnRecord['userId'],
          'productName': returnRecord['productName'],
          'quantity': returnRecord['quantity'],
          'customerId': returnRecord['customerId'],
          'returnDate': returnRecord['returnDate'],
          'totalReturnPrice': returnRecord['totalReturnPrice'],
          'note': returnRecord['note'],
        };
        await LocalAuditLogService().logDelete(
          entityType: EntityType.return_,
          entityId: returnId,
          entityName: entityName,
          oldData: oldData,
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录退货删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    });
  }
}


