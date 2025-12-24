/// 认证服务
/// 处理用户登录、注册、Token 管理等功能

import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import 'api_service.dart';

/// 用户信息模型
class UserInfo {
  final int id;
  final String username;
  final String? createdAt;
  final String? lastLoginAt;

  UserInfo({
    required this.id,
    required this.username,
    this.createdAt,
    this.lastLoginAt,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as int,
      username: json['username'] as String,
      createdAt: json['created_at'] as String?,
      lastLoginAt: json['last_login_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (createdAt != null) 'created_at': createdAt,
      if (lastLoginAt != null) 'last_login_at': lastLoginAt,
    };
  }
}

/// 登录响应模型
class LoginResponse {
  final UserInfo user;
  final String token;
  final int expiresIn;

  LoginResponse({
    required this.user,
    required this.token,
    required this.expiresIn,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      user: UserInfo.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
      expiresIn: json['expires_in'] as int? ?? 86400,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'token': token,
      'expires_in': expiresIn,
    };
  }
}

class AuthService {
  // 单例模式
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final ApiService _apiService = ApiService();

  /// 用户名存储键
  static const String _usernameKey = 'current_username';

  /// 获取当前登录的用户名
  Future<String?> getCurrentUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  /// 保存当前登录的用户名
  Future<void> _saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
  }

  /// 清除当前登录的用户名
  Future<void> _clearUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final token = await _apiService.getToken();
    return token != null && token.isNotEmpty;
  }

  /// 用户注册
  /// 
  /// [username] 用户名
  /// [password] 密码
  /// 
  /// 返回 [LoginResponse] 包含用户信息和 Token
  /// 
  /// 注册过程中会自动尝试多个服务器地址（配置地址 → HTTPS → 局域网），
  /// 直到找到可用的地址
  Future<LoginResponse> register(String username, String password) async {
    try {
      // 使用多地址回退机制
      final loginResponse = await _apiService.tryMultipleUrls<LoginResponse>(
        operation: (currentUrl) async {
          print('尝试注册，当前服务器地址: $currentUrl');
          
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/auth/register',
        body: {
          'username': username,
          'password': password,
        },
        fromJsonT: (json) => json as Map<String, dynamic>,
        includeAuth: false, // 注册不需要认证
      );

      if (response.isSuccess && response.data != null) {
            return LoginResponse.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
        },
      );
      
      // 注册成功，保存 Token 和用户名
      // 注意：tryMultipleUrls 已经保存了成功的服务器地址并更新了 baseUrl
      await _apiService.setToken(loginResponse.token);
      await _saveUsername(loginResponse.user.username);

      return loginResponse;
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('注册失败', e);
    }
  }

  /// 用户登录
  /// 
  /// [username] 用户名
  /// [password] 密码
  /// 
  /// 返回 [LoginResponse] 包含用户信息和 Token
  /// 
  /// 登录过程中会自动尝试多个服务器地址（配置地址 → HTTPS → 局域网），
  /// 直到找到可用的地址
  Future<LoginResponse> login(String username, String password) async {
    try {
      // 使用多地址回退机制
      final loginResponse = await _apiService.tryMultipleUrls<LoginResponse>(
        operation: (currentUrl) async {
          print('尝试登录，当前服务器地址: $currentUrl');
          
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/auth/login',
        body: {
          'username': username,
          'password': password,
        },
        fromJsonT: (json) => json as Map<String, dynamic>,
        includeAuth: false, // 登录不需要认证
      );

      if (response.isSuccess && response.data != null) {
            return LoginResponse.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
        },
      );
      
      // 登录成功，保存 Token 和用户名
      // 注意：tryMultipleUrls 已经保存了成功的服务器地址并更新了 baseUrl
      await _apiService.setToken(loginResponse.token);
      await _saveUsername(loginResponse.user.username);

      return loginResponse;
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('登录失败', e);
    }
  }

  /// 用户登出
  Future<void> logout() async {
    try {
      // 获取设备ID（如果可用）
      String? deviceId;
      try {
        final prefs = await SharedPreferences.getInstance();
        deviceId = prefs.getString('device_id');
      } catch (e) {
        // 忽略错误，继续登出
      }
      
      // 调用服务器登出接口（发送设备ID，只删除当前设备的记录）
      await _apiService.post(
        '/api/auth/logout',
        body: deviceId != null ? {'device_id': deviceId} : null,
        fromJsonT: (json) => json,
      );
    } catch (e) {
      // 即使服务器登出失败，也要清除本地 Token
      print('登出时出错: $e');
    } finally {
      // 清除本地 Token 和用户名
      await _apiService.clearToken();
      await _clearUsername();
    }
  }

  /// 获取当前用户信息
  /// 
  /// 返回 [UserInfo] 当前用户信息
  Future<UserInfo> getCurrentUser() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/auth/me',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return UserInfo.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取用户信息失败', e);
    }
  }

  /// 刷新 Token
  /// 
  /// 返回新的 Token 和过期时间
  Future<Map<String, dynamic>> refreshToken() async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final tokenData = response.data!;
        final newToken = tokenData['token'] as String;
        
        // 更新 Token
        await _apiService.setToken(newToken);

        return tokenData;
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('刷新 Token 失败', e);
    }
  }

  /// 修改密码
  /// 
  /// [oldPassword] 当前密码
  /// [newPassword] 新密码
  Future<void> changePassword(String oldPassword, String newPassword) async {
    try {
      final response = await _apiService.post(
        '/api/auth/change-password',
        body: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
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
      throw ApiError.unknown('修改密码失败', e);
    }
  }

  /// 删除账户（注销账户）
  /// 
  /// [password] 用户密码（用于确认身份）
  /// 
  /// 注意：此操作不可恢复，将删除用户的所有数据
  Future<void> deleteAccount(String password) async {
    try {
      final response = await _apiService.post(
        '/api/auth/account/delete',
        body: {
          'password': password,
        },
        fromJsonT: (json) => json,
      );

      if (!response.isSuccess) {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
      
      // 删除成功后，清除本地数据
      await _apiService.clearToken();
      await _clearUsername();
      await _apiService.clearWorkspaceId();
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('注销账户失败', e);
    }
  }

  /// 自动登录（使用保存的用户名和 Token）
  /// 
  /// 如果 Token 有效，返回用户信息；否则返回 null
  /// 
  /// 自动登录过程中会自动尝试多个服务器地址（配置地址 → HTTPS → 局域网），
  /// 直到找到可用的地址
  Future<UserInfo?> autoLogin() async {
    try {
      // 检查是否有 Token
      if (!await isLoggedIn()) {
        return null;
      }

      // 使用多地址回退机制尝试获取用户信息（验证 Token 是否有效）
      // 注意：tryMultipleUrls 已经保存了成功的服务器地址并更新了 baseUrl
      final userInfo = await _apiService.tryMultipleUrls<UserInfo>(
        operation: (currentUrl) async {
          print('尝试自动登录，当前服务器地址: $currentUrl');
      return await getCurrentUser();
        },
      );
      
      return userInfo;
    } catch (e) {
      // Token 无效或所有地址都失败，清除本地数据
      if (e is ApiError && e.isUnauthorized) {
        await _apiService.clearToken();
        await _clearUsername();
      }
      return null;
    }
  }
}

