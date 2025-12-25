/// Workspace 数据管理界面
/// 仅针对当前 workspace 的数据进行导入和导出

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'dart:io';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/workspace_repository.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../models/workspace.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';
import '../database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../services/local_audit_log_service.dart';
import '../models/audit_log.dart';

class WorkspaceDataManagementScreen extends StatefulWidget {
  @override
  _WorkspaceDataManagementScreenState createState() => _WorkspaceDataManagementScreenState();
}

class _WorkspaceDataManagementScreenState extends State<WorkspaceDataManagementScreen> {
  final ProductRepository _productRepo = ProductRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  
  String? _userRole;
  Workspace? _currentWorkspace;
  bool _isLoadingRole = true;

  // 导出当前 workspace 的数据
  Future<void> _exportWorkspaceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        context.showSnackBar('请先登录');
        return;
      }

      // 检查是否选择了 workspace
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        context.showSnackBar('请先选择 Workspace');
        return;
      }

      // 获取当前 workspace 信息
      final workspace = await _apiService.getCurrentWorkspace();
      if (workspace == null) {
        context.showSnackBar('无法获取 Workspace 信息');
        return;
      }

      final workspaceName = workspace['name'] as String;

      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在导出数据...'),
            ],
          ),
        ),
      );

      // 验证用户登录状态
      final userInfo = await _authService.getCurrentUser();
      if (userInfo == null) {
        Navigator.of(context).pop(); // 关闭加载对话框
        context.showSnackBar('请先登录');
        return;
      }

      // 从 API 获取当前 workspace 的所有数据
      final results = await Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 10000),
        _supplierRepo.getAllSuppliers(),
        _customerRepo.getAllCustomers(),
        _employeeRepo.getAllEmployees(),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
        _remittanceRepo.getRemittances(page: 1, pageSize: 10000),
      ]);
      
      // 转换为 Map 格式
      final products = (results[0] as PaginatedResponse).items.map((p) => p.toJson()).toList();
      final suppliers = (results[1] as List).map((s) => s.toJson()).toList();
      final customers = (results[2] as List).map((c) => c.toJson()).toList();
      final employees = (results[3] as List).map((e) => e.toJson()).toList();
      final purchases = (results[4] as PaginatedResponse).items.map((p) => p.toJson()).toList();
      final sales = (results[5] as PaginatedResponse).items.map((s) => s.toJson()).toList();
      final returns = (results[6] as PaginatedResponse).items.map((r) => r.toJson()).toList();
      final income = (results[7] as PaginatedResponse).items.map((i) => i.toJson()).toList();
      final remittance = (results[8] as PaginatedResponse).items.map((r) => r.toJson()).toList();
      
      // 构建导出数据
      final exportData = {
        'exportInfo': {
          'username': username,
          'workspaceName': workspaceName,
          'workspaceId': workspaceId,
          'exportTime': DateTime.now().toIso8601String(),
          'version': (await PackageInfo.fromPlatform()).version,
        },
        'data': {
          'products': products,
          'suppliers': suppliers,
          'customers': customers,
          'employees': employees,
          'purchases': purchases,
          'sales': sales,
          'returns': returns,
          'income': income,
          'remittance': remittance,
        }
      };

      // 转换为JSON
      final jsonString = jsonEncode(exportData);
      
      // 生成文件名：{账户名}_{workspace名}数据_{时间戳}.json
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final fileName = '${username}_${workspaceName}数据_$timestamp.json';
          
      Navigator.of(context).pop(); // 关闭加载对话框
          
      // 使用统一的导出服务
      await ExportService.showJSONExportOptions(
        context: context,
        jsonData: jsonString,
        fileName: fileName,
      );

    } catch (e) {
      Navigator.of(context).pop(); // 关闭加载对话框
      context.showSnackBar('导出失败: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  /// 加载当前用户在workspace中的角色
  Future<void> _loadUserRole() async {
    setState(() {
      _isLoadingRole = true;
    });

    try {
      // 检查是否选择了 workspace
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        if (mounted) {
          setState(() {
            _isLoadingRole = false;
          });
        }
        return;
      }

      // 获取workspace信息
      _currentWorkspace = await _workspaceRepo.getWorkspace(workspaceId);
      
      // 对于服务器workspace，检查用户角色
      if (_currentWorkspace?.storageType == 'server') {
        final currentUser = await _authService.getCurrentUser();
        if (currentUser == null) {
          if (mounted) {
            setState(() {
              _isLoadingRole = false;
            });
          }
          return;
        }

        // 检查是否是拥有者
        if (_currentWorkspace!.ownerId == currentUser.id) {
          if (mounted) {
            setState(() {
              _userRole = 'owner';
              _isLoadingRole = false;
            });
          }
          return;
        }

        // 获取成员列表并找到当前用户的角色
        try {
          final members = await _workspaceRepo.getWorkspaceMembers(workspaceId);
          final member = members.firstWhere(
            (m) => m.userId == currentUser.id,
            orElse: () => throw Exception('Not found'),
          );
          if (mounted) {
            setState(() {
              _userRole = member.role;
              _isLoadingRole = false;
            });
          }
        } catch (e) {
          // 如果不是成员，没有权限
          if (mounted) {
            setState(() {
              _userRole = null;
              _isLoadingRole = false;
            });
          }
        }
      } else {
        // 本地workspace，拥有者就是创建者
        final currentUser = await _authService.getCurrentUser();
        if (currentUser != null && _currentWorkspace!.ownerId == currentUser.id) {
          if (mounted) {
            setState(() {
              _userRole = 'owner';
              _isLoadingRole = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoadingRole = false;
            });
          }
        }
      }
    } catch (e) {
      print('加载用户角色失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingRole = false;
        });
      }
    }
  }

  /// 检查是否有导入权限（只有拥有者和管理员可以导入）
  bool _canImportData() {
    if (_currentWorkspace == null) return false;
    
    // 本地workspace，只有拥有者可以导入
    if (_currentWorkspace!.storageType == 'local') {
      return _userRole == 'owner';
    }
    
    // 服务器workspace，拥有者和管理员可以导入
    return _userRole == 'owner' || _userRole == 'admin';
  }

  // 数据恢复功能（仅覆盖模式）
  Future<void> _importWorkspaceData() async {
    // 检查权限
    if (!_canImportData()) {
      context.showErrorSnackBar('只有 Workspace 拥有者和管理员可以导入数据（覆盖）');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        context.showSnackBar('请先登录');
        return;
      }

      // 检查是否选择了 workspace
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        context.showSnackBar('请先选择 Workspace');
        return;
      }

      // 选择文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        
        // 解析JSON数据
        final Map<String, dynamic> importData = jsonDecode(jsonString);
        
        // 验证数据格式
        if (!importData.containsKey('exportInfo') || !importData.containsKey('data')) {
          context.showSnackBar('文件格式错误，请选择正确的备份文件');
          return;
        }

        // 检查数据来源
        final backupUsername = importData['exportInfo']['username'] ?? '未知';
        final backupWorkspaceName = importData['exportInfo']['workspaceName'] ?? '未知';
        final backupWorkspaceId = importData['exportInfo']['workspaceId'];
        final backupVersion = importData['exportInfo']['version'] ?? '未知';
        final backupTime = importData['exportInfo']['exportTime'] ?? '未知';
        final isFromDifferentUser = backupUsername != username;
        final isFromDifferentWorkspace = backupWorkspaceId != workspaceId;
        
        // 检查数据量
        final data = importData['data'] as Map<String, dynamic>;
        final backupSupplierCount = (data['suppliers'] as List?)?.length ?? 0;
        final backupCustomerCount = (data['customers'] as List?)?.length ?? 0;
        final backupProductCount = (data['products'] as List?)?.length ?? 0;
        final backupEmployeeCount = (data['employees'] as List?)?.length ?? 0;
        final backupPurchaseCount = (data['purchases'] as List?)?.length ?? 0;
        final backupSaleCount = (data['sales'] as List?)?.length ?? 0;
        final backupReturnCount = (data['returns'] as List?)?.length ?? 0;
        final backupIncomeCount = (data['income'] as List?)?.length ?? 0;
        final backupRemittanceCount = (data['remittance'] as List?)?.length ?? 0;

        // 显示确认对话框
        final confirmResult = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('确认导入数据'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFromDifferentUser)
                    Container(
                      padding: EdgeInsets.all(8),
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange[800], size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '警告：备份文件来自其他用户（$backupUsername）',
                              style: TextStyle(color: Colors.orange[800], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isFromDifferentWorkspace)
                    Container(
                      padding: EdgeInsets.all(8),
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange[800], size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '警告：备份文件来自其他 Workspace（$backupWorkspaceName）',
                              style: TextStyle(color: Colors.orange[800], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    '备份信息：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('用户：$backupUsername'),
                  Text('Workspace：$backupWorkspaceName'),
                  Text('备份时间：$backupTime'),
                  Text('版本：$backupVersion'),
                  SizedBox(height: 16),
                  Text(
                    '数据统计：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('产品：$backupProductCount'),
                  Text('供应商：$backupSupplierCount'),
                  Text('客户：$backupCustomerCount'),
                  Text('员工：$backupEmployeeCount'),
                  Text('采购：$backupPurchaseCount'),
                  Text('销售：$backupSaleCount'),
                  Text('退货：$backupReturnCount'),
                  Text('进账：$backupIncomeCount'),
                  Text('汇款：$backupRemittanceCount'),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.red[800], size: 20),
                            SizedBox(width: 8),
                            Text(
                              '警告',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red[800],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '导入数据将完全替换当前 Workspace 的所有业务数据，此操作不可恢复！',
                          style: TextStyle(color: Colors.red[800], fontSize: 12),
                        ),
                      ],
                    ),
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
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text('确认导入'),
              ),
            ],
          ),
        );

        if (confirmResult == true) {
          // 显示加载对话框
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('正在导入数据...'),
                ],
              ),
            ),
          );

          try {
            // 导入数据（覆盖模式）
            if (_currentWorkspace!.storageType == 'server') {
              // 服务器workspace：调用API导入
              final result = await _workspaceRepo.importWorkspaceData(workspaceId, importData);
              
              Navigator.of(context).pop(); // 关闭加载对话框
              
              final counts = result['counts'] as Map<String, dynamic>?;
              final countsText = counts != null
                  ? '供应商: ${counts['suppliers']}, 客户: ${counts['customers']}, 员工: ${counts['employees']}, 产品: ${counts['products']}, 采购: ${counts['purchases']}, 销售: ${counts['sales']}, 退货: ${counts['returns']}, 进账: ${counts['income']}, 汇款: ${counts['remittance']}'
                  : '';
              
              context.showSuccessSnackBar('数据导入成功！\n$countsText');
            } else {
              // 本地workspace：直接操作本地数据库
              await _importDataToLocal(workspaceId, data);
              
              Navigator.of(context).pop(); // 关闭加载对话框
              context.showSuccessSnackBar('数据导入成功');
            }
          } catch (e) {
            Navigator.of(context).pop(); // 关闭加载对话框
            if (e is ApiError) {
              context.showErrorSnackBar('导入失败: ${e.message}');
            } else {
              context.showSnackBar('导入失败: $e');
            }
          }
        }
      }
    } catch (e) {
      context.showSnackBar('导入失败: $e');
    }
  }

  /// 导入数据到本地workspace
  Future<void> _importDataToLocal(int workspaceId, Map<String, dynamic> data) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final username = await _authService.getCurrentUsername();
    
    if (username == null) {
      throw ApiError(message: '未登录');
    }
    
    final userId = await dbHelper.getCurrentUserId(username);
    if (userId == null) {
      throw ApiError(message: '用户不存在');
    }
    
    // 在事务中执行导入
    await db.transaction((txn) async {
      // 0. 在删除前，先获取当前数据作为 oldData（用于日志对比）
      final oldData = <String, dynamic>{
        'workspaceId': workspaceId,
        'import_counts': <String, int>{},
      };
      
      // 统计当前各表的数据量
      final tables = ['suppliers', 'customers', 'employees', 'products', 
                     'purchases', 'sales', 'returns', 'income', 'remittance'];
      for (final table in tables) {
        final result = await txn.rawQuery(
          'SELECT COUNT(*) as count FROM $table WHERE workspaceId = ?',
          [workspaceId]
        );
        final count = result.first['count'] as int? ?? 0;
        oldData['import_counts'][table] = count;
      }
      
      final oldTotalCount = (oldData['import_counts'] as Map<String, int>)
          .values
          .fold<int>(0, (sum, count) => sum + count);
      oldData['total_count'] = oldTotalCount;
      
      // 1. 删除该workspace的所有业务数据
      await txn.delete('remittance', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('income', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('returns', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('sales', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('purchases', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('products', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('employees', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('customers', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('suppliers', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      
      // 2. 创建ID映射表（旧ID -> 新ID）
      final supplierIdMap = <int, int>{};
      final customerIdMap = <int, int>{};
      final employeeIdMap = <int, int>{};
      final productIdMap = <int, int>{};
      
      // 3. 导入suppliers
      final suppliers = (data['suppliers'] as List?) ?? [];
      for (final supplierData in suppliers) {
        final originalId = supplierData['id'] as int?;
        final newId = await txn.insert('suppliers', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': supplierData['name'] as String? ?? '',
          'note': supplierData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          supplierIdMap[originalId] = newId;
        }
      }
      
      // 4. 导入customers
      final customers = (data['customers'] as List?) ?? [];
      for (final customerData in customers) {
        final originalId = customerData['id'] as int?;
        final newId = await txn.insert('customers', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': customerData['name'] as String? ?? '',
          'note': customerData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          customerIdMap[originalId] = newId;
        }
      }
      
      // 5. 导入employees
      final employees = (data['employees'] as List?) ?? [];
      for (final employeeData in employees) {
        final originalId = employeeData['id'] as int?;
        final newId = await txn.insert('employees', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': employeeData['name'] as String? ?? '',
          'note': employeeData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          employeeIdMap[originalId] = newId;
        }
      }
      
      // 6. 导入products
      final products = (data['products'] as List?) ?? [];
      for (final productData in products) {
        final originalId = productData['id'] as int?;
        // 处理supplierId映射
        int? supplierId = productData['supplierId'] as int?;
        if (supplierId != null && supplierIdMap.containsKey(supplierId)) {
          supplierId = supplierIdMap[supplierId];
        } else if (supplierId != null && !supplierIdMap.containsKey(supplierId)) {
          supplierId = null; // 如果映射不存在，设为null
        }
        
        // 处理unit
        String unit = productData['unit'] as String? ?? '公斤';
        if (unit != '斤' && unit != '公斤' && unit != '袋') {
          unit = '公斤';
        }
        
        final newId = await txn.insert('products', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': productData['name'] as String? ?? '',
          'description': productData['description'] as String?,
          'stock': (productData['stock'] as num?)?.toDouble() ?? 0.0,
          'unit': unit,
          'supplierId': supplierId,
          'version': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          productIdMap[originalId] = newId;
        }
      }
      
      // 7. 导入purchases
      final purchases = (data['purchases'] as List?) ?? [];
      for (final purchaseData in purchases) {
        int? supplierId = purchaseData['supplierId'] as int?;
        if (supplierId == 0) {
          supplierId = null;
        } else if (supplierId != null && supplierIdMap.containsKey(supplierId)) {
          supplierId = supplierIdMap[supplierId];
        } else if (supplierId != null && !supplierIdMap.containsKey(supplierId)) {
          supplierId = null;
        }
        
        await txn.insert('purchases', {
          'userId': userId,
          'workspaceId': workspaceId,
          'productName': purchaseData['productName'] as String? ?? '',
          'quantity': (purchaseData['quantity'] as num?)?.toDouble() ?? 0.0,
          'purchaseDate': purchaseData['purchaseDate'] as String?,
          'supplierId': supplierId,
          'totalPurchasePrice': (purchaseData['totalPurchasePrice'] as num?)?.toDouble(),
          'note': purchaseData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 8. 导入sales
      final sales = (data['sales'] as List?) ?? [];
      for (final saleData in sales) {
        int? customerId = saleData['customerId'] as int?;
        if (customerId != null && customerIdMap.containsKey(customerId)) {
          customerId = customerIdMap[customerId];
        } else if (customerId != null && !customerIdMap.containsKey(customerId)) {
          customerId = null;
        }
        
        await txn.insert('sales', {
          'userId': userId,
          'workspaceId': workspaceId,
          'productName': saleData['productName'] as String? ?? '',
          'quantity': (saleData['quantity'] as num?)?.toDouble() ?? 0.0,
          'saleDate': saleData['saleDate'] as String?,
          'customerId': customerId,
          'totalSalePrice': (saleData['totalSalePrice'] as num?)?.toDouble(),
          'note': saleData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 9. 导入returns
      final returns = (data['returns'] as List?) ?? [];
      for (final returnData in returns) {
        int? customerId = returnData['customerId'] as int?;
        if (customerId != null && customerIdMap.containsKey(customerId)) {
          customerId = customerIdMap[customerId];
        } else if (customerId != null && !customerIdMap.containsKey(customerId)) {
          customerId = null;
        }
        
        await txn.insert('returns', {
          'userId': userId,
          'workspaceId': workspaceId,
          'productName': returnData['productName'] as String? ?? '',
          'quantity': (returnData['quantity'] as num?)?.toDouble() ?? 0.0,
          'returnDate': returnData['returnDate'] as String?,
          'customerId': customerId,
          'totalReturnPrice': (returnData['totalReturnPrice'] as num?)?.toDouble(),
          'note': returnData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 10. 导入income
      final income = (data['income'] as List?) ?? [];
      for (final incomeData in income) {
        int? customerId = incomeData['customerId'] as int?;
        if (customerId != null && customerIdMap.containsKey(customerId)) {
          customerId = customerIdMap[customerId];
        } else if (customerId != null && !customerIdMap.containsKey(customerId)) {
          customerId = null;
        }
        
        int? employeeId = incomeData['employeeId'] as int?;
        if (employeeId != null && employeeIdMap.containsKey(employeeId)) {
          employeeId = employeeIdMap[employeeId];
        } else if (employeeId != null && !employeeIdMap.containsKey(employeeId)) {
          employeeId = null;
        }
        
        String paymentMethod = incomeData['paymentMethod'] as String? ?? '现金';
        if (paymentMethod != '现金' && paymentMethod != '银行卡' && paymentMethod != '微信转账' && paymentMethod != '支付宝') {
          paymentMethod = '现金';
        }
        
        await txn.insert('income', {
          'userId': userId,
          'workspaceId': workspaceId,
          'incomeDate': incomeData['incomeDate'] as String?,
          'customerId': customerId,
          'amount': (incomeData['amount'] as num?)?.toDouble() ?? 0.0,
          'discount': (incomeData['discount'] as num?)?.toDouble() ?? 0.0,
          'employeeId': employeeId,
          'paymentMethod': paymentMethod,
          'note': incomeData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 11. 导入remittance
      final remittance = (data['remittance'] as List?) ?? [];
      for (final remittanceData in remittance) {
        int? supplierId = remittanceData['supplierId'] as int?;
        if (supplierId != null && supplierIdMap.containsKey(supplierId)) {
          supplierId = supplierIdMap[supplierId];
        } else if (supplierId != null && !supplierIdMap.containsKey(supplierId)) {
          supplierId = null;
        }
        
        int? employeeId = remittanceData['employeeId'] as int?;
        if (employeeId != null && employeeIdMap.containsKey(employeeId)) {
          employeeId = employeeIdMap[employeeId];
        } else if (employeeId != null && !employeeIdMap.containsKey(employeeId)) {
          employeeId = null;
        }
        
        String paymentMethod = remittanceData['paymentMethod'] as String? ?? '现金';
        if (paymentMethod != '现金' && paymentMethod != '银行卡' && paymentMethod != '微信转账' && paymentMethod != '支付宝') {
          paymentMethod = '现金';
        }
        
        await txn.insert('remittance', {
          'userId': userId,
          'workspaceId': workspaceId,
          'remittanceDate': remittanceData['remittanceDate'] as String?,
          'supplierId': supplierId,
          'amount': (remittanceData['amount'] as num?)?.toDouble() ?? 0.0,
          'employeeId': employeeId,
          'paymentMethod': paymentMethod,
          'note': remittanceData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 统计导入的数据量
      final supplierCount = suppliers.length;
      final customerCount = customers.length;
      final employeeCount = employees.length;
      final productCount = products.length;
      final purchaseCount = purchases.length;
      final saleCount = sales.length;
      final returnCount = returns.length;
      final incomeCount = income.length;
      final remittanceCount = remittance.length;
      final totalCount = supplierCount + customerCount + employeeCount + productCount + 
                        purchaseCount + saleCount + returnCount + incomeCount + remittanceCount;
      
      // 记录操作日志（在事务内）
      try {
        await LocalAuditLogService().logOperation(
          operationType: OperationType.cover,
          entityType: EntityType.workspace_data,
          entityId: workspaceId,
          entityName: '数据导入',
          oldData: oldData,
          newData: {
            'workspaceId': workspaceId,
            'import_counts': {
              'suppliers': supplierCount,
              'customers': customerCount,
              'employees': employeeCount,
              'products': productCount,
              'purchases': purchaseCount,
              'sales': saleCount,
              'returns': returnCount,
              'income': incomeCount,
              'remittance': remittanceCount,
            },
            'total_count': totalCount,
          },
          note: '导入数据（覆盖）：供应商 $supplierCount，客户 $customerCount，员工 $employeeCount，产品 $productCount，采购 $purchaseCount，销售 $saleCount，退货 $returnCount，进账 $incomeCount，汇款 $remittanceCount，总计 $totalCount 条',
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录数据导入日志失败: $e');
        // 日志记录失败不影响业务
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '数据管理',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoadingRole
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.0),
              children: [
                // 数据管理卡片
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '数据管理',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '仅针对当前 Workspace 的数据进行导入和导出',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Divider(),
                        ListTile(
                          leading: Icon(Icons.download, color: Colors.green),
                          title: Text('导出 Workspace 数据'),
                          subtitle: Text('将当前 Workspace 的所有数据导出为JSON备份文件'),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _exportWorkspaceData,
                        ),
                        Divider(),
                        ListTile(
                          leading: Icon(
                            Icons.upload, 
                            color: _canImportData() ? Colors.orange : Colors.grey[400],
                          ),
                          title: Text(
                            '导入数据（覆盖）',
                            style: TextStyle(
                              color: _canImportData() ? Colors.black : Colors.grey[600],
                            ),
                          ),
                          subtitle: Text(
                            _canImportData() 
                                ? '从备份文件恢复数据，将完全替换当前 Workspace 的业务数据'
                                : '只有 Workspace 拥有者和管理员可以导入数据（覆盖）',
                            style: TextStyle(
                              color: _canImportData() ? Colors.black : Colors.red[600],
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios, 
                            size: 16,
                            color: _canImportData() ? Colors.grey : Colors.grey[400],
                          ),
                          enabled: _canImportData(),
                          onTap: _canImportData() ? _importWorkspaceData : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}


