// lib/screens/income_screen.dart

import 'package:flutter/material.dart';
import '../widgets/footer_widget.dart';
import 'package:intl/intl.dart';
import '../repositories/income_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/employee_repository.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class IncomeScreen extends StatefulWidget {
  @override
  _IncomeScreenState createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  final IncomeRepository _incomeRepo = IncomeRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  
  List<Income> _incomes = [];
  List<Customer> _customers = [];
  List<Employee> _employees = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;

  // 添加搜索相关的状态变量
  List<Income> _filteredIncomes = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedCustomerFilter;
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
      _filterIncomes();
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
      _selectedCustomerFilter = null;
      _selectedEmployeeFilter = null;
      _selectedPaymentMethodFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredIncomes = List.from(_incomes);
      _isSearching = false;
      _showAdvancedSearch = false;
    });
  }

  // 更新搜索条件并显示活跃的过滤条件
  void _updateActiveFilters() {
    List<String> filters = [];
    
    if (_selectedCustomerFilter != null) {
      filters.add('客户: $_selectedCustomerFilter');
    }
    
    if (_selectedEmployeeFilter != null) {
      filters.add('员工: $_selectedEmployeeFilter');
    }
    
    if (_selectedPaymentMethodFilter != null) {
      filters.add('付款方式: $_selectedPaymentMethodFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 获取客户名称
  String _getCustomerName(int? customerId) {
    if (customerId == null) return '';
    final customer = _customers.firstWhere(
      (c) => c.id == customerId,
      orElse: () => Customer(id: -1, userId: 0, name: ''),
    );
    return customer.name;
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

  // 添加过滤进账记录的方法
  void _filterIncomes() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      // 开始筛选
      List<Income> result = List.from(_incomes);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((income) {
          final customerName = _getCustomerName(income.customerId).toLowerCase();
          final employeeName = _getEmployeeName(income.employeeId).toLowerCase();
          final date = income.incomeDate.toLowerCase();
          final note = (income.note ?? '').toLowerCase();
          final amount = income.amount.toString().toLowerCase();
          final discount = income.discount.toString().toLowerCase();
          final paymentMethod = income.paymentMethod.value.toLowerCase();
          
          // 检查所有搜索词是否都匹配
          return searchTerms.every((term) =>
            customerName.contains(term) ||
            employeeName.contains(term) ||
            date.contains(term) ||
            note.contains(term) ||
            amount.contains(term) ||
            discount.contains(term) ||
            paymentMethod.contains(term)
          );
        }).toList();
      }
      
      // 客户筛选
      if (_selectedCustomerFilter != null) {
        hasFilters = true;
        result = result.where((income) => 
          _getCustomerName(income.customerId) == _selectedCustomerFilter).toList();
      }
      
      // 员工筛选
      if (_selectedEmployeeFilter != null) {
        hasFilters = true;
        result = result.where((income) => 
          _getEmployeeName(income.employeeId) == _selectedEmployeeFilter).toList();
      }
      
      // 付款方式筛选
      if (_selectedPaymentMethodFilter != null) {
        hasFilters = true;
        result = result.where((income) => 
          income.paymentMethod.value == _selectedPaymentMethodFilter).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((income) {
          final incomeDate = DateTime.parse(income.incomeDate);
          return incomeDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 incomeDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredIncomes = result;
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
        _fetchCustomers(),
        _fetchEmployees(),
        _fetchIncomes(),
      ]);
      
      setState(() {
        _isLoading = false;
      });
      
      // 刷新后重新应用过滤条件
      if (isRefresh) {
        _filterIncomes();
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

  Future<void> _fetchCustomers() async {
    try {
      final customers = await _customerRepo.getAllCustomers();
      setState(() {
        _customers = customers;
      });
    } catch (e) {
      // 错误已在 _fetchData 中处理
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
      // 错误已在 _fetchData 中处理
      rethrow;
    }
  }

  Future<void> _fetchIncomes() async {
    try {
      final incomesResponse = await _incomeRepo.getIncomes(page: 1, pageSize: 10000);
      final incomes = incomesResponse.items;
      setState(() {
        _incomes = incomes;
        _filteredIncomes = incomes;
      });
    } catch (e) {
      // 错误已在 _fetchData 中处理
      rethrow;
    }
  }

  Future<void> _addIncome() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => IncomeDialog(
        customers: _customers,
        employees: _employees,
      ),
    );
    if (result != null) {
      try {
        final incomeCreate = IncomeCreate(
          incomeDate: result['incomeDate'] as String,
          customerId: result['customerId'] as int?,
          amount: (result['amount'] as num).toDouble(),
          discount: (result['discount'] as num?)?.toDouble() ?? 0.0,
          employeeId: result['employeeId'] as int?,
          paymentMethod: PaymentMethod.fromString(result['paymentMethod'] as String),
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _incomeRepo.createIncome(incomeCreate);
        _fetchIncomes();
        
        if (mounted) {
          context.showSuccessSnackBar('进账记录添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('添加进账记录失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editIncome(Income income) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => IncomeDialog(
        income: income,
        customers: _customers,
        employees: _employees,
      ),
    );
    if (result != null) {
      try {
        final incomeUpdate = IncomeUpdate(
          incomeDate: result['incomeDate'] as String?,
          customerId: result['customerId'] as int?,
          amount: (result['amount'] as num?)?.toDouble(),
          discount: (result['discount'] as num?)?.toDouble(),
          employeeId: result['employeeId'] as int?,
          paymentMethod: result['paymentMethod'] != null 
              ? PaymentMethod.fromString(result['paymentMethod'] as String)
              : null,
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _incomeRepo.updateIncome(income.id, incomeUpdate);
        _fetchIncomes();
        
        if (mounted) {
          context.showSuccessSnackBar('进账记录更新成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新进账记录失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _deleteIncome(Income income) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除这条进账记录吗？'),
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
        await _incomeRepo.deleteIncome(income.id);
        _fetchIncomes();
        
        if (mounted) {
          context.showSuccessSnackBar('进账记录删除成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('删除进账记录失败: ${e.toString()}');
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
                    
                    // 客户筛选
                    Text('按客户筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedCustomerFilter,
                        hint: Text('选择客户'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部客户'),
                          ),
                          ..._customers.map((customer) => DropdownMenuItem<String?>(
                            value: customer.name,
                            child: Text(customer.name),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedCustomerFilter = value;
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
                    
                    // 付款方式筛选
                    Text('按付款方式筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
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
                        hint: Text('选择付款方式'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部付款方式'),
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
                                  primary: Colors.teal,
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
                            _filterIncomes();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
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
        title: Text('进账', style: TextStyle(
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
                Icon(Icons.account_balance_wallet, color: Colors.teal[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '进账记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800],
                  ),
                ),
                Spacer(),
                Text(
                  '共 ${_filteredIncomes.length} 条记录',
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
            child: _isLoading && _incomes.isEmpty
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _fetchData(isRefresh: true),
                    child: _filteredIncomes.isEmpty
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
                                Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  _isSearching ? '没有匹配的进账记录' : '暂无进账记录',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _isSearching ? '请尝试其他搜索条件' : '点击右下角 + 按钮添加进账记录',
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
                    itemCount: _filteredIncomes.length,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemBuilder: (context, index) {
                      final income = _filteredIncomes[index];
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
                                        DateFormat('yyyy-MM-dd').format(DateTime.parse(income.incomeDate)),
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
                                        icon: Icon(Icons.edit, color: Colors.teal),
                                        tooltip: '编辑',
                                        onPressed: () => _editIncome(income),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                        IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteIncome(income),
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
                                        '客户: ${_getCustomerName(income.customerId).isEmpty ? '未指定' : _getCustomerName(income.customerId)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '经办人: ${_getEmployeeName(income.employeeId).isEmpty ? '未指定' : _getEmployeeName(income.employeeId)}',
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
                                      // 显示实际进账金额
                                      Text(
                                        '¥${income.amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[600],
                                        ),
                                      ),
                                      // 如果有优惠，显示优惠信息
                                      if (income.discount > 0) ...[
                                        SizedBox(height: 2),
                                        Text(
                                          '原价: ¥${(income.amount + income.discount).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                        Text(
                                          '优惠: ¥${income.discount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      SizedBox(height: 4),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.teal[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.teal[300]!),
                                        ),
                                        child: Text(
                                          income.paymentMethod.value,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.teal[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (income.note != null && income.note!.isNotEmpty)
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
                                      '备注: ${income.note}',
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
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal[100]!)
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, size: 16, color: Colors.teal),
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
                                      backgroundColor: Colors.teal[100],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.clear, size: 16, color: Colors.teal),
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
                          hintText: '搜索进账记录...',
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
                            borderSide: BorderSide(color: Colors.teal),
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
                        color: _showAdvancedSearch ? Colors.teal : Colors.grey[600],
                        size: 20,
                      ),
                      tooltip: '高级搜索',
                    ),
                    SizedBox(width: 8),
                    // 添加按钮
                    FloatingActionButton(
                      onPressed: _addIncome,
                      child: Icon(Icons.add),
                      tooltip: '添加进账记录',
                      backgroundColor: Colors.teal,
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

class IncomeDialog extends StatefulWidget {
  final Income? income;
  final List<Customer> customers;
  final List<Employee> employees;

  IncomeDialog({
    this.income,
    required this.customers,
    required this.employees,
  });

  @override
  _IncomeDialogState createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<IncomeDialog> {
  final _amountController = TextEditingController();
  final _discountController = TextEditingController();
  final _originalPriceController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  DateTime _selectedDate = DateTime.now();
  int? _selectedCustomerId;
  int? _selectedEmployeeId;
  String _selectedPaymentMethod = '现金';
  bool _isUpdatingDiscountFields = false;
  String? _lastEditedDiscountField; // 'discount' | 'original'
  bool _originalPriceError = false; // 优惠前价格错误状态
  
  final List<String> _paymentMethods = ['现金', '微信转账', '银行卡'];

  @override
  void initState() {
    super.initState();
    if (widget.income != null) {
      _selectedDate = DateTime.parse(widget.income!.incomeDate);
      _selectedCustomerId = widget.income!.customerId;
      _selectedEmployeeId = widget.income!.employeeId;
      _selectedPaymentMethod = widget.income!.paymentMethod.value;
      _amountController.text = widget.income!.amount.toString();
      _discountController.text = widget.income!.discount.toString();
      _noteController.text = widget.income!.note ?? '';
      
      // 如果有优惠，计算优惠前价格
      final amount = widget.income!.amount;
      final discount = widget.income!.discount;
      if (discount > 0) {
        _originalPriceController.text = (amount + discount).toString();
      }
    } else {
      _discountController.text = '0';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _discountController.dispose();
    _originalPriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _updateCalculations({required String source}) {
    if (_isUpdatingDiscountFields) return;
    _isUpdatingDiscountFields = true;

    try {
      final double amount = double.tryParse(_amountController.text.trim()) ?? 0.0;

      if (source == 'discount') {
        _lastEditedDiscountField = 'discount';
        final double discount = double.tryParse(_discountController.text.trim()) ?? 0.0;
        final double originalPrice = amount + discount;
        _originalPriceController.text = originalPrice.toString();
      } else if (source == 'original') {
        _lastEditedDiscountField = 'original';
        final double originalPrice = double.tryParse(_originalPriceController.text.trim()) ?? 0.0;
        final double discount = originalPrice - amount;
        if (discount >= 0) {
          _discountController.text = discount.toString();
        }
      } else if (source == 'amount') {
        // 金额变化时，按用户最后编辑的优惠字段来更新另一个字段
        if (_lastEditedDiscountField == 'original') {
          final double originalPrice = double.tryParse(_originalPriceController.text.trim()) ?? 0.0;
          final double discount = originalPrice - amount;
          if (discount >= 0) {
            _discountController.text = discount.toString();
          }
          // 检查优惠前价格是否仍然有效
          setState(() {
            _originalPriceError = originalPrice < amount;
          });
        } else {
          final double discount = double.tryParse(_discountController.text.trim()) ?? 0.0;
          final double originalPrice = amount + discount;
          _originalPriceController.text = originalPrice.toString();
          // 自动计算的情况下，优惠前价格总是有效的
          setState(() {
            _originalPriceError = false;
          });
        }
      }
    } finally {
      _isUpdatingDiscountFields = false;
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
        widget.income == null ? '添加进账记录' : '编辑进账记录',
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
                    labelText: '进账日期',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.teal),
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
              
              // 客户选择
              DropdownButtonFormField<int>(
                value: _selectedCustomerId,
                decoration: InputDecoration(
                  labelText: '选择客户',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.person, color: Colors.teal),
                ),
                isExpanded: true,
                hint: Text('选择客户', overflow: TextOverflow.ellipsis),
                items: widget.customers.map<DropdownMenuItem<int>>((customer) {
                  return DropdownMenuItem<int>(
                    value: customer.id,
                    child: Text(customer.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCustomerId = value;
                  });
                },
              ),
              SizedBox(height: 16),

              // 实际进账金额（独占一行，放在选择客户下面）
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: '实际进账金额',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.attach_money, color: Colors.teal),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入实际进账金额';
                  }
                  if (double.tryParse(value) == null) {
                    return '请输入有效的金额';
                  }
                  if (double.parse(value) <= 0) {
                    return '金额必须大于0';
                  }
                  return null;
                },
                onChanged: (value) => _updateCalculations(source: 'amount'),
              ),
              SizedBox(height: 16),
              
              // 优惠金额（左）+ 优惠前价格（右）同一排：两者都可输入，自动互算
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      decoration: InputDecoration(
                        labelText: '优惠金额',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.discount, color: Colors.orange),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final discount = double.tryParse(value);
                          if (discount == null) {
                            return '请输入有效的优惠金额';
                          }
                          if (discount < 0) {
                            return '优惠金额不能为负数';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) => _updateCalculations(source: 'discount'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _originalPriceController,
                      decoration: InputDecoration(
                        labelText: '优惠前价格',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.red, width: 2),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.red, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.local_offer, color: Colors.orange),
                        errorText: _originalPriceError ? '应不小于实际进账' : null,
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final original = double.tryParse(value);
                          if (original == null) {
                            return '请输入有效的优惠前价格';
                          }
                          if (original < 0) {
                            return '优惠前价格不能为负数';
                          }
                          // 检查优惠前价格是否 >= 实际进账金额
                          final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
                          if (original < amount) {
                            return '应不小于实际进账';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // 实时检查优惠前价格是否 >= 实际进账金额
                        final original = double.tryParse(value.trim());
                        final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
                        setState(() {
                          if (original != null && original < amount) {
                            _originalPriceError = true;
                          } else {
                            _originalPriceError = false;
                          }
                        });
                        _updateCalculations(source: 'original');
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              
              // 经办人 + 付款方式 同一排
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
                        prefixIcon: Icon(Icons.badge, color: Colors.teal),
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
                        labelText: '付款方式',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.payment, color: Colors.teal),
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
                  prefixIcon: Icon(Icons.note, color: Colors.teal),
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
                
                // i. 进账日期已选择（默认当日，应该总是有值，但检查一下）
                if (_selectedDate == null) {
                  errorMessage = '请选择进账日期';
                }
                // i. 客户已选择
                else if (_selectedCustomerId == null) {
                  errorMessage = '请选择客户';
                }
                // ii. 实际进账金额、优惠金额、优惠前价格都已输入且 >= 0，且满足关系
                else {
                  final amountText = _amountController.text.trim();
                  final discountText = _discountController.text.trim();
                  final originalText = _originalPriceController.text.trim();
                  
                  if (amountText.isEmpty) {
                    errorMessage = '请输入实际进账金额';
                  } else {
                    final amount = double.tryParse(amountText);
                    if (amount == null) {
                      errorMessage = '实际进账金额格式无效';
                    } else if (amount <= 0) {
                      errorMessage = '实际进账金额必须大于0';
                    } else {
                      // 检查优惠金额和优惠前价格
                      final discount = discountText.isEmpty ? 0.0 : double.tryParse(discountText);
                      final original = originalText.isEmpty ? null : double.tryParse(originalText);
                      
                      if (discount == null && discountText.isNotEmpty) {
                        errorMessage = '优惠金额格式无效';
                      } else if (discount != null && discount < 0) {
                        errorMessage = '优惠金额不能为负数';
                      } else if (original == null && originalText.isNotEmpty) {
                        errorMessage = '优惠前价格格式无效';
                      } else if (original != null && original < 0) {
                        errorMessage = '优惠前价格不能为负数';
                      } else if (original != null && original < amount) {
                        errorMessage = '优惠前价格必须大于等于实际进账金额';
                      } else {
                        // 计算检查：实际进账金额 + 优惠金额 = 优惠前价格（浮点数计算，容忍小误差）
                        final calculatedOriginal = amount + (discount ?? 0.0);
                        if (original != null) {
                          final diff = (calculatedOriginal - original).abs();
                          if (diff > 0.01) { // 允许0.01的误差
                            errorMessage = '金额关系不正确：实际进账金额(${amount.toStringAsFixed(2)}) + 优惠金额(${(discount ?? 0.0).toStringAsFixed(2)}) = ${calculatedOriginal.toStringAsFixed(2)}，但优惠前价格为${original.toStringAsFixed(2)}';
                          }
                        }
                      }
                    }
                  }
                }
                
                // iii. 付款方式需要选择（默认现金，应该总是有值，但检查一下）
                if (errorMessage == null && (_selectedPaymentMethod == null || _selectedPaymentMethod.isEmpty)) {
                  errorMessage = '请选择付款方式';
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
                  final Map<String, dynamic> income = {
                    'incomeDate': _selectedDate.toIso8601String().split('T')[0],
                    'customerId': _selectedCustomerId,
                    'amount': double.parse(_amountController.text.trim()),
                    'discount': double.tryParse(_discountController.text.trim()) ?? 0.0,
                    'employeeId': _selectedEmployeeId,
                    'paymentMethod': _selectedPaymentMethod,
                    'note': _noteController.text.trim().isEmpty 
                        ? null 
                        : _noteController.text.trim(),
                  };
                  Navigator.of(context).pop(income);
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
}
 