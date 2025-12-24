// lib/screens/remittance_screen.dart

import 'package:flutter/material.dart';
import '../widgets/footer_widget.dart';
import 'package:intl/intl.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/income_repository.dart'; // 用于 PaymentMethod
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class RemittanceScreen extends StatefulWidget {
  @override
  _RemittanceScreenState createState() => _RemittanceScreenState();
}

class _RemittanceScreenState extends State<RemittanceScreen> {
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  
  List<Remittance> _remittances = [];
  List<Supplier> _suppliers = [];
  List<Employee> _employees = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;

  // 添加搜索相关的状态变量
  List<Remittance> _filteredRemittances = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedSupplierFilter;
  String? _selectedEmployeeFilter;
  String? _selectedPaymentMethodFilter;
  DateTimeRange? _selectedDateRange;
  final ValueNotifier<List<String>> _activeFilters = ValueNotifier<List<String>>([]);
  final List<String> _paymentMethods = ['现金', '微信转账', '银行卡'];

  @override
  void initState() {
    super.initState();
    _fetchData();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterRemittances();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _activeFilters.dispose();
    super.dispose();
  }

  // 重置所有过滤条件
  void _resetFilters() {
    setState(() {
      _selectedSupplierFilter = null;
      _selectedEmployeeFilter = null;
      _selectedPaymentMethodFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredRemittances = List.from(_remittances);
      _isSearching = false;
      _showAdvancedSearch = false;
    });
  }

  // 更新搜索条件并显示活跃的过滤条件
  void _updateActiveFilters() {
    List<String> filters = [];
    
    if (_selectedSupplierFilter != null) {
      filters.add('供应商: $_selectedSupplierFilter');
    }
    
    if (_selectedEmployeeFilter != null) {
      filters.add('员工: $_selectedEmployeeFilter');
    }
    
    if (_selectedPaymentMethodFilter != null) {
      filters.add('汇款方式: $_selectedPaymentMethodFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 获取供应商名称
  String _getSupplierName(int? supplierId) {
    if (supplierId == null) return '';
    final supplier = _suppliers.firstWhere(
      (s) => s.id == supplierId,
      orElse: () => Supplier(id: -1, userId: 0, name: ''),
    );
    return supplier.name;
  }

  // 获取员工名称
  String _getEmployeeName(int? employeeId) {
    if (employeeId == null) return '';
    final employee = _employees.firstWhere(
      (e) => e.id == employeeId,
      orElse: () => Employee(id: -1, userId: 0, name: ''),
    );
    return employee.name;
  }

  // 添加过滤汇款记录的方法
  void _filterRemittances() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      // 开始筛选
      List<Remittance> result = List.from(_remittances);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((remittance) {
          final supplierName = _getSupplierName(remittance.supplierId).toLowerCase();
          final employeeName = _getEmployeeName(remittance.employeeId).toLowerCase();
          final date = remittance.remittanceDate.toLowerCase();
          final note = (remittance.note ?? '').toLowerCase();
          final amount = remittance.amount.toString().toLowerCase();
          final paymentMethod = remittance.paymentMethod.value.toLowerCase();
          
          // 检查所有搜索词是否都匹配
          return searchTerms.every((term) =>
            supplierName.contains(term) ||
            employeeName.contains(term) ||
            date.contains(term) ||
            note.contains(term) ||
            amount.contains(term) ||
            paymentMethod.contains(term)
          );
        }).toList();
      }
      
      // 供应商筛选
      if (_selectedSupplierFilter != null) {
        hasFilters = true;
        result = result.where((remittance) => 
          _getSupplierName(remittance.supplierId) == _selectedSupplierFilter).toList();
      }
      
      // 员工筛选
      if (_selectedEmployeeFilter != null) {
        hasFilters = true;
        result = result.where((remittance) => 
          _getEmployeeName(remittance.employeeId) == _selectedEmployeeFilter).toList();
      }
      
      // 汇款方式筛选
      if (_selectedPaymentMethodFilter != null) {
        hasFilters = true;
        result = result.where((remittance) => 
          remittance.paymentMethod.value == _selectedPaymentMethodFilter).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((remittance) {
          final remittanceDate = DateTime.parse(remittance.remittanceDate);
          return remittanceDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 remittanceDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredRemittances = result;
      _updateActiveFilters();
    });
  }

  Future<void> _fetchData({bool isRefresh = false}) async {
    if (!isRefresh) {
    setState(() {
      _isLoading = true;
    });
    }
    
    try {
      await Future.wait([
        _fetchSuppliers(),
        _fetchEmployees(),
        _fetchRemittances(),
      ]);
      
      setState(() {
        _isLoading = false;
      });
      
      // 刷新后重新应用过滤条件
      if (isRefresh) {
        _filterRemittances();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取数据失败: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchSuppliers() async {
    try {
      final suppliers = await _supplierRepo.getAllSuppliers();
        setState(() {
          _suppliers = suppliers;
        });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _fetchEmployees() async {
    try {
      final employees = await _employeeRepo.getAllEmployees();
        setState(() {
          _employees = employees;
        });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _fetchRemittances() async {
    try {
      final remittancesResponse = await _remittanceRepo.getRemittances(page: 1, pageSize: 10000);
      final remittances = remittancesResponse.items;
        setState(() {
          _remittances = remittances;
        _filteredRemittances = remittances;
        });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _addRemittance() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RemittanceDialog(
        suppliers: _suppliers,
        employees: _employees,
      ),
    );
    if (result != null) {
      try {
        final remittanceCreate = RemittanceCreate(
          remittanceDate: result['remittanceDate'] as String,
          supplierId: result['supplierId'] as int?,
          amount: (result['amount'] as num).toDouble(),
          employeeId: result['employeeId'] as int?,
          paymentMethod: PaymentMethod.fromString(result['paymentMethod'] as String),
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _remittanceRepo.createRemittance(remittanceCreate);
          _fetchRemittances();
        
        if (mounted) {
          context.showSuccessSnackBar('汇款记录添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('添加汇款记录失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editRemittance(Remittance remittance) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RemittanceDialog(
        remittance: remittance,
        suppliers: _suppliers,
        employees: _employees,
      ),
    );
    if (result != null) {
      try {
        final remittanceUpdate = RemittanceUpdate(
          remittanceDate: result['remittanceDate'] as String?,
          supplierId: result['supplierId'] as int?,
          amount: (result['amount'] as num?)?.toDouble(),
          employeeId: result['employeeId'] as int?,
          paymentMethod: result['paymentMethod'] != null 
              ? PaymentMethod.fromString(result['paymentMethod'] as String)
              : null,
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _remittanceRepo.updateRemittance(remittance.id, remittanceUpdate);
          _fetchRemittances();
        
        if (mounted) {
          context.showSuccessSnackBar('汇款记录更新成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新汇款记录失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _deleteRemittance(Remittance remittance) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除这条汇款记录吗？'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('确认'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _remittanceRepo.deleteRemittance(remittance.id);
          _fetchRemittances();
        
        if (mounted) {
          context.showSuccessSnackBar('汇款记录删除成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('删除汇款记录失败: ${e.toString()}');
        }
      }
    }
  }

  // 显示高级搜索对话框
  void _showAdvancedSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '高级搜索',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _resetFilters();
                          },
                          child: Text('重置所有'),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    
                    // 供应商筛选
                    Text('按供应商筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedSupplierFilter,
                        hint: Text('选择供应商'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部供应商'),
                          ),
                          ..._suppliers.map((supplier) => DropdownMenuItem<String?>(
                            value: supplier.name,
                            child: Text(supplier.name),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedSupplierFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 员工筛选
                    Text('按员工筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedEmployeeFilter,
                        hint: Text('选择员工'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部员工'),
                          ),
                          ..._employees.map((employee) => DropdownMenuItem<String?>(
                            value: employee.name,
                            child: Text(employee.name),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedEmployeeFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 汇款方式筛选
                    Text('按汇款方式筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedPaymentMethodFilter,
                        hint: Text('选择汇款方式'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部汇款方式'),
                          ),
                          ..._paymentMethods.map((method) => DropdownMenuItem<String?>(
                            value: method,
                            child: Text(method),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedPaymentMethodFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 日期范围筛选
                    Text('按日期筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final initialDateRange = _selectedDateRange ??
                            DateTimeRange(
                              start: now.subtract(Duration(days: 30)),
                              end: now,
                            );
                        
                        final pickedRange = await showDateRangePicker(
                          context: context,
                          initialDateRange: initialDateRange,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: Colors.orange,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        
                        if (pickedRange != null) {
                          setState(() {
                            _selectedDateRange = pickedRange;
                          });
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedDateRange != null
                                  ? '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} 至 ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                                  : '选择日期范围',
                              style: TextStyle(
                                color: _selectedDateRange != null
                                    ? Colors.black
                                    : Colors.grey.shade600,
                              ),
                            ),
                            Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // 确认按钮
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _filterRemittances();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            '应用筛选',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 添加手势检测器，点击空白处收起键盘
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('汇款', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(_showDeleteButtons ? Icons.cancel : Icons.delete),
            tooltip: _showDeleteButtons ? '取消删除模式' : '开启删除模式',
            onPressed: () {
              setState(() {
                _showDeleteButtons = !_showDeleteButtons;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.send, color: Colors.orange[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '汇款记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
                Spacer(),
                Text(
                  '共 ${_filteredRemittances.length} 条记录',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          Expanded(
            child: _isLoading && _remittances.isEmpty
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _fetchData(isRefresh: true),
                    child: _filteredRemittances.isEmpty
                        ? SingleChildScrollView(
                            physics: AlwaysScrollableScrollPhysics(),
                            child: Container(
                              height: MediaQuery.of(context).size.height * 0.7,
                              child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_outlined, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              _isSearching ? '没有匹配的汇款记录' : '暂无汇款记录',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              _isSearching ? '请尝试其他搜索条件' : '点击右下角 + 按钮添加汇款记录',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                                  ),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    // 让列表也能点击收起键盘
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _filteredRemittances.length,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemBuilder: (context, index) {
                      final remittance = _filteredRemittances[index];
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                      SizedBox(width: 4),
                                      Text(
                                        DateFormat('yyyy-MM-dd').format(DateTime.parse(remittance.remittanceDate)),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.orange),
                                        tooltip: '编辑',
                                        onPressed: () => _editRemittance(remittance),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteRemittance(remittance),
                                          constraints: BoxConstraints(),
                                          padding: EdgeInsets.all(8),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '供应商: ${_getSupplierName(remittance.supplierId).isEmpty ? '未指定' : _getSupplierName(remittance.supplierId)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '经办人: ${_getEmployeeName(remittance.employeeId).isEmpty ? '未指定' : _getEmployeeName(remittance.employeeId)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '¥${remittance.amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red[600],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.orange[300]!),
                                        ),
                                        child: Text(
                                          remittance.paymentMethod.value,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (remittance.note != null && remittance.note!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '备注: ${remittance.note}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  ),
          ),
          // 添加搜索栏和浮动按钮的容器
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 活跃过滤条件显示
                ValueListenableBuilder<List<String>>(
                  valueListenable: _activeFilters,
                  builder: (context, filters, child) {
                    if (filters.isEmpty) return SizedBox.shrink();
                    
                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[100]!)
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, size: 16, color: Colors.orange),
                          SizedBox(width: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: filters.map((filter) {
                                  return Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Chip(
                                      label: Text(filter, style: TextStyle(fontSize: 12)),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                                      backgroundColor: Colors.orange[100],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.clear, size: 16, color: Colors.orange),
                            onPressed: _resetFilters,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
        ],
      ),
                    );
                  },
                ),
                Row(
                  children: [
                    // 搜索框
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索汇款记录...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                          suffixIcon: _isSearching
                              ? IconButton(
                                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                                  onPressed: () {
                                    _searchController.clear();
                                    FocusScope.of(context).unfocus();
                                  },
                                )
                              : null,
                          contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.orange),
                          ),
                        ),
                        // 添加键盘相关设置
                        textInputAction: TextInputAction.search,
                        onEditingComplete: () {
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    // 高级搜索按钮
                    IconButton(
                      onPressed: _showAdvancedSearchDialog,
                      icon: Icon(
                        Icons.tune,
                        color: _showAdvancedSearch ? Colors.orange : Colors.grey[600],
                        size: 20,
                      ),
                      tooltip: '高级搜索',
                    ),
                    SizedBox(width: 8),
                    // 添加按钮
                    FloatingActionButton(
        onPressed: _addRemittance,
        child: Icon(Icons.add),
        tooltip: '添加汇款记录',
        backgroundColor: Colors.orange,
                      mini: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
          FooterWidget(),
        ],
      ),
      ),
    );
  }
}

class RemittanceDialog extends StatefulWidget {
  final Remittance? remittance;
  final List<Supplier> suppliers;
  final List<Employee> employees;

  RemittanceDialog({
    this.remittance,
    required this.suppliers,
    required this.employees,
  });

  @override
  _RemittanceDialogState createState() => _RemittanceDialogState();
}

class _RemittanceDialogState extends State<RemittanceDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  DateTime _selectedDate = DateTime.now();
  int? _selectedSupplierId;
  int? _selectedEmployeeId;
  String _selectedPaymentMethod = '现金';
  
  final List<String> _paymentMethods = ['现金', '微信转账', '银行卡'];

  @override
  void initState() {
    super.initState();
    if (widget.remittance != null) {
      _selectedDate = DateTime.parse(widget.remittance!.remittanceDate);
      _selectedSupplierId = widget.remittance!.supplierId;
      _selectedEmployeeId = widget.remittance!.employeeId;
      _selectedPaymentMethod = widget.remittance!.paymentMethod.value;
      _amountController.text = widget.remittance!.amount.toString();
      _noteController.text = widget.remittance!.note ?? '';
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.remittance == null ? '添加汇款记录' : '编辑汇款记录',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 日期选择
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '汇款日期',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('yyyy-MM-dd').format(_selectedDate),
                          style: TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              
              // 供应商选择
              DropdownButtonFormField<int>(
                value: _selectedSupplierId,
                decoration: InputDecoration(
                  labelText: '选择供应商',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.business, color: Colors.orange),
                ),
                isExpanded: true,
                hint: Text('选择供应商', overflow: TextOverflow.ellipsis),
                items: widget.suppliers.map<DropdownMenuItem<int>>((supplier) {
                  return DropdownMenuItem<int>(
                    value: supplier.id,
                    child: Text(supplier.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSupplierId = value;
                  });
                },
              ),
              SizedBox(height: 16),
              
              // 金额输入
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: '金额',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.attach_money, color: Colors.orange),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入金额';
                  }
                  if (double.tryParse(value) == null) {
                    return '请输入有效的金额';
                  }
                  if (double.parse(value) <= 0) {
                    return '金额必须大于0';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              // 经办人 + 汇款方式 同一排
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedEmployeeId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '经办人',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.badge, color: Colors.orange),
                      ),
                      items: [
                        DropdownMenuItem<int>(
                          value: null,
                          child: Text('经办人', overflow: TextOverflow.ellipsis),
                        ),
                        ...widget.employees.map<DropdownMenuItem<int>>((employee) {
                          return DropdownMenuItem<int>(
                            value: employee.id,
                            child: Text(employee.name, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedEmployeeId = value;
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedPaymentMethod,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '汇款方式',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.send, color: Colors.orange),
                      ),
                      items: _paymentMethods.map<DropdownMenuItem<String>>((method) {
                        return DropdownMenuItem<String>(
                          value: method,
                          child: Text(method, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentMethod = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              
              // 备注
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.note, color: Colors.orange),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                // 本地验证：检查所有必填项和业务规则
                String? errorMessage;
                
                // 1. 供应商已选择
                if (_selectedSupplierId == null) {
                  errorMessage = '请选择供应商';
                }
                // 2. 金额输入合法，为正实数
                else {
                  final amountText = _amountController.text.trim();
                  if (amountText.isEmpty) {
                    errorMessage = '请输入金额';
                  } else {
                    final amount = double.tryParse(amountText);
                    if (amount == null) {
                      errorMessage = '金额格式无效';
                    } else if (amount <= 0) {
                      errorMessage = '金额必须大于0';
                    }
                  }
                }
                
                // 4. 汇款方式已选（默认已选为现金，但检查一下）
                if (errorMessage == null && (_selectedPaymentMethod == null || _selectedPaymentMethod.isEmpty)) {
                  errorMessage = '请选择汇款方式';
                }
                
                // 如果有错误，显示弹窗
                if (errorMessage != null) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('保存失败'),
                      content: Text(errorMessage!),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('确定'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                
                // 所有验证通过，执行保存
                if (_formKey.currentState!.validate()) {
                  final Map<String, dynamic> remittance = {
                    'remittanceDate': _selectedDate.toIso8601String().split('T')[0],
                    'supplierId': _selectedSupplierId,
                    'amount': double.parse(_amountController.text.trim()),
                    'employeeId': _selectedEmployeeId,
                    'paymentMethod': _selectedPaymentMethod,
                    'note': _noteController.text.trim().isEmpty 
                        ? null 
                        : _noteController.text.trim(),
                  };
                  Navigator.of(context).pop(remittance);
                }
              },
              child: Text('保存'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('取消'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}
