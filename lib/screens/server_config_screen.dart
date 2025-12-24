import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../services/api_service.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class ServerConfigScreen extends StatefulWidget {
  @override
  _ServerConfigScreenState createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _lanUrlController = TextEditingController(); // 局域网地址控制器
  bool _isLoading = false;
  bool _isTesting = false;
  String? _testResult;
  String? _currentServerUrl;
  String? _selectedQuickConfig; // 当前选中的快速配置选项
  int? _testDuration; // 测试连接耗时（毫秒）

  @override
  void initState() {
    super.initState();
    _loadCurrentServerUrl();
    _loadLanUrl();
    // 监听输入框变化，实时更新快速配置选中状态
    _serverUrlController.addListener(() {
      final currentText = _serverUrlController.text.trim();
      String? newSelected;
      if (currentText == 'https://agrisalews.drflo.org') {
        newSelected = 'https';
      } else if (currentText == _lanUrlController.text.trim()) {
        newSelected = 'lan';
      } else {
        newSelected = null;
      }
      // 只在状态改变时更新，避免不必要的重建
      if (_selectedQuickConfig != newSelected) {
        setState(() {
          _selectedQuickConfig = newSelected;
        });
      }
    });
    // 监听局域网地址变化，实时更新说明卡片
    _lanUrlController.addListener(() {
      setState(() {
        // 触发重建以更新说明卡片中的局域网地址显示
      });
    });
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _lanUrlController.dispose();
    super.dispose();
  }
  
  // 加载局域网地址
  Future<void> _loadLanUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final lanUrl = prefs.getString('lan_url') ?? 'http://192.168.10.12:8000';
    setState(() {
      _lanUrlController.text = lanUrl;
    });
  }
  
  // 保存局域网地址
  Future<void> _saveLanUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lan_url', _lanUrlController.text.trim());
  }

  // 加载当前服务器地址
  Future<void> _loadCurrentServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url');
    // 默认使用 HTTPS 地址（内网穿透），同时支持内网和外网访问
    final defaultUrl = 'https://agrisalews.drflo.org';
    final currentUrl = serverUrl ?? defaultUrl;
    setState(() {
      _currentServerUrl = currentUrl;
      _serverUrlController.text = currentUrl;
      // 根据当前地址设置选中的快速配置
      _updateSelectedQuickConfig(currentUrl);
    });
  }
  
  // 更新选中的快速配置选项
  void _updateSelectedQuickConfig(String url) {
    final trimmedUrl = url.trim();
    if (trimmedUrl == 'https://agrisalews.drflo.org') {
      _selectedQuickConfig = 'https';
    } else if (trimmedUrl == _lanUrlController.text.trim()) {
      _selectedQuickConfig = 'lan';
    } else {
      _selectedQuickConfig = null;
    }
  }

  // 测试服务器连接
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testDuration = null;
    });

    final startTime = DateTime.now();
    
    try {
      final testUrl = _serverUrlController.text.trim();
      
      // 直接使用 HTTP 请求测试，不通过 ApiService（避免格式问题）
      final uri = Uri.parse('$testUrl/health');
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: 10));
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      
      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final status = json['status'] as String?;
      
          if (status == 'healthy') {
            setState(() {
              _testResult = '连接成功！服务器运行正常';
              _testDuration = duration;
            });
          } else {
            setState(() {
              _testResult = '连接成功，但服务器状态异常：$status';
              _testDuration = duration;
            });
          }
        } catch (e) {
          // 如果响应不是 JSON，但状态码是 200，也算成功
          setState(() {
            _testResult = '连接成功！服务器响应正常（状态码：${response.statusCode}）';
            _testDuration = duration;
          });
        }
      } else if (response.statusCode == 503) {
        setState(() {
          _testResult = '连接成功，但服务器健康检查失败（数据库可能未连接）';
          _testDuration = duration;
        });
      } else {
        setState(() {
          _testResult = '连接失败：服务器返回错误（状态码：${response.statusCode}）';
          _testDuration = duration;
        });
      }
    } on TimeoutException {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      setState(() {
        _testResult = '连接失败：请求超时，请检查服务器地址和网络连接';
        _testDuration = duration;
      });
    } on SocketException catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      setState(() {
        _testResult = '连接失败：无法连接到服务器，请检查：\n1. 服务器地址是否正确\n2. 是否与服务器在同一网络（内网）\n3. 防火墙是否阻止连接';
        _testDuration = duration;
      });
    } on FormatException catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      setState(() {
        _testResult = '连接失败：服务器地址格式不正确';
        _testDuration = duration;
      });
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      setState(() {
        _testResult = '连接失败：${e.toString()}';
        _testDuration = duration;
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  // 保存服务器地址
  Future<void> _saveServerUrl() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final serverUrl = _serverUrlController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', serverUrl);
      
      // 更新 ApiService
      ApiService().setBaseUrl(serverUrl);
      
      setState(() {
        _currentServerUrl = serverUrl;
      });

      if (mounted) {
        context.showSuccessSnackBar('服务器地址已保存');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('保存失败：${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // URL验证
  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入服务器地址';
    }
    
    final url = value.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return '地址必须以 http:// 或 https:// 开头';
    }
    
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) {
        return '请输入有效的服务器地址';
      }
    } catch (e) {
      return '地址格式不正确';
    }
    
    return null;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('服务器配置',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // 说明卡片
            Card(
              elevation: 2,
              color: Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        SizedBox(width: 8),
                        Text(
                          '配置说明',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      '• HTTPS 地址：https://agrisalews.drflo.org（内网穿透）',
                      style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• 局域网地址：192.168.x.x（同一WiFi下）',
                      style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• 智能连接：登录时会自动尝试多个地址（配置地址 → HTTPS → 局域网），直到找到可用的地址',
                      style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• 自动保存：成功连接的地址会自动保存，下次优先使用',
                      style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 24),
            
            // 当前服务器地址
            if (_currentServerUrl != null) ...[
              Text(
                '当前服务器地址',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey[200]!, style: BorderStyle.solid, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                        child: Text(
                          _currentServerUrl!,
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ),
                    ),
                    Icon(Icons.lock, size: 18, color: Colors.grey[400]),
                  ],
                ),
              ),
              SizedBox(height: 24),
            ],
            
            // 服务器地址输入
            Text(
              '修改服务器地址',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid, width: 1),
              ),
              child: TextFormField(
                controller: _serverUrlController,
                style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                decoration: InputDecoration(
                  hintText: 'https://agrisalews.drflo.org',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                ),
                keyboardType: TextInputType.url,
                validator: _validateUrl,
                enabled: !_isLoading && !_isTesting,
              ),
            ),
            
            SizedBox(height: 16),
            
            // 测试连接按钮
            ElevatedButton(
              onPressed: _isTesting ? null : _testConnection,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
              child: _isTesting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                        ),
                        SizedBox(width: 12),
                        Text('测试中...', style: TextStyle(fontSize: 16)),
                      ],
                    )
                  : Text('测试连接', style: TextStyle(fontSize: 16)),
            ),
            
            // 测试结果
            if (_testResult != null) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!.contains('成功')
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testResult!.contains('成功')
                        ? Colors.green[300]!
                        : Colors.red[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.contains('成功')
                          ? Icons.check_circle
                          : Icons.error,
                      color: _testResult!.contains('成功')
                          ? Colors.green[700]
                          : Colors.red[700],
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult! + (_testDuration != null ? ' (${(_testDuration! / 1000).toStringAsFixed(1)}s)' : ''),
                        style: TextStyle(
                          fontSize: 13,
                          color: _testResult!.contains('成功')
                              ? Colors.green[900]
                              : Colors.red[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            SizedBox(height: 24),
            
            // 保存按钮
            ElevatedButton(
              onPressed: _isLoading ? null : _saveServerUrl,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                        ),
                        SizedBox(width: 12),
                        Text('保存中...', style: TextStyle(fontSize: 16)),
                      ],
                    )
                  : Text('保存配置', style: TextStyle(fontSize: 16)),
            ),
            
            SizedBox(height: 16),
            
            // 快速配置
            Text(
              '快速配置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            
            // HTTPS 配置
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: ActionChip(
                    label: Text('HTTPS'),
                    onPressed: () {
                      setState(() {
                        _serverUrlController.text = 'https://agrisalews.drflo.org';
                        _selectedQuickConfig = 'https';
                      });
                    },
                    avatar: Icon(Icons.lock, size: 18),
                    backgroundColor: _selectedQuickConfig == 'https' 
                        ? Colors.green[100] 
                        : null,
                    labelPadding: EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!, style: BorderStyle.solid, width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                            child: Text(
                              'https://agrisalews.drflo.org',
                              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                            ),
                          ),
                        ),
                        Icon(Icons.lock, size: 18, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 12),
            
            // 局域网配置
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: ActionChip(
                    label: Text('局域网'),
                    onPressed: () {
                      setState(() {
                        _serverUrlController.text = _lanUrlController.text.trim();
                        _selectedQuickConfig = 'lan';
                      });
                    },
                    avatar: Icon(Icons.home, size: 18),
                    backgroundColor: _selectedQuickConfig == 'lan' 
                        ? Colors.green[100] 
                        : null,
                    labelPadding: EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid, width: 1),
                    ),
                    child: TextFormField(
                      controller: _lanUrlController,
                      style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                      decoration: InputDecoration(
                        hintText: 'http://192.168.10.12:8000',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                      ),
                      keyboardType: TextInputType.url,
                      validator: _validateUrl,
                      enabled: !_isLoading && !_isTesting,
                      onChanged: (value) {
                        // 当局域网地址改变时，自动保存
                        _saveLanUrl();
                      },
                    ),
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

