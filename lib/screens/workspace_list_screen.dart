/// Workspace 列表/选择界面
/// 显示用户的所有workspace，允许选择、创建、管理

import 'package:flutter/material.dart';
import '../models/workspace.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_service.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';
import 'workspace_detail_screen.dart';

class WorkspaceListScreen extends StatefulWidget {
  final bool isSelectionMode; // 是否为选择模式（登录后选择workspace）

  const WorkspaceListScreen({
    Key? key,
    this.isSelectionMode = false,
  }) : super(key: key);

  @override
  _WorkspaceListScreenState createState() => _WorkspaceListScreenState();
}

class _WorkspaceListScreenState extends State<WorkspaceListScreen> {
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final ApiService _apiService = ApiService();
  List<Workspace> _workspaces = [];
  bool _isLoading = true;
  int? _currentWorkspaceId;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
    _loadCurrentWorkspace();
  }

  /// 加载当前选中的workspace
  Future<void> _loadCurrentWorkspace() async {
    final workspaceId = await _apiService.getWorkspaceId();
    if (mounted) {
      setState(() {
        _currentWorkspaceId = workspaceId;
      });
    }
  }

  /// 加载workspace列表
  Future<void> _loadWorkspaces() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final workspaces = await _workspaceRepo.getWorkspaces();
      if (mounted) {
        setState(() {
          _workspaces = workspaces;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        context.showErrorSnackBar('加载 Workspace 列表失败: ${e is ApiError ? e.message : e.toString()}');
      }
    }
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

  /// 选择workspace
  Future<void> _selectWorkspace(Workspace workspace) async {
    try {
      await _apiService.setWorkspaceId(workspace.id);
      if (mounted) {
        setState(() {
          _currentWorkspaceId = workspace.id;
        });
        
        if (widget.isSelectionMode) {
          // 如果是选择模式，选择后返回主界面
          Navigator.pushReplacementNamed(context, '/main');
        } else {
          context.showSuccessSnackBar('已切换到 Workspace: ${workspace.name}');
        }
      }
    } catch (e) {
      context.showErrorSnackBar('切换 Workspace 失败: ${e.toString()}');
    }
  }

  /// 创建新workspace
  Future<void> _createWorkspace() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final storageType = 'server'; // 默认服务器存储

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
              if (nameController.text.trim().isEmpty) {
                context.showErrorSnackBar('请输入 Workspace 名称');
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text('创建'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final workspace = await _workspaceRepo.createWorkspace(
          WorkspaceCreate(
            name: nameController.text.trim(),
            description: descriptionController.text.trim().isEmpty 
                ? null 
                : descriptionController.text.trim(),
            storageType: storageType,
          ),
        );
        
        await _loadWorkspaces();
        
        if (mounted) {
          context.showSuccessSnackBar('创建 Workspace 成功');
          // 自动选择新创建的workspace
          await _selectWorkspace(workspace);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('创建 Workspace 失败: ${e is ApiError ? e.message : e.toString()}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSelectionMode ? '选择 Workspace' : 'Workspace 管理',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          if (!widget.isSelectionMode)
            IconButton(
              icon: Icon(Icons.add),
              onPressed: _createWorkspace,
              tooltip: '创建 Workspace',
            ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadWorkspaces,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _workspaces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        '还没有 Workspace',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '点击右上角的 + 按钮创建一个',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _workspaces.length,
                  itemBuilder: (context, index) {
                    final workspace = _workspaces[index];
                    final isSelected = _currentWorkspaceId == workspace.id;
                    
                    return Card(
                      margin: EdgeInsets.only(bottom: 12),
                      elevation: isSelected ? 6 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isSelected 
                            ? BorderSide(
                                color: Theme.of(context).primaryColor,
                                width: 2,
                              )
                            : BorderSide.none,
                      ),
                      child: InkWell(
                        onTap: widget.isSelectionMode
                            ? () => _selectWorkspace(workspace)
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => WorkspaceDetailScreen(workspace: workspace),
                                  ),
                                ).then((_) => _loadWorkspaces());
                              },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
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
                                              color: isSelected 
                                                  ? Theme.of(context).primaryColor 
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        // 右上角标签：当前标签在左边，存储类型标签在右边
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isSelected) ...[
                                              _buildCurrentBadge(),
                                              SizedBox(width: 6),
                                            ],
                                            _buildStorageTypeBadge(workspace.storageType),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (workspace.description != null && workspace.description!.isNotEmpty) ...[
                                      SizedBox(height: 4),
                                      Text(
                                        workspace.description!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    SizedBox(height: 4),
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
                              if (widget.isSelectionMode)
                                (isSelected
                                    ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor, size: 24)
                                    : Icon(Icons.arrow_forward, color: Colors.grey))
                              else
                                IconButton(
                                  icon: Icon(Icons.arrow_forward_ios, size: 16),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => WorkspaceDetailScreen(workspace: workspace),
                                      ),
                                    ).then((_) => _loadWorkspaces());
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

