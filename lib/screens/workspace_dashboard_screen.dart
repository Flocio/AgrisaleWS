/// Workspace 管理仪表盘
/// 登录后的主界面，用于管理所有workspace

import 'package:flutter/material.dart';
import '../models/workspace.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';
import 'workspace_detail_screen.dart';
import 'workspace_list_screen.dart';
import 'main_screen.dart';

class WorkspaceDashboardScreen extends StatefulWidget {
  const WorkspaceDashboardScreen({Key? key}) : super(key: key);

  @override
  _WorkspaceDashboardScreenState createState() => _WorkspaceDashboardScreenState();
}

class _WorkspaceDashboardScreenState extends State<WorkspaceDashboardScreen> {
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<Workspace> _workspaces = [];
  List<Workspace> _filteredWorkspaces = [];
  bool _isLoading = true;
  int? _currentWorkspaceId;
  String _filterType = 'all'; // 'all', 'local', 'server'
  Map<int, String> _workspaceRoles = {}; // workspaceId -> role

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载数据
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 并行加载workspace列表、当前workspace和当前用户信息
      final results = await Future.wait([
        _loadWorkspaces(),
        _loadCurrentWorkspace(),
        _authService.getCurrentUser(),
      ]);
      
      // workspace列表加载完成后，立即设置拥有者角色（不需要API调用）
      final currentUser = results[2] as UserInfo?;
      if (currentUser != null && _workspaces.isNotEmpty) {
        _setOwnerRolesImmediately(currentUser);
      }

      // 先显示workspace列表，不等待角色信息加载
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      
      // 然后异步加载角色信息（不阻塞UI显示）
      if (currentUser != null && _workspaces.isNotEmpty) {
        _loadWorkspaceRoles(); // 不等待，后台加载
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        context.showErrorSnackBar('加载数据失败: ${e is ApiError ? e.message : e.toString()}');
      }
    }
  }

  /// 立即设置拥有者角色（不需要API调用，在workspace列表加载后立即执行）
  void _setOwnerRolesImmediately(UserInfo currentUser) {
    final roles = <int, String>{};
    final serverWorkspaces = _workspaces.where((w) => w.storageType == 'server').toList();
    
    for (final workspace in serverWorkspaces) {
      if (workspace.ownerId == currentUser.id) {
        roles[workspace.id] = 'owner';
      }
    }

    // 立即更新UI，让用户看到拥有者标签
    if (roles.isNotEmpty && mounted) {
      setState(() {
        _workspaceRoles = Map.from(roles);
      });
    }
  }

  /// 加载服务器workspace的角色信息（优化：并行加载所有角色）
  Future<void> _loadWorkspaceRoles() async {
    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser == null) return;

      final serverWorkspaces = _workspaces.where((w) => w.storageType == 'server').toList();
      if (serverWorkspaces.isEmpty) return;
      
      // 从已有的角色信息开始（可能已经包含拥有者）
      final roles = Map<int, String>.from(_workspaceRoles);

      // 并行加载所有服务器workspace的角色信息（包括拥有者和非拥有者）
      final roleFutures = serverWorkspaces.map((workspace) async {
        // 如果已经是拥有者，直接返回（不需要API调用）
        if (workspace.ownerId == currentUser.id) {
          return MapEntry(workspace.id, 'owner');
        }
        
        // 对于非拥有者，通过API获取角色
        try {
          final members = await _workspaceRepo.getWorkspaceMembers(workspace.id);
          final member = members.firstWhere(
            (m) => m.userId == currentUser.id,
            orElse: () => throw Exception('Not found'),
          );
          return MapEntry(workspace.id, member.role);
        } catch (e) {
          // 如果获取失败，可能是没有权限或不是成员，返回null
          print('获取workspace ${workspace.id}的角色失败: $e');
          return null;
        }
      }).toList();

      final roleResults = await Future.wait(roleFutures);
      for (final result in roleResults) {
        if (result != null) {
          roles[result.key] = result.value;
        }
      }

      // 更新UI（合并拥有者和其他角色）
      if (mounted) {
        setState(() {
          _workspaceRoles = roles;
        });
      }
    } catch (e) {
      print('加载workspace角色失败: $e');
    }
  }

  /// 加载当前选中的workspace
  Future<void> _loadCurrentWorkspace() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (mounted) {
        setState(() {
          _currentWorkspaceId = workspaceId;
        });
      }
    } catch (e) {
      print('加载当前workspace失败: $e');
    }
  }

  /// 加载workspace列表（不设置isLoading状态，由_loadData统一管理）
  Future<void> _loadWorkspaces() async {
    try {
      final workspaces = await _workspaceRepo.getWorkspaces();
      if (mounted) {
        setState(() {
          _workspaces = workspaces;
          _applyFilter();
        });
      }
    } catch (e) {
      // 错误会在_loadData中统一处理
      rethrow;
    }
  }

  /// 切换workspace（只切换当前workspace，不进入）
  Future<void> _switchWorkspace(Workspace workspace) async {
    try {
      await _apiService.setWorkspaceId(workspace.id);
      if (mounted) {
        setState(() {
          _currentWorkspaceId = workspace.id;
        });
        context.showSnackBar('已切换到 ${workspace.name}');
      }
    } catch (e) {
      context.showErrorSnackBar('切换 Workspace 失败: ${e.toString()}');
    }
  }

  /// 进入workspace（跳转到账本界面）
  Future<void> _enterWorkspace(Workspace workspace) async {
    try {
      await _apiService.setWorkspaceId(workspace.id);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(),
          ),
        );
      }
    } catch (e) {
      context.showErrorSnackBar('进入 Workspace 失败: ${e.toString()}');
    }
  }

  /// 创建新workspace
  Future<void> _createWorkspace() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedStorageType = 'server'; // 默认云端存储

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('创建 Workspace'),
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
                  SizedBox(height: 16),
                  Text(
                    '存储类型 *',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  RadioListTile<String>(
                    title: Text('云端'),
                    subtitle: Text('数据存储在服务器'),
                    value: 'server',
                    groupValue: selectedStorageType,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedStorageType = value!;
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: Text('本地'),
                    subtitle: Text('数据存储在本地设备'),
                    value: 'local',
                    groupValue: selectedStorageType,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedStorageType = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) {
                    context.showErrorSnackBar('请输入 Workspace 名称');
                    return;
                  }
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim().isEmpty 
                        ? null 
                        : descriptionController.text.trim(),
                    'storageType': selectedStorageType,
                  });
                },
                child: Text('创建'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      try {
        final workspace = await _workspaceRepo.createWorkspace(
          WorkspaceCreate(
            name: result['name'] as String,
            description: result['description'] as String?,
            storageType: result['storageType'] as String,
          ),
        );
        
        await _loadData();
        
        if (mounted) {
          context.showSuccessSnackBar('创建 Workspace 成功');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('创建 Workspace 失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
  }

  /// 应用筛选
  void _applyFilter() {
    setState(() {
      if (_filterType == 'all') {
        _filteredWorkspaces = _workspaces;
      } else {
        _filteredWorkspaces = _workspaces.where((w) => w.storageType == _filterType).toList();
      }
    });
  }

  /// 切换筛选类型（轮转）
  void _toggleFilter() {
    setState(() {
      // 轮转逻辑：all -> server -> local -> all
      if (_filterType == 'all') {
        _filterType = 'server';
      } else if (_filterType == 'server') {
        _filterType = 'local';
      } else {
        _filterType = 'all';
      }
    });
    _applyFilter();
  }

  /// 获取筛选标签文本
  String _getFilterLabel() {
    switch (_filterType) {
      case 'all':
        return '全部Workspace';
      case 'server':
        return '云端Workspace';
      case 'local':
        return '本地Workspace';
      default:
        return '全部Workspace';
    }
  }

  /// 获取筛选标签颜色
  Color _getFilterColor() {
    switch (_filterType) {
      case 'all':
        return Colors.green;
      case 'server':
        return Colors.orange;
      case 'local':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  /// 管理workspace（查看详情、编辑、删除等）
  Future<void> _manageWorkspace(Workspace workspace) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkspaceDetailScreen(workspace: workspace),
      ),
    );
    
    // 刷新列表
    if (result == true || result == null) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶部绿色标题栏（高度对齐 AppBar，居中 AgrisaleWS）
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

          // 标题栏下方白色区域：左侧"工作台"标题+筛选标签，右侧"创建 Workspace"按钮
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                // "工作台"标题
                Text(
                  '工作台',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                SizedBox(width: 12),
                // 筛选标签按钮（轮转式）
                InkWell(
                  onTap: _toggleFilter,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getFilterColor().withOpacity(0.1),
                      border: Border.all(
                        color: _getFilterColor(),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getFilterLabel(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _getFilterColor(),
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: _getFilterColor(),
                        ),
                      ],
                    ),
                  ),
                ),
                Spacer(),
                // "创建 Workspace"按钮（绿底白字）
                ElevatedButton.icon(
                  onPressed: _createWorkspace,
                  icon: Icon(Icons.add, size: 18, color: Colors.white),
                  label: Text('创建 Workspace', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          // 内容区域：Workspace 列表从“工作台”标题和按钮下方开始
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: _filteredWorkspaces.isEmpty
                        ? _buildEmptyState()
                        : _buildWorkspaceList(),
                  ),
          ),
        ],
      ),
      // 创建 Workspace 按钮已经移动到白色区域右上角，这里不再需要悬浮按钮
    );
  }

  /// 构建空状态（没有workspace时）
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 
                     MediaQuery.of(context).padding.top - 
                     kToolbarHeight - 
                     200, // 减去顶部标题栏和筛选区域的高度
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 120,
              color: Colors.grey[400],
            ),
            SizedBox(height: 24),
            Text(
              '还没有 Workspace',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Workspace 是您管理账本的工作空间\n可以创建多个 Workspace 来管理不同的业务',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _createWorkspace,
              icon: Icon(Icons.add),
              label: Text('创建第一个 Workspace'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  /// 构建当前标签（400米跑道形状）
  Widget _buildCurrentBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: Theme.of(context).primaryColor,
        shape: StadiumBorder(),
      ),
      child: Text(
        '当前',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
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

  /// 构建workspace列表
  Widget _buildWorkspaceList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _filteredWorkspaces.length,
      itemBuilder: (context, index) {
        final workspace = _filteredWorkspaces[index];
        final isCurrent = _currentWorkspaceId == workspace.id;
        
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: isCurrent ? 6 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCurrent 
                ? BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  )
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () => _switchWorkspace(workspace),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _getWorkspaceIcon(workspace),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    workspace.name,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isCurrent 
                                          ? Theme.of(context).primaryColor 
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                // 右上角标签：角色权限标签（仅服务器workspace）+ 存储类型标签
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 角色权限标签（仅服务器workspace显示）
                                    if (workspace.storageType == 'server' && _workspaceRoles.containsKey(workspace.id)) ...[
                                      _buildRoleBadge(_workspaceRoles[workspace.id]!),
                                      SizedBox(width: 6),
                                    ],
                                    _buildStorageTypeBadge(workspace.storageType),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            // 只有服务器 workspace 且已共享时才显示"共享"标签
                            if (workspace.storageType == 'server' && workspace.isShared)
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
                  if (workspace.description != null && workspace.description!.isNotEmpty) ...[
                    SizedBox(height: 12),
                    Text(
                      workspace.description!,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左下角："当前"标签（如果不存在则用空容器占位）
                      isCurrent 
                          ? _buildCurrentBadge()
                          : SizedBox.shrink(),
                      // 右下角：管理按钮和进入按钮
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _manageWorkspace(workspace),
                            icon: Icon(Icons.info_outline, size: 18),
                            label: Text('详情'),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _enterWorkspace(workspace),
                            icon: Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                            label: Text('进入', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCurrent 
                                  ? Theme.of(context).primaryColor 
                                  : Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

