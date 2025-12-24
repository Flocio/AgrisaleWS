/// 销售仓库
/// 处理销售记录的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 销售记录模型
class Sale {
  final int id;
  final int userId;
  final String productName;
  final double quantity; // 销售数量（必须大于0）
  final int? customerId;
  final String? saleDate;
  final double? totalSalePrice;
  final String? note;
  final String? createdAt;

  Sale({
    required this.id,
    required this.userId,
    required this.productName,
    required this.quantity,
    this.customerId,
    this.saleDate,
    this.totalSalePrice,
    this.note,
    this.createdAt,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      productName: json['productName'] as String? ?? json['product_name'] as String,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      customerId: json['customerId'] as int? ?? json['customer_id'] as int?,
      saleDate: json['saleDate'] as String? ?? json['sale_date'] as String?,
      totalSalePrice: (json['totalSalePrice'] as num?)?.toDouble() ??
          (json['total_sale_price'] as num?)?.toDouble(),
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
      if (saleDate != null) 'saleDate': saleDate,
      if (totalSalePrice != null) 'totalSalePrice': totalSalePrice,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  Sale copyWith({
    int? id,
    int? userId,
    String? productName,
    double? quantity,
    int? customerId,
    String? saleDate,
    double? totalSalePrice,
    String? note,
    String? createdAt,
  }) {
    return Sale(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      customerId: customerId ?? this.customerId,
      saleDate: saleDate ?? this.saleDate,
      totalSalePrice: totalSalePrice ?? this.totalSalePrice,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 销售创建请求
class SaleCreate {
  final String productName;
  final double quantity; // 销售数量（必须大于0）
  final int? customerId;
  final String? saleDate;
  final double? totalSalePrice;
  final String? note;

  SaleCreate({
    required this.productName,
    required this.quantity,
    this.customerId,
    this.saleDate,
    this.totalSalePrice,
    this.note,
  }) : assert(quantity > 0, '销售数量必须大于0');

  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
      'quantity': quantity,
      if (customerId != null) 'customerId': customerId,
      if (saleDate != null) 'saleDate': saleDate,
      if (totalSalePrice != null) 'totalSalePrice': totalSalePrice,
      if (note != null) 'note': note,
    };
  }
}

/// 销售更新请求
class SaleUpdate {
  final String? productName;
  final double? quantity; // 销售数量（必须大于0）
  final int? customerId;
  final String? saleDate;
  final double? totalSalePrice;
  final String? note;

  SaleUpdate({
    this.productName,
    this.quantity,
    this.customerId,
    this.saleDate,
    this.totalSalePrice,
    this.note,
  }) : assert(quantity == null || quantity! > 0, '销售数量必须大于0');

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (productName != null) json['productName'] = productName;
    if (quantity != null) json['quantity'] = quantity;
    if (customerId != null) json['customerId'] = customerId;
    if (saleDate != null) json['saleDate'] = saleDate;
    if (totalSalePrice != null) json['totalSalePrice'] = totalSalePrice;
    if (note != null) json['note'] = note;
    return json;
  }
}

class SaleRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取销售记录列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（产品名称）
  /// [startDate] 开始日期（ISO8601格式）
  /// [endDate] 结束日期（ISO8601格式）
  /// [customerId] 客户ID筛选（null 表示不筛选，0 表示未分配客户）
  /// 
  /// 返回分页的销售记录列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Sale>> getSales({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? customerId,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getSalesLocal(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
      );
    } else {
      return await _getSalesServer(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
      );
    }
  }

  /// 从服务器获取销售记录列表
  Future<PaginatedResponse<Sale>> _getSalesServer({
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
        '/api/sales',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Sale>.fromJson(
          response.data!,
          (json) => Sale.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取销售记录列表失败', e);
    }
  }

  /// 从本地数据库获取销售记录列表
  Future<PaginatedResponse<Sale>> _getSalesLocal({
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
        whereClause += ' AND saleDate >= ?';
        whereArgs.add(startDate);
      }
      
      if (endDate != null) {
        whereClause += ' AND saleDate <= ?';
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
        'SELECT COUNT(*) as count FROM sales WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final salesResult = await db.query(
        'sales',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Sale 对象
      final sales = salesResult.map((row) {
        return Sale(
          id: row['id'] as int,
          userId: row['userId'] as int,
          productName: row['productName'] as String,
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
          customerId: row['customerId'] as int?,
          saleDate: row['saleDate'] as String?,
          totalSalePrice: (row['totalSalePrice'] as num?)?.toDouble(),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Sale>(
        items: sales,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取销售记录列表失败', e);
    }
  }

  /// 获取单个销售记录详情
  /// 
  /// [saleId] 销售记录ID
  /// 
  /// 返回销售记录详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Sale> getSale(int saleId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getSaleLocal(saleId);
    } else {
      return await _getSaleServer(saleId);
    }
  }

  /// 从服务器获取单个销售记录
  Future<Sale> _getSaleServer(int saleId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/sales/$saleId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Sale.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取销售记录详情失败', e);
    }
  }

  /// 从本地数据库获取单个销售记录
  Future<Sale> _getSaleLocal(int saleId) async {
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
        'sales',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [saleId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '销售记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Sale(
        id: row['id'] as int,
        userId: row['userId'] as int,
        productName: row['productName'] as String,
        quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        customerId: row['customerId'] as int?,
        saleDate: row['saleDate'] as String?,
        totalSalePrice: (row['totalSalePrice'] as num?)?.toDouble(),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取销售记录详情失败', e);
    }
  }

  /// 创建销售记录
  /// 
  /// [sale] 销售创建请求
  /// 
  /// 注意：销售时会自动减少产品库存，销售前必须检查库存是否充足
  /// 
  /// 返回创建的销售记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Sale> createSale(SaleCreate sale) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createSaleLocal(sale);
    } else {
      return await _createSaleServer(sale);
    }
  }

  /// 在服务器创建销售记录
  Future<Sale> _createSaleServer(SaleCreate sale) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/sales',
        body: sale.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Sale.fromJson(response.data!);
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
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建销售记录失败', e);
    }
  }

  /// 在本地数据库创建销售记录（需要处理库存更新）
  Future<Sale> _createSaleLocal(SaleCreate sale) async {
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
    if (sale.customerId != null) {
      final customer = await db.query(
        'customers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [sale.customerId, userId, workspaceId],
      );
      
      if (customer.isEmpty) {
        throw ApiError(message: '客户不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
    }
    
    // 查找产品并检查库存
    final products = await db.query(
      'products',
      where: 'userId = ? AND workspaceId = ? AND name = ?',
      whereArgs: [userId, workspaceId, sale.productName],
    );
    
    if (products.isEmpty) {
      throw ApiError(message: '产品不存在: ${sale.productName}', errorCode: 'NOT_FOUND');
    }
    
    final product = products.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final currentVersion = product['version'] as int;
    
    // 检查库存是否充足
    if (currentStock < sale.quantity) {
      throw ApiError(
        message: '库存不足，当前库存：$currentStock，需要：${sale.quantity}',
        errorCode: 'INSUFFICIENT_STOCK',
        statusCode: 400,
      );
    }
    
    // 使用事务确保数据一致性
    return await db.transaction((txn) async {
      // 减少产品库存
      await txn.update(
        'products',
        {
          'stock': currentStock - sale.quantity,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [product['id'], userId, workspaceId, currentVersion],
      );
      
      // 插入销售记录
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('sales', {
        'userId': userId,
        'workspaceId': workspaceId,
        'productName': sale.productName,
        'quantity': sale.quantity,
        'customerId': sale.customerId,
        'saleDate': sale.saleDate ?? now,
        'totalSalePrice': sale.totalSalePrice,
        'note': sale.note,
        'created_at': now,
      });
      
      // 记录操作日志（在事务内）
      try {
        final entityName = '${sale.productName} (数量: ${sale.quantity})';
        await LocalAuditLogService().logCreate(
          entityType: EntityType.sale,
          entityId: id,
          entityName: entityName,
          newData: {
            'id': id,
            'userId': userId,
            'productName': sale.productName,
            'quantity': sale.quantity,
            'customerId': sale.customerId,
            'saleDate': sale.saleDate ?? now,
            'totalSalePrice': sale.totalSalePrice,
            'note': sale.note,
          },
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录销售创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      // 返回创建的销售记录
      return Sale(
        id: id,
        userId: userId,
        productName: sale.productName,
        quantity: sale.quantity,
        customerId: sale.customerId,
        saleDate: sale.saleDate ?? now,
        totalSalePrice: sale.totalSalePrice,
        note: sale.note,
        createdAt: now,
      );
    });
  }

  /// 更新销售记录
  /// 
  /// [saleId] 销售记录ID
  /// [update] 销售更新请求
  /// 
  /// 注意：更新时会计算库存变化差值并更新产品库存
  /// - 如果新数量 > 旧数量，需要减少更多库存（检查库存是否足够）
  /// - 如果新数量 < 旧数量，需要恢复部分库存
  /// 
  /// 返回更新后的销售记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Sale> updateSale(int saleId, SaleUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateSaleLocal(saleId, update);
    } else {
      return await _updateSaleServer(saleId, update);
    }
  }

  /// 在服务器更新销售记录
  Future<Sale> _updateSaleServer(int saleId, SaleUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/sales/$saleId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Sale.fromJson(response.data!);
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
      throw ApiError.unknown('更新销售记录失败', e);
    }
  }

  /// 在本地数据库更新销售记录（需要处理库存更新）
  Future<Sale> _updateSaleLocal(int saleId, SaleUpdate update) async {
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
    
    // 获取当前销售记录
    final currentSaleResult = await db.query(
      'sales',
      where: 'id = ? AND userId = ? AND workspaceId = ?',
      whereArgs: [saleId, userId, workspaceId],
    );
    
    if (currentSaleResult.isEmpty) {
      throw ApiError(message: '销售记录不存在或无权限访问', errorCode: 'NOT_FOUND');
    }
    
    final currentSale = currentSaleResult.first;
    final oldQuantity = (currentSale['quantity'] as num?)?.toDouble() ?? 0.0;
    final productName = update.productName ?? currentSale['productName'] as String;
    
    // 验证客户是否存在（如果更新了 customerId）
    if (update.customerId != null && update.customerId != currentSale['customerId']) {
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
      final quantityDiff = update.quantity! - oldQuantity;
      
      // 如果数量增加，检查库存是否足够
      if (quantityDiff > 0 && currentStock < quantityDiff) {
        throw ApiError(
          message: '库存不足，当前库存：$currentStock，需要增加：$quantityDiff',
          errorCode: 'INSUFFICIENT_STOCK',
          statusCode: 400,
        );
      }
      
      // 使用事务确保数据一致性
      return await db.transaction((txn) async {
        // 更新产品库存
        await txn.update(
          'products',
          {
            'stock': currentStock - quantityDiff,
            'version': currentVersion + 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
          whereArgs: [product['id'], userId, workspaceId, currentVersion],
        );
        
        // 更新销售记录
        final updateData = <String, dynamic>{};
        if (update.productName != null) updateData['productName'] = update.productName;
        if (update.quantity != null) updateData['quantity'] = update.quantity;
        if (update.customerId != null) updateData['customerId'] = update.customerId;
        if (update.saleDate != null) updateData['saleDate'] = update.saleDate;
        if (update.totalSalePrice != null) updateData['totalSalePrice'] = update.totalSalePrice;
        if (update.note != null) updateData['note'] = update.note;
        
        await txn.update(
          'sales',
          updateData,
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [saleId, userId, workspaceId],
        );
        
        // 返回更新后的销售记录
        final updatedResult = await txn.query(
          'sales',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [saleId, userId, workspaceId],
        );
        
        final row = updatedResult.first;
        
        // 记录操作日志（在事务内）
        try {
          final entityName = '${row['productName']} (数量: ${row['quantity']})';
          final oldData = {
            'id': currentSale['id'],
            'userId': currentSale['userId'],
            'productName': currentSale['productName'],
            'quantity': currentSale['quantity'],
            'customerId': currentSale['customerId'],
            'saleDate': currentSale['saleDate'],
            'totalSalePrice': currentSale['totalSalePrice'],
            'note': currentSale['note'],
          };
          final newData = {
            'id': row['id'],
            'userId': row['userId'],
            'productName': row['productName'],
            'quantity': row['quantity'],
            'customerId': row['customerId'],
            'saleDate': row['saleDate'],
            'totalSalePrice': row['totalSalePrice'],
            'note': row['note'],
          };
          await LocalAuditLogService().logUpdate(
            entityType: EntityType.sale,
            entityId: saleId,
            entityName: entityName,
            oldData: oldData,
            newData: newData,
            transaction: txn,
            userId: userId,
            workspaceId: workspaceId,
            username: username,
          );
        } catch (e) {
          print('记录销售更新日志失败: $e');
          // 日志记录失败不影响业务
        }

        return Sale(
          id: row['id'] as int,
          userId: row['userId'] as int,
          productName: row['productName'] as String,
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
          customerId: row['customerId'] as int?,
          saleDate: row['saleDate'] as String?,
          totalSalePrice: (row['totalSalePrice'] as num?)?.toDouble(),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      });
    } else {
      // 如果没有更新数量，直接更新销售记录
      final updateData = <String, dynamic>{};
      if (update.productName != null) updateData['productName'] = update.productName;
      if (update.customerId != null) updateData['customerId'] = update.customerId;
      if (update.saleDate != null) updateData['saleDate'] = update.saleDate;
      if (update.totalSalePrice != null) updateData['totalSalePrice'] = update.totalSalePrice;
      if (update.note != null) updateData['note'] = update.note;
      
      await db.update(
        'sales',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [saleId, userId, workspaceId],
      );
      
      // 返回更新后的销售记录
      final updatedResult = await db.query(
        'sales',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [saleId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedSale = Sale(
        id: row['id'] as int,
        userId: row['userId'] as int,
        productName: row['productName'] as String,
        quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        customerId: row['customerId'] as int?,
        saleDate: row['saleDate'] as String?,
        totalSalePrice: (row['totalSalePrice'] as num?)?.toDouble(),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );

      // 记录操作日志
      try {
        final entityName = '${updatedSale.productName} (数量: ${updatedSale.quantity})';
        final oldData = {
          'id': currentSale['id'],
          'userId': currentSale['userId'],
          'productName': currentSale['productName'],
          'quantity': currentSale['quantity'],
          'customerId': currentSale['customerId'],
          'saleDate': currentSale['saleDate'],
          'totalSalePrice': currentSale['totalSalePrice'],
          'note': currentSale['note'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'productName': row['productName'],
          'quantity': row['quantity'],
          'customerId': row['customerId'],
          'saleDate': row['saleDate'],
          'totalSalePrice': row['totalSalePrice'],
          'note': row['note'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.sale,
          entityId: saleId,
          entityName: entityName,
          oldData: oldData,
          newData: newData,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录销售更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedSale;
    }
  }

  /// 删除销售记录
  /// 
  /// [saleId] 销售记录ID
  /// 
  /// 注意：删除时会自动恢复产品库存（增加库存）
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteSale(int saleId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteSaleLocal(saleId);
    } else {
      return await _deleteSaleServer(saleId);
    }
  }

  /// 在服务器删除销售记录
  Future<void> _deleteSaleServer(int saleId) async {
    try {
      final response = await _apiService.delete(
        '/api/sales/$saleId',
        fromJsonT: (json) => json,
      );

      if (!response.isSuccess) {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError catch (e) {
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
      throw ApiError.unknown('删除销售记录失败', e);
    }
  }

  /// 在本地数据库删除销售记录（需要恢复库存）
  Future<void> _deleteSaleLocal(int saleId) async {
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
    
    // 获取当前销售记录
    final saleResult = await db.query(
      'sales',
      where: 'id = ? AND userId = ? AND workspaceId = ?',
      whereArgs: [saleId, userId, workspaceId],
    );
    
    if (saleResult.isEmpty) {
      throw ApiError(message: '销售记录不存在或无权限访问', errorCode: 'NOT_FOUND');
    }
    
    final sale = saleResult.first;
    final productName = sale['productName'] as String;
    final quantity = (sale['quantity'] as num?)?.toDouble() ?? 0.0;
    
    // 查找产品
    final products = await db.query(
      'products',
      where: 'userId = ? AND workspaceId = ? AND name = ?',
      whereArgs: [userId, workspaceId, productName],
    );
    
    if (products.isEmpty) {
      // 产品不存在，仍然删除销售记录（可能是产品已被删除）
      await db.delete(
        'sales',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [saleId, userId, workspaceId],
      );
      return;
    }
    
    final product = products.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final currentVersion = product['version'] as int;
    
    // 使用事务确保数据一致性
    await db.transaction((txn) async {
      // 恢复产品库存
      await txn.update(
        'products',
        {
          'stock': currentStock + quantity,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [product['id'], userId, workspaceId, currentVersion],
      );
      
      // 删除销售记录
      final deleted = await txn.delete(
        'sales',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [saleId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除销售记录失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志（在事务内）
      try {
        final entityName = '$productName (数量: $quantity)';
        final oldData = {
          'id': sale['id'],
          'userId': sale['userId'],
          'productName': sale['productName'],
          'quantity': sale['quantity'],
          'customerId': sale['customerId'],
          'saleDate': sale['saleDate'],
          'totalSalePrice': sale['totalSalePrice'],
          'note': sale['note'],
        };
        await LocalAuditLogService().logDelete(
          entityType: EntityType.sale,
          entityId: saleId,
          entityName: entityName,
          oldData: oldData,
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录销售删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    });
  }
}


