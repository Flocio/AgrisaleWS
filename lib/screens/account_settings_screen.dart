/// 账户设置界面
/// 包含修改密码和在线设备功能

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/settings_repository.dart';
import '../services/auth_service.dart';
import '../services/user_status_service.dart';
import '../services/auto_backup_service.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';
import 'login_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  @override
  _AccountSettingsScreenState createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _username;
  
  final SettingsRepository _settingsRepo = SettingsRepository();
  final AuthService _authService = AuthService();
  
  // 在线设备提示开关
  bool _showOnlineUsers = true;
  bool _notifyDeviceOnline = true;
  bool _notifyDeviceOffline = true;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadSystemSettings();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('current_username') ?? '未登录';
    });
  }
  
  Future<void> _loadSystemSettings() async {
    try {
      final settings = await _settingsRepo.getUserSettings();
      if (mounted) {
        setState(() {
          _showOnlineUsers = settings.isShowOnlineUsers;
          _notifyDeviceOnline = settings.isNotifyDeviceOnline;
          _notifyDeviceOffline = settings.isNotifyDeviceOffline;
        });
      }
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载设置失败: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载设置失败: ${e.toString()}');
      }
    }
  }

  Future<bool> _saveSettings() async {
    try {
      await _settingsRepo.updateUserSettings(
        UserSettingsUpdate(
          showOnlineUsers: _showOnlineUsers ? 1 : 0,
          notifyDeviceOnline: _notifyDeviceOnline ? 1 : 0,
          notifyDeviceOffline: _notifyDeviceOffline ? 1 : 0,
        ),
      );
      return true;
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('保存设置失败: ${e.message}');
      }
      return false;
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('保存设置失败: ${e.toString()}');
      }
      return false;
    }
  }

  Future<void> _autoSaveSettings() async {
    final success = await _saveSettings();
    if (!success) {
      await _loadSystemSettings();
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await _authService.changePassword(
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      context.showSuccessSnackBar('密码已更新');

      // 清空输入框
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    } on ApiError catch (e) {
      context.showErrorSnackBar('更新密码失败: ${e.message}');
    } catch (e) {
      context.showErrorSnackBar('更新密码失败: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '账户',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          // 注销账户按钮（右上角icon）
          IconButton(
            icon: Icon(Icons.person_remove, color: Colors.white),
            tooltip: '注销账户',
            onPressed: _deleteAccount,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16.0),
        children: [
          // 账户设置卡片
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '账户设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Divider(),
                  SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,  // 明确指定字体大小，与Text默认一致
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      children: [
                        TextSpan(text: '当前用户: '),
                        TextSpan(
                          text: _username ?? '未登录',
                          style: TextStyle(
                            fontSize: 14,  // 明确指定字体大小
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '修改密码',
                    style: TextStyle(
                      fontSize: 14,  // 明确指定字体大小
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // 当前密码输入框
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid, width: 1),
                          ),
                          child: TextFormField(
                            controller: _currentPasswordController,
                            style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                            decoration: InputDecoration(
                              hintText: '当前密码',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureCurrentPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureCurrentPassword = !_obscureCurrentPassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscureCurrentPassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入当前密码';
                              }
                              return null;
                            },
                          ),
                        ),
                        SizedBox(height: 12),
                        // 新密码输入框
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid, width: 1),
                          ),
                          child: TextFormField(
                            controller: _newPasswordController,
                            style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                            decoration: InputDecoration(
                              hintText: '新密码',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNewPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureNewPassword = !_obscureNewPassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscureNewPassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请输入新密码';
                              }
                              if (value.length < 3) {
                                return '密码长度至少为3个字符';
                              }
                              return null;
                            },
                          ),
                        ),
                        SizedBox(height: 12),
                        // 确认新密码输入框
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid, width: 1),
                          ),
                          child: TextFormField(
                            controller: _confirmPasswordController,
                            style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                            decoration: InputDecoration(
                              hintText: '确认新密码',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscureConfirmPassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return '请确认新密码';
                              }
                              if (value != _newPasswordController.text) {
                                return '两次输入的密码不一致';
                              }
                              return null;
                            },
                          ),
                        ),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _changePassword,
                          child: Text('更新密码'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(double.infinity, 50),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          
          // 在线设备卡片
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '在线设备',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Divider(),
                  SwitchListTile(
                    title: Text('显示在线设备提示'),
                    subtitle: Text('在主界面显示该账号的在线设备数量'),
                    value: _showOnlineUsers,
                    onChanged: (value) {
                      setState(() {
                        _showOnlineUsers = value;
                      });
                      _autoSaveSettings();
                    },
                    secondary: Icon(Icons.devices, color: Colors.blue),
                  ),
                  Divider(),
                  SwitchListTile(
                    title: Text('设备上线通知'),
                    subtitle: Text('当有新设备登录时显示通知'),
                    value: _notifyDeviceOnline,
                    onChanged: (value) {
                      setState(() {
                        _notifyDeviceOnline = value;
                      });
                      _autoSaveSettings();
                    },
                    secondary: Icon(Icons.device_hub, color: Colors.green),
                  ),
                  Divider(),
                  SwitchListTile(
                    title: Text('设备下线通知'),
                    subtitle: Text('当有设备离线时显示通知'),
                    value: _notifyDeviceOffline,
                    onChanged: (value) {
                      setState(() {
                        _notifyDeviceOffline = value;
                      });
                      _autoSaveSettings();
                    },
                    secondary: Icon(Icons.devices_other, color: Colors.orange),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          
          // 退出登录按钮（页面最下方）
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: ElevatedButton(
              onPressed: _logout,
              child: Text('退出登录'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Colors.red[100],
                foregroundColor: Colors.red[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 退出登录
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认退出'),
        content: Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('退出'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        // 退出账号前，如果开启了"退出时自动备份"，先备份当前workspace
        await AutoBackupService().backupOnWorkspaceExitIfNeeded();

        // 先发送一次心跳，确保设备ID已同步到服务器
        // 然后停止心跳服务（必须在清除 Token 之前，因为需要 Token 来调用服务器接口）
        final userStatusService = UserStatusService();
        try {
          // 发送最后一次心跳，确保设备ID在服务器端
          await userStatusService.updateHeartbeat();
        } catch (e) {
          print('发送最后心跳失败: $e');
        }
        userStatusService.stopHeartbeat();
        
        // 停止自动备份服务（workspace级别）
        await AutoBackupService().stopAutoBackup();
        
        // 调用 AuthService 的 logout 方法，清除 Token 和用户名
        // logout 方法会发送 device_id 到服务器，只删除当前设备的记录
        await AuthService().logout();
        
        // 跳转到登录界面
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => LoginScreen(),
            ),
            (route) => false,
          );
        }
      } catch (e) {
        print('退出登录时出错: $e');
        // 即使出错，也要清除本地 Token 并跳转
        try {
          await AuthService().logout();
        } catch (e2) {
          print('清除 Token 时出错: $e2');
        }
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => LoginScreen(),
            ),
            (route) => false,
          );
        }
      }
    }
  }

  /// 注销账户
  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              '注销账户',
              style: TextStyle(color: Colors.red[700]),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '警告：此操作不可恢复！',
                    style: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '注销账户将永久删除：',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text('• 您的账户信息'),
                  Text('• 所有 Workspace 及其数据'),
                  Text('• 所有业务数据（产品、销售、采购等）'),
                  Text('• 用户设置和配置'),
                  SizedBox(height: 16),
                  Text(
                    '请输入您的密码以确认注销：',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: '密码',
                      hintText: '请输入您的密码',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        Navigator.pop(context, true);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (passwordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('请输入密码'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                child: Text('确认注销'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && passwordController.text.isNotEmpty) {
      try {
        // 显示加载提示
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('正在注销账户...'),
              ],
            ),
          ),
        );

        await _authService.deleteAccount(passwordController.text);
        
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框
          
          // 显示成功提示
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Text('账户已注销'),
              content: Text('您的账户已成功注销，所有数据已删除。'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LoginScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  child: Text('确定'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框
          context.showErrorSnackBar('注销账户失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
  }
}

