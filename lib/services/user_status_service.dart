/// 用户在线状态服务
/// 处理用户心跳、在线用户列表、操作状态更新等功能

import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import 'api_service.dart';

/// 在线用户信息模型
class OnlineUser {
  final int userId;
  final String deviceId;
  final String username;
  final String lastHeartbeat;
  final String? currentAction;
  final String? platform;
  final String? deviceName;

  OnlineUser({
    required this.userId,
    required this.deviceId,
    required this.username,
    required this.lastHeartbeat,
    this.currentAction,
    this.platform,
    this.deviceName,
  });

  factory OnlineUser.fromJson(Map<String, dynamic> json) {
    return OnlineUser(
      userId: json['userId'] as int? ?? json['user_id'] as int,
      deviceId: json['deviceId'] as String? ?? json['device_id'] as String? ?? 'unknown',
      username: json['username'] as String,
      lastHeartbeat: json['last_heartbeat'] as String? ?? json['lastHeartbeat'] as String,
      currentAction: json['current_action'] as String? ?? json['currentAction'] as String?,
      platform: json['platform'] as String?,
      deviceName: json['device_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'last_heartbeat': lastHeartbeat,
      if (currentAction != null) 'current_action': currentAction,
    };
  }
}

/// 在线用户列表响应
class OnlineUsersResponse {
  final List<OnlineUser> onlineUsers;
  final int count;

  OnlineUsersResponse({
    required this.onlineUsers,
    required this.count,
  });

  factory OnlineUsersResponse.fromJson(Map<String, dynamic> json) {
    final usersJson = json['online_users'] as List<dynamic>? ?? [];
    return OnlineUsersResponse(
      onlineUsers: usersJson
          .map((user) => OnlineUser.fromJson(user as Map<String, dynamic>))
          .toList(),
      count: json['count'] as int? ?? 0,
    );
  }
}

class UserStatusService {
  // 单例模式
  static final UserStatusService _instance = UserStatusService._internal();
  factory UserStatusService() => _instance;
  UserStatusService._internal();

  final ApiService _apiService = ApiService();
  
  /// 设备ID（用于区分同一用户的不同设备）
  String? _deviceId;
  
  /// 获取或生成设备ID
  Future<String> _getDeviceId() async {
    if (_deviceId != null) {
      return _deviceId!;
    }
    
    // 从 SharedPreferences 获取或生成设备ID
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    
    if (_deviceId == null || _deviceId!.isEmpty) {
      // 生成新的设备ID（使用时间戳和随机数）
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9999 - 1000) * (DateTime.now().microsecond / 1000000)).toInt()}';
      await prefs.setString('device_id', _deviceId!);
    }
    
    return _deviceId!;
  }

  /// 心跳定时器
  Timer? _heartbeatTimer;

  /// 在线用户列表更新定时器
  Timer? _onlineUsersTimer;

  /// 心跳间隔（秒），默认 10 秒
  int heartbeatInterval = 10;

  /// 在线用户列表更新间隔（秒），默认 5 秒
  int onlineUsersUpdateInterval = 5;

  /// 是否正在运行
  bool _isRunning = false;

  /// 当前操作描述
  String? _currentAction;

  /// 在线用户列表
  List<OnlineUser> _onlineUsers = [];

  /// 上一次的在线用户列表（用于检测变化）
  List<OnlineUser> _previousOnlineUsers = [];

  /// 在线用户数量
  int _onlineUsersCount = 0;

  /// 在线用户列表更新回调
  Function(List<OnlineUser>, int)? onOnlineUsersUpdated;

  /// 设备上线通知回调 (deviceName, platform)
  Function(String, String)? onDeviceOnline;

  /// 设备下线通知回调 (deviceName, platform)
  Function(String, String)? onDeviceOffline;

  /// 在线用户数量更新回调
  Function(int)? onOnlineUsersCountUpdated;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 获取当前在线用户列表
  List<OnlineUser> get onlineUsers => List.unmodifiable(_onlineUsers);

  /// 获取在线用户数量
  int get onlineUsersCount => _onlineUsersCount;

  /// 启动心跳服务
  /// 
  /// [interval] 心跳间隔（秒），默认 10 秒
  Future<void> startHeartbeat({int? interval}) async {
    if (_isRunning) {
      return; // 已经在运行
    }

    if (interval != null) {
      heartbeatInterval = interval;
    }

    _isRunning = true;

    // 立即发送一次心跳
    await updateHeartbeat();

    // 启动定时心跳
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatInterval),
      (_) => updateHeartbeat(),
    );
  }

  /// 停止心跳服务
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isRunning = false;
  }

  /// 获取设备平台信息
  String _getPlatform() {
    if (Platform.isAndroid) {
      return 'Android';
    } else if (Platform.isIOS) {
      return 'iOS';
    } else if (Platform.isMacOS) {
      return 'macOS';
    } else if (Platform.isWindows) {
      return 'Windows';
    } else if (Platform.isLinux) {
      return 'Linux';
    } else {
      return 'Unknown';
    }
  }

  /// 获取设备名称
  Future<String?> _getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // 返回设备型号和制造商，例如：Samsung Galaxy S21
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // 返回设备名称，例如：iPhone 14 Pro
        return iosInfo.name.isNotEmpty ? iosInfo.name : iosInfo.model;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        // 返回设备名称，优先使用 computerName，然后是 hostName，最后是 model
        if (macInfo.computerName.isNotEmpty) {
          return macInfo.computerName;
        } else if (macInfo.hostName.isNotEmpty) {
          return macInfo.hostName;
        } else if (macInfo.model.isNotEmpty) {
          return macInfo.model;
        } else {
          return 'Mac';
        }
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        // 返回计算机名称
        return windowsInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        // 返回机器ID或主机名
        return linuxInfo.prettyName.isNotEmpty ? linuxInfo.prettyName : linuxInfo.machineId;
      } else {
        return null;
      }
    } catch (e) {
      print('获取设备名称失败: $e');
      return null;
    }
  }

  /// 更新心跳
  /// 
  /// [action] 当前操作描述（可选）
  Future<void> updateHeartbeat({String? action}) async {
    try {
      _currentAction = action;
      
      // 获取设备ID、平台信息和设备名称
      final deviceId = await _getDeviceId();
      final platform = _getPlatform();
      final deviceName = await _getDeviceName();
      
      await _apiService.post(
        '/api/users/heartbeat',
        body: {
          'device_id': deviceId,
          if (action != null) 'current_action': action,
          'platform': platform,
          if (deviceName != null) 'device_name': deviceName,
        },
        fromJsonT: (json) => json,
      );
    } catch (e) {
      // 心跳失败不影响主流程，只打印日志
      print('心跳更新失败: $e');
    }
  }

  /// 启动在线用户列表自动更新
  /// 
  /// [interval] 更新间隔（秒），默认 5 秒
  /// [onUpdated] 更新回调
  void startOnlineUsersUpdate({
    int? interval,
    Function(List<OnlineUser>, int)? onUpdated,
  }) {
    if (interval != null) {
      onlineUsersUpdateInterval = interval;
    }

    if (onUpdated != null) {
      onOnlineUsersUpdated = onUpdated;
    }

    // 立即获取一次
    getOnlineUsers().catchError((e) {
      // 静默处理错误，避免未处理的异常
      print('获取在线用户列表失败: $e');
    });

    // 启动定时更新
    _onlineUsersTimer?.cancel();
    _onlineUsersTimer = Timer.periodic(
      Duration(seconds: onlineUsersUpdateInterval),
      (_) async {
        try {
          await getOnlineUsers();
        } catch (e) {
          // 静默处理错误，避免未处理的异常
          // 401错误会在getOnlineUsers内部处理并停止定时器
          print('定时更新在线用户列表失败: $e');
        }
      },
    );
  }

  /// 停止在线用户列表自动更新
  void stopOnlineUsersUpdate() {
    _onlineUsersTimer?.cancel();
    _onlineUsersTimer = null;
    onOnlineUsersUpdated = null;
  }

  /// 获取在线用户列表
  Future<List<OnlineUser>> getOnlineUsers() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/users/online',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final onlineUsersResponse = OnlineUsersResponse.fromJson(response.data!);
        final newUsers = onlineUsersResponse.onlineUsers;
        _onlineUsersCount = onlineUsersResponse.count;

        // 检测设备变化
        _detectDeviceChanges(_previousOnlineUsers, newUsers);

        // 更新列表
        _previousOnlineUsers = List.from(newUsers);
        _onlineUsers = newUsers;

        // 触发回调
        onOnlineUsersUpdated?.call(_onlineUsers, _onlineUsersCount);

        return _onlineUsers;
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError catch (e) {
      // 如果是401错误（未授权），自动停止更新
      if (e.isUnauthorized) {
        print('获取在线用户列表失败：未授权，停止自动更新');
        stopOnlineUsersUpdate();
      }
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取在线用户列表失败', e);
    }
  }

  /// 获取在线用户数量（轻量级接口）
  Future<int> getOnlineUsersCount() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/users/online/count',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        final count = response.data!['count'] as int? ?? 0;
        _onlineUsersCount = count;

        // 触发回调
        onOnlineUsersCountUpdated?.call(_onlineUsersCount);

        return count;
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取在线用户数量失败', e);
    }
  }

  /// 检测设备变化（上线/下线）
  void _detectDeviceChanges(List<OnlineUser> oldUsers, List<OnlineUser> newUsers) {
    // 如果这是第一次获取列表，不触发通知（避免初始化时误报）
    if (oldUsers.isEmpty) return;

    // 获取当前设备的 deviceId（用于排除自己）
    final currentDeviceId = _deviceId;
    if (currentDeviceId == null) {
      // 如果还没有设备ID，异步获取（但这次不触发通知）
      _getDeviceId().then((deviceId) {
        _deviceId = deviceId;
      });
      return;
    }

    // 构建设备ID到设备的映射（排除当前设备）
    final oldDeviceMap = <String, OnlineUser>{};
    for (var user in oldUsers) {
      if (user.deviceId != currentDeviceId) {
        oldDeviceMap[user.deviceId] = user;
      }
    }

    final newDeviceMap = <String, OnlineUser>{};
    for (var user in newUsers) {
      if (user.deviceId != currentDeviceId) {
        newDeviceMap[user.deviceId] = user;
      }
    }

    // 检测新上线的设备
    for (var entry in newDeviceMap.entries) {
      if (!oldDeviceMap.containsKey(entry.key)) {
        // 新设备上线
        final device = entry.value;
        final deviceName = device.deviceName ?? device.platform ?? '未知设备';
        final platform = device.platform ?? '未知平台';
        onDeviceOnline?.call(deviceName, platform);
      }
    }

    // 检测下线的设备
    for (var entry in oldDeviceMap.entries) {
      if (!newDeviceMap.containsKey(entry.key)) {
        // 设备下线
        final device = entry.value;
        final deviceName = device.deviceName ?? device.platform ?? '未知设备';
        final platform = device.platform ?? '未知平台';
        onDeviceOffline?.call(deviceName, platform);
      }
    }
  }

  /// 更新当前操作描述
  ///
  /// [action] 当前操作描述（如"正在查看产品列表"）
  Future<void> updateCurrentAction(String action) async {
    try {
      _currentAction = action;

      await _apiService.post(
        '/api/users/online/update-action',
        body: {'current_action': action},
        fromJsonT: (json) => json,
      );

      // 同时更新心跳（确保在线状态）
      await updateHeartbeat(action: action);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新操作状态失败', e);
    }
  }

  /// 清除当前操作描述
  Future<void> clearCurrentAction() async {
    try {
      _currentAction = null;

      await _apiService.post(
        '/api/users/online/clear-action',
        fromJsonT: (json) => json,
      );

      // 同时更新心跳（确保在线状态）
      await updateHeartbeat();
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('清除操作状态失败', e);
    }
  }

  /// 获取指定用户的在线状态
  /// 
  /// [userId] 用户ID
  Future<Map<String, dynamic>> getUserOnlineStatus(int userId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/users/online/$userId/status',
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
      throw ApiError.unknown('获取用户在线状态失败', e);
    }
  }

  /// 停止所有服务
  void stopAll() {
    stopHeartbeat();
    stopOnlineUsersUpdate();
    _currentAction = null;
  }

  /// 清理资源
  void dispose() {
    stopAll();
    onOnlineUsersUpdated = null;
    onOnlineUsersCountUpdated = null;
  }
}

