/// 用户设置仓库
/// 处理用户设置的增删改查功能

import '../models/api_response.dart';
import '../models/api_error.dart';
import '../services/api_service.dart';

/// 用户设置模型
class UserSettings {
  final int id;
  final int userId;
  final String? deepseekApiKey;
  final String deepseekModel;
  final double deepseekTemperature;
  final int deepseekMaxTokens;
  final int darkMode;
  final int autoBackupEnabled;
  final int autoBackupInterval;
  final int autoBackupMaxCount;
  final String? lastBackupTime;
  final int showOnlineUsers;
  final int notifyDeviceOnline;
  final int notifyDeviceOffline;
  final String? createdAt;
  final String? updatedAt;

  UserSettings({
    required this.id,
    required this.userId,
    this.deepseekApiKey,
    this.deepseekModel = 'deepseek-chat',
    this.deepseekTemperature = 0.7,
    this.deepseekMaxTokens = 2000,
    this.darkMode = 0,
    this.autoBackupEnabled = 0,
    this.autoBackupInterval = 15,
    this.autoBackupMaxCount = 20,
    this.lastBackupTime,
    this.showOnlineUsers = 1,
    this.notifyDeviceOnline = 1,
    this.notifyDeviceOffline = 1,
    this.createdAt,
    this.updatedAt,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      id: json['id'] as int,
      userId: json['userId'] as int? ?? json['user_id'] as int,
      deepseekApiKey: json['deepseek_api_key'] as String?,
      deepseekModel: json['deepseek_model'] as String? ?? 'deepseek-chat',
      deepseekTemperature: (json['deepseek_temperature'] as num?)?.toDouble() ?? 0.7,
      deepseekMaxTokens: json['deepseek_max_tokens'] as int? ?? 2000,
      darkMode: json['dark_mode'] as int? ?? 0,
      autoBackupEnabled: json['auto_backup_enabled'] as int? ?? 0,
      autoBackupInterval: json['auto_backup_interval'] as int? ?? 15,
      autoBackupMaxCount: json['auto_backup_max_count'] as int? ?? 20,
      lastBackupTime: json['last_backup_time'] as String?,
      showOnlineUsers: json['show_online_users'] as int? ?? 1,
      notifyDeviceOnline: json['notify_device_online'] as int? ?? 1,
      notifyDeviceOffline: json['notify_device_offline'] as int? ?? 1,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      if (deepseekApiKey != null) 'deepseek_api_key': deepseekApiKey,
      'deepseek_model': deepseekModel,
      'deepseek_temperature': deepseekTemperature,
      'deepseek_max_tokens': deepseekMaxTokens,
      'dark_mode': darkMode,
      'auto_backup_enabled': autoBackupEnabled,
      'auto_backup_interval': autoBackupInterval,
      'auto_backup_max_count': autoBackupMaxCount,
      if (lastBackupTime != null) 'last_backup_time': lastBackupTime,
      'show_online_users': showOnlineUsers,
      'notify_device_online': notifyDeviceOnline,
      'notify_device_offline': notifyDeviceOffline,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  UserSettings copyWith({
    int? id,
    int? userId,
    String? deepseekApiKey,
    String? deepseekModel,
    double? deepseekTemperature,
    int? deepseekMaxTokens,
    int? darkMode,
    int? autoBackupEnabled,
    int? autoBackupInterval,
    int? autoBackupMaxCount,
    String? lastBackupTime,
    int? showOnlineUsers,
    String? createdAt,
    String? updatedAt,
  }) {
    return UserSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deepseekApiKey: deepseekApiKey ?? this.deepseekApiKey,
      deepseekModel: deepseekModel ?? this.deepseekModel,
      deepseekTemperature: deepseekTemperature ?? this.deepseekTemperature,
      deepseekMaxTokens: deepseekMaxTokens ?? this.deepseekMaxTokens,
      darkMode: darkMode ?? this.darkMode,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupInterval: autoBackupInterval ?? this.autoBackupInterval,
      autoBackupMaxCount: autoBackupMaxCount ?? this.autoBackupMaxCount,
      lastBackupTime: lastBackupTime ?? this.lastBackupTime,
      showOnlineUsers: showOnlineUsers ?? this.showOnlineUsers,
      notifyDeviceOnline: notifyDeviceOnline ?? this.notifyDeviceOnline,
      notifyDeviceOffline: notifyDeviceOffline ?? this.notifyDeviceOffline,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 是否启用深色模式
  bool get isDarkMode => darkMode == 1;

  /// 是否启用自动备份
  bool get isAutoBackupEnabled => autoBackupEnabled == 1;

  /// 是否显示在线用户提示
  bool get isShowOnlineUsers => showOnlineUsers == 1;

  /// 是否启用设备上线通知
  bool get isNotifyDeviceOnline => notifyDeviceOnline == 1;

  /// 是否启用设备下线通知
  bool get isNotifyDeviceOffline => notifyDeviceOffline == 1;
}

/// 用户设置更新请求
class UserSettingsUpdate {
  final String? deepseekApiKey;
  final String? deepseekModel;
  final double? deepseekTemperature;
  final int? deepseekMaxTokens;
  final int? darkMode;
  final int? autoBackupEnabled;
  final int? autoBackupInterval;
  final int? autoBackupMaxCount;
  final String? lastBackupTime;
  final int? showOnlineUsers;
  final int? notifyDeviceOnline;
  final int? notifyDeviceOffline;

  UserSettingsUpdate({
    this.deepseekApiKey,
    this.deepseekModel,
    this.deepseekTemperature,
    this.deepseekMaxTokens,
    this.darkMode,
    this.autoBackupEnabled,
    this.autoBackupInterval,
    this.autoBackupMaxCount,
    this.lastBackupTime,
    this.showOnlineUsers,
    this.notifyDeviceOnline,
    this.notifyDeviceOffline,
  }) : assert(
          deepseekTemperature == null ||
              (deepseekTemperature >= 0.0 && deepseekTemperature <= 1.0),
          '温度值必须在 0.0 到 1.0 之间',
        ),
        assert(
          deepseekMaxTokens == null ||
              (deepseekMaxTokens >= 500 && deepseekMaxTokens <= 4000),
          '最大令牌数必须在 500 到 4000 之间',
        ),
        assert(
          darkMode == null || darkMode == 0 || darkMode == 1,
          '深色模式值必须是 0 或 1',
        ),
        assert(
          autoBackupEnabled == null || autoBackupEnabled == 0 || autoBackupEnabled == 1,
          '自动备份启用值必须是 0 或 1',
        ),
        assert(
          autoBackupInterval == null || autoBackupInterval >= 1,
          '自动备份间隔必须大于等于 1 分钟',
        ),
        assert(
          autoBackupMaxCount == null || autoBackupMaxCount >= 1,
          '自动备份最大数量必须大于等于 1',
        ),
        assert(
          showOnlineUsers == null || showOnlineUsers == 0 || showOnlineUsers == 1,
          '显示在线用户值必须是 0 或 1',
        ),
        assert(
          notifyDeviceOnline == null || notifyDeviceOnline == 0 || notifyDeviceOnline == 1,
          '设备上线通知值必须是 0 或 1',
        ),
        assert(
          notifyDeviceOffline == null || notifyDeviceOffline == 0 || notifyDeviceOffline == 1,
          '设备下线通知值必须是 0 或 1',
        );

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (deepseekApiKey != null) json['deepseek_api_key'] = deepseekApiKey;
    if (deepseekModel != null) json['deepseek_model'] = deepseekModel;
    if (deepseekTemperature != null) {
      json['deepseek_temperature'] = deepseekTemperature;
    }
    if (deepseekMaxTokens != null) json['deepseek_max_tokens'] = deepseekMaxTokens;
    if (darkMode != null) json['dark_mode'] = darkMode;
    if (autoBackupEnabled != null) json['auto_backup_enabled'] = autoBackupEnabled;
    if (autoBackupInterval != null) json['auto_backup_interval'] = autoBackupInterval;
    if (autoBackupMaxCount != null) json['auto_backup_max_count'] = autoBackupMaxCount;
    if (lastBackupTime != null) json['last_backup_time'] = lastBackupTime;
    if (showOnlineUsers != null) json['show_online_users'] = showOnlineUsers;
    if (notifyDeviceOnline != null) json['notify_device_online'] = notifyDeviceOnline;
    if (notifyDeviceOffline != null) json['notify_device_offline'] = notifyDeviceOffline;
    return json;
  }
}

class SettingsRepository {
  final ApiService _apiService = ApiService();

  /// 获取当前用户的设置
  /// 
  /// 返回用户设置
  Future<UserSettings> getUserSettings() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/settings',
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return UserSettings.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('获取用户设置失败', e);
    }
  }

  /// 更新用户设置
  /// 
  /// [update] 用户设置更新请求（只包含要更新的字段）
  /// 
  /// 返回更新后的用户设置
  Future<UserSettings> updateUserSettings(UserSettingsUpdate update) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '/api/settings',
        body: update.toJson(),
        fromJsonT: (json) => json as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return UserSettings.fromJson(response.data!);
      } else {
        throw ApiError(
          message: response.message,
          errorCode: response.errorCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.unknown('更新用户设置失败', e);
    }
  }

  /// 更新 DeepSeek API 配置
  /// 
  /// [apiKey] API Key
  /// [model] 模型名称（可选）
  /// [temperature] 温度值（可选，0.0-1.0）
  /// [maxTokens] 最大令牌数（可选，500-4000）
  /// 
  /// 返回更新后的用户设置
  Future<UserSettings> updateDeepSeekConfig({
    String? apiKey,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    return updateUserSettings(
      UserSettingsUpdate(
        deepseekApiKey: apiKey,
        deepseekModel: model,
        deepseekTemperature: temperature,
        deepseekMaxTokens: maxTokens,
      ),
    );
  }

  /// 更新深色模式设置
  /// 
  /// [enabled] 是否启用深色模式
  /// 
  /// 返回更新后的用户设置
  Future<UserSettings> updateDarkMode(bool enabled) async {
    return updateUserSettings(
      UserSettingsUpdate(darkMode: enabled ? 1 : 0),
    );
  }

  /// 更新自动备份设置
  /// 
  /// [enabled] 是否启用自动备份
  /// [interval] 备份间隔（分钟）
  /// [maxCount] 最大备份数量
  /// 
  /// 返回更新后的用户设置
  Future<UserSettings> updateAutoBackupSettings({
    bool? enabled,
    int? interval,
    int? maxCount,
  }) async {
    return updateUserSettings(
      UserSettingsUpdate(
        autoBackupEnabled: enabled != null ? (enabled ? 1 : 0) : null,
        autoBackupInterval: interval,
        autoBackupMaxCount: maxCount,
      ),
    );
  }

  /// 更新显示在线用户设置
  /// 
  /// [enabled] 是否显示在线用户提示
  /// 
  /// 返回更新后的用户设置
  Future<UserSettings> updateShowOnlineUsers(bool enabled) async {
    return updateUserSettings(
      UserSettingsUpdate(showOnlineUsers: enabled ? 1 : 0),
    );
  }

  /// 批量导入数据（覆盖模式）
  /// 
  /// [importData] 导入数据（包含 exportInfo 和 data）
  /// 
  /// 返回导入结果统计
  Future<Map<String, dynamic>> importData(Map<String, dynamic> importData) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/api/settings/import-data',
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
      throw ApiError.unknown('数据导入失败', e);
    }
  }
}

