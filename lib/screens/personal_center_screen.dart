/// 个人中心界面
/// 登录后的主界面子页，显示个人信息和快捷入口（不再包含“我的工作台”板块）

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/user_status_service.dart';
import '../repositories/settings_repository.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/online_users_indicator.dart';
import 'main_screen.dart';
import 'account_settings_screen.dart';
import 'model_settings_screen.dart';
import 'server_config_screen.dart';
import 'version_info_screen.dart';

class PersonalCenterScreen extends StatefulWidget {
  /// 可选：从个人中心切换到底部导航的“工作台”Tab（目前保留以便将来扩展）
  final VoidCallback? onSwitchToWorkspace;
  
  const PersonalCenterScreen({
    Key? key,
    this.onSwitchToWorkspace,
  }) : super(key: key);

  @override
  _PersonalCenterScreenState createState() => _PersonalCenterScreenState();
}

class _PersonalCenterScreenState extends State<PersonalCenterScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  UserInfo? _userInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载个人信息
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _authService.getCurrentUser();
      if (mounted) {
        setState(() {
          _userInfo = user;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        context.showErrorSnackBar('加载个人信息失败: ${e is ApiError ? e.message : e.toString()}');
      }
    }
  }

  /// 进入当前 workspace 的账本（如果有）
  Future<void> _enterCurrentWorkspace() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(),
          ),
        );
      } else {
        context.showSnackBar('当前还没有选择 Workspace，请先在工作台中创建或选择。');
      }
    } catch (e) {
      context.showErrorSnackBar('进入账本失败: ${e.toString()}');
    }
  }

  // 注意：退出登录和注销账户功能已移至 AccountSettingsScreen

  /// 格式化日期时间为 UTC+8 时区
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) {
      return '';
    }
    
    try {
      DateTime dateTime;
      
      // 如果格式是 "YYYY-MM-DD HH:MM:SS"（没有时区信息），假设是 UTC 时间
      if (dateTimeStr.length == 19 && 
          dateTimeStr.contains(' ') && 
          !dateTimeStr.contains('T') && 
          !dateTimeStr.contains('+') && 
          !dateTimeStr.contains('Z')) {
        // 手动解析为 UTC 时间
        final parts = dateTimeStr.split(' ');
        if (parts.length == 2) {
          final dateParts = parts[0].split('-');
          final timeParts = parts[1].split(':');
          
          if (dateParts.length == 3 && timeParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            final hour = int.parse(timeParts[0]);
            final minute = int.parse(timeParts[1]);
            final second = int.parse(timeParts[2]);
            
            // 创建 UTC 时间的 DateTime 对象
            dateTime = DateTime.utc(year, month, day, hour, minute, second);
          } else {
            // 解析失败，尝试标准解析
            dateTime = DateTime.parse(dateTimeStr).toUtc();
          }
        } else {
          dateTime = DateTime.parse(dateTimeStr).toUtc();
        }
      } else {
        // 标准 ISO8601 格式解析（可能包含时区信息）
        dateTime = DateTime.parse(dateTimeStr);
        // 统一转换为 UTC 时间
        dateTime = dateTime.toUtc();
      }
      
      // 格式化为 UTC+8 时区显示（UTC时间 + 8小时）
      final utc8 = dateTime.add(Duration(hours: 8));
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(utc8);
    } catch (e) {
      // 如果解析失败，返回原始字符串
      return dateTimeStr ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部标题栏（与主界面风格一致，高度对齐 AppBar，标题居中）
                  Container(
                    color: Theme.of(context).primaryColor,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top,
                      left: 16,
                      right: 16,
                    ),
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/background.png',
                              width: 36,
                              height: 36,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'AgrisaleWS',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 内容区域：只保留个人信息 + 快捷操作
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUserInfoCard(),
                        SizedBox(height: 16),
                        _buildQuickActions(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 构建用户信息卡片
  Widget _buildUserInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                // 头像
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    size: 50,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                SizedBox(width: 16),
                // 基本信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userInfo?.username ?? '未登录用户',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      if (_userInfo?.createdAt != null)
                        Text(
                          '注册时间：${_formatDateTime(_userInfo!.createdAt)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (_userInfo?.lastLoginAt != null)
                        Text(
                          '上次登录：${_formatDateTime(_userInfo!.lastLoginAt)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 在线设备标签（右上角）
          Positioned(
            top: 8,
            right: 8,
            child: _buildOnlineUsersBadge(),
          ),
        ],
      ),
    );
  }

  /// 构建在线设备标签（受设置控制）
  Widget _buildOnlineUsersBadge() {
    // 使用OnlineUsersIndicator的内部逻辑，但适配卡片布局
    return _OnlineUsersBadgeWidget();
  }

  /// 构建设置区（账户设置）
  Widget _buildQuickActions() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            // 账户设置入口
            ListTile(
              leading: Icon(Icons.account_circle, color: Colors.green),
              title: Text(
                '账户',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AccountSettingsScreen(),
                  ),
                );
              },
            ),
            // 模型设置入口
            ListTile(
              leading: Icon(Icons.tune, color: Colors.green),
              title: Text(
                '模型',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ModelSettingsScreen(),
                  ),
                );
              },
            ),
            // 服务器配置入口
            ListTile(
              leading: Icon(Icons.dns, color: Colors.green),
              title: Text(
                '服务器',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ServerConfigScreen(),
                  ),
                );
              },
            ),
            // 关于入口
            ListTile(
              leading: Icon(Icons.info_outline, color: Colors.green),
              title: Text(
                '关于',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VersionInfoScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 在线设备标签组件（用于卡片内部）
class _OnlineUsersBadgeWidget extends StatefulWidget {
  @override
  _OnlineUsersBadgeWidgetState createState() => _OnlineUsersBadgeWidgetState();
}

class _OnlineUsersBadgeWidgetState extends State<_OnlineUsersBadgeWidget> {
  final UserStatusService _userStatusService = UserStatusService();
  final SettingsRepository _settingsRepo = SettingsRepository();

  int _onlineUsersCount = 0;
  List<OnlineUser> _onlineUsers = [];
  bool _showOnlineUsers = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startListening();
  }

  /// 加载用户设置（是否显示在线设备提示）
  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsRepo.getUserSettings();
      if (mounted) {
        setState(() {
          _showOnlineUsers = settings.isShowOnlineUsers;
        });
      }
    } catch (e) {
      print('加载用户设置失败: $e');
      if (mounted) {
        setState(() {
          _showOnlineUsers = true;
        });
      }
    }
  }

  /// 开始监听在线用户更新
  void _startListening() {
    _userStatusService.onOnlineUsersUpdated = (users, count) {
      if (mounted) {
        setState(() {
          _onlineUsersCount = count;
          _onlineUsers = users;
          _isLoading = false;
        });
        _loadSettings();
      }
    };

    _userStatusService.startOnlineUsersUpdate(
      interval: 5,
      onUpdated: (users, count) {
        if (mounted) {
          setState(() {
            _onlineUsersCount = count;
            _onlineUsers = users;
            _isLoading = false;
          });
          _loadSettings();
        }
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 显示在线设备详情对话框
  void _showOnlineUsersDialog() {
    // 使用OnlineUsersIndicator中的对话框
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('在线设备 ($_onlineUsersCount)'),
        content: SizedBox(
          width: double.maxFinite,
          child: _onlineUsers.isEmpty
              ? Center(
                  child: Text(
                    '暂无在线设备',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _onlineUsers.length,
                  itemBuilder: (context, index) {
                    final user = _onlineUsers[index];
                    final platformText = user.platform ?? '未知平台';
                    final subtitleText = user.currentAction != null
                        ? user.currentAction!
                        : '在线';
                    
                    String deviceDisplayName;
                    String? deviceInfo;
                    
                    if (user.deviceName != null && user.deviceName!.isNotEmpty) {
                      deviceDisplayName = user.deviceName!;
                      deviceInfo = platformText;
                    } else {
                      deviceDisplayName = platformText;
                      deviceInfo = null;
                    }
                    
                    IconData platformIcon;
                    if (platformText == 'Android' || platformText == 'iOS') {
                      platformIcon = Icons.smartphone;
                    } else if (platformText == 'macOS' || platformText == 'Windows' || platformText == 'Linux') {
                      platformIcon = Icons.computer;
                    } else {
                      platformIcon = Icons.devices;
                    }
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green,
                        child: Icon(
                          platformIcon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        deviceDisplayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (deviceInfo != null) ...[
                            Text(
                              deviceInfo,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 2),
                          ],
                          Text(
                            subtitleText,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: Icon(
                        Icons.circle,
                        size: 8,
                        color: Colors.green,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 如果不显示在线设备提示，返回空组件
    if (!_showOnlineUsers) {
      return SizedBox.shrink();
    }

    // 如果正在加载，显示加载指示器
    if (_isLoading) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 4),
            Text(
              '加载中...',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    }

    // 显示在线设备数量
    return GestureDetector(
      onTap: _showOnlineUsersDialog,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices,
              size: 16,
              color: Colors.white,
            ),
            SizedBox(width: 4),
            Text(
              '设备: $_onlineUsersCount',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_onlineUsersCount > 0) ...[
              SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


