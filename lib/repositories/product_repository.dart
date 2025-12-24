/// 产品仓库
/// 处理产品的增删改查、库存更新等功能
/// 支持本地存储和服务器存储两种模式

import 'package:sqflite/sqflite.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_audit_log_service.dart';
import '../database_helper.dart';

/// 产品单位枚举
enum ProductUnit {
  jin('斤'),
  kilogram('公斤'),
  bag('袋');

  final String value;
  const ProductUnit(this.value);

  static ProductUnit fromString(String value) {
    return ProductUnit.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProductUnit.kilogram,
    );
  }
}

/// 产品模型
class Product {
  final int id;
  final int userId;
  final String name;
  final String? description;
  final double stock;
  final ProductUnit unit;
  final int? supplierId;
  final int version; // 乐观锁版本号
  final String? createdAt;
  final String? updatedAt;

  Product({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    required this.stock,
    required this.unit,
    this.supplierId,
    required this.version,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
      unit: ProductUnit.fromString(json['unit'] as String? ?? '公斤'),
      supplierId: json['supplierId'] as int? ?? json['supplier_id'] as int?,
      version: json['version'] as int? ?? 1,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      if (description != null) 'description': description,
      'stock': stock,
      'unit': unit.value,
      if (supplierId != null) 'supplierId': supplierId,
      'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  Product copyWith({
    int? id,
    int? userId,
    String? name,
    String? description,
    double? stock,
    ProductUnit? unit,
    int? supplierId,
    int? version,
    String? createdAt,
    String? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      supplierId: supplierId ?? this.supplierId,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 产品创建请求
class ProductCreate {
  final String name;
  final String? description;
  final double stock;
  final ProductUnit unit;
  final int? supplierId;

  ProductCreate({
    required this.name,
    this.description,
    required this.stock,
    required this.unit,
    this.supplierId,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'stock': stock,
      'unit': unit.value,
      if (supplierId != null) 'supplierId': supplierId,
    };
  }
}

/// 产品更新请求
class ProductUpdate {
  final String? name;
  final String? description;
  final double? stock;
  final ProductUnit? unit;
  final int? supplierId;
  final int? version; // 乐观锁版本号

  ProductUpdate({
    this.name,
    this.description,
    this.stock,
    this.unit,
    this.supplierId,
    this.version,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (name != null) json['name'] = name;
    if (description != null) json['description'] = description;
    if (stock != null) json['stock'] = stock;
    if (unit != null) json['unit'] = unit!.value;
    if (supplierId != null) json['supplierId'] = supplierId;
    if (version != null) json['version'] = version;
    return json;
  }
}

/// 库存更新请求
class ProductStockUpdate {
  final double quantity; // 数量变化（正数增加，负数减少）
  final int version; // 当前版本号

  ProductStockUpdate({
    required this.quantity,
    required this.version,
  });

  Map<String, dynamic> toJson() {
    return {
      'quantity': quantity,
      'version': version,
    };
  }
}

class ProductRepository {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 获取产品列表
  /// 
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [search] 搜索关键词（产品名称或描述）
  /// [supplierId] 供应商ID筛选（null 表示不筛选，0 表示未分配供应商）
  /// 
  /// 返回分页的产品列表
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<PaginatedResponse<Product>> getProducts({
    int page = 1,
    int pageSize = 20,
    String? search,
    int? supplierId,
  }) async {
    // 检查是否为本地 workspace
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getProductsLocal(
        page: page,
        pageSize: pageSize,
        search: search,
        supplierId: supplierId,
      );
    } else {
      return await _getProductsServer(
        page: page,
        pageSize: pageSize,
        search: search,
        supplierId: supplierId,
      );
    }
  }

  /// 从服务器获取产品列表
  Future<PaginatedResponse<Product>> _getProductsServer({
    int page = 1,
    int pageSize = 20,
    String? search,
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

      if (supplierId != null) {
        queryParams['supplier_id'] = supplierId.toString();
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/products',
        queryParameters: queryParams,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return PaginatedResponse<Product>.fromJson(
          response.data!,
          (json) => Product.fromJson(json as Map<String, dynamic>),
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
      throw ApiError.unknown('获取产品列表失败', e);
    }
  }

  /// 从本地数据库获取产品列表
  Future<PaginatedResponse<Product>> _getProductsLocal({
    int page = 1,
    int pageSize = 20,
    String? search,
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
      
      // 获取用户ID
      final userId = await _dbHelper.getCurrentUserId(username);
      if (userId == null) {
        throw ApiError(message: '用户不存在');
      }
      
      // 构建查询条件
      var whereClause = 'userId = ? AND workspaceId = ?';
      var whereArgs = <dynamic>[userId, workspaceId];
      
      if (search != null && search.isNotEmpty) {
        whereClause += ' AND (name LIKE ? OR description LIKE ?)';
        whereArgs.add('%$search%');
        whereArgs.add('%$search%');
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
        'SELECT COUNT(*) as count FROM products WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;
      
      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final productsResult = await db.query(
        'products',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
        limit: pageSize,
        offset: offset,
      );
      
      // 转换为 Product 对象
      final products = productsResult.map((row) {
        return Product(
          id: row['id'] as int,
          userId: row['userId'] as int,
          name: row['name'] as String,
          description: row['description'] as String?,
          stock: (row['stock'] as num?)?.toDouble() ?? 0.0,
          unit: ProductUnit.fromString(row['unit'] as String? ?? '公斤'),
          supplierId: row['supplierId'] as int?,
          version: row['version'] as int? ?? 1,
          createdAt: row['created_at'] as String?,
          updatedAt: row['updated_at'] as String?,
        );
      }).toList();
      
      return PaginatedResponse<Product>(
        items: products,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取产品列表失败', e);
    }
  }

  /// 获取单个产品详情
  /// 
  /// [productId] 产品ID
  /// 
  /// 返回产品详情
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Product> getProduct(int productId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _getProductLocal(productId);
    } else {
      return await _getProductServer(productId);
    }
  }

  /// 从服务器获取单个产品
  Future<Product> _getProductServer(int productId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/products/$productId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Product.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取产品详情失败', e);
    }
  }

  /// 从本地数据库获取单个产品
  Future<Product> _getProductLocal(int productId) async {
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
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      if (result.isEmpty) {
        throw ApiError(message: '产品不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final row = result.first;
      return Product(
        id: row['id'] as int,
        userId: row['userId'] as int,
        name: row['name'] as String,
        description: row['description'] as String?,
        stock: (row['stock'] as num?)?.toDouble() ?? 0.0,
        unit: ProductUnit.fromString(row['unit'] as String? ?? '公斤'),
        supplierId: row['supplierId'] as int?,
        version: row['version'] as int? ?? 1,
        createdAt: row['created_at'] as String?,
        updatedAt: row['updated_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('获取产品详情失败', e);
    }
  }

  /// 创建产品
  /// 
  /// [product] 产品创建请求
  /// 
  /// 返回创建的产品
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Product> createProduct(ProductCreate product) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _createProductLocal(product);
    } else {
      return await _createProductServer(product);
    }
  }

  /// 在服务器创建产品
  Future<Product> _createProductServer(ProductCreate product) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/products',
        body: product.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Product.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建产品失败', e);
    }
  }

  /// 在本地数据库创建产品
  Future<Product> _createProductLocal(ProductCreate product) async {
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
      
      // 检查产品名称是否已存在（同一 workspace 下）
      final existing = await db.query(
        'products',
        where: 'userId = ? AND workspaceId = ? AND name = ?',
        whereArgs: [userId, workspaceId, product.name],
      );
      
      if (existing.isNotEmpty) {
        throw ApiError(message: '产品名称已存在', errorCode: 'DUPLICATE');
      }
      
      // 验证供应商是否存在（如果提供了 supplierId）
      if (product.supplierId != null) {
        final supplier = await db.query(
          'suppliers',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [product.supplierId, userId, workspaceId],
        );
        
        if (supplier.isEmpty) {
          throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 插入产品
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('products', {
        'userId': userId,
        'workspaceId': workspaceId,
        'name': product.name,
        'description': product.description,
        'stock': product.stock,
        'unit': product.unit.value,
        'supplierId': product.supplierId,
        'version': 1,
        'created_at': now,
        'updated_at': now,
      });
      
      // 返回创建的产品
      final createdProduct = Product(
        id: id,
        userId: userId,
        name: product.name,
        description: product.description,
        stock: product.stock,
        unit: product.unit,
        supplierId: product.supplierId,
        version: 1,
        createdAt: now,
        updatedAt: now,
      );

      // 记录操作日志
      try {
        await LocalAuditLogService().logCreate(
          entityType: EntityType.product,
          entityId: id,
          entityName: product.name,
          newData: {
            'id': id,
            'userId': userId,
            'name': product.name,
            'description': product.description,
            'stock': product.stock,
            'unit': product.unit.value,
            'supplierId': product.supplierId,
            'version': 1,
          },
        );
      } catch (e) {
        print('记录产品创建日志失败: $e');
        // 日志记录失败不影响业务
      }

      return createdProduct;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('创建产品失败', e);
    }
  }

  /// 更新产品
  /// 
  /// [productId] 产品ID
  /// [update] 产品更新请求（必须包含版本号用于乐观锁）
  /// 
  /// 返回更新后的产品
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Product> updateProduct(int productId, ProductUpdate update) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateProductLocal(productId, update);
    } else {
      return await _updateProductServer(productId, update);
    }
  }

  /// 在服务器更新产品
  Future<Product> _updateProductServer(int productId, ProductUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/products/$productId',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Product.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError catch (e) {
      // 如果是版本冲突，提供更友好的错误信息
      if (e.statusCode == 409) {
        throw ApiError(
          message: '产品已被其他操作修改，请刷新后重试',
          errorCode: 'VERSION_CONFLICT',
          statusCode: 409,
        );
      }
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新产品失败', e);
    }
  }

  /// 在本地数据库更新产品
  Future<Product> _updateProductLocal(int productId, ProductUpdate update) async {
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
      
      // 获取当前产品信息
      final currentResult = await db.query(
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '产品不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final current = currentResult.first;
      final currentVersion = current['version'] as int;
      
      // 检查版本号（乐观锁）
      if (update.version != null && update.version != currentVersion) {
        throw ApiError(
          message: '产品已被其他操作修改，请刷新后重试',
          errorCode: 'VERSION_CONFLICT',
          statusCode: 409,
        );
      }
      
      // 如果更新了名称，检查是否与其他产品重名
      if (update.name != null && update.name != current['name']) {
        final existing = await db.query(
          'products',
          where: 'userId = ? AND workspaceId = ? AND name = ? AND id != ?',
          whereArgs: [userId, workspaceId, update.name, productId],
        );
        
        if (existing.isNotEmpty) {
          throw ApiError(message: '产品名称已存在', errorCode: 'DUPLICATE');
        }
      }
      
      // 验证供应商是否存在（如果更新了 supplierId）
      if (update.supplierId != null && update.supplierId != current['supplierId']) {
        final supplier = await db.query(
          'suppliers',
          where: 'id = ? AND userId = ? AND workspaceId = ?',
          whereArgs: [update.supplierId, userId, workspaceId],
        );
        
        if (supplier.isEmpty) {
          throw ApiError(message: '供应商不存在或无权限访问', errorCode: 'NOT_FOUND');
        }
      }
      
      // 构建更新数据
      final updateData = <String, dynamic>{
        'version': currentVersion + 1,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (update.name != null) updateData['name'] = update.name;
      if (update.description != null) updateData['description'] = update.description;
      if (update.stock != null) updateData['stock'] = update.stock;
      if (update.unit != null) updateData['unit'] = update.unit!.value;
      if (update.supplierId != null) updateData['supplierId'] = update.supplierId;
      
      // 更新产品
      await db.update(
        'products',
        updateData,
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [productId, userId, workspaceId, currentVersion],
      );
      
      // 返回更新后的产品
      final updatedResult = await db.query(
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      final updatedProduct = Product(
        id: row['id'] as int,
        userId: row['userId'] as int,
        name: row['name'] as String,
        description: row['description'] as String?,
        stock: (row['stock'] as num?)?.toDouble() ?? 0.0,
        unit: ProductUnit.fromString(row['unit'] as String? ?? '公斤'),
        supplierId: row['supplierId'] as int?,
        version: row['version'] as int,
        createdAt: row['created_at'] as String?,
        updatedAt: row['updated_at'] as String?,
      );

      // 记录操作日志
      try {
        final oldData = {
          'id': current['id'],
          'userId': current['userId'],
          'name': current['name'],
          'description': current['description'],
          'stock': current['stock'],
          'unit': current['unit'],
          'supplierId': current['supplierId'],
          'version': current['version'],
        };
        final newData = {
          'id': row['id'],
          'userId': row['userId'],
          'name': row['name'],
          'description': row['description'],
          'stock': row['stock'],
          'unit': row['unit'],
          'supplierId': row['supplierId'],
          'version': row['version'],
        };
        await LocalAuditLogService().logUpdate(
          entityType: EntityType.product,
          entityId: productId,
          entityName: updatedProduct.name,
          oldData: oldData,
          newData: newData,
        );
      } catch (e) {
        print('记录产品更新日志失败: $e');
        // 日志记录失败不影响业务
      }

      return updatedProduct;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新产品失败', e);
    }
  }

  /// 删除产品
  /// 
  /// [productId] 产品ID
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<void> deleteProduct(int productId) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _deleteProductLocal(productId);
    } else {
      return await _deleteProductServer(productId);
    }
  }

  /// 在服务器删除产品
  Future<void> _deleteProductServer(int productId) async {
    try {
      final response = await _apiService.delete(
        '/api/products/$productId',
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
      throw ApiError.unknown('删除产品失败', e);
    }
  }

  /// 在本地数据库删除产品
  Future<void> _deleteProductLocal(int productId) async {
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
      
      // 检查产品是否存在，并保存旧数据用于日志
      final product = await db.query(
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      if (product.isEmpty) {
        throw ApiError(message: '产品不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final productRow = product.first;
      final productName = productRow['name'] as String;
      final oldData = {
        'id': productRow['id'],
        'userId': productRow['userId'],
        'name': productRow['name'],
        'description': productRow['description'],
        'stock': productRow['stock'],
        'unit': productRow['unit'],
        'supplierId': productRow['supplierId'],
        'version': productRow['version'],
      };
      
      // 删除产品
      final deleted = await db.delete(
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      if (deleted == 0) {
        throw ApiError(message: '删除产品失败', errorCode: 'DELETE_FAILED');
      }

      // 记录操作日志
      try {
        await LocalAuditLogService().logDelete(
          entityType: EntityType.product,
          entityId: productId,
          entityName: productName,
          oldData: oldData,
        );
      } catch (e) {
        print('记录产品删除日志失败: $e');
        // 日志记录失败不影响业务
      }
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除产品失败', e);
    }
  }

  /// 更新产品库存
  /// 
  /// [productId] 产品ID
  /// [stockUpdate] 库存更新请求（必须包含版本号用于乐观锁）
  /// 
  /// 返回更新后的产品
  /// 根据当前 workspace 的 storage_type 自动路由到本地数据库或 API
  Future<Product> updateProductStock(
    int productId,
    ProductStockUpdate stockUpdate,
  ) async {
    final isLocal = await _apiService.isLocalWorkspace();
    
    if (isLocal) {
      return await _updateProductStockLocal(productId, stockUpdate);
    } else {
      return await _updateProductStockServer(productId, stockUpdate);
    }
  }

  /// 在服务器更新产品库存
  Future<Product> _updateProductStockServer(
    int productId,
    ProductStockUpdate stockUpdate,
  ) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/products/$productId/stock',
        body: stockUpdate.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Product.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError catch (e) {
      // 如果是版本冲突，提供更友好的错误信息
      if (e.statusCode == 409) {
        throw ApiError(
          message: '产品库存已被其他操作修改，请刷新后重试',
          errorCode: 'VERSION_CONFLICT',
          statusCode: 409,
        );
      }
      // 如果是库存不足
      if (e.statusCode == 400 && e.message.contains('库存不足')) {
        throw ApiError(
          message: e.message,
          errorCode: 'INSUFFICIENT_STOCK',
          statusCode: 400,
        );
      }
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新产品库存失败', e);
    }
  }

  /// 在本地数据库更新产品库存
  Future<Product> _updateProductStockLocal(
    int productId,
    ProductStockUpdate stockUpdate,
  ) async {
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
      
      // 获取当前产品信息
      final currentResult = await db.query(
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      if (currentResult.isEmpty) {
        throw ApiError(message: '产品不存在或无权限访问', errorCode: 'NOT_FOUND');
      }
      
      final current = currentResult.first;
      final currentVersion = current['version'] as int;
      final currentStock = (current['stock'] as num?)?.toDouble() ?? 0.0;
      
      // 检查版本号（乐观锁）
      if (stockUpdate.version != currentVersion) {
        throw ApiError(
          message: '产品库存已被其他操作修改，请刷新后重试',
          errorCode: 'VERSION_CONFLICT',
          statusCode: 409,
        );
      }
      
      // 计算新库存
      final newStock = currentStock + stockUpdate.quantity;
      
      // 检查库存是否足够（如果是减少库存）
      if (newStock < 0) {
        throw ApiError(
          message: '库存不足，当前库存：$currentStock',
          errorCode: 'INSUFFICIENT_STOCK',
          statusCode: 400,
        );
      }
      
      // 更新库存
      await db.update(
        'products',
        {
          'stock': newStock,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND userId = ? AND workspaceId = ? AND version = ?',
        whereArgs: [productId, userId, workspaceId, currentVersion],
      );
      
      // 返回更新后的产品
      final updatedResult = await db.query(
        'products',
        where: 'id = ? AND userId = ? AND workspaceId = ?',
        whereArgs: [productId, userId, workspaceId],
      );
      
      final row = updatedResult.first;
      return Product(
        id: row['id'] as int,
        userId: row['userId'] as int,
        name: row['name'] as String,
        description: row['description'] as String?,
        stock: (row['stock'] as num?)?.toDouble() ?? 0.0,
        unit: ProductUnit.fromString(row['unit'] as String? ?? '公斤'),
        supplierId: row['supplierId'] as int?,
        version: row['version'] as int,
        createdAt: row['created_at'] as String?,
        updatedAt: row['updated_at'] as String?,
      );
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('更新产品库存失败', e);
    }
  }

  /// 搜索所有产品（不分页，用于下拉选择等场景）
  /// 
  /// [search] 搜索关键词
  /// 
  /// 返回匹配的产品列表（最多 50 条）
  Future<List<Product>> searchAllProducts(String search) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/products/search/all',
        queryParameters: {'search': search},
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final productsJson = response.data!['products'] as List<dynamic>? ?? [];
        return productsJson
            .map((json) => Product.fromJson(json as Map<String, dynamic>))
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
      throw ApiError.unknown('搜索产品失败', e);
    }
  }
}


