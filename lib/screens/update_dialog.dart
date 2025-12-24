import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import '../utils/snackbar_helper.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  
  const UpdateDialog({Key? key, required this.updateInfo}) : super(key: key);
  
  @override
  _UpdateDialogState createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadPath; // 保存下载路径
  
  Future<void> _downloadUpdate() async {
    if (widget.updateInfo.downloadUrl == null) {
      setState(() {
        _errorMessage = '无法获取下载链接\n\n请点击"前往 GitHub 下载"按钮手动下载更新';
      });
      return;
    }
    
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });
    
    try {
      await UpdateService.downloadAndInstall(
        widget.updateInfo.downloadUrl!,
        (received, total, downloadPath) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
              _downloadPath = downloadPath;
            });
          }
        },
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        
        // 显示下载路径提示
        if (_downloadPath != null) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.download, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('下载完成'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '文件已下载到：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      _downloadPath!,
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('知道了'),
                ),
              ],
          ),
        );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = '更新失败，请手动从 GitHub 下载';
        });
      }
    }
  }
  
  Future<void> _openGitHubReleases() async {
    final url = widget.updateInfo.githubReleasesUrl ?? 
                'https://github.com/Flocio/AgrisaleWS/releases/latest';
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          context.showWarningSnackBar('无法打开链接，请手动访问: $url');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('打开链接失败: $e');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text('发现新版本 ${widget.updateInfo.version}'),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Text(
                        _errorMessage!,
                style: TextStyle(color: Colors.red[700], fontSize: 14),
              ),
              SizedBox(height: 16),
            ],
            if (_isDownloading) ...[
              Text('正在下载更新...', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              LinearProgressIndicator(
                value: _totalBytes > 0 ? _downloadedBytes / _totalBytes : null,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (_totalBytes > 0)
                    Text(
                      '${(_totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
              if (_totalBytes > 0) ...[
                SizedBox(height: 4),
                Text(
                  '${((_downloadedBytes / _totalBytes) * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_downloadPath != null) ...[
                SizedBox(height: 12),
              Container(
                  padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                ),
                  child: Row(
                  children: [
                      Icon(Icons.folder, size: 16, color: Colors.grey[600]),
                        SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '下载路径: $_downloadPath',
                          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ),
                  ],
                ),
              ),
              ],
            ] else ...[
              if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
              Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                constraints: BoxConstraints(maxHeight: 200),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.updateInfo.releaseNotes.isEmpty 
                        ? '暂无更新说明' 
                        : widget.updateInfo.releaseNotes,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('稍后'),
          ),
          // 如果没有下载链接或下载失败，显示 GitHub 链接按钮
          if (widget.updateInfo.downloadUrl == null || _errorMessage != null)
            ElevatedButton.icon(
              onPressed: _openGitHubReleases,
              icon: Icon(Icons.open_in_browser, size: 18),
              label: Text('前往Github'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          // 如果有下载链接且没有错误，显示更新按钮
          if (widget.updateInfo.downloadUrl != null && _errorMessage == null)
            ElevatedButton(
              onPressed: _downloadUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('立即更新'),
            ),
        ],
      ],
    );
  }
  
}
