import 'package:flutter/material.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/product_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';

class CustomerTransactionsScreen extends StatefulWidget {
  final int customerId;
  final String customerName;

  CustomerTransactionsScreen({
    required this.customerId, 
    required this.customerName,
  });

  @override
  _CustomerTransactionsScreenState createState() => _CustomerTransactionsScreenState();
}

class _CustomerTransactionsScreenState extends State<CustomerTransactionsScreen> {
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  final ProductRepository _productRepo = ProductRepository();
  
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  bool _isLoading = true;
  
  // 搜索相关
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 筛选相关
  String _selectedFilter = 'all'; // all, sale, return, income
  String _dateFilter = 'all'; // all, today, week, month, custom
  DateTime? _startDate;
  DateTime? _endDate;
  
  // 排序相关
  String _sortBy = 'date'; // date, amount
  bool _sortAscending = false; // false = 降序（最新/最大在前）

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
    _searchController.addListener(() {
      _applyFiltersAndSort();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 并行获取所有数据
      final results = await Future.wait([
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
        _employeeRepo.getAllEmployees(),
        _productRepo.getProducts(page: 1, pageSize: 10000),
      ]);
      
      final salesResponse = results[0] as PaginatedResponse<Sale>;
      final returnsResponse = results[1] as PaginatedResponse<Return>;
      final incomesResponse = results[2] as PaginatedResponse<Income>;
      final employees = results[3] as List<Employee>;
      final productsResponse = results[4] as PaginatedResponse<Product>;
      final products = productsResponse.items;
      
      // 按客户ID筛选
      final sales = salesResponse.items.where((s) => s.customerId == widget.customerId).toList();
      final returns = returnsResponse.items.where((r) => r.customerId == widget.customerId).toList();
      final incomes = incomesResponse.items.where((i) => i.customerId == widget.customerId).toList();
      
      List<Map<String, dynamic>> allTransactions = [];

      // 处理销售记录
      for (var sale in sales) {
        final product = products.firstWhere(
          (p) => p.name == sale.productName,
          orElse: () => Product(
            id: -1,
            userId: -1,
            name: '',
            stock: 0,
            unit: ProductUnit.kilogram,
            version: 1,
          ),
        );
        
        allTransactions.add({
          'type': 'sale',
          'typeName': '销售',
          'date': sale.saleDate ?? '',
          'productName': sale.productName,
          'quantity': sale.quantity,
          'unit': product.unit.value,
          'amount': sale.totalSalePrice ?? 0.0,
          'note': sale.note ?? '',
          'icon': Icons.sell,
          'color': Colors.green,
        });
      }

      // 处理退货记录
      for (var returnRecord in returns) {
        final product = products.firstWhere(
          (p) => p.name == returnRecord.productName,
          orElse: () => Product(
            id: -1,
            userId: -1,
            name: '',
            stock: 0,
            unit: ProductUnit.kilogram,
            version: 1,
          ),
        );
        
        allTransactions.add({
          'type': 'return',
          'typeName': '退货',
          'date': returnRecord.returnDate ?? '',
          'productName': returnRecord.productName,
          'quantity': returnRecord.quantity,
          'unit': product.unit.value,
          'amount': returnRecord.totalReturnPrice ?? 0.0,
          'note': returnRecord.note ?? '',
          'icon': Icons.keyboard_return,
          'color': Colors.red,
        });
      }

      // 处理进账记录
      for (var income in incomes) {
        final employee = income.employeeId != null && income.employeeId != 0
            ? employees.firstWhere(
                (e) => e.id == income.employeeId,
                orElse: () => Employee(id: -1, userId: -1, name: ''),
              )
            : null;

        allTransactions.add({
          'type': 'income',
          'typeName': '进账',
          'date': income.incomeDate ?? '',
          'amount': income.amount ?? 0.0,
          'discount': income.discount ?? 0.0,
          'paymentMethod': income.paymentMethod?.value ?? '',
          'employeeName': employee?.name ?? '',
          'note': income.note ?? '',
          'icon': Icons.payment,
          'color': Colors.amber, // 改为黄色
        });
      }

      // 按日期排序，最新的在前面
      allTransactions.sort((a, b) {
        DateTime dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime.now();
        DateTime dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      setState(() {
        _transactions = allTransactions;
        _isLoading = false;
      });
      
      _applyFiltersAndSort();
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载交易记录失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载交易记录失败: ${e.toString()}');
      }
    }
  }

  // 应用搜索、筛选和排序
  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> filtered = List.from(_transactions);
    
    // 搜索筛选
    final searchText = _searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered.where((transaction) {
        final productName = (transaction['productName'] ?? '').toString().toLowerCase();
        final note = (transaction['note'] ?? '').toString().toLowerCase();
        final typeName = transaction['typeName'].toString().toLowerCase();
        final amount = transaction['amount'].toString();
        final paymentMethod = (transaction['paymentMethod'] ?? '').toString().toLowerCase();
        final employeeName = (transaction['employeeName'] ?? '').toString().toLowerCase();
        
        return productName.contains(searchText) ||
               note.contains(searchText) ||
               typeName.contains(searchText) ||
               amount.contains(searchText) ||
               paymentMethod.contains(searchText) ||
               employeeName.contains(searchText);
      }).toList();
    }
    
    // 类型筛选
    if (_selectedFilter != 'all') {
      filtered = filtered.where((transaction) => 
          transaction['type'] == _selectedFilter).toList();
    }
    
    // 日期筛选
    if (_dateFilter != 'all') {
      DateTime now = DateTime.now();
      DateTime? filterStartDate;
      DateTime? filterEndDate;
      
      switch (_dateFilter) {
        case 'today':
          filterStartDate = DateTime(now.year, now.month, now.day);
          filterEndDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'week':
          int weekday = now.weekday;
          filterStartDate = now.subtract(Duration(days: weekday - 1));
          filterStartDate = DateTime(filterStartDate.year, filterStartDate.month, filterStartDate.day);
          filterEndDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'month':
          filterStartDate = DateTime(now.year, now.month, 1);
          filterEndDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'custom':
          filterStartDate = _startDate;
          filterEndDate = _endDate;
          break;
      }
      
      if (filterStartDate != null || filterEndDate != null) {
        filtered = filtered.where((transaction) {
          DateTime? transactionDate = DateTime.tryParse(transaction['date']);
          if (transactionDate == null) return false;
          
          if (filterStartDate != null && transactionDate.isBefore(filterStartDate)) {
            return false;
          }
          if (filterEndDate != null && transactionDate.isAfter(filterEndDate)) {
            return false;
          }
          return true;
        }).toList();
      }
    }
    
    // 排序
    filtered.sort((a, b) {
      if (_sortBy == 'date') {
        DateTime dateA = DateTime.tryParse(a['date']) ?? DateTime.now();
        DateTime dateB = DateTime.tryParse(b['date']) ?? DateTime.now();
        return _sortAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      } else if (_sortBy == 'amount') {
        double amountA = double.tryParse(a['amount'].toString()) ?? 0.0;
        double amountB = double.tryParse(b['amount'].toString()) ?? 0.0;
        return _sortAscending ? amountA.compareTo(amountB) : amountB.compareTo(amountA);
      }
      return 0;
    });
    
    setState(() {
      _filteredTransactions = filtered;
      _isSearching = searchText.isNotEmpty || _selectedFilter != 'all' || _dateFilter != 'all';
    });
  }

  // 显示筛选选项
  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                '筛选选项',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              Text('按类型筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip('all', '全部', null, setModalState),
                  _buildFilterChip('sale', '销售', Colors.green, setModalState),
                  _buildFilterChip('return', '退货', Colors.red, setModalState),
                  _buildFilterChip('income', '进账', Colors.amber, setModalState),
                ],
              ),
              SizedBox(height: 16),
              Text('按日期筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildDateFilterChip('all', '全部', setModalState),
                  _buildDateFilterChip('today', '今天', setModalState),
                  _buildDateFilterChip('week', '本周', setModalState),
                  _buildDateFilterChip('month', '本月', setModalState),
                  _buildDateFilterChip('custom', '指定日期', setModalState),
                ],
              ),
              if (_dateFilter == 'custom')
                Container(
                  margin: EdgeInsets.only(top: 12),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择日期范围:',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[700],
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _selectDate(true, setModalState),
                              icon: Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                _startDate != null 
                                    ? _formatDate(_startDate.toString())
                                    : '开始日期',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue[700],
                                side: BorderSide(color: Colors.blue[300]!),
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('至', style: TextStyle(color: Colors.grey[600])),
                          SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _selectDate(false, setModalState),
                              icon: Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                _endDate != null 
                                    ? _formatDate(_endDate.toString())
                                    : '结束日期',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue[700],
                                side: BorderSide(color: Colors.blue[300]!),
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_startDate != null && _endDate != null)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '已选择: ${_formatDate(_startDate.toString())} 到 ${_formatDate(_endDate.toString())}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              SizedBox(height: 16),
              Text('排序方式:', style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildSortChip('date', '按日期', setModalState),
                  _buildSortChip('amount', '按金额', setModalState),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Text('排序顺序: '),
                  Switch(
                    value: _sortAscending,
                    onChanged: (value) {
                      setState(() {
                        _sortAscending = value;
                      });
                      setModalState(() {
                        _sortAscending = value;
                      });
                      _applyFiltersAndSort();
                    },
                    activeColor: Colors.orange,
                  ),
                  Text(_sortAscending ? '升序' : '降序'),
                ],
              ),
              SizedBox(height: 24),
              // 底部操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedFilter = 'all';
                          _dateFilter = 'all';
                          _startDate = null;
                          _endDate = null;
                          _sortBy = 'date';
                          _sortAscending = false;
                          _searchController.clear();
                        });
                        setModalState(() {
                          _selectedFilter = 'all';
                          _dateFilter = 'all';
                          _startDate = null;
                          _endDate = null;
                          _sortBy = 'date';
                          _sortAscending = false;
                        });
                        _applyFiltersAndSort();
                      },
                      child: Text(
                        '重置所有',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey[400]!),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text(
                        '完成',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String value, String label, Color? color, StateSetter setModalState) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
        setModalState(() {
          _selectedFilter = value;
        });
        _applyFiltersAndSort();
      },
      selectedColor: color?.withOpacity(0.2) ?? Colors.orange.withOpacity(0.2),
      checkmarkColor: color ?? Colors.orange,
    );
  }

  Widget _buildSortChip(String value, String label, StateSetter setModalState) {
    final isSelected = _sortBy == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _sortBy = value;
        });
        setModalState(() {
          _sortBy = value;
        });
        _applyFiltersAndSort();
      },
      selectedColor: Colors.orange.withOpacity(0.2),
      checkmarkColor: Colors.orange,
    );
  }

  Widget _buildDateFilterChip(String value, String label, StateSetter setModalState) {
    final isSelected = _dateFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _dateFilter = value;
          if (value != 'custom') {
            _startDate = null;
            _endDate = null;
          }
        });
        setModalState(() {
          _dateFilter = value;
          if (value != 'custom') {
            _startDate = null;
            _endDate = null;
          }
        });
        _applyFiltersAndSort();
      },
      selectedColor: Colors.blue.withOpacity(0.2),
      checkmarkColor: Colors.blue,
    );
  }

  Future<void> _selectDate(bool isStartDate, [StateSetter? setModalState]) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
      if (setModalState != null) {
        setModalState(() {
          if (isStartDate) {
            _startDate = picked;
          } else {
            _endDate = picked;
          }
        });
      }
      _applyFiltersAndSort();
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      DateTime date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0.00';
    double value = amount is double ? amount : double.tryParse(amount.toString()) ?? 0.0;
    return value.toStringAsFixed(2);
  }

  // 格式化数字显示：整数显示为整数，小数显示为小数
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
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
            // 头部信息
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: transaction['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    transaction['icon'],
                    color: transaction['color'],
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            transaction['typeName'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: transaction['color'],
                            ),
                          ),
                          Spacer(),
                          Text(
                            _formatDate(transaction['date']),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '¥${_formatAmount(transaction['amount'])}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: transaction['color'],
                            ),
                          ),
                          if (transaction['discount'] != null && transaction['discount'] > 0)
                            Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '折扣 ¥${_formatAmount(transaction['discount'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // 详细信息
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 产品信息（销售和退货）
                  if (transaction['productName'] != null)
                    _buildDetailRow('产品', transaction['productName']),
                  
                  if (transaction['quantity'] != null)
                    _buildDetailRow('数量', '${_formatNumber(transaction['quantity'])} ${transaction['unit'] ?? ''}'),
                  
                  // 支付方式（进账）
                  if (transaction['paymentMethod'] != null)
                    _buildDetailRow('支付方式', transaction['paymentMethod']),
                  
                  // 员工信息（进账）
                  if (transaction['employeeName'] != null && transaction['employeeName'].isNotEmpty)
                    _buildDetailRow('经手员工', transaction['employeeName']),
                  
                  // 备注
                  if (transaction['note'].isNotEmpty)
                    _buildDetailRow('备注', transaction['note']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.customerName}的往来记录',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // 搜索框和筛选按钮
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索产品、备注、金额等...',
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
                    textInputAction: TextInputAction.search,
                    onEditingComplete: () {
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: (_selectedFilter != 'all' || _dateFilter != 'all') 
                        ? Colors.orange 
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.filter_list,
                      color: (_selectedFilter != 'all' || _dateFilter != 'all') 
                          ? Colors.white 
                          : Colors.grey[600],
                    ),
                    tooltip: '筛选和排序',
                    onPressed: _showFilterOptions,
                  ),
                ),
              ],
            ),
          ),

          // 筛选状态提示和统计信息
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '总计 ${_filteredTransactions.length} 条记录: 销售 ${_filteredTransactions.where((t) => t['type'] == 'sale').length} | 退货 ${_filteredTransactions.where((t) => t['type'] == 'return').length} | 进账 ${_filteredTransactions.where((t) => t['type'] == 'income').length}',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_selectedFilter != 'all' || _dateFilter != 'all' || _searchController.text.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedFilter = 'all';
                        _dateFilter = 'all';
                        _startDate = null;
                        _endDate = null;
                        _sortBy = 'date';
                        _sortAscending = false;
                        _searchController.clear();
                      });
                      _applyFiltersAndSort();
                    },
                    child: Text(
                      '清除筛选',
                      style: TextStyle(color: Colors.orange[700], fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size(0, 24),
                    ),
                  ),
              ],
            ),
          ),

          // 记录列表
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  )
                : _filteredTransactions.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  _transactions.isEmpty ? '暂无往来记录' : '没有符合条件的记录',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (_transactions.isNotEmpty && _filteredTransactions.isEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      '请尝试调整搜索或筛选条件',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: _filteredTransactions.length,
                        itemBuilder: (context, index) {
                          return _buildTransactionCard(_filteredTransactions[index]);
                        },
                      ),
          ),

          FooterWidget(),
        ],
      ),
      ),
    );
  }
} 