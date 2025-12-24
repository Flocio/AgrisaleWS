import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 导入剪贴板功能
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/product_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/auth_service.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';

class DataAssistantScreen extends StatefulWidget {
  @override
  _DataAssistantScreenState createState() => _DataAssistantScreenState();
}

class _DataAssistantScreenState extends State<DataAssistantScreen> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _chatHistory = [];
  
  // Repository 实例
  final ProductRepository _productRepo = ProductRepository();
  final SaleRepository _saleRepo = SaleRepository();
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final SettingsRepository _settingsRepo = SettingsRepository();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }
  
  // 加载对话历史
  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        _addSystemMessage("欢迎使用数据分析助手！您可以询问关于系统中的产品、销售、采购、库存等数据的问题。");
        return;
      }
      
      final chatHistoryKey = 'chat_history_$username';
      final chatHistoryJson = prefs.getString(chatHistoryKey);
      
      if (chatHistoryJson != null && chatHistoryJson.isNotEmpty) {
        final List<dynamic> historyList = jsonDecode(chatHistoryJson);
        setState(() {
          _chatHistory = historyList.map((item) => Map<String, dynamic>.from(item)).toList();
        });
        
        // 滚动到底部
        Future.delayed(Duration(milliseconds: 300), () {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      } else {
        // 如果没有历史记录，添加欢迎消息
        _addSystemMessage("欢迎使用数据分析助手！您可以询问关于系统中的产品、销售、采购、库存等数据的问题。");
      }
    } catch (e) {
      print('加载对话历史失败: $e');
    _addSystemMessage("欢迎使用数据分析助手！您可以询问关于系统中的产品、销售、采购、库存等数据的问题。");
    }
  }
  
  // 保存对话历史
  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) return;
      
      final chatHistoryKey = 'chat_history_$username';
      final chatHistoryJson = jsonEncode(_chatHistory);
      await prefs.setString(chatHistoryKey, chatHistoryJson);
    } catch (e) {
      print('保存对话历史失败: $e');
    }
  }
  
  // 清空对话历史
  Future<void> _clearChatHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认清空'),
        content: Text('确定要清空所有对话记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('确认', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('current_username');
        
        if (username != null) {
          final chatHistoryKey = 'chat_history_$username';
          await prefs.remove(chatHistoryKey);
        }
        
        setState(() {
          _chatHistory = [];
        });
        
        _addSystemMessage("欢迎使用数据分析助手！您可以询问关于系统中的产品、销售、采购、库存等数据的问题。");
        
        if (mounted) {
          context.showSuccessSnackBar('对话记录已清空');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('清空失败: $e');
        }
      }
    }
  }

  void _addSystemMessage(String message) {
    setState(() {
      _chatHistory.add({
        'role': 'system',
        'content': message,
      });
    });
  }

  void _addUserMessage(String message) {
    setState(() {
      _chatHistory.add({
        'role': 'user',
        'content': message,
      });
    });
    _saveChatHistory(); // 自动保存
  }

  void _addAssistantMessage(String message) {
    setState(() {
      _chatHistory.add({
        'role': 'assistant',
        'content': message,
      });
      _isLoading = false;
    });
    _saveChatHistory(); // 自动保存
    
    // 滚动到底部
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 更新最后一条助手消息的内容（用于流式输出）
  void _updateLastAssistantMessage(String content) {
    setState(() {
      if (_chatHistory.isNotEmpty && 
          _chatHistory.last['role'] == 'assistant') {
        _chatHistory.last['content'] = content;
      }
    });
    
    // 自动滚动到底部
    Future.delayed(Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // 开始流式助手消息（创建空消息用于后续更新）
  void _startAssistantMessage() {
    setState(() {
      _chatHistory.add({
        'role': 'assistant',
        'content': '',
      });
      _isLoading = true;
    });
  }

  // 复制文本到剪贴板
  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
    context.showSuccessSnackBar('文本已复制到剪贴板');
    }
  }

  Future<Map<String, dynamic>> _fetchSystemData() async {
    try {
      // 获取当前用户信息
      final userInfo = await _authService.getCurrentUser();
      if (userInfo == null) {
        return {'error': '用户未登录'};
      }
      
      final username = userInfo.username;
      
      // 并行获取所有数据（使用较大的 pageSize 获取所有数据）
      final results = await Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 10000),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
        _employeeRepo.getAllEmployees(),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
        _remittanceRepo.getRemittances(page: 1, pageSize: 10000),
      ]);
      
      // 将对象列表转换为 Map 列表
      final products = (results[0] as PaginatedResponse<Product>).items.map((p) => p.toJson()).toList();
      final sales = (results[1] as PaginatedResponse<Sale>).items.map((s) => s.toJson()).toList();
      final purchases = (results[2] as PaginatedResponse<Purchase>).items.map((p) => p.toJson()).toList();
      final returns = (results[3] as PaginatedResponse<Return>).items.map((r) => r.toJson()).toList();
      final customers = (results[4] as List<Customer>).map((c) => c.toJson()).toList();
      final suppliers = (results[5] as List<Supplier>).map((s) => s.toJson()).toList();
      final employees = (results[6] as List<Employee>).map((e) => e.toJson()).toList();
      final income = (results[7] as PaginatedResponse<Income>).items.map((i) => i.toJson()).toList();
      final remittance = (results[8] as PaginatedResponse<Remittance>).items.map((r) => r.toJson()).toList();
      
      // 获取用户数据（出于安全考虑，不包含密码）
      final safeUsers = [{
        'id': userInfo.id,
        'username': userInfo.username,
      }];
      
      // 数据库结构信息
      final dbStructure = {
      'tables': [
        {
          'name': 'users',
          'columns': ['id', 'username', 'password'],
          'description': '系统用户表，存储登录凭证'
        },
        {
          'name': 'products',
          'columns': ['id', 'userId', 'name', 'description', 'stock', 'unit', 'supplierId'],
          'description': '产品表，存储农资产品信息。stock为REAL类型支持小数。单位可以是斤、公斤或袋。supplierId为外键关联到suppliers表，表示产品的供应商。每个用户有独立的产品数据'
        },
        {
          'name': 'suppliers',
          'columns': ['id', 'userId', 'name', 'note'],
          'description': '供应商表，存储产品供应商信息，每个用户有独立的供应商数据'
        },
        {
          'name': 'customers',
          'columns': ['id', 'userId', 'name', 'note'],
          'description': '客户表，存储客户信息，每个用户有独立的客户数据'
        },
        {
          'name': 'employees',
          'columns': ['id', 'userId', 'name', 'note'],
          'description': '员工表，存储员工信息，用于记录收款和汇款的经手人，每个用户有独立的员工数据'
        },
        {
          'name': 'purchases',
          'columns': ['id', 'userId', 'productName', 'quantity', 'purchaseDate', 'supplierId', 'totalPurchasePrice', 'note'],
          'description': '采购记录表，记录产品进货信息。quantity为REAL类型支持小数，可为负数表示采购退货。totalPurchasePrice为总进价。每个用户有独立的采购记录'
        },
        {
          'name': 'sales',
          'columns': ['id', 'userId', 'productName', 'quantity', 'customerId', 'saleDate', 'totalSalePrice', 'note'],
          'description': '销售记录表，记录产品销售信息。quantity为REAL类型支持小数。totalSalePrice为总售价。每个用户有独立的销售记录'
        },
        {
          'name': 'returns',
          'columns': ['id', 'userId', 'productName', 'quantity', 'customerId', 'returnDate', 'totalReturnPrice', 'note'],
          'description': '退货记录表，记录客户退货信息。quantity为REAL类型支持小数。totalReturnPrice为总退货金额。每个用户有独立的退货记录'
        },
        {
          'name': 'income',
          'columns': ['id', 'userId', 'incomeDate', 'customerId', 'amount', 'discount', 'employeeId', 'paymentMethod', 'note'],
          'description': '进账记录表，记录客户付款信息。amount为REAL类型表示收款金额，discount为优惠金额（默认0）。employeeId关联到employees表表示经手人。paymentMethod可为现金、微信转账或银行卡。每个用户有独立的进账记录'
        },
        {
          'name': 'remittance',
          'columns': ['id', 'userId', 'remittanceDate', 'supplierId', 'amount', 'employeeId', 'paymentMethod', 'note'],
          'description': '汇款记录表，记录向供应商付款信息。amount为REAL类型表示汇款金额。employeeId关联到employees表表示经手人。paymentMethod可为现金、微信转账或银行卡。每个用户有独立的汇款记录'
        }
      ]
    };
    
      // 构建系统数据摘要
      return {
        'databaseStructure': dbStructure,
        'products': products,
        'sales': sales,
        'purchases': purchases,
        'returns': returns,
        'customers': customers,
        'suppliers': suppliers,
        'employees': employees,
        'income': income,
        'remittance': remittance,
        'users': safeUsers,
        'currentUser': username,
      };
    } on ApiError catch (e) {
      return {'error': '获取数据失败: ${e.message}'};
    } catch (e) {
      return {'error': '获取数据失败: ${e.toString()}'};
    }
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    
    _addUserMessage(question);
    _questionController.clear();
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 获取用户的模型设置，包括API Key
      final userInfo = await _authService.getCurrentUser();
      
      if (userInfo == null) {
        _addAssistantMessage('请先登录系统。');
        return;
      }
      
      final settings = await _settingsRepo.getUserSettings();
      final apiKey = settings.deepseekApiKey ?? '';
      final temperature = settings.deepseekTemperature;
      final maxTokens = settings.deepseekMaxTokens;
      final model = settings.deepseekModel;
      
      // 验证API Key是否存在
      if (apiKey.isEmpty) {
        _addAssistantMessage('请先在设置中配置您的DeepSeek API Key。');
        return;
      }
      
      // 获取系统数据
      final systemData = await _fetchSystemData();
      final systemDataJson = jsonEncode(systemData);
      
      // 构建提示词
      final messages = [
        {
          'role': 'system',
          'content': '''
你是AgrisaleWS的数据分析助手。你可以分析系统中的产品、销售、采购、库存、员工、进账、汇款等数据，并回答用户的问题。

系统包含以下数据表：
1. users - 系统用户表
2. products - 产品表（包含名称、描述、库存（REAL类型支持小数）、单位、供应商ID）
3. suppliers - 供应商表
4. customers - 客户表
5. employees - 员工表（记录收款和汇款的经手人）
6. purchases - 采购记录表（quantity支持小数和负数，负数表示采购退货）
7. sales - 销售记录表（quantity支持小数）
8. returns - 退货记录表（客户退货，quantity支持小数）
9. income - 进账记录表（客户付款，包含优惠金额discount）
10. remittance - 汇款记录表（向供应商付款）

关键业务逻辑：
- 产品的stock、采购/销售/退货的quantity、金额amount都是REAL类型，支持小数
- 采购的quantity可为负数，表示采购退货（退货给供应商）
- 产品表中的supplierId关联到供应商，表示该产品来自哪个供应商
- income表记录客户的付款，可包含优惠discount
- remittance表记录向供应商的汇款
- employees表记录经手人，与income和remittance关联

请根据用户提问，分析相关数据并提供专业、准确的回答。请以中文回复用户的所有问题，确保回复是有意义且可读的中文文本。

系统数据和结构：
$systemDataJson
'''
        }
      ];
      
      // 添加聊天历史
      for (final message in _chatHistory) {
        if (message['role'] != 'system') {
          messages.add({
            'role': message['role'],
            'content': message['content'],
          });
        }
      }
      
      // 开始流式消息
      _startAssistantMessage();
      
      // 使用流式请求
      try {
        final client = HttpClient();
        final request = await client.postUrl(
          Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        );
        
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.headers.set('Authorization', 'Bearer $apiKey');
        
        final requestBody = jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': true, // 启用流式输出
          'response_format': {'type': 'text'}, // 确保响应为纯文本
        });
        
        request.write(requestBody);
        final response = await request.close().timeout(
          Duration(seconds: 60), // 流式请求需要更长的超时时间
          onTimeout: () {
            client.close();
            throw Exception('请求超时：DeepSeek API响应时间过长，请稍后重试');
          },
        );
        
        if (response.statusCode == 200) {
          String accumulatedContent = '';
          String buffer = ''; // 用于处理跨行的数据块
          
          // 处理流式响应
          await for (final data in response.transform(utf8.decoder)) {
            buffer += data;
            final lines = buffer.split('\n');
            
            // 保留最后一个不完整的行（如果有）
            buffer = lines.last;
            
            // 处理完整的行
            for (int i = 0; i < lines.length - 1; i++) {
              final line = lines[i].trim();
              
              if (line.startsWith('data: ')) {
                final jsonStr = line.substring(6); // 移除 'data: ' 前缀
                
                if (jsonStr.trim() == '[DONE]') {
                  // 流式输出完成
                  setState(() {
                    _isLoading = false;
                  });
                  _saveChatHistory();
                  break;
                }
                
                if (jsonStr.trim().isEmpty) {
                  continue; // 跳过空数据
                }
                
                try {
                  final chunk = jsonDecode(jsonStr);
                  final delta = chunk['choices']?[0]?['delta'];
                  
                  if (delta != null && delta['content'] != null) {
                    accumulatedContent += delta['content'];
                    _updateLastAssistantMessage(accumulatedContent);
                  }
                } catch (e) {
                  // 忽略解析错误，继续处理下一个数据块
                  print('解析流式数据块失败: $e, jsonStr: $jsonStr');
                }
              }
            }
          }
          
          // 确保最终保存
          if (accumulatedContent.isNotEmpty) {
            setState(() {
              _isLoading = false;
            });
            _saveChatHistory();
          } else {
            // 如果没有收到任何内容，移除空消息
            setState(() {
              _isLoading = false;
              if (_chatHistory.isNotEmpty && 
                  _chatHistory.last['role'] == 'assistant' &&
                  _chatHistory.last['content'] == '') {
                _chatHistory.removeLast();
              }
            });
            _addAssistantMessage('抱歉，没有收到任何回复内容。');
          }
        } else {
          // 读取错误响应
          final errorBody = await response.transform(utf8.decoder).join();
          setState(() {
            _isLoading = false;
            if (_chatHistory.isNotEmpty && 
                _chatHistory.last['role'] == 'assistant' &&
                _chatHistory.last['content'] == '') {
              _chatHistory.removeLast();
            }
          });
          _addAssistantMessage('抱歉，API请求失败。\n错误代码: ${response.statusCode}\n错误详情: $errorBody');
        }
        
        client.close();
      } on SocketException catch (e) {
        setState(() {
          _isLoading = false;
          if (_chatHistory.isNotEmpty && 
              _chatHistory.last['role'] == 'assistant' &&
              _chatHistory.last['content'] == '') {
            _chatHistory.removeLast();
          }
        });
        _addAssistantMessage('网络连接失败，请检查：\n'
                           '1. 网络连接是否正常\n'
                           '2. 是否使用了代理服务器\n'
                           '3. API密钥是否正确\n'
                           '4. 防火墙是否阻止了连接\n\n'
                           '详细错误: $e');
      } on TimeoutException catch (e) {
        setState(() {
          _isLoading = false;
          if (_chatHistory.isNotEmpty && 
              _chatHistory.last['role'] == 'assistant' &&
              _chatHistory.last['content'] == '') {
            _chatHistory.removeLast();
          }
        });
        _addAssistantMessage('请求超时，请稍后重试。\n详细错误: $e');
      } catch (e) {
        setState(() {
          _isLoading = false;
          if (_chatHistory.isNotEmpty && 
              _chatHistory.last['role'] == 'assistant' &&
              _chatHistory.last['content'] == '') {
            _chatHistory.removeLast();
          }
        });
        _addAssistantMessage('抱歉，发生了错误: $e');
      }
    } catch (e) {
      String errorMessage = '抱歉，发生了错误: ';
      
      // 根据错误类型提供更具体的错误信息
      if (e.toString().contains('Connection failed') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage += '网络连接失败，请检查：\n'
                       '1. 网络连接是否正常\n'
                       '2. 是否使用了代理服务器\n'
                       '3. API密钥是否正确\n'
                       '4. 防火墙是否阻止了连接\n\n'
                       '详细错误: $e';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage += '请求超时，请稍后重试。\n详细错误: $e';
      } else if (e.toString().contains('FormatException')) {
        errorMessage += 'API响应格式错误。\n详细错误: $e';
      } else {
        errorMessage += '$e';
             }
       
       _addAssistantMessage(errorMessage);
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '数据分析助手',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
            tooltip: '清空对话',
            onPressed: _clearChatHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(16),
                itemCount: _chatHistory.length,
                itemBuilder: (context, index) {
                  final message = _chatHistory[index];
                  final isUser = message['role'] == 'user';
                  final isSystem = message['role'] == 'system';
                  final isAssistant = message['role'] == 'assistant';
                  
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      onLongPress: () {
                        _copyToClipboard(message['content']);
                      },
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 8),
                        padding: EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isUser 
                              ? Colors.green[100] 
                              : isSystem 
                                  ? Colors.blue[50] 
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // 对 assistant 消息使用 Markdown 渲染，其他使用普通文本
                            isAssistant
                                ? MarkdownBody(
                                    data: message['content'],
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black87,
                                        height: 1.5,
                                      ),
                                      h1: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      h2: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      h3: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      code: TextStyle(
                                        fontSize: 14,
                                        fontFamily: 'monospace',
                                        backgroundColor: Colors.grey[200],
                                      ),
                                      codeblockDecoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      listBullet: TextStyle(
                                        color: Colors.black87,
                                      ),
                                      strong: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      em: TextStyle(
                                        fontStyle: FontStyle.italic,
                                      ),
                                      blockquote: TextStyle(
                                        color: Colors.grey[700],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    selectable: true,
                                  )
                                : SelectableText(
                              message['content'],
                              style: TextStyle(
                                fontSize: 16,
                                      color: isUser 
                                          ? Colors.green[900] 
                                          : isSystem 
                                              ? Colors.blue[900] 
                                              : Colors.black87,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: () => _copyToClipboard(message['content']),
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.copy,
                                    size: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('正在分析数据...'),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 3,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      hintText: '请输入您的问题...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => _sendQuestion(),
                  ),
                ),
                SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendQuestion,
                  mini: true,
                  backgroundColor: Colors.green,
                  child: Icon(Icons.send),
                ),
              ],
            ),
          ),
          FooterWidget(),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
} 