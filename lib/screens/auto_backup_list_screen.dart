import 'package:flutter/material.dart';
import '../services/auto_backup_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/footer_widget.dart';
import '../utils/snackbar_helper.dart';

class AutoBackupListScreen extends StatefulWidget {
  @override
  _AutoBackupListScreenState createState() => _AutoBackupListScreenState();
}

class _AutoBackupListScreenState extends State<AutoBackupListScreen> {
  List<Map<String, dynamic>> _backupList = [];
  bool _isLoading = true;
  final _backupService = AutoBackupService();

  @override
  void initState() {
    super.initState();
    _loadBackupList();
  }

  Future<void> _loadBackupList() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final apiService = ApiService();
      final workspaceId = await apiService.getWorkspaceId();
      if (workspaceId == null) {
        setState(() {
          _backupList = [];
          _isLoading = false;
        });
        return;
      }

      final workspace = await apiService.getCurrentWorkspace();
      if (workspace == null) {
        setState(() {
          _backupList = [];
          _isLoading = false;
        });
        return;
      }

      final workspaceName = workspace['name'] as String;
      final allBackups = await _backupService.getBackupList();
      
      // 过滤出当前workspace的备份（文件名包含workspace名称）
      final workspaceBackups = allBackups.where((backup) {
        final fileName = backup['fileName'] as String;
        return fileName.contains('_${workspaceName}_');
      }).toList();
      
      setState(() {
        _backupList = workspaceBackups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      context.showSnackBar('加载备份列表失败: $e');
    }
  }

  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除这个备份吗？\n\n${backup['fileName']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _backupService.deleteBackup(backup['path']);
      if (success) {
        context.showSnackBar('删除成功');
        _loadBackupList();
      } else {
        context.showSnackBar('删除失败');
      }
    }
  }

  Future<void> _deleteAllBackups() async {
    if (_backupList.isEmpty) {
      context.showSnackBar('没有备份可删除');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除全部', style: TextStyle(color: Colors.red[700])),
        content: Text('确定要删除所有 ${_backupList.length} 个备份吗？\n\n此操作不可撤销！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('全部删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在删除...'),
            ],
          ),
        ),
      );

      final deletedCount = await _backupService.deleteAllBackups();
      Navigator.of(context).pop(); // 关闭加载对话框

      context.showSnackBar('已删除 $deletedCount 个备份');
      _loadBackupList();
    }
  }

  Future<void> _restoreBackup(Map<String, dynamic> backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认恢复', style: TextStyle(color: Colors.orange[700])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要恢复到这个备份吗？'),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('备份时间: ${_formatDateTime(backup['modifiedTime'])}', style: TextStyle(fontSize: 12)),
                  Text('文件大小: ${_formatFileSize(backup['size'])}', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Text(
                '⚠️ 当前数据将被覆盖，此操作不可撤销！',
                style: TextStyle(fontSize: 12, color: Colors.red[900]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('确认恢复'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在恢复数据...'),
            ],
          ),
        ),
      );

      try {
        final authService = AuthService();
        final userInfo = await authService.getCurrentUser();
        
        if (userInfo == null) {
          Navigator.of(context).pop();
          context.showSnackBar('未登录');
          return;
        }

        // 通过服务器 API 恢复备份（不再需要本地 userId）
        final success = await _backupService.restoreBackup(backup['path']);
        Navigator.of(context).pop(); // 关闭加载对话框

        if (success) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('恢复成功'),
              content: Text('数据已恢复！建议重启应用以确保数据完全加载。'),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(); // 返回设置页面
                  },
                  child: Text('确定'),
                ),
              ],
            ),
          );
        } else {
          context.showSnackBar('恢复失败');
        }
      } catch (e) {
        Navigator.of(context).pop();
        context.showSnackBar('恢复失败: $e');
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} 分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} 小时前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  String _getTimeCategory(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0 && dateTime.day == now.day) {
      return '今天';
    } else if (difference.inDays == 1 || (difference.inDays == 0 && dateTime.day == now.day - 1)) {
      return '昨天';
    } else if (difference.inDays < 7) {
      return '本周';
    } else if (difference.inDays < 30) {
      return '本月';
    } else {
      return '更早';
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupBackupsByTime() {
    Map<String, List<Map<String, dynamic>>> grouped = {
      '今天': [],
      '昨天': [],
      '本周': [],
      '本月': [],
      '更早': [],
    };

    for (var backup in _backupList) {
      final category = _getTimeCategory(backup['modifiedTime']);
      grouped[category]!.add(backup);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '自动备份列表',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_backupList.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep),
              tooltip: '全部删除',
              onPressed: _deleteAllBackups,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _backupList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.backup, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              '暂无备份',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '开启自动备份后将在这里显示',
                              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadBackupList,
                        child: ListView(
                          padding: EdgeInsets.all(16),
                          children: _buildGroupedBackupList(),
                        ),
                      ),
          ),
          FooterWidget(),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedBackupList() {
    final grouped = _groupBackupsByTime();
    List<Widget> widgets = [];

    for (var category in ['今天', '昨天', '本周', '本月', '更早']) {
      final backups = grouped[category]!;
      if (backups.isEmpty) continue;

      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
            category,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
              ),
              Text(
                '共 ${backups.length} 个备份',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );

      for (var backup in backups) {
        widgets.add(_buildBackupCard(backup));
        widgets.add(SizedBox(height: 8));
      }
    }

    return widgets;
  }

  Widget _buildBackupCard(Map<String, dynamic> backup) {
    final DateTime dateTime = backup['modifiedTime'];
    final String timestamp = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, size: 20, color: Colors.blue[600]),
                SizedBox(width: 8),
                Text(
                  _formatDateTime(backup['modifiedTime']),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            // 显示完整时间戳
            Padding(
              padding: EdgeInsets.only(left: 28),
              child: Text(
                timestamp,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.storage, size: 16, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text(
                  '大小: ${_formatFileSize(backup['size'])}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _deleteBackup(backup),
                  icon: Icon(Icons.delete, size: 18, color: Colors.red),
                  label: Text('删除', style: TextStyle(color: Colors.red)),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _restoreBackup(backup),
                  icon: Icon(Icons.restore, size: 18),
                  label: Text('恢复'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

