// lib/screens/model_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  
  final List<String> _availableModels = [
    'deepseek-chat',
    'deepseek-coder',
    'deepseek-lite'
  ];

  @override
  void initState() {
    super.initState();
    _loadModelSettings(); // 从本地加载，不需要加载状态
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadModelSettings() async {
    // 从本地存储读取模型设置，不需要加载转圈圈
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _temperature = prefs.getDouble('deepseek_temperature') ?? 0.7;
      _maxTokens = prefs.getInt('deepseek_max_tokens') ?? 2000;
      _selectedModel = prefs.getString('deepseek_model') ?? 'deepseek-chat';
      _apiKey = prefs.getString('deepseek_api_key') ?? '';
      _apiKeyController.text = _apiKey;
    });
  }

  Future<bool> _saveSettings() async {
    // 先保存到本地存储（立即生效）
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('deepseek_temperature', _temperature);
    await prefs.setInt('deepseek_max_tokens', _maxTokens);
    await prefs.setString('deepseek_model', _selectedModel);
    if (_apiKeyController.text.trim().isEmpty) {
      await prefs.remove('deepseek_api_key');
    } else {
      await prefs.setString('deepseek_api_key', _apiKeyController.text.trim());
    }
    
    // 然后异步同步到服务器（不阻塞UI）
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
      // 服务器保存失败不影响本地使用，只记录错误
      print('同步设置到服务器失败: ${e.message}');
      return true; // 本地已保存，返回成功
    } catch (e) {
      // 服务器保存失败不影响本地使用，只记录错误
      print('同步设置到服务器失败: ${e.toString()}');
      return true; // 本地已保存，返回成功
    }
  }

  // 自动保存设置（不显示成功提示，失败时显示错误提示）
  Future<void> _autoSaveSettings() async {
    await _saveSettings(); // 本地保存总是成功，不需要检查
  }

  // 手动保存设置（显示成功提示）
  Future<void> _manualSaveSettings() async {
    await _saveSettings();
    context.showSnackBar('设置已保存');
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
    
    if (mounted) {
      context.showSnackBar('已重置为默认设置');
    }
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
      body: SingleChildScrollView(
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

