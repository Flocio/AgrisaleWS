/// Workspace 详情界面
/// 显示workspace详情、成员管理、设置等

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/workspace.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';
import 'workspace_members_screen.dart';

class WorkspaceDetailScreen extends StatefulWidget {
  final Workspace workspace;

  const WorkspaceDetailScreen({
    Key? key,
    required this.workspace,
  }) : super(key: key);

  @override
  _WorkspaceDetailScreenState createState() => _WorkspaceDetailScreenState();
}

class _WorkspaceDetailScreenState extends State<WorkspaceDetailScreen> {
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  late Workspace _workspace;
  bool _isLoading = false; // 全局加载状态
  String? _userRole;
  int _memberCount = 0;
  List<WorkspaceMember> _members = []; // 成员列表
  int? _currentUserId; // 当前用户ID（用于标记"我"）

  /// 获取workspace的彩色图标
  Widget _getWorkspaceIcon(Workspace workspace) {
    // 根据workspace的ID生成一个稳定的颜色
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    final colorIndex = workspace.id % colors.length;
    final iconColor = colors[colorIndex];
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.work_outline,
        size: 28,
        color: iconColor,
      ),
    );
  }

  /// 获取角色显示名称
  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'owner':
        return '拥有者';
      case 'admin':
        return '管理员';
      case 'editor':
        return '编辑者';
      case 'viewer':
        return '查看者';
      default:
        return role;
    }
  }

  /// 获取角色颜色（与成员管理界面一致）
  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.purple;
      case 'admin':
        return Colors.red;
      case 'editor':
        return Colors.blue;
      case 'viewer':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// 构建角色权限标签（400米跑道形状，与服务器标签样式一致）
  Widget _buildRoleBadge(String role) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: _getRoleColor(role),
        shape: StadiumBorder(),
      ),
      child: Text(
        _getRoleDisplayName(role),
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建存储类型标签（400米跑道形状）
  Widget _buildStorageTypeBadge(String storageType) {
    final isServer = storageType == 'server';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: isServer ? Color(0xFFD4AF37) : Colors.blue, // 深黄色或蓝色
        shape: StadiumBorder(),
      ),
      child: Text(
        isServer ? '服务器' : '本地',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建成员数标签
  Widget _buildMemberCountBadge(int count) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: Colors.grey[400],
        shape: StadiumBorder(),
      ),
      child: Text(
        '$count 名成员',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建成员信息卡片
  Widget _buildMembersInfoCard() {
    final canManageMembers = _userRole == 'owner' || _userRole == 'admin';
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行：左侧"成员信息"和帮助图标，右侧"管理成员"按钮（仅owner和admin显示）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '成员信息',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showRolePermissionsHelp,
                      child: Icon(
                        Icons.help_outline,
                        size: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                if (canManageMembers)
                  TextButton.icon(
                    onPressed: () => _navigateToMembersManagement(),
                    icon: Icon(Icons.settings, size: 18),
                    label: Text('管理成员'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                    ),
                  ),
              ],
            ),
            SizedBox(height: 12),
            // 成员列表（加载完成后显示）
            if (_members.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '暂无成员',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              ..._members.map((member) => _buildMemberItem(member)).toList(),
          ],
        ),
      ),
    );
  }

  /// 构建成员项
  Widget _buildMemberItem(WorkspaceMember member) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // 头像
          CircleAvatar(
            radius: 20,
            backgroundColor: _getRoleColor(member.role),
            child: Text(
              member.username[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 12),
          // 成员信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.username,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // 如果是当前用户，显示"(当前用户)"标记
                    if (_currentUserId != null && member.userId == _currentUserId) ...[
                      SizedBox(width: 4),
                      Text(
                        '(当前用户)',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    // 角色标签
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: ShapeDecoration(
                        color: _getRoleColor(member.role),
                        shape: StadiumBorder(),
                      ),
                      child: Text(
                        _getRoleDisplayName(member.role),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 邀请信息
                    if (member.invitedByUsername != null) ...[
                      SizedBox(width: 8),
                      Text(
                        '由 ${member.invitedByUsername} 邀请',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace;
    _loadAllData(); // 统一加载所有数据
  }

  /// 格式化日期时间为 UTC+8 时区（与个人中心一致）
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
      print('日期时间解析失败: $e');
      return dateTimeStr;
    }
  }

  /// 统一加载所有数据（workspace详情、角色、成员信息）
  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 并行加载workspace详情和角色/成员信息
      await Future.wait([
        _loadWorkspace(),
        _loadRoleAndMemberInfo(),
      ]);
    } catch (e) {
      print('加载workspace数据失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 导航到成员管理界面（带权限检查）
  Future<void> _navigateToMembersManagement() async {
    // 重新检查权限（防止权限在界面显示后被修改）
    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        context.showErrorSnackBar('无法获取用户信息');
        return;
      }

      // 检查是否是拥有者
      bool hasPermission = false;
      if (_workspace.ownerId == currentUser.id) {
        hasPermission = true;
      } else {
        // 获取最新的成员列表，检查当前用户角色
        try {
          final members = await _workspaceRepo.getWorkspaceMembers(_workspace.id);
          final member = members.firstWhere(
            (m) => m.userId == currentUser.id,
          );
          hasPermission = member.role == 'admin' || member.role == 'owner';
          
          // 更新当前角色（可能已被修改）
          if (mounted) {
            setState(() {
              _userRole = member.role;
            });
          }
        } catch (e) {
          // 不是成员或获取失败
          hasPermission = false;
        }
      }

      if (!hasPermission) {
        // 权限不足，刷新界面并提示
        await _loadRoleAndMemberInfo(); // 刷新角色和成员信息
        if (mounted) {
          context.showErrorSnackBar('无权限管理成员');
        }
        return;
      }

      // 权限足够，跳转到成员管理界面
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WorkspaceMembersScreen(workspace: _workspace),
          ),
        ).then((_) {
          _loadWorkspace();
          _loadRoleAndMemberInfo(); // 刷新成员列表
        });
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('检查权限失败: ${e is ApiError ? e.message : e.toString()}');
        // 刷新角色信息
        await _loadRoleAndMemberInfo();
      }
    }
  }

  /// 加载角色和成员信息
  Future<void> _loadRoleAndMemberInfo() async {
    if (_workspace.storageType != 'server') return; // 本地workspace不需要角色和成员数
    
    try {
      // 获取当前用户信息
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) return;

      // 保存当前用户ID（用于标记"我"）
      if (mounted) {
        setState(() {
          _currentUserId = currentUser.id;
        });
      }

      // 检查是否是拥有者
      if (_workspace.ownerId == currentUser.id) {
        if (mounted) {
          setState(() {
            _userRole = 'owner';
          });
        }
        // 加载成员列表
        await _loadMembersList();
        return;
      }

      // 如果不是拥有者，加载成员列表
      final members = await _workspaceRepo.getWorkspaceMembers(_workspace.id);
      
      // 从成员列表中找到当前用户的角色
      try {
        final member = members.firstWhere(
          (m) => m.userId == currentUser.id,
        );
        if (mounted) {
          setState(() {
            _userRole = member.role;
            _members = _sortMembersByRole(members);
            _memberCount = members.length;
          });
        }
      } catch (e) {
        // 如果不是成员，只设置成员列表和数量
        if (mounted) {
          setState(() {
            _members = _sortMembersByRole(members);
            _memberCount = members.length;
          });
        }
      }
    } catch (e) {
      print('获取workspace角色和成员信息失败: $e');
    }
  }

  /// 加载成员列表（用于拥有者）
  Future<void> _loadMembersList() async {
    if (_workspace.storageType != 'server') return;
    
    try {
      final members = await _workspaceRepo.getWorkspaceMembers(_workspace.id);
      if (mounted) {
        setState(() {
          _members = _sortMembersByRole(members);
          _memberCount = members.length;
        });
      }
    } catch (e) {
      print('获取成员列表失败: $e');
    }
  }

  /// 显示角色权限说明对话框
  void _showRolePermissionsHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('成员权限说明'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '云端 Workspace 支持以下四种角色：',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 16),
              _buildPermissionsTable(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 构建权限说明表格
  Widget _buildPermissionsTable() {
    // 权限列表
    final permissions = [
      {'name': '查看数据', 'key': 'read'},
      {'name': '创建数据', 'key': 'create'},
      {'name': '编辑数据', 'key': 'update'},
      {'name': '删除数据', 'key': 'delete'},
      {'name': '管理成员', 'key': 'manage_members'},
      {'name': '管理设置', 'key': 'manage_settings'},
    ];

    // 角色列表
    final roles = [
      {'name': '拥有者', 'key': 'owner', 'color': Colors.purple},
      {'name': '管理员', 'key': 'admin', 'color': Colors.red},
      {'name': '编辑者', 'key': 'editor', 'color': Colors.blue},
      {'name': '查看者', 'key': 'viewer', 'color': Colors.grey},
    ];

    // 权限矩阵
    final permissionMatrix = {
      'owner': {'read': true, 'create': true, 'update': true, 'delete': true, 'manage_members': true, 'manage_settings': true},
      'admin': {'read': true, 'create': true, 'update': true, 'delete': true, 'manage_members': true, 'manage_settings': false},
      'editor': {'read': true, 'create': true, 'update': true, 'delete': false, 'manage_members': false, 'manage_settings': false},
      'viewer': {'read': true, 'create': false, 'update': false, 'delete': false, 'manage_members': false, 'manage_settings': false},
    };

    return Table(
      border: TableBorder.all(color: Colors.grey[300]!, width: 1),
      columnWidths: {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1.5),
        4: FlexColumnWidth(1.5),
      },
      children: [
        // 表头
        TableRow(
          decoration: BoxDecoration(
            color: Colors.grey[200],
          ),
          children: [
            _buildTableCell('权限', isHeader: true),
            ...roles.map((role) => _buildTableCell(
                  role['name'] as String,
                  isHeader: true,
                  color: role['color'] as Color,
                )),
          ],
        ),
        // 数据行
        ...permissions.map((permission) => TableRow(
              children: [
                _buildTableCell(permission['name'] as String, isHeader: false),
                ...roles.map((role) {
                  final hasPermission = permissionMatrix[role['key']]![permission['key']] ?? false;
                  return _buildTableCell(
                    hasPermission ? '✅' : '❌',
                    isHeader: false,
                    center: true,
                  );
                }),
              ],
            )),
      ],
    );
  }

  /// 构建表格单元格
  Widget _buildTableCell(String text, {bool isHeader = false, Color? color, bool center = false}) {
    return Container(
      padding: EdgeInsets.all(12),
      child: center
          ? Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: isHeader ? 13 : 14,
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                  color: color ?? (isHeader ? Colors.black87 : Colors.black87),
                ),
              ),
            )
          : Text(
              text,
              style: TextStyle(
                fontSize: isHeader ? 13 : 14,
                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                color: color ?? (isHeader ? Colors.black87 : Colors.black87),
              ),
            ),
    );
  }

  /// 按权限顺序排序成员（owner -> admin -> editor -> viewer）
  List<WorkspaceMember> _sortMembersByRole(List<WorkspaceMember> members) {
    final roleOrder = {'owner': 0, 'admin': 1, 'editor': 2, 'viewer': 3};
    members.sort((a, b) {
      final orderA = roleOrder[a.role] ?? 999;
      final orderB = roleOrder[b.role] ?? 999;
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      // 如果角色相同，按用户名排序
      return a.username.compareTo(b.username);
    });
    return members;
  }

  /// 加载workspace详情
  Future<void> _loadWorkspace() async {
    try {
      final workspace = await _workspaceRepo.getWorkspace(_workspace.id);
      if (mounted) {
        setState(() {
          _workspace = workspace;
        });
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载 Workspace 详情失败: ${e is ApiError ? e.message : e.toString()}');
      }
    }
  }

  /// 编辑workspace
  Future<void> _editWorkspace() async {
    final nameController = TextEditingController(text: _workspace.name);
    final descriptionController = TextEditingController(text: _workspace.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑 Workspace'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '名称 *',
                  hintText: '请输入 Workspace 名称',
                ),
                autofocus: true,
              ),
              SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: '描述',
                  hintText: '请输入 Workspace 描述（可选）',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              TextButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) {
                    context.showErrorSnackBar('请输入 Workspace 名称');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: Text('保存'),
              ),
              Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final updatedWorkspace = await _workspaceRepo.updateWorkspace(
          _workspace.id,
          WorkspaceUpdate(
            name: nameController.text.trim(),
            description: descriptionController.text.trim().isEmpty 
                ? null 
                : descriptionController.text.trim(),
          ),
        );
        
        if (mounted) {
          setState(() {
            _workspace = updatedWorkspace;
          });
          context.showSuccessSnackBar('更新 Workspace 成功');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新 Workspace 失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
  }

  /// 删除workspace（需要密码验证）
  Future<void> _deleteWorkspace() async {
    // 检查是否是拥有者
    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) {
        context.showErrorSnackBar('请先登录');
        return;
      }

      // 检查是否是拥有者（本地和服务器workspace都需要）
      if (_workspace.ownerId != currentUser.id) {
        context.showErrorSnackBar('只有 Workspace 拥有者可以删除');
        return;
      }

      // 显示密码输入对话框
      final passwordController = TextEditingController();
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('删除 Workspace'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('确定要删除 Workspace "${_workspace.name}" 吗？此操作不可恢复，所有数据将被删除。'),
                SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: '请输入密码以确认删除',
                    hintText: '请输入您的账户密码',
                  ),
                  obscureText: true,
                  autofocus: true,
                ),
              ],
            ),
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: () {
                    if (passwordController.text.trim().isEmpty) {
                      context.showErrorSnackBar('请输入密码');
                      return;
                    }
                    Navigator.pop(context, {
                      'password': passwordController.text.trim(),
                    });
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text('删除'),
                ),
                Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('取消'),
                ),
              ],
            ),
          ],
        ),
      );

      if (result != null && result['password'] != null) {
        try {
          // 验证密码（通过调用change-password API来验证密码，或者创建一个专门的验证密码API）
          // 这里我们直接调用deleteWorkspace，服务器端会验证密码
          await _workspaceRepo.deleteWorkspace(_workspace.id, password: result['password'] as String);
          
          // 如果删除的是当前选中的workspace，清除workspace ID
          final currentWorkspaceId = await _apiService.getWorkspaceId();
          if (currentWorkspaceId == _workspace.id) {
            await _apiService.clearWorkspaceId();
          }
          
          if (mounted) {
            context.showSuccessSnackBar('删除 Workspace 成功');
            Navigator.pop(context, true);
          }
        } catch (e) {
          if (mounted) {
            context.showErrorSnackBar('删除 Workspace 失败: ${e is ApiError ? e.message : e.toString()}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('删除 Workspace 失败: ${e.toString()}');
      }
    }
  }

  /// 选择workspace
  Future<void> _selectWorkspace() async {
    try {
      await _apiService.setWorkspaceId(_workspace.id);
      if (mounted) {
        context.showSuccessSnackBar('已切换到 Workspace: ${_workspace.name}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      context.showErrorSnackBar('切换 Workspace 失败: ${e.toString()}');
    }
  }

  /// 检查当前用户是否是拥有者
  Future<bool> _isOwner() async {
    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) return false;
      
      // 检查是否是拥有者（适用于本地和服务器workspace）
      return _workspace.ownerId == currentUser.id;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: _apiService.getWorkspaceId(),
      builder: (context, snapshot) {
        final currentWorkspaceId = snapshot.data;
        final isCurrentWorkspace = currentWorkspaceId == _workspace.id;

        return FutureBuilder<bool>(
          future: _isOwner(),
          builder: (context, ownerSnapshot) {
            final isOwner = ownerSnapshot.data ?? false;

            return Scaffold(
              appBar: AppBar(
                title: Text(
                  'Workspace 详情',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                actions: [
                  // 只有拥有者才显示编辑按钮
                  if (isOwner)
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: _editWorkspace,
                      tooltip: '编辑',
                    ),
                  // 只有拥有者才显示删除按钮
                  if (isOwner)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteWorkspace();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text('删除', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Workspace信息卡片
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _getWorkspaceIcon(_workspace),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _workspace.name,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        // 右上角标签：角色权限标签（仅服务器workspace）+ 存储类型标签
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 角色权限标签（仅服务器workspace显示）
                                            if (_workspace.storageType == 'server' && _userRole != null) ...[
                                              _buildRoleBadge(_userRole!),
                                              SizedBox(width: 6),
                                            ],
                                            _buildStorageTypeBadge(_workspace.storageType),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    // 只有服务器 workspace 且已共享时才显示"共享"标签
                                    if (_workspace.storageType == 'server' && _workspace.isShared)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: ShapeDecoration(
                                          color: Colors.grey[300],
                                          shape: StadiumBorder(),
                                        ),
                                        child: Text(
                                          '共享',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_workspace.description != null && _workspace.description!.isNotEmpty) ...[
                            SizedBox(height: 12),
                            Divider(),
                            SizedBox(height: 12),
                            Text(_workspace.description!),
                          ],
                          if (_workspace.createdAt != null) ...[
                            SizedBox(height: 12),
                            Divider(),
                            SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '创建时间: ${_formatDateTime(_workspace.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                // 右下角：成员数标签（仅服务器workspace显示）
                                if (_workspace.storageType == 'server' && _memberCount > 0)
                                  _buildMemberCountBadge(_memberCount),
                              ],
                            ),
                          ] else if (_workspace.storageType == 'server' && _memberCount > 0) ...[
                            SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _buildMemberCountBadge(_memberCount),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // 操作按钮
                  if (!isCurrentWorkspace)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _selectWorkspace,
                        icon: Icon(Icons.check_circle),
                        label: Text('切换到该 Workspace'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  
                  SizedBox(height: 16),
                  
                  // 成员信息块（仅服务器 workspace 显示）
                  if (_workspace.storageType == 'server')
                    _buildMembersInfoCard(),
                ],
              ),
            ),
            );
          },
        );
      },
    );
  }
}

