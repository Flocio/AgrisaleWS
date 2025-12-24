/// 在线设备指示器组件
/// 显示当前账号的在线设备数量和列表

import 'package:flutter/material.dart';
import '../services/user_status_service.dart';
import '../repositories/settings_repository.dart';

class OnlineUsersIndicator extends StatefulWidget {
  /// 是否显示详细信息（点击后显示用户列表）
  final bool showDetails;

  /// 指示器位置
  final Alignment alignment;

  const OnlineUsersIndicator({
    Key? key,
    this.showDetails = true,
    this.alignment = Alignment.topRight,
  }) : super(key: key);

  @override
  _OnlineUsersIndicatorState createState() => _OnlineUsersIndicatorState();
}

class _OnlineUsersIndicatorState extends State<OnlineUsersIndicator> {
  final UserStatusService _userStatusService = UserStatusService();
  final SettingsRepository _settingsRepo = SettingsRepository();

  int _onlineUsersCount = 0;
  List<OnlineUser> _onlineUsers = [];
  bool _showOnlineUsers = true; // 默认显示
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
      // 默认显示
      if (mounted) {
        setState(() {
          _showOnlineUsers = true;
        });
      }
    }
  }

  /// 开始监听在线用户更新
  void _startListening() {
    // 设置更新回调
    _userStatusService.onOnlineUsersUpdated = (users, count) {
      if (mounted) {
        setState(() {
          _onlineUsersCount = count;
          _onlineUsers = users;
          _isLoading = false;
        });
        // 同时重新加载设置（检查是否显示）
        _loadSettings();
      }
    };

    // 启动在线用户列表自动更新
    _userStatusService.startOnlineUsersUpdate(
      interval: 5, // 每 5 秒更新一次
      onUpdated: (users, count) {
        if (mounted) {
          setState(() {
            _onlineUsersCount = count;
            _onlineUsers = users;
            _isLoading = false;
          });
          // 同时重新加载设置（检查是否显示）
          _loadSettings();
        }
      },
    );
  }

  @override
  void dispose() {
    // 注意：不要在这里停止服务，因为其他组件可能也在使用
    // _userStatusService.stopOnlineUsersUpdate();
    super.dispose();
  }

  /// 显示在线设备详情对话框
  void _showOnlineUsersDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => _OnlineUsersDialog(
        initialUsers: _onlineUsers,
        initialCount: _onlineUsersCount,
        userStatusService: _userStatusService,
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
      return Positioned(
        top: 8,
        right: 8,
        child: Container(
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
        ),
      );
    }

    // 显示在线设备数量
    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: widget.showDetails ? _showOnlineUsersDialog : null,
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
              if (widget.showDetails && _onlineUsersCount > 0) ...[
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
      ),
    );
  }
}

/// 在线设备详情对话框（独立组件，支持自动更新）
class _OnlineUsersDialog extends StatefulWidget {
  final List<OnlineUser> initialUsers;
  final int initialCount;
  final UserStatusService userStatusService;

  const _OnlineUsersDialog({
    required this.initialUsers,
    required this.initialCount,
    required this.userStatusService,
  });

  @override
  _OnlineUsersDialogState createState() => _OnlineUsersDialogState();
}

class _OnlineUsersDialogState extends State<_OnlineUsersDialog> {
  late List<OnlineUser> _currentUsers;
  late int _currentCount;
  Function(List<OnlineUser>, int)? _updateCallback;
  Function(List<OnlineUser>, int)? _originalCallback;

  @override
  void initState() {
    super.initState();
    _currentUsers = widget.initialUsers;
    _currentCount = widget.initialCount;

    // 保存原来的回调
    _originalCallback = widget.userStatusService.onOnlineUsersUpdated;

    // 创建新的回调，同时更新对话框和原来的回调
    _updateCallback = (users, count) {
      if (mounted) {
        setState(() {
          _currentUsers = users;
          _currentCount = count;
        });
      }
      // 同时调用原来的回调（如果有）
      if (_originalCallback != null) {
        _originalCallback!(users, count);
      }
    };

    // 设置更新回调
    widget.userStatusService.onOnlineUsersUpdated = _updateCallback;
  }

  @override
  void dispose() {
    // 恢复原来的回调
    widget.userStatusService.onOnlineUsersUpdated = _originalCallback;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('在线设备 ($_currentCount)'),
      content: SizedBox(
        width: double.maxFinite,
        child: _currentUsers.isEmpty
            ? Center(
                child: Text(
                  '暂无在线设备',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _currentUsers.length,
                itemBuilder: (context, index) {
                  final user = _currentUsers[index];
                  final platformText = user.platform ?? '未知平台';
                  final subtitleText = user.currentAction != null
                      ? user.currentAction!
                      : '在线';
                    
                  // 构建设备显示名称
                  String deviceDisplayName;
                  String? deviceInfo; // 设备详细信息（平台 + 其他信息）
                  
                  if (user.deviceName != null && user.deviceName!.isNotEmpty) {
                    // 有设备名称，使用设备名称作为标题
                    deviceDisplayName = user.deviceName!;
                    deviceInfo = platformText; // 平台信息作为副标题第一行
                  } else {
                    // 没有设备名称，使用平台名称作为标题
                    deviceDisplayName = platformText;
                    deviceInfo = null; // 不显示额外的设备信息
                  }
                  
                  // 根据平台选择图标
                  IconData platformIcon;
                  if (platformText == 'Android' || platformText == 'iOS') {
                    // 手机端：显示手机图标
                    platformIcon = Icons.smartphone;
                  } else if (platformText == 'macOS' || platformText == 'Windows' || platformText == 'Linux') {
                    // 电脑端：显示电脑图标
                    platformIcon = Icons.computer;
                  } else {
                    // 未知平台：使用默认设备图标
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
    );
  }
}


