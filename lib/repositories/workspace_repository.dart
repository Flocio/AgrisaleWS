/// Workspace 仓库
/// 处理工作空间的增删改查、成员管理、邀请等功能

import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/workspace.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../database_helper.dart';

/// Workspace 创建请求
class WorkspaceCreate {
  final String name;
  final String? description;
  final String storageType; // 'local' 或 'server'

  WorkspaceCreate({
    required this.name,
    this.description,
    this.storageType = 'server',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'storage_type': storageType,
    };
  }
}

/// Workspace 更新请求
class WorkspaceUpdate {
  final String? name;
  final String? description;
  final bool? isShared;

  WorkspaceUpdate({
    this.name,
    this.description,
    this.isShared,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (name != null) json['name'] = name;
    if (description != null) json['description'] = description;
    if (isShared != null) json['is_shared'] = isShared;
    return json;
  }
}

/// Workspace 邀请请求
class WorkspaceInviteRequest {
  final String? username;
  final String? email;
  final int? userId;
  final String role; // 'admin', 'editor', 'viewer'

  WorkspaceInviteRequest({
    this.username,
    this.email,
    this.userId,
    required this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (userId != null) 'userId': userId,
      'role': role,
    };
  }
}

/// Workspace 成员更新请求
class WorkspaceMemberUpdate {
  final String role;

  WorkspaceMemberUpdate({
    required this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
    };
  }
}

class WorkspaceRepository {
  final ApiService _apiService = ApiService();

  /// 获取当前用户的所有 Workspace
  /// 返回服务器 workspace + 本地数据库中的本地 workspace
  Future<List<Workspace>> getWorkspaces() async {
    try {
      // 1. 从服务器获取服务器 workspace（服务器不返回本地 workspace）
      final response = await _apiService.get<List<dynamic>>(
        '/api/workspaces',
        fromJsonT: (json) => json as List<dynamic>,
      );

      final List<Workspace> workspaces = [];
      
      if (response.isSuccess && response.data != null) {
        // 添加服务器 workspace
        workspaces.addAll(
          (response.data as List)
              .map((json) => Workspace.fromJson(json as Map<String, dynamic>))
        );
      }
      
      // 2. 从本地数据库获取本地 workspace
      try {
        final dbHelper = DatabaseHelper();
        await dbHelper.ensureWorkspacesTableExists();
        final db = await dbHelper.database;
        final username = await AuthService().getCurrentUsername();
        
        if (username != null) {
          final userId = await dbHelper.getCurrentUserId(username);
          if (userId != null) {
            final localWorkspaces = await db.query(
              'workspaces',
              where: 'ownerId = ? AND storage_type = ?',
              whereArgs: [userId, 'local'],
              orderBy: 'created_at DESC',
            );
            
            // 添加本地 workspace
            for (final row in localWorkspaces) {
              workspaces.add(Workspace(
                id: row['id'] as int,
                name: row['name'] as String,
                description: row['description'] as String?,
                ownerId: row['ownerId'] as int,
                storageType: row['storage_type'] as String,
                isShared: (row['is_shared'] as int) == 1,
                createdAt: row['created_at'] as String?,
                updatedAt: row['updated_at'] as String?,
              ));
            }
          }
        }
      } catch (e) {
        print('从本地数据库获取本地 Workspace 失败: $e');
        // 不抛出错误，继续返回服务器 workspace
      }
      
      return workspaces;
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取 Workspace 列表失败', e);
    }
  }

  /// 获取单个 Workspace 详情
  /// 如果是本地 workspace，从本地数据库获取；否则从服务器获取
  Future<Workspace> getWorkspace(int workspaceId) async {
    try {
      // 先尝试从本地数据库获取（可能是本地 workspace）
      try {
        final dbHelper = DatabaseHelper();
        await dbHelper.ensureWorkspacesTableExists();
        final db = await dbHelper.database;
        final username = await AuthService().getCurrentUsername();
        
        if (username != null) {
          final userId = await dbHelper.getCurrentUserId(username);
          if (userId != null) {
            final result = await db.query(
              'workspaces',
              where: 'id = ? AND ownerId = ?',
              whereArgs: [workspaceId, userId],
            );
            
            if (result.isNotEmpty) {
              final row = result.first;
              return Workspace(
                id: row['id'] as int,
                name: row['name'] as String,
                description: row['description'] as String?,
                ownerId: row['ownerId'] as int,
                storageType: row['storage_type'] as String,
                isShared: (row['is_shared'] as int) == 1,
                createdAt: row['created_at'] as String?,
                updatedAt: row['updated_at'] as String?,
              );
            }
          }
        }
      } catch (e) {
        print('从本地数据库获取 Workspace 失败: $e');
        // 继续尝试从服务器获取
      }
      
      // 从服务器获取（服务器 workspace）
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/workspaces/$workspaceId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Workspace.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取 Workspace 详情失败', e);
    }
  }

  /// 创建 Workspace
  Future<Workspace> createWorkspace(WorkspaceCreate data) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/workspaces',
        body: data.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final workspace = Workspace.fromJson(response.data!);
        
        // 如果是本地 workspace，也存储到本地数据库
        if (workspace.storageType == 'local') {
          try {
            final dbHelper = DatabaseHelper();
            final db = await dbHelper.database;
            final username = await AuthService().getCurrentUsername();
            
            if (username != null) {
              // 确保 workspaces 表存在
              await dbHelper.ensureWorkspacesTableExists();
              
              // 确保本地数据库中有用户记录
              var userId = await dbHelper.getCurrentUserId(username);
              if (userId == null) {
                // 如果本地数据库没有用户记录，创建一个（使用服务器返回的 ownerId）
                userId = workspace.ownerId;
                await db.insert('users', {
                  'id': userId,
                  'username': username,
                  'password': '', // 本地数据库不需要密码
                });
              }
              
              // 存储 workspace 信息到本地数据库
              await db.insert('workspaces', {
                'id': workspace.id,
                'name': workspace.name,
                'description': workspace.description,
                'ownerId': userId,
                'storage_type': workspace.storageType,
                'is_shared': workspace.isShared ? 1 : 0,
                'created_at': workspace.createdAt ?? DateTime.now().toIso8601String(),
                'updated_at': workspace.updatedAt ?? DateTime.now().toIso8601String(),
              });
            }
          } catch (e) {
            print('存储本地 Workspace 到数据库失败: $e');
            // 不抛出错误，因为服务器已经创建成功
          }
        }
        
        return workspace;
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('创建 Workspace 失败', e);
    }
  }

  /// 更新 Workspace
  Future<Workspace> updateWorkspace(int workspaceId, WorkspaceUpdate data) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/workspaces/$workspaceId',
        body: data.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return Workspace.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新 Workspace 失败', e);
    }
  }

  /// 删除 Workspace
  /// 如果是本地 workspace，从本地数据库删除；如果是服务器 workspace，调用 API 删除
  /// [password] 仅用于服务器 workspace 的密码验证
  Future<void> deleteWorkspace(int workspaceId, {String? password}) async {
    try {
      // 先检查是否是本地 workspace
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      
      // 确保 workspaces 表存在
      await dbHelper.ensureWorkspacesTableExists();
      
      final localWorkspace = await db.query(
        'workspaces',
        where: 'id = ?',
        whereArgs: [workspaceId],
      );
      
      if (localWorkspace.isNotEmpty) {
        // 这是本地 workspace，也需要密码验证
        if (password == null || password.isEmpty) {
          throw ApiError(
            message: '删除 Workspace 需要密码验证',
            errorCode: 'PASSWORD_REQUIRED',
          );
        }
        
        // 通过调用服务器API验证密码（即使workspace是本地的，用户账户也在服务器上）
        // 使用change-password API来验证密码（传入相同的旧密码和新密码）
        try {
          final authService = AuthService();
          // 尝试用旧密码和新密码相同的方式调用change-password来验证密码
          // 如果密码错误会抛出异常
          await authService.changePassword(password, password);
        } catch (e) {
          // 如果密码验证失败，抛出错误
          if (e is ApiError) {
            if (e.errorCode == 'INVALID_PASSWORD' || e.message.contains('密码')) {
              throw ApiError(
                message: '密码不正确，无法删除 Workspace',
                errorCode: 'PASSWORD_INVALID',
              );
            }
          }
          // 其他错误也抛出
          rethrow;
        }
        
        // 从本地数据库删除
        // 先删除该 workspace 的所有业务数据
        final workspaceIdStr = workspaceId.toString();
        await db.delete('products', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('suppliers', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('customers', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('employees', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('purchases', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('sales', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('returns', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('income', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        await db.delete('remittance', where: 'workspaceId = ?', whereArgs: [workspaceId]);
        
        // 最后删除 workspace 本身
        final deleted = await db.delete(
          'workspaces',
          where: 'id = ?',
          whereArgs: [workspaceId],
        );
        
        if (deleted == 0) {
          throw ApiError(message: '删除本地 Workspace 失败', errorCode: 'DELETE_FAILED');
        }
      } else {
        // 这是服务器 workspace，调用 API 删除（需要密码）
        if (password == null || password.isEmpty) {
          throw ApiError(
            message: '删除服务器 Workspace 需要密码验证',
            errorCode: 'PASSWORD_REQUIRED',
          );
        }
        
        final response = await _apiService.post(
          '/api/workspaces/$workspaceId/delete',
          body: {
            'password': password,
          },
        );

        if (!response.isSuccess) {
          throw ApiError(
            message: response.message,
            errorCode: response.errorCode,
          );
        }
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      if (e is ApiError) {
        rethrow;
      }
      throw ApiError.unknown('删除 Workspace 失败', e);
    }
  }

  /// 获取 Workspace 成员列表
  Future<List<WorkspaceMember>> getWorkspaceMembers(int workspaceId) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        '/api/workspaces/$workspaceId/members',
        fromJsonT: (json) => json as List<dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return (response.data as List)
            .map((json) => WorkspaceMember.fromJson(json as Map<String, dynamic>))
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
      throw ApiError.unknown('获取 Workspace 成员列表失败', e);
    }
  }

  /// 邀请成员加入 Workspace
  Future<void> inviteMember(int workspaceId, WorkspaceInviteRequest data) async {
    try {
      final response = await _apiService.post(
        '/api/workspaces/$workspaceId/members/invite',
        body: data.toJson(),
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
      throw ApiError.unknown('邀请成员失败', e);
    }
  }

  /// 更新成员角色
  Future<void> updateMemberRole(int workspaceId, int memberUserId, WorkspaceMemberUpdate data) async {
    try {
      final response = await _apiService.put(
        '/api/workspaces/$workspaceId/members/$memberUserId',
        body: data.toJson(),
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
      throw ApiError.unknown('更新成员角色失败', e);
    }
  }

  /// 移除成员
  Future<void> removeMember(int workspaceId, int memberUserId) async {
    try {
      final response = await _apiService.delete(
        '/api/workspaces/$workspaceId/members/$memberUserId',
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
      throw ApiError.unknown('移除成员失败', e);
    }
  }

  /// 接受邀请
  Future<void> acceptInvitation(String token) async {
    try {
      final response = await _apiService.post(
        '/api/workspaces/invitations/$token/accept',
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
      throw ApiError.unknown('接受邀请失败', e);
    }
  }

  /// 导入数据到 Workspace（服务器workspace）
  Future<Map<String, dynamic>> importWorkspaceData(int workspaceId, Map<String, dynamic> importData) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/workspaces/$workspaceId/import-data',
        body: importData,
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return response.data!;
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('导入数据失败', e);
    }
  }
}


