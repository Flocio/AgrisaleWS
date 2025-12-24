/// Workspace 成员管理界面
/// 显示成员列表、邀请成员、修改角色、移除成员等

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/workspace.dart';
import '../repositories/workspace_repository.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';
import '../services/auth_service.dart';

class WorkspaceMembersScreen extends StatefulWidget {
  final Workspace workspace;

  const WorkspaceMembersScreen({
    Key? key,
    required this.workspace,
  }) : super(key: key);

  @override
  _WorkspaceMembersScreenState createState() => _WorkspaceMembersScreenState();
}

class _WorkspaceMembersScreenState extends State<WorkspaceMembersScreen> {
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final AuthService _authService = AuthService();
  List<WorkspaceMember> _members = [];
  bool _isLoading = true;
  int? _currentUserId; // 当前用户ID（用于标记"我"）

  @override
  void initState() {
    super.initState();
    _loadMembers();
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

  /// 加载成员列表
  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取当前用户ID（用于标记"我"）
      final currentUser = await _authService.getCurrentUser();
      
      final members = await _workspaceRepo.getWorkspaceMembers(widget.workspace.id);
      if (mounted) {
        setState(() {
          _members = members;
          _currentUserId = currentUser?.id;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        context.showErrorSnackBar('加载成员列表失败: ${e is ApiError ? e.message : e.toString()}');
      }
    }
  }

  /// 邀请成员
  Future<void> _inviteMember() async {
    final usernameController = TextEditingController();
    String selectedRole = 'editor';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('邀请成员'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: '用户名 *',
                    hintText: '请输入成员用户名',
                  ),
                  autofocus: true,
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: InputDecoration(
                    labelText: '角色 *',
                  ),
                  items: [
                    DropdownMenuItem(value: 'admin', child: Text('管理员')),
                    DropdownMenuItem(value: 'editor', child: Text('编辑者')),
                    DropdownMenuItem(value: 'viewer', child: Text('查看者')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value ?? 'editor';
                    });
                  },
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
                    if (usernameController.text.trim().isEmpty) {
                      context.showErrorSnackBar('请输入用户名');
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: Text('邀请'),
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
      ),
    );

    if (result == true) {
      try {
        await _workspaceRepo.inviteMember(
          widget.workspace.id,
          WorkspaceInviteRequest(
            username: usernameController.text.trim(),
            role: selectedRole,
          ),
        );
        
        await _loadMembers(); // 刷新成员列表
        
        if (mounted) {
          context.showSuccessSnackBar('成员已添加');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('添加成员失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
  }

  /// 更新成员角色
  Future<void> _updateMemberRole(WorkspaceMember member) async {
    String selectedRole = member.role;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('修改角色'),
          content: DropdownButtonFormField<String>(
            value: selectedRole,
            decoration: InputDecoration(
              labelText: '角色 *',
            ),
            items: [
              DropdownMenuItem(value: 'admin', child: Text('管理员')),
              DropdownMenuItem(value: 'editor', child: Text('编辑者')),
              DropdownMenuItem(value: 'viewer', child: Text('查看者')),
            ],
            onChanged: (value) {
              setDialogState(() {
                selectedRole = value ?? member.role;
              });
            },
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
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
      ),
    );

    if (result == true && selectedRole != member.role) {
      try {
        await _workspaceRepo.updateMemberRole(
          widget.workspace.id,
          member.userId,
          WorkspaceMemberUpdate(role: selectedRole),
        );
        
        await _loadMembers();
        
        if (mounted) {
          context.showSuccessSnackBar('角色已更新');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新角色失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
  }

  /// 移除成员
  Future<void> _removeMember(WorkspaceMember member) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除成员'),
        content: Text('确定要移除成员 "${member.username}" 吗？'),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text('移除'),
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
        await _workspaceRepo.removeMember(widget.workspace.id, member.userId);
        
        await _loadMembers();
        
        if (mounted) {
          context.showSuccessSnackBar('成员已移除');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('移除成员失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
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

  /// 获取角色颜色
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

  /// 构建角色权限标签（与workspace详情界面一致）
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '成员管理',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showRolePermissionsHelp,
            tooltip: '权限说明',
          ),
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: _inviteMember,
            tooltip: '邀请成员',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        '还没有成员',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '点击右上角的 + 按钮邀请成员',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    return Card(
                      margin: EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // 头像（使用角色颜色作为背景）
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
                                  // 用户名和角色标签（同一行）
                                  Row(
                                    children: [
                                      Text(
                                        member.username,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      // 角色标签（与workspace详情界面一致）
                                      _buildRoleBadge(member.role),
                                      // 如果是当前用户，显示"(当前用户)"标记
                                      if (_currentUserId != null && member.userId == _currentUserId) ...[
                                        SizedBox(width: 8),
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
                                  // 邀请信息和加入时间
                                  if (member.invitedByUsername != null || member.joinedAt != null) ...[
                                    SizedBox(height: 4),
                                    if (member.invitedByUsername != null)
                                      Text(
                                        '由 ${member.invitedByUsername} 邀请',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    if (member.invitedByUsername != null && member.joinedAt != null)
                                      SizedBox(height: 2),
                                    if (member.joinedAt != null)
                                      Text(
                                        '加入时间: ${_formatDateTime(member.joinedAt)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            // 操作菜单（只有非owner成员显示）
                            if (member.role != 'owner')
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _updateMemberRole(member);
                                  } else if (value == 'remove') {
                                    _removeMember(member);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text('修改角色'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_remove, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('移除', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

