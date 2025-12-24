/// API 服务基础类
/// 提供统一的 HTTP 请求、错误处理、重试机制

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../database_helper.dart';
import 'auth_service.dart';

class ApiService {
  // 单例模式
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// 服务器基础 URL（从环境变量或配置读取）
  String baseUrl = 'https://agrisalews.drflo.org'; // 默认值，HTTPS 内网穿透地址（同时支持内网和外网）

  /// 持久化 HTTP 客户端（连接复用，提高性能）
  http.Client? _httpClient;

  /// 获取或创建 HTTP 客户端
  http.Client get _client {
    _httpClient ??= http.Client();
    return _httpClient!;
  }

  /// 请求超时时间（秒）
  /// 针对 Cloudflare Tunnel 优化：增加超时时间以应对网络延迟
  static const int timeoutSeconds = 20;

  /// 最大重试次数
  /// 针对 Cloudflare Tunnel 优化：减少重试次数，避免累积延迟
  static const int maxRetries = 2;

  /// 重试延迟（毫秒）
  /// 针对 Cloudflare Tunnel 优化：减少重试延迟
  static const int retryDelayMs = 500;

  /// Token 存储键
  static const String _tokenKey = 'api_token';

  /// Workspace ID 存储键
  static const String _workspaceIdKey = 'current_workspace_id';

  /// 获取当前 Token（公开方法，供其他服务使用）
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// 获取当前 Token（内部方法，保持向后兼容）
  Future<String?> _getToken() async => getToken();

  /// 保存 Token
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// 清除 Token
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// 获取当前 Workspace ID（公开方法，供其他服务使用）
  Future<int?> getWorkspaceId() async {
    final prefs = await SharedPreferences.getInstance();
    final workspaceIdStr = prefs.getString(_workspaceIdKey);
    if (workspaceIdStr == null) {
      return null;
    }
    return int.tryParse(workspaceIdStr);
  }

  /// 设置 Workspace ID
  Future<void> setWorkspaceId(int? workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (workspaceId == null) {
      await prefs.remove(_workspaceIdKey);
    } else {
      await prefs.setString(_workspaceIdKey, workspaceId.toString());
    }
  }

  /// 清除 Workspace ID
  Future<void> clearWorkspaceId() async {
    await setWorkspaceId(null);
  }

  /// 获取当前 Workspace 信息（包括 storage_type）
  /// 返回 null 如果未设置 workspace 或获取失败
  /// 优先从本地数据库查找，如果找不到再尝试服务器
  Future<Map<String, dynamic>?> getCurrentWorkspace() async {
    final workspaceId = await getWorkspaceId();
    if (workspaceId == null) {
      return null;
    }
    
    // 先从本地数据库查找（用于本地 workspace）
    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      
      // 确保 workspaces 表存在
      await dbHelper.ensureWorkspacesTableExists();
      
      final result = await db.query(
        'workspaces',
        where: 'id = ?',
        whereArgs: [workspaceId],
      );
      
      if (result.isNotEmpty) {
        final row = result.first;
        return {
          'id': row['id'] as int,
          'name': row['name'] as String,
          'description': row['description'] as String?,
          'ownerId': row['ownerId'] as int,
          'storage_type': row['storage_type'] as String,
          'is_shared': (row['is_shared'] as int) == 1,
          'created_at': row['created_at'] as String?,
          'updated_at': row['updated_at'] as String?,
        };
      }
    } catch (e) {
      print('从本地数据库获取 Workspace 信息失败: $e');
    }
    
    // 如果本地数据库找不到，尝试从服务器获取（用于服务器 workspace）
    try {
      final response = await get<Map<String, dynamic>>(
        '/api/workspaces/$workspaceId',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );
      
      if (response.isSuccess && response.data != null) {
        final workspaceData = response.data!;
        final storageType = workspaceData['storage_type'] as String? ?? workspaceData['storageType'] as String?;
        
        // 如果是本地 workspace，存储到本地数据库（用于下次快速访问）
        if (storageType == 'local') {
          try {
            final dbHelper = DatabaseHelper();
            final db = await dbHelper.database;
            
            // 确保 workspaces 表存在
            await dbHelper.ensureWorkspacesTableExists();
            
            // 检查是否已存在，如果不存在则插入
            final existing = await db.query(
              'workspaces',
              where: 'id = ?',
              whereArgs: [workspaceId],
            );
            
            if (existing.isEmpty) {
              final username = await AuthService().getCurrentUsername();
              if (username != null) {
                // 确保本地数据库中有用户记录
                var userId = await dbHelper.getCurrentUserId(username);
                if (userId == null) {
                  userId = workspaceData['ownerId'] as int? ?? workspaceData['owner_id'] as int?;
                  if (userId != null) {
                    await db.insert('users', {
                      'id': userId,
                      'username': username,
                      'password': '', // 本地数据库不需要密码
                    });
                  }
                }
                
                if (userId != null) {
                  await db.insert('workspaces', {
                    'id': workspaceId,
                    'name': workspaceData['name'] as String,
                    'description': workspaceData['description'] as String?,
                    'ownerId': userId,
                    'storage_type': storageType,
                    'is_shared': (workspaceData['is_shared'] as bool? ?? workspaceData['isShared'] as bool? ?? false) ? 1 : 0,
                    'created_at': workspaceData['created_at'] as String? ?? workspaceData['createdAt'] as String?,
                    'updated_at': workspaceData['updated_at'] as String? ?? workspaceData['updatedAt'] as String?,
                  });
                  print('✓ 本地 Workspace 信息已同步到本地数据库');
                }
              }
            }
          } catch (e) {
            print('同步本地 Workspace 到数据库失败: $e');
            // 不抛出错误，继续返回服务器数据
          }
        }
        
        return workspaceData;
      }
      return null;
    } catch (e) {
      print('从服务器获取 Workspace 信息失败: $e');
      return null;
    }
  }

  /// 判断当前 Workspace 是否为本地存储类型
  Future<bool> isLocalWorkspace() async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) {
      return false;
    }
    final storageType = workspace['storage_type'] as String? ?? workspace['storageType'] as String?;
    return storageType == 'local';
  }

  /// 设置服务器地址
  void setBaseUrl(String url) {
    baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 设置 Token
  Future<void> setToken(String token) async {
    await _saveToken(token);
  }

  /// 构建请求头
  Future<Map<String, String>> _buildHeaders({
    Map<String, String>? additionalHeaders,
    bool includeAuth = true,
    int? workspaceId, // 可选的workspace ID，如果提供则覆盖默认值
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip, deflate', // 支持响应压缩
      'Connection': 'keep-alive', // 保持连接复用
    };

    if (includeAuth) {
      final token = await _getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    // 添加 Workspace ID header（如果提供了workspaceId参数，使用参数；否则从存储中读取）
    final currentWorkspaceId = workspaceId ?? await getWorkspaceId();
    if (currentWorkspaceId != null) {
      headers['X-Workspace-ID'] = currentWorkspaceId.toString();
    }

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    return headers;
  }

  /// 处理 HTTP 响应
  Future<ApiResponse<T>> _handleResponse<T>(
    http.Response response,
    T? Function(dynamic)? fromJsonT,
  ) async {
    // 解析响应体
    Map<String, dynamic>? json;
    try {
      if (response.body.isNotEmpty) {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // 如果响应不是 JSON，尝试从响应体中提取文本信息
      String errorMessage = '服务器返回了无效的响应格式';
      if (response.body.isNotEmpty) {
        // 如果响应体不是 JSON，可能是纯文本错误信息
        errorMessage = response.body;
      }
      throw ApiError.server(
        response.statusCode,
        errorMessage,
      );
    }

    // 检查 HTTP 状态码
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 成功响应
      return ApiResponse.fromJson(json ?? {}, fromJsonT);
    } else {
      // 错误响应
      throw ApiError.fromHttpResponse(response.statusCode, json);
    }
  }

  /// 执行 HTTP 请求（带重试）
  Future<http.Response> _executeRequest(
    Future<http.Response> Function() request,
  ) async {
    int attempts = 0;
    Exception? lastException;

    while (attempts < maxRetries) {
      try {
        print('API 请求尝试 ${attempts + 1}/$maxRetries'); // 调试日志
        
        final response = await request()
            .timeout(Duration(seconds: timeoutSeconds));

        print('API 响应状态码: ${response.statusCode}'); // 调试日志

        // 如果是 401 未授权，不重试
        if (response.statusCode == 401) {
          throw ApiError.unauthorized();
        }

        // 如果是 5xx 服务器错误，重试
        if (response.statusCode >= 500 && attempts < maxRetries - 1) {
          print('服务器错误，准备重试...'); // 调试日志
          await Future.delayed(Duration(milliseconds: retryDelayMs * (attempts + 1)));
          attempts++;
          continue;
        }

        return response;
      } on ApiError {
        rethrow;
      } on TimeoutException catch (e) {
        lastException = e;
        print('请求超时 (尝试 ${attempts + 1}/$maxRetries)'); // 调试日志
        if (attempts < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: retryDelayMs * (attempts + 1)));
          attempts++;
          continue;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        print('请求异常: $e (尝试 ${attempts + 1}/$maxRetries)'); // 调试日志
        
        // 如果是超时或网络错误，重试
        if (attempts < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: retryDelayMs * (attempts + 1)));
          attempts++;
          continue;
        }
      }
    }

    // 所有重试都失败
    if (lastException != null) {
      if (lastException.toString().contains('TimeoutException') || 
          lastException is TimeoutException) {
        print('所有重试失败：超时'); // 调试日志
        throw ApiError.timeout('连接超时，请检查网络连接和服务器地址');
      } else {
        print('所有重试失败：网络错误'); // 调试日志
        throw ApiError.network('无法连接到服务器，请检查：\n1. 是否与服务器在同一网络\n2. 服务器地址是否正确\n3. 防火墙是否阻止连接', lastException);
      }
    }

    throw ApiError.unknown('请求失败');
  }

  /// GET 请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? queryParameters,
    T? Function(dynamic)? fromJsonT,
    bool includeAuth = true,
    int? workspaceId, // 可选的workspace ID
  }) async {
    try {
      // 构建 URL
      var uri = Uri.parse('$baseUrl$path');
      if (queryParameters != null && queryParameters.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParameters);
      }

      // 执行请求（使用持久化客户端）
      final response = await _executeRequest(() async {
        final headers = await _buildHeaders(includeAuth: includeAuth, workspaceId: workspaceId);
        return await _client.get(uri, headers: headers);
      });

      return await _handleResponse<T>(response, fromJsonT);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('GET 请求失败', e);
    }
  }

  /// POST 请求
  Future<ApiResponse<T>> post<T>(
    String path, {
    Map<String, dynamic>? body,
    T? Function(dynamic)? fromJsonT,
    bool includeAuth = true,
    int? workspaceId, // 可选的workspace ID
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      // 执行请求（使用持久化客户端）
      final response = await _executeRequest(() async {
        final headers = await _buildHeaders(includeAuth: includeAuth, workspaceId: workspaceId);
        final bodyJson = body != null ? jsonEncode(body) : null;
        return await _client.post(uri, headers: headers, body: bodyJson);
      });

      return await _handleResponse<T>(response, fromJsonT);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('POST 请求失败', e);
    }
  }

  /// PUT 请求
  Future<ApiResponse<T>> put<T>(
    String path, {
    Map<String, dynamic>? body,
    T? Function(dynamic)? fromJsonT,
    bool includeAuth = true,
    int? workspaceId, // 可选的workspace ID
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      // 执行请求（使用持久化客户端）
      final response = await _executeRequest(() async {
        final headers = await _buildHeaders(includeAuth: includeAuth, workspaceId: workspaceId);
        final bodyJson = body != null ? jsonEncode(body) : null;
        return await _client.put(uri, headers: headers, body: bodyJson);
      });

      return await _handleResponse<T>(response, fromJsonT);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('PUT 请求失败', e);
    }
  }

  /// DELETE 请求
  Future<ApiResponse<T>> delete<T>(
    String path, {
    T? Function(dynamic)? fromJsonT,
    bool includeAuth = true,
    int? workspaceId, // 可选的workspace ID
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      // 执行请求（使用持久化客户端）
      final response = await _executeRequest(() async {
        final headers = await _buildHeaders(includeAuth: includeAuth, workspaceId: workspaceId);
        return await _client.delete(uri, headers: headers);
      });

      return await _handleResponse<T>(response, fromJsonT);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('DELETE 请求失败', e);
    }
  }

  /// PATCH 请求
  Future<ApiResponse<T>> patch<T>(
    String path, {
    Map<String, dynamic>? body,
    T? Function(dynamic)? fromJsonT,
    bool includeAuth = true,
    int? workspaceId, // 可选的workspace ID
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');

      // 执行请求（使用持久化客户端）
      final response = await _executeRequest(() async {
        final headers = await _buildHeaders(includeAuth: includeAuth, workspaceId: workspaceId);
        final bodyJson = body != null ? jsonEncode(body) : null;
        return await _client.patch(uri, headers: headers, body: bodyJson);
      });

      return await _handleResponse<T>(response, fromJsonT);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('PATCH 请求失败', e);
    }
  }

  /// 关闭 HTTP 客户端（清理资源）
  void close() {
    _httpClient?.close();
    _httpClient = null;
  }

  /// 快速测试服务器地址是否可达（用于多地址尝试时的预检查）
  /// 
  /// [url] 要测试的服务器地址
  /// [timeoutSeconds] 超时时间（秒），默认 5 秒
  /// 
  /// 返回 true 表示可达，false 表示不可达
  Future<bool> _quickTestUrl(String url, {int timeoutSeconds = 5}) async {
    try {
      final uri = Uri.parse('$url/health');
      final response = await _client
          .get(uri)
          .timeout(Duration(seconds: timeoutSeconds));
      
      // 只要能返回 200 或 503（数据库未连接但服务器在线）就算可达
      return response.statusCode == 200 || response.statusCode == 503;
    } catch (e) {
      return false;
    }
  }

  /// 尝试多个服务器地址执行操作
  /// 
  /// [operation] 需要执行的操作（接受当前 baseUrl 作为参数）
  /// [preferredUrl] 优先尝试的地址（如果为 null，则从 SharedPreferences 读取）
  /// 
  /// 返回操作结果，如果所有地址都失败则抛出最后一个异常
  Future<T> tryMultipleUrls<T>({
    required Future<T> Function(String currentUrl) operation,
    String? preferredUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 构建地址列表（按优先级排序）
    final List<String> urlsToTry = [];
    
    // 1. 优先使用传入的 preferredUrl 或从 SharedPreferences 读取的地址
    final configuredUrl = preferredUrl ?? prefs.getString('server_url');
    if (configuredUrl != null && configuredUrl.isNotEmpty) {
      urlsToTry.add(configuredUrl);
    }
    
    // 2. HTTPS 地址（内网穿透）
    const httpsUrl = 'https://agrisalews.drflo.org';
    if (!urlsToTry.contains(httpsUrl)) {
      urlsToTry.add(httpsUrl);
    }
    
    // 3. 局域网地址（从配置读取，如果没有配置则使用默认值）
    final lanUrl = prefs.getString('lan_url') ?? 'http://192.168.10.12:8000';
    if (lanUrl.isNotEmpty && !urlsToTry.contains(lanUrl)) {
      urlsToTry.add(lanUrl);
    }
    
    print('将按顺序尝试以下服务器地址: ${urlsToTry.join(', ')}');
    
    Exception? lastException;
    String? lastFailedUrl;
    
    // 尝试每个地址
    for (final url in urlsToTry) {
      try {
        print('正在测试服务器地址: $url');
        
        // 先快速测试地址是否可达（5秒超时，快速失败）
        final isReachable = await _quickTestUrl(url, timeoutSeconds: 5);
        
        if (!isReachable) {
          print('服务器地址 $url 不可达，快速跳过');
          lastException = Exception('服务器地址不可达');
          lastFailedUrl = url;
          continue; // 直接尝试下一个地址
        }
        
        print('服务器地址 $url 可达，执行登录操作...');
        
        // 临时设置 baseUrl
        final originalUrl = baseUrl;
        setBaseUrl(url);
        
        try {
          // 执行操作
          final result = await operation(url);
          
          // 如果成功，保存这个地址到 SharedPreferences 并更新 baseUrl
          await prefs.setString('server_url', url);
          setBaseUrl(url); // 确保使用成功的地址
          print('操作成功，已保存并切换到服务器地址: $url');
          
          return result;
        } catch (e) {
          // 操作失败，恢复原始地址以便尝试下一个地址
          baseUrl = originalUrl;
          rethrow;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        lastFailedUrl = url;
        print('服务器地址 $url 失败: $e');
        
        // 继续尝试下一个地址
        continue;
      }
    }
    
    // 所有地址都失败
    print('所有服务器地址都失败，最后失败的地址: $lastFailedUrl');
    if (lastException != null) {
      throw lastException;
    }
    throw Exception('无法连接到任何服务器地址');
  }
}

