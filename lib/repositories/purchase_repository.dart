/// 采购仓库
/// 处理采购记录的增删改查功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 采购记录模型
class Purchase {
  final int id;
  final int userId;
  final String productName;
  final double quantity; // 采购数量（可为负数表示采购退货）
  final String? purchaseDate;
  final int? supplierId;
  final double? totalPurchasePrice;
  final String? note;
  final String? createdAt;

  Purchase({
    required this.id,
    required this.userId,
    required this.productName,
    required this.quantity,
    this.purchaseDate,
    this.supplierId,
    this.totalPurchasePrice,
    this.note,
    this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      productName: json['productName'] as String? ?? json['product_name'] as String,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      purchaseDate: json['purchaseDate'] as String? ?? json['purchase_date'] as String?,
      supplierId: json['supplierId'] as int? ?? json['supplier_id'] as int?,
      totalPurchasePrice: (json['totalPurchasePrice'] as num?)?.toDouble() ??
          (json['total_purchase_price'] as num?)?.toDouble(),
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
      if (purchaseDate != null) 'purchaseDate': purchaseDate,
      if (supplierId != null) 'supplierId': supplierId,
      if (totalPurchasePrice != null) 'totalPurchasePrice': totalPurchasePrice,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  Purchase copyWith({
    int? id,
    int? userId,
    String? productName,
    double? quantity,
    String? purchaseDate,
    int? supplierId,
    double? totalPurchasePrice,
    String? note,
    String? createdAt,
  }) {
    return Purchase(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      supplierId: supplierId ?? this.supplierId,
      totalPurchasePrice: totalPurchasePrice ?? this.totalPurchasePrice,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 采购创建请求
class PurchaseCreate {
  final String productName;
  final double quantity; // 采购数量（可为负数表示采购退货）
  final String? purchaseDate;
  final int? supplierId;
  final double? totalPurchasePrice;
  final String? note;

  PurchaseCreate({
    required this.productName,
    required this.quantity,
    this.purchaseDate,
    this.supplierId,
    this.totalPurchasePrice,
    this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      'productName': productName,
      'quantity': quantity,
      if (purchaseDate != null) 'purchaseDate': purchaseDate,
      // 如果 supplierId 为 0，也发送 0（服务器端会将其转换为 NULL）
      if (supplierId != null) 'supplierId': supplierId,
      if (totalPurchasePrice != null) 'totalPurchasePrice': totalPurchasePrice,
      if (note != null) 'note': note,
    };
  }
}

/// 采购更新请求
class PurchaseUpdate {
  final String? productName;
  final double? quantity;
  final String? purchaseDate;
  final int? supplierId;
  final double? totalPurchasePrice;
  final String? note;

  PurchaseUpdate({
    this.productName,
    this.quantity,
    this.purchaseDate,
    this.supplierId,
    this.totalPurchasePrice,
    this.note,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (productName != null) json['productName'] = productName;
    if (quantity != null) json['quantity'] = quantity;
    if (purchaseDate != null) json['purchaseDate'] = purchaseDate;
    if (supplierId != null) json['supplierId'] = supplierId;
    if (totalPurchasePrice != null) json['totalPurchasePrice'] = totalPurchasePrice;
    if (note != null) json['note'] = note;
    return json;
  }
}

class PurchaseRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取采购记录列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（产品名称）
  /// [startDate] 开始日期（ISO8601格式）
  /// [endDate] 结束日期（ISO8601格式）
  /// [supplierId] 供应商ID筛选（null 表示不筛选，0 表示未分配供应商）
  /// 
  /// 返回分页的采购记录列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Purchase>> getPurchases({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? startDate,
    String? endDate,
    int? supplierId,
  }) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getPurchasesLocal(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        supplierId: supplierId,
      );
    } else {
      return await _getPurchasesServer(
        page: page,
        pageSize: pageSize,
        search: search,
        startDate: startDate,
        endDate: endDate,
        supplierId: supplierId,
      );
    }
  }

  /// 从服务器获取采购记录列表
  Future<PaginatedResponse<Purchase>> _getPurchasesServer({
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
        '/api/purchases',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Purchase>.fromJson(
          response.data!,
          (json) => Purchase.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取采购记录列表失败', e);
    }
  }

  /// 从本地数据库获取采购记录列表
  Future<PaginatedResponse<Purchase>> _getPurchasesLocal({
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
        whereClause += ' AND productName LIKE ?';
        whereArgs.add('%$search%');
      }
      
      if (startDate != null) {
        whereClause += ' AND purchaseDate >= ?';
        whereArgs.add(startDate);
      }
      
      if (endDate != null) {
        whereClause += ' AND purchaseDate <= ?';
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
        'SELECT COUNT(*) as count FROM purchases WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final purchasesResult = await db.query(
        'purchases',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Purchase 对象
      final purchases = purchasesResult.map((row) {
        return Purchase(
          id: row['id'] as int,
          userId: row['userId'] as int,
          productName: row['productName'] as String,
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
          purchaseDate: row['purchaseDate'] as String?,
          supplierId: row['supplierId'] as int?,
          totalPurchasePrice: (row['totalPurchasePrice'] as num?)?.toDouble(),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Purchase>(
        items: purchases,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取采购记录列表失败', e);
    }
  }

  /// 获取单个采购记录详情
  /// 
  /// [purchaseId] 采购记录ID
  /// 
  /// 返回采购记录详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Purchase> getPurchase(int purchaseId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getPurchaseLocal(purchaseId);
    } else {
      return await _getPurchaseServer(purchaseId);
    }
  }

  /// 从服务器获取单个采购记录
  Future<Purchase> _getPurchaseServer(int purchaseId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/purchases/$purchaseId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Purchase.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取采购记录详情失败', e);
    }
  }

  /// 从本地数据库获取单个采购记录
  Future<Purchase> _getPurchaseLocal(int purchaseId) async {
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
        'purchases',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [purchaseId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '采购记录不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Purchase(
        id: row['id'] as int,
        userId: row['userId'] as int,
        productName: row['productName'] as String,
        quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        purchaseDate: row['purchaseDate'] as String?,
        supplierId: row['supplierId'] as int?,
        totalPurchasePrice: (row['totalPurchasePrice'] as num?)?.toDouble(),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取采购记录详情失败', e);
    }
  }

  /// 创建采购记录
  /// 
  /// [purchase] 采购创建请求
  /// 
  /// 注意：采购时会自动更新产品库存
  /// - 正数数量：增加库存
  /// - 负数数量：减少库存（采购退货，需要检查库存是否足够）
  /// 
  /// 返回创建的采购记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Purchase> createPurchase(PurchaseCreate purchase) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createPurchaseLocal(purchase);
    } else {
      return await _createPurchaseServer(purchase);
    }
  }

  /// 在服务器创建采购记录
  Future<Purchase> _createPurchaseServer(PurchaseCreate purchase) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/purchases',
        body: purchase.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Purchase.fromJson(response.data!);
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
      throw ApiError.unknown('创建采购记录失败', e);
    }
  }

  /// 在本地数据库创建采购记录（需要处理库存更新）
  Future<Purchase> _createPurchaseLocal(PurchaseCreate purchase) async {
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
    if (purchase.supplierId != null && purchase.supplierId != 0) {
      final supplier = await db.query(
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [purchase.supplierId, userId, workspaceId],
      );
      
      if (supplier.isEmpty) {
        throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
    }
    
    // 查找产品
    final products = await db.query(
      'products',
      where: 'userId = ? AND workspaceId = ? AND name = ?',
      whereArgs: [userId, workspaceId, purchase.productName],
    );
    
    if (products.isEmpty) {
      throw ApiError(message: '产品不存在: ${purchase.productName}', errorCode: 'NOT_FOUND');
    }
    
    final product = products.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final currentVersion = product['version'] as int;
    
    // 如果是负数（采购退货），检查库存是否充足
    if (purchase.quantity < 0 && currentStock < -purchase.quantity) {
      throw ApiError(
        message: '库存不足，当前库存：$currentStock，需要：${-purchase.quantity}',
        errorCode: 'INSUFFICIENT_STOCK',
        statusCode: 400,
      );
    }
    
    // 使用事务确保数据一致性
    return await db.transaction((txn) async {
      // 更新产品库存（采购增加库存，采购退货减少库存）
      await txn.update(
        'products',
        {
          'stock': currentStock + purchase.quantity,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [product['id'], userId, workspaceId, currentVersion],
      );
      
      // 插入采购记录
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('purchases', {
        'userId': userId,
        'workspaceId': workspaceId,
        'productName': purchase.productName,
        'quantity': purchase.quantity,
        'purchaseDate': purchase.purchaseDate ?? now,
        'supplierId': purchase.supplierId == 0 ? null : purchase.supplierId,
        'totalPurchasePrice': purchase.totalPurchasePrice,
        'note': purchase.note,
        'created_at': now,
      });
      
      // 记录操作日志（在事务内）
      try {
        final entityName = '${purchase.productName} (数量: ${purchase.quantity})';
        await LocalAuditLogService().logCreate(
          entityType: EntityType.purchase,
          entityId: id,
          entityName: entityName,
          newData: {
            'id': id,
            'userId': userId,
            'productName': purchase.productName,
            'quantity': purchase.quantity,
            'purchaseDate': purchase.purchaseDate ?? now,
            'supplierId': purchase.supplierId == 0 ? null : purchase.supplierId,
            'totalPurchasePrice': purchase.totalPurchasePrice,
            'note': purchase.note,
          },
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录采购创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      // 返回创建的采购记录
      return Purchase(
        id: id,
        userId: userId,
        productName: purchase.productName,
        quantity: purchase.quantity,
        purchaseDate: purchase.purchaseDate ?? now,
        supplierId: purchase.supplierId == 0 ? null : purchase.supplierId,
        totalPurchasePrice: purchase.totalPurchasePrice,
        note: purchase.note,
        createdAt: now,
      );
    });
  }

  /// 更新采购记录
  /// 
  /// [purchaseId] 采购记录ID
  /// [update] 采购更新请求
  /// 
  /// 注意：更新时会计算库存变化差值并更新产品库存
  /// 
  /// 返回更新后的采购记录
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Purchase> updatePurchase(int purchaseId, PurchaseUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updatePurchaseLocal(purchaseId, update);
    } else {
      return await _updatePurchaseServer(purchaseId, update);
    }
  }

  /// 在服务器更新采购记录
  Future<Purchase> _updatePurchaseServer(int purchaseId, PurchaseUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/purchases/$purchaseId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Purchase.fromJson(response.data!);
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
      throw ApiError.unknown('更新采购记录失败', e);
    }
  }

  /// 在本地数据库更新采购记录（需要处理库存更新）
  Future<Purchase> _updatePurchaseLocal(int purchaseId, PurchaseUpdate update) async {
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
    
    // 获取当前采购记录
    final currentPurchaseResult = await db.query(
      'purchases',
      where: 'id = ? AND userId = ? AND workspaceId = ?',
      whereArgs: [purchaseId, userId, workspaceId],
    );
    
    if (currentPurchaseResult.isEmpty) {
      throw ApiError(message: '采购记录不存在或无权限访问', errorCode: 'NOT_FOUND');
    }
    
    final currentPurchase = currentPurchaseResult.first;
    final oldQuantity = (currentPurchase['quantity'] as num?)?.toDouble() ?? 0.0;
    final productName = update.productName ?? currentPurchase['productName'] as String;
    
    // 验证供应商是否存在（如果更新了 supplierId）
    if (update.supplierId != null && update.supplierId != currentPurchase['supplierId'] && update.supplierId != 0) {
      final supplier = await db.query(
        'suppliers',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [update.supplierId, userId, workspaceId],
      );
      
      if (supplier.isEmpty) {
        throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
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
        
        // 更新采购记录
        final updateData = <String, dynamic>{};
        if (update.productName != null) updateData['productName'] = update.productName;
        if (update.quantity != null) updateData['quantity'] = update.quantity;
        if (update.supplierId != null) updateData['supplierId'] = update.supplierId == 0 ? null : update.supplierId;
        if (update.purchaseDate != null) updateData['purchaseDate'] = update.purchaseDate;
        if (update.totalPurchasePrice != null) updateData['totalPurchasePrice'] = update.totalPurchasePrice;
        if (update.note != null) updateData['note'] = update.note;
        
        await txn.update(
          'purchases',
          updateData,
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [purchaseId, userId, workspaceId],
        );
        
        // 返回更新后的采购记录
        final updatedResult = await txn.query(
          'purchases',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [purchaseId, userId, workspaceId],
        );
        
        final row = updatedResult.first;
        
        // 记录操作日志（在事务内）
        try {
          final entityName = '${row['productName']} (数量: ${row['quantity']})';
          final oldData = {
            'id': currentPurchase['id'],
            'userId': currentPurchase['userId'],
            'productName': currentPurchase['productName'],
            'quantity': currentPurchase['quantity'],
            'purchaseDate': currentPurchase['purchaseDate'],
            'supplierId': currentPurchase['supplierId'],
            'totalPurchasePrice': currentPurchase['totalPurchasePrice'],
            'note': currentPurchase['note'],
          };
          final newData = {
            'id': row['id'],
            'userId': row['userId'],
            'productName': row['productName'],
            'quantity': row['quantity'],
            'purchaseDate': row['purchaseDate'],
            'supplierId': row['supplierId'],
            'totalPurchasePrice': row['totalPurchasePrice'],
            'note': row['note'],
          };
          await LocalAuditLogService().logUpdate(
            entityType: EntityType.purchase,
            entityId: purchaseId,
            entityName: entityName,
            oldData: oldData,
            newData: newData,
            transaction: txn,
            userId: userId,
            workspaceId: workspaceId,
            username: username,
          );
        } catch (e) {
          print('记录采购更新日志失败: $e');
          // 日志记录失败不影响业务
        }

        return Purchase(
          id: row['id'] as int,
          userId: row['userId'] as int,
          productName: row['productName'] as String,
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
          purchaseDate: row['purchaseDate'] as String?,
          supplierId: row['supplierId'] as int?,
          totalPurchasePrice: (row['totalPurchasePrice'] as num?)?.toDouble(),
          note: row['note'] as String?,
          createdAt: row['created_at'] as String?,
        );
      });
    } else {
      // 如果没有更新数量，直接更新采购记录
      final updateData = <String, dynamic>{};
      if (update.productName != null) updateData['productName'] = update.productName;
      if (update.supplierId != null) updateData['supplierId'] = update.supplierId == 0 ? null : update.supplierId;
      if (update.purchaseDate != null) updateData['purchaseDate'] = update.purchaseDate;
      if (update.totalPurchasePrice != null) updateData['totalPurchasePrice'] = update.totalPurchasePrice;
      if (update.note != null) updateData['note'] = update.note;
      
      await db.update(
        'purchases',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [purchaseId, userId, workspaceId],
      );
      
      // 返回更新后的采购记录
      final updatedResult = await db.query(
        'purchases',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [purchaseId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedPurchase = Purchase(
        id: row['id'] as int,
        userId: row['userId'] as int,
        productName: row['productName'] as String,
        quantity: (row['quantity'] as num?)?.toDouble() ?? 0.0,
        purchaseDate: row['purchaseDate'] as String?,
        supplierId: row['supplierId'] as int?,
        totalPurchasePrice: (row['totalPurchasePrice'] as num?)?.toDouble(),
        note: row['note'] as String?,
        createdAt: row['created_at'] as String?,
      );

      // 记录操作日志
      try {
        final entityName = '${updatedPurchase.productName} (数量: ${updatedPurchase.quantity})';
        final oldData = {
          'id': currentPurchase['id'],
          'userId': currentPurchase['userId'],
          'productName': currentPurchase['productName'],
          'quantity': currentPurchase['quantity'],
          'purchaseDate': currentPurchase['purchaseDate'],
          'supplierId': currentPurchase['supplierId'],
          'totalPurchasePrice': currentPurchase['totalPurchasePrice'],
          'note': currentPurchase['note'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'productName': row['productName'],
          'quantity': row['quantity'],
          'purchaseDate': row['purchaseDate'],
          'supplierId': row['supplierId'],
          'totalPurchasePrice': row['totalPurchasePrice'],
          'note': row['note'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.purchase,
          entityId: purchaseId,
          entityName: entityName,
          oldData: oldData,
          newData: newData,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录采购更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedPurchase;
    }
  }

  /// 删除采购记录
  /// 
  /// [purchaseId] 采购记录ID
  /// 
  /// 注意：删除时会自动恢复产品库存（减去采购数量）
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deletePurchase(int purchaseId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deletePurchaseLocal(purchaseId);
    } else {
      return await _deletePurchaseServer(purchaseId);
    }
  }

  /// 在服务器删除采购记录
  Future<void> _deletePurchaseServer(int purchaseId) async {
    try {
      final response = await _apiService.delete(
        '/api/purchases/$purchaseId',
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
      throw ApiError.unknown('删除采购记录失败', e);
    }
  }

  /// 在本地数据库删除采购记录（需要恢复库存）
  Future<void> _deletePurchaseLocal(int purchaseId) async {
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
    
    // 获取当前采购记录
    final purchaseResult = await db.query(
      'purchases',
      where: 'id = ? AND userId = ? AND workspaceId = ?',
      whereArgs: [purchaseId, userId, workspaceId],
    );
    
    if (purchaseResult.isEmpty) {
      throw ApiError(message: '采购记录不存在或无权限访问', errorCode: 'NOT_FOUND');
    }
    
    final purchase = purchaseResult.first;
    final productName = purchase['productName'] as String;
    final quantity = (purchase['quantity'] as num?)?.toDouble() ?? 0.0;
    
    // 查找产品
    final products = await db.query(
      'products',
      where: 'userId = ? AND workspaceId = ? AND name = ?',
      whereArgs: [userId, workspaceId, productName],
    );
    
    if (products.isEmpty) {
      // 产品不存在，仍然删除采购记录（可能是产品已被删除）
      await db.delete(
        'purchases',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [purchaseId, userId, workspaceId],
      );
      return;
    }
    
    final product = products.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final currentVersion = product['version'] as int;
    
    // 如果采购数量为正数，删除时需要减少库存；如果为负数，删除时需要增加库存
    // 即：stock = stock - quantity（如果 quantity 为正，则减少；如果 quantity 为负，则增加）
    
    // 使用事务确保数据一致性
    await db.transaction((txn) async {
      // 恢复产品库存（减去采购数量）
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
      
      // 删除采购记录
      final deleted = await txn.delete(
        'purchases',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [purchaseId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除采购记录失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志（在事务内）
      try {
        final entityName = '$productName (数量: $quantity)';
        final oldData = {
          'id': purchase['id'],
          'userId': purchase['userId'],
          'productName': purchase['productName'],
          'quantity': purchase['quantity'],
          'purchaseDate': purchase['purchaseDate'],
          'supplierId': purchase['supplierId'],
          'totalPurchasePrice': purchase['totalPurchasePrice'],
          'note': purchase['note'],
        };
        await LocalAuditLogService().logDelete(
          entityType: EntityType.purchase,
          entityId: purchaseId,
          entityName: entityName,
          oldData: oldData,
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录采购删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    });
  }
}


