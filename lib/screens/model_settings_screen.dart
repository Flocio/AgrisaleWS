// lib/screens/model_settings_screen.dart

import 'package:flutter/material.dart';
import '../repositories/settings_repository.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class ModelSettingsScreen extends StatefulWidget {
  @override
  _ModelSettingsScreenState createState() => _ModelSettingsScreenState();
}

class _ModelSettingsScreenState extends State<ModelSettingsScreen> {
  final SettingsRepository _settingsRepo = SettingsRepository();
  
  // DeepSeek 模型参数
  double _temperature = 0.7;
  int _maxTokens = 2000;
  String _selectedModel = 'deepseek-chat';
  String _apiKey = '';
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  bool _isLoading = true; // 添加加载状态
  
  final List<String> _availableModels = [
    'deepseek-chat',
    'deepseek-coder',
    'deepseek-lite'
  ];

  @override
  void initState() {
    super.initState();
    _loadModelSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadModelSettings() async {
    setState(() {
      _isLoading = true; // 开始加载
    });
    
    try {
      final settings = await _settingsRepo.getUserSettings();
      setState(() {
        _temperature = settings.deepseekTemperature;
        _maxTokens = settings.deepseekMaxTokens;
        _selectedModel = settings.deepseekModel;
        _apiKey = settings.deepseekApiKey ?? '';
        _apiKeyController.text = _apiKey;
        _isLoading = false; // 加载完成
      });
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false; // 即使失败也要停止加载状态
      });
      if (mounted) {
        context.showErrorSnackBar('加载设置失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false; // 即使失败也要停止加载状态
      });
      if (mounted) {
        context.showErrorSnackBar('加载设置失败: ${e.toString()}');
      }
    }
  }

  Future<bool> _saveSettings() async {
    try {
      await _settingsRepo.updateUserSettings(
        UserSettingsUpdate(
          deepseekApiKey: _apiKeyController.text.trim().isEmpty 
              ? null 
              : _apiKeyController.text.trim(),
          deepseekModel: _selectedModel,
          deepseekTemperature: _temperature,
          deepseekMaxTokens: _maxTokens,
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
      await _loadModelSettings();
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
      await _loadModelSettings();
    }
  }

  void _resetModelSettings() {
    setState(() {
      _temperature = 0.7;
      _maxTokens = 2000;
      _selectedModel = 'deepseek-chat';
      _apiKey = '';
      _apiKeyController.clear();
    });
    
    // 重置后自动保存
    _autoSaveSettings();
    
    context.showSnackBar('已重置为默认设置');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('模型设置', 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DeepSeek 模型设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      icon: Icon(Icons.refresh, size: 18),
                      label: Text('恢复默认'),
                      onPressed: _resetModelSettings,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                Divider(),
                
                // API Key 输入
                ListTile(
                  title: Text('API Key'),
                  subtitle: Text('请输入您的DeepSeek API密钥'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      hintText: '请输入API Key',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureApiKey
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureApiKey = !_obscureApiKey;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscureApiKey,
                    onChanged: (value) {
                      setState(() {
                        _apiKey = value;
                      });
                      // API Key修改时自动保存
                      _autoSaveSettings();
                    },
                  ),
                ),
                SizedBox(height: 16),
                
                // 模型选择
                ListTile(
                  title: Text('模型'),
                  subtitle: Text('选择使用的DeepSeek模型'),
                  trailing: DropdownButton<String>(
                    value: _selectedModel,
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedModel = newValue;
                        });
                        // 模型选择变更时自动保存
                        _autoSaveSettings();
                      }
                    },
                    items: _availableModels.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
                
                // 温度滑块
                ListTile(
                  title: Text('温度 (Temperature)'),
                  subtitle: Text('控制回答的创造性和随机性，值越高回答越多样'),
                  trailing: Text(_temperature.toStringAsFixed(1)),
                ),
                Slider(
                  value: _temperature,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: _temperature.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _temperature = value;
                    });
                    // 温度调整时自动保存
                    _autoSaveSettings();
                  },
                ),
                
                // 最大令牌数
                ListTile(
                  title: Text('最大输出长度'),
                  subtitle: Text('控制回答的最大长度，值越大回答越详细'),
                  trailing: Text('$_maxTokens'),
                ),
                Slider(
                  value: _maxTokens.toDouble(),
                  min: 500,
                  max: 4000,
                  divisions: 7,
                  label: _maxTokens.toString(),
                  onChanged: (value) {
                    setState(() {
                      _maxTokens = value.toInt();
                    });
                    // 最大令牌数调整时自动保存
                    _autoSaveSettings();
                  },
                ),
                
                // 参数说明
                Container(
                  margin: EdgeInsets.only(top: 16),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '参数说明:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '温度: 较低的值 (0.2) 使回答更加确定和精确，较高的值 (0.8) 使回答更有创意和多样化。',
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '最大输出长度: 控制AI回答的最大长度。增加这个值可以获得更详细的回答，但会消耗更多API资源。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

