import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../services/auto_backup_service.dart';
import '../repositories/settings_repository.dart';
import '../services/auth_service.dart';
import '../services/user_status_service.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
      return true; // 保存成功
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('保存设置失败: ${e.message}');
      }
      return false; // 保存失败
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('保存设置失败: ${e.toString()}');
      }
      return false; // 保存失败
    }
  }

  // 自动保存设置（不显示成功提示，失败时显示错误提示）
  Future<void> _autoSaveSettings() async {
    final success = await _saveSettings();
    // 如果保存失败，重新从服务器加载设置以恢复一致状态
    if (!success) {
      await _loadSystemSettings();
    }
  }

  // 手动保存设置（显示成功提示）
  Future<void> _manualSaveSettings() async {
    final success = await _saveSettings();
    if (success) {
      context.showSnackBar('设置已保存');
    }
    // 如果保存失败，重新从服务器加载设置以恢复一致状态
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

  // 注意：数据管理功能已移至 WorkspaceDataManagementScreen，这里不再包含
  // 账户设置和在线设备功能已移至 PersonalCenterScreen
  
  // 退出登录
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
        // 退出账号前，如果开启了“退出时自动备份”，先备份当前workspace
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
        
        // 停止自动备份服务
        await AutoBackupService().stopAutoBackup();
        
        // 调用 AuthService 的 logout 方法，清除 Token 和用户名
        // logout 方法会发送 device_id 到服务器，只删除当前设备的记录
        await AuthService().logout();
        
        // 跳转到登录界面
        Navigator.of(context).pushReplacementNamed('/');
      } catch (e) {
        print('退出登录时出错: $e');
        // 即使出错，也要清除本地 Token 并跳转
        try {
          await AuthService().logout();
        } catch (e2) {
          print('清除 Token 时出错: $e2');
        }
        Navigator.of(context).pushReplacementNamed('/');
      }
    }
  }
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('账户设置', 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
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
                        Text('当前用户: $_username'),
                        SizedBox(height: 16),
                        Text(
                          '修改密码',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _currentPasswordController,
                                decoration: InputDecoration(
                                  labelText: '当前密码',
                                  border: OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureCurrentPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
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
                              SizedBox(height: 8),
                              TextFormField(
                                controller: _newPasswordController,
                                decoration: InputDecoration(
                                  labelText: '新密码',
                                  border: OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureNewPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
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
                              SizedBox(height: 8),
                              TextFormField(
                                controller: _confirmPasswordController,
                                decoration: InputDecoration(
                                  labelText: '确认新密码',
                                  border: OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
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
                            // 自动保存设置
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
                            // 自动保存设置
                            _autoSaveSettings();
                          },
                          secondary: Icon(Icons.device_hub, color: Colors.green),
                        ),
                        SwitchListTile(
                          title: Text('设备下线通知'),
                          subtitle: Text('当有设备离线时显示通知'),
                          value: _notifyDeviceOffline,
                          onChanged: (value) {
                            setState(() {
                              _notifyDeviceOffline = value;
                            });
                            // 自动保存设置
                            _autoSaveSettings();
                          },
                          secondary: Icon(Icons.devices_other, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          FooterWidget(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}