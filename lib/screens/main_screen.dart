// lib/screens/main_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/online_users_indicator.dart';
import '../widgets/device_notification_banner.dart';
import '../services/user_status_service.dart';
import '../services/api_service.dart';
import '../services/auto_backup_service.dart';
import '../repositories/settings_repository.dart';
import '../repositories/workspace_repository.dart';
import '../models/workspace.dart';
import 'workspace_list_screen.dart';
import 'home_screen.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final UserStatusService _userStatusService = UserStatusService();
  final SettingsRepository _settingsRepo = SettingsRepository();
  final ApiService _apiService = ApiService();
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  bool _notifyDeviceOnline = true;
  bool _notifyDeviceOffline = true;
  Timer? _settingsRefreshTimer;
  Workspace? _currentWorkspace;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
    _setupDeviceNotificationCallbacks();
    _loadCurrentWorkspace();
    _handleWorkspaceBackupOnLaunch(); // 处理workspace启动时的备份
    
    // 定期刷新通知设置（每30秒），以便在设置界面修改后能及时生效
    _settingsRefreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
      if (mounted) {
        _loadNotificationSettings();
      }
    });
  }

  @override
  void dispose() {
    _settingsRefreshTimer?.cancel();
    super.dispose();
  }

  /// 加载通知设置
  Future<void> _loadNotificationSettings() async {
    try {
      final settings = await _settingsRepo.getUserSettings();
      if (mounted) {
        setState(() {
          _notifyDeviceOnline = settings.isNotifyDeviceOnline;
          _notifyDeviceOffline = settings.isNotifyDeviceOffline;
        });
      }
    } catch (e) {
      print('加载通知设置失败: $e');
    }
  }

  /// 设置设备通知回调
  void _setupDeviceNotificationCallbacks() {
    _userStatusService.onDeviceOnline = (deviceName, platform) {
      if (_notifyDeviceOnline && mounted) {
        DeviceNotificationBanner.showOnlineNotification(context, deviceName, platform);
      }
    };

    _userStatusService.onDeviceOffline = (deviceName, platform) {
      if (_notifyDeviceOffline && mounted) {
        DeviceNotificationBanner.showOfflineNotification(context, deviceName, platform);
      }
    };
  }

  /// 加载当前workspace
  Future<void> _loadCurrentWorkspace() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId != null) {
        final workspace = await _workspaceRepo.getWorkspace(workspaceId);
        if (mounted) {
          setState(() {
            _currentWorkspace = workspace;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentWorkspace = null;
          });
        }
      }
    } catch (e) {
      print('加载当前workspace失败: $e');
      // 如果加载失败，清除workspace ID
      await _apiService.clearWorkspaceId();
      if (mounted) {
        setState(() {
          _currentWorkspace = null;
        });
      }
    }
  }

  /// 处理workspace启动时的备份
  Future<void> _handleWorkspaceBackupOnLaunch() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        return; // 没有workspace，不需要备份
      }

      final prefs = await SharedPreferences.getInstance();
      final backupService = AutoBackupService();
      
      // 1. 首先检查并恢复上次退出时未完成的备份
      await backupService.checkAndRecoverWorkspaceExitBackup();

      // 2. 如果配置了"启动时自动备份"，先备份一次
      final backupOnLaunchKey = 'auto_backup_on_launch_workspace_$workspaceId';
      final backupOnLaunch = prefs.getBool(backupOnLaunchKey) ?? false;
      
      if (backupOnLaunch) {
        try {
          final success = await backupService.performAutoBackup();
          if (success) {
            print('workspace启动时自动备份成功');
          } else {
            print('workspace启动时自动备份失败');
          }
        } catch (e) {
          print('workspace启动时自动备份异常: $e');
        }
      }

      // 3. 启动定时自动备份（如果已启用）
      final autoBackupEnabledKey = 'auto_backup_enabled_workspace_$workspaceId';
      final autoBackupEnabled = prefs.getBool(autoBackupEnabledKey) ?? false;
      final autoBackupIntervalKey = 'auto_backup_interval_workspace_$workspaceId';
      final autoBackupInterval = prefs.getInt(autoBackupIntervalKey) ?? 15;
      
      if (autoBackupEnabled) {
        await backupService.startAutoBackup(autoBackupInterval);
        print('workspace自动备份服务已启动，间隔: $autoBackupInterval 分钟');
      }
    } catch (e) {
      print('处理workspace启动备份失败: $e');
      // 失败不影响workspace使用
    }
  }

  /// 打开workspace选择界面或返回工作台
  Future<void> _openWorkspaceSelector() async {
    // 从顶部workspace标题下方弹出选择菜单：返回工作台或切换workspace
    final mediaQuery = MediaQuery.of(context);
    
    // 计算菜单位置：在屏幕中央（workspace标题下方）
    final screenWidth = mediaQuery.size.width;
    final menuWidth = 200.0; // 菜单宽度
    final leftPosition = (screenWidth - menuWidth) / 2; // 居中
    
    final position = RelativeRect.fromLTRB(
      leftPosition,
      mediaQuery.padding.top + kToolbarHeight,
      leftPosition + menuWidth,
      0,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<String>(
          value: 'dashboard',
          child: Row(
            children: [
              Icon(Icons.dashboard, color: Colors.green),
              SizedBox(width: 8),
              Text('返回我的工作台'),
            ],
          ),
        ),
        PopupMenuDivider(height: 4),
        PopupMenuItem<String>(
          value: 'switch',
          child: Row(
            children: [
              Icon(Icons.swap_horiz, color: Colors.green),
              SizedBox(width: 8),
              Text('切换 Workspace'),
            ],
          ),
        ),
      ],
    );
    
    if (result == 'dashboard') {
      // 返回主界面（使用自定义转场动画，向左滑动，后退效果）
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // 后退动画：新页面从左侧滑入（Offset(-1.0, 0.0) -> Offset.zero）
            const begin = Offset(-1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.ease;

            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        ),
      );
    } else if (result == 'switch') {
      // 切换workspace
      final switchResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WorkspaceListScreen(),
        ),
      );
      
      // 刷新当前workspace
      if (switchResult == true || switchResult == null) {
        // 先备份当前workspace（如果开启了退出备份）
        await AutoBackupService().backupOnWorkspaceExitIfNeeded();
        // 停止当前workspace的自动备份
        await AutoBackupService().stopAutoBackup();
        
        await _loadCurrentWorkspace();
        // 启动新workspace的备份服务
        await _handleWorkspaceBackupOnLaunch();
      }
    }
  }

  // 定义第一页的功能项
  final List<Map<String, dynamic>> _page1Items = [
    {
      'title': '基础功能',
      'items': [
        {'name': '采购', 'icon': Icons.shopping_cart, 'route': '/purchases'},
        {'name': '销售', 'icon': Icons.point_of_sale, 'route': '/sales'},
        {'name': '退货', 'icon': Icons.assignment_return, 'route': '/returns'},
        {'name': '进账', 'icon': Icons.account_balance_wallet, 'route': '/income'},
        {'name': '汇款', 'icon': Icons.send, 'route': '/remittance'},
      ]
    },
    {
      'title': '基础信息',
      'items': [
        {'name': '产品', 'icon': Icons.inventory, 'route': '/products'},
        {'name': '客户', 'icon': Icons.people, 'route': '/customers'},
        {'name': '供应商', 'icon': Icons.business, 'route': '/suppliers'},
        {'name': '员工', 'icon': Icons.badge, 'route': '/employees'},
      ]
    },
  ];

  // 定义第二页的功能项
  final List<Map<String, dynamic>> _page2Items = [
    {
      'title': '基础统计',
      'items': [
        {'name': '库存', 'icon': Icons.assessment, 'route': '/stock_report'},
        {'name': '采购', 'icon': Icons.receipt_long, 'route': '/purchase_report'},
        {'name': '销售', 'icon': Icons.bar_chart, 'route': '/sales_report'},
        {'name': '退货', 'icon': Icons.assignment_return, 'route': '/returns_report'},
      ]
    },
    {
      'title': '综合分析',
      'items': [
        {'name': '销售汇总', 'icon': Icons.bar_chart, 'route': '/total_sales_report'},
        {'name': '销售与进账', 'icon': Icons.compare_arrows, 'route': '/sales_income_analysis'},
        {'name': '采购与汇款', 'icon': Icons.sync_alt, 'route': '/purchase_remittance_analysis'},
        {'name': '财务统计', 'icon': Icons.attach_money, 'route': '/financial_statistics'},
      ]
    },
    {
      'title': '智能分析',
      'items': [
        {'name': '数据仪表盘', 'icon': Icons.dashboard, 'route': '/dashboard'},
        {'name': '数据分析助手', 'icon': Icons.analytics, 'route': '/data_assistant'},
      ]
    },
  ];

  // 定义第三页的功能项
  final List<Map<String, dynamic>> _page3Items = [
    {
      'title': '系统工具',
      'items': [
        {'name': '数据管理', 'icon': Icons.dataset, 'route': '/workspace-data-management'},
        {'name': '数据备份', 'icon': Icons.backup, 'route': '/auto_backup'},
        {'name': '日志', 'icon': Icons.history, 'route': '/audit-logs'},
      ]
    },
  ];


  // 构建功能页面
  Widget _buildPage(List<Map<String, dynamic>> menuItems) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: menuItems.length,
      itemBuilder: (context, groupIndex) {
        final group = menuItems[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(
                group['title'],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: EdgeInsets.only(bottom: 16),
              child: ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: group['items'].length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = group['items'][index];
                  return ListTile(
                    leading: Icon(item['icon'], color: Colors.green),
                    title: Text(
                      item['name'],
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      if (item['route'] != null) {
                        Navigator.pushNamed(context, item['route']);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        title: InkWell(
          onTap: _openWorkspaceSelector,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspaces,
                  size: 22,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Text(
                  _currentWorkspace?.name ?? '选择Workspace',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
        centerTitle: true,
        actions: const [],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildPage(_page1Items),
              _buildPage(_page2Items),
              _buildPage(_page3Items),
            ],
          ),
          // 在线用户指示器
          OnlineUsersIndicator(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey[600],
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.apps, size: 24),
            activeIcon: Icon(Icons.apps, size: 28),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart, size: 24),
            activeIcon: Icon(Icons.bar_chart, size: 28),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home, size: 24),
            activeIcon: Icon(Icons.home, size: 28),
            label: '',
          ),
        ],
      ),
    );
  }
}