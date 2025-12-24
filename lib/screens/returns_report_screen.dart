// lib/screens/returns_report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/return_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/product_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class ReturnsReportScreen extends StatefulWidget {
  @override
  _ReturnsReportScreenState createState() => _ReturnsReportScreenState();
}

class _ReturnsReportScreenState extends State<ReturnsReportScreen> {
  final ReturnRepository _returnRepo = ReturnRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final ProductRepository _productRepo = ProductRepository();
  
  List<Return> _allReturns = []; // 存储所有退货记录
  List<Return> _returns = []; // 存储筛选后的退货记录
  List<Customer> _customers = [];
  List<Product> _products = [];
  bool _isDescending = true; // 默认按时间倒序排列
  bool _isLoading = false;
  
  // 筛选条件
  String? _selectedProductName;
  int? _selectedCustomerId;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // 统计数据
  double _totalQuantity = 0.0;
  double _totalPrice = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _fetchData();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDescending = prefs.getBool('returns_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('returns_sort_descending', _isDescending);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 并行获取所有数据
      final results = await Future.wait([
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _customerRepo.getAllCustomers(),
        _productRepo.getProducts(page: 1, pageSize: 10000),
      ]);
      
      final returnsResponse = results[0] as PaginatedResponse<Return>;
      final customers = results[1] as List<Customer>;
      final productsResponse = results[2] as PaginatedResponse<Product>;
      
      // 按日期排序
      List<Return> returns = returnsResponse.items;
      returns.sort((a, b) {
        final dateA = a.returnDate != null ? DateTime.parse(a.returnDate!) : DateTime(1970);
        final dateB = b.returnDate != null ? DateTime.parse(b.returnDate!) : DateTime(1970);
        return _isDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });
      
        setState(() {
          _allReturns = returns;
          _customers = customers;
        _products = productsResponse.items;
        _isLoading = false;
          _applyFilters(); // 应用筛选
        });
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载数据失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载数据失败: ${e.toString()}');
      }
    }
  }
  
  // 应用筛选条件
  void _applyFilters() {
    List<Return> filteredReturns = List.from(_allReturns);
    
    // 按产品名称筛选
    if (_selectedProductName != null) {
      filteredReturns = filteredReturns.where(
        (returnItem) => returnItem.productName == _selectedProductName
      ).toList();
    }
    
    // 按客户筛选
    if (_selectedCustomerId != null) {
      filteredReturns = filteredReturns.where(
        (returnItem) => returnItem.customerId == _selectedCustomerId
      ).toList();
    }
    
    // 按日期范围筛选
    if (_startDate != null) {
      filteredReturns = filteredReturns.where((returnItem) {
        if (returnItem.returnDate == null) return false;
        final returnDate = DateTime.parse(returnItem.returnDate!);
        return returnDate.isAfter(_startDate!) || 
               returnDate.isAtSameMomentAs(_startDate!);
      }).toList();
    }
    
    if (_endDate != null) {
      final endDatePlusOne = _endDate!.add(Duration(days: 1)); // 包含结束日期
      filteredReturns = filteredReturns.where((returnItem) {
        if (returnItem.returnDate == null) return false;
        final returnDate = DateTime.parse(returnItem.returnDate!);
        return returnDate.isBefore(endDatePlusOne);
      }).toList();
    }
    
    // 计算总量和总退款
    _calculateTotals(filteredReturns);
    
    setState(() {
      _returns = filteredReturns;
    });
  }
  
  // 计算总量和总退款
  void _calculateTotals(List<Return> filteredReturns) {
    double totalQuantity = 0.0;
    double totalPrice = 0.0;
    
    for (var returnItem in filteredReturns) {
      totalQuantity += returnItem.quantity;
      totalPrice += returnItem.totalReturnPrice ?? 0.0;
    }
    
    setState(() {
      _totalQuantity = totalQuantity;
      _totalPrice = totalPrice;
    });
  }
  
  // 重置筛选条件
  void _resetFilters() {
    setState(() {
      _selectedProductName = null;
      _selectedCustomerId = null;
      _startDate = null;
      _endDate = null;
      _returns = _allReturns;
      _calculateTotals(_returns);
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _saveSortPreference();
      _fetchData();
    });
  }

  void _navigateToTableView() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReturnsTableScreen(
          returns: _returns.map((r) => r.toJson()).toList(),
          customers: _customers.map((c) => c.toJson()).toList(),
          products: _products.map((p) => p.toJson()).toList(),
          totalQuantity: _totalQuantity,
          totalPrice: _totalPrice,
          selectedProductName: _selectedProductName,
          selectedCustomerId: _selectedCustomerId,
          startDate: _startDate,
          endDate: _endDate,
          allCustomers: _customers,
        ),
      ),
    );
  }
  
  // 显示筛选菜单
  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '筛选与刷新',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.refresh),
                    label: Text('刷新数据'),
                    onPressed: () {
                      _fetchData();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.inventory, color: Colors.green),
                title: Text('按产品筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showProductSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.person, color: Colors.orange),
                title: Text('按客户筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showCustomerSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.date_range, color: Colors.red),
                title: Text('按日期范围筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showDateRangePickerDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.sort, color: Colors.purple),
                title: Text('切换排序顺序'),
                subtitle: Text(_isDescending ? '当前: 最新在前' : '当前: 最早在前'),
                onTap: () {
                  _toggleSortOrder();
                  Navigator.pop(context);
                },
              ),
              if (_hasFilters())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.clear_all),
                    label: Text('清除所有筛选条件'),
                    onPressed: () {
                      _resetFilters();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 44),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // 检查是否有筛选条件
  bool _hasFilters() {
    return _selectedProductName != null || 
           _selectedCustomerId != null || 
           _startDate != null || 
           _endDate != null;
  }
  
  // 选择产品对话框
  Future<void> _showProductSelectionDialog() async {
    // 创建选项列表：第一个是"所有产品"，后面是所有产品
    final List<MapEntry<String?, String>> productOptions = [
      MapEntry<String?, String>(null, '所有产品'),
      ..._products.map((p) => MapEntry<String?, String>(p.name, p.name)),
    ];
    
    // 找到当前选中项的索引
    int currentIndex = productOptions.indexWhere((entry) => entry.key == _selectedProductName);
    if (currentIndex < 0) {
      currentIndex = 0; // 默认选中"所有产品"
    }
    
    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择产品'),
          content: SizedBox(
            height: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setStateDialog) {
                      return CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: currentIndex),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          setStateDialog(() {
                            tempIndex = index;
                          });
                        },
                        children: productOptions
                            .map((entry) => Center(child: Text(entry.value)))
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < productOptions.length) {
      final selectedEntry = productOptions[selectedIndex];
      if (selectedEntry.key != _selectedProductName) {
        setState(() {
          _selectedProductName = selectedEntry.key;
        });
        _applyFilters();
      }
    }
  }
  
  // 选择客户对话框
  Future<void> _showCustomerSelectionDialog() async {
    // 创建选项列表：第一个是"所有客户"，后面是所有客户
    final List<MapEntry<int?, String>> customerOptions = [
      MapEntry<int?, String>(null, '所有客户'),
      ..._customers.map((c) => MapEntry<int?, String>(c.id, c.name)),
    ];
    
    // 找到当前选中项的索引
    int currentIndex = customerOptions.indexWhere((entry) => entry.key == _selectedCustomerId);
    if (currentIndex < 0) {
      currentIndex = 0; // 默认选中"所有客户"
    }
    
    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择客户'),
          content: SizedBox(
            height: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setStateDialog) {
                      return CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: currentIndex),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          setStateDialog(() {
                            tempIndex = index;
                          });
                        },
                        children: customerOptions
                            .map((entry) => Center(child: Text(entry.value)))
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < customerOptions.length) {
      final selectedEntry = customerOptions[selectedIndex];
      if (selectedEntry.key != _selectedCustomerId) {
        setState(() {
          _selectedCustomerId = selectedEntry.key;
        });
        _applyFilters();
      }
    }
  }
  
  // 选择日期范围对话框
  Future<void> _showDateRangePickerDialog() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.red,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _applyFilters();
      });
    }
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
  
  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('退货统计', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.table_chart),
            tooltip: '表格视图',
            onPressed: _navigateToTableView,
          ),
          IconButton(
            icon: Icon(Icons.more_vert),
            tooltip: '更多选项',
            onPressed: _showFilterOptions,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 筛选条件指示器
          _buildFilterIndicator(),
          
          // 统计信息
          if (_returns.isNotEmpty && _hasFilters())
            _buildSummaryCard(),
            
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.assignment_return, color: Colors.red[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '退货记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[800],
                  ),
                ),
                Spacer(),
                Text(
                  '排序: ${_isDescending ? '最新在前' : '最早在前'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  _isDescending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 14,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          Expanded(
            child: _isLoading && _allReturns.isEmpty
                ? Center(child: CircularProgressIndicator())
                : _returns.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_return, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _allReturns.isEmpty ? '暂无退货记录' : '没有符合条件的记录',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _allReturns.isEmpty ? '添加退货记录后会显示在这里' : '请尝试更改筛选条件',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (!_allReturns.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.clear),
                                label: Text('清除筛选条件'),
                                onPressed: _resetFilters,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchData,
            child: ListView.builder(
              itemCount: _returns.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                final returnItem = _returns[index];
                final customer = _customers.firstWhere(
                      (c) => c.id == returnItem.customerId,
                  orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
                );
                final product = _products.firstWhere(
                      (p) => p.name == returnItem.productName,
                  orElse: () => Product(
                    id: -1,
                    userId: -1,
                    name: '',
                    stock: 0,
                    unit: ProductUnit.kilogram,
                    version: 1,
                  ),
                );
                        
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      returnItem.returnDate ?? '未知日期',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '¥ ${returnItem.totalReturnPrice ?? 0.0}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.red[700],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  returnItem.productName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2, 
                                         size: 14, 
                                         color: Colors.green[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '数量: ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      _formatNumber(returnItem.quantity),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.red[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      ' ${product.unit.value}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Icon(Icons.person, 
                                         size: 14, 
                                         color: Colors.orange[700]),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '客户: ${customer.name}',
                                        style: TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (returnItem.note != null && returnItem.note!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Text(
                                          '备注: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.purple,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            returnItem.note ?? '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
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
          FooterWidget(),
        ],
      ),
    );
  }
  
  // 筛选条件指示器
  Widget _buildFilterIndicator() {
    if (!_hasFilters()) {
      return SizedBox.shrink(); // 没有筛选条件，不显示指示器
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red[50],
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selectedProductName != null)
                  Chip(
                    label: Text('产品: $_selectedProductName'),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedProductName = null;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.green[100],
                  ),
                if (_selectedCustomerId != null)
                  Chip(
                    label: Text('客户: ${_customers.firstWhere(
                      (c) => c.id == _selectedCustomerId,
                      orElse: () => Customer(id: -1, userId: -1, name: '未知')
                    ).name}'),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedCustomerId = null;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.orange[100],
                  ),
                if (_startDate != null || _endDate != null)
                  Chip(
                    label: Text(
                      '时间: ${_startDate != null ? _formatDate(_startDate!) : '无限制'} 至 ${_endDate != null ? _formatDate(_endDate!) : '无限制'}'
                    ),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _startDate = null;
                        _endDate = null;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.red[100],
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20),
            tooltip: '清除所有筛选',
            onPressed: _resetFilters,
          ),
        ],
      ),
    );
  }
  
  // 统计摘要卡片
  Widget _buildSummaryCard() {
    final String productUnit = _selectedProductName != null 
        ? (_products.firstWhere(
            (p) => p.name == _selectedProductName,
            orElse: () => Product(id: -1, userId: -1, name: '', unit: ProductUnit.kilogram, stock: 0.0, version: 1)
          ).unit.value)
        : '';
    
    return Card(
      margin: EdgeInsets.all(8),
      color: Colors.red[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '统计信息',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总记录数: ${_returns.length}'),
                Text('总数量: ${_formatNumber(_totalQuantity)} ${_selectedProductName != null ? productUnit : ""}'),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总退款: ¥${_totalPrice.toStringAsFixed(2)}'),
                if (_selectedProductName != null && _totalQuantity > 0)
                  Text('平均单价: ¥${(_totalPrice / _totalQuantity).toStringAsFixed(2)}/${productUnit}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReturnsTableScreen extends StatelessWidget {
  final List<Map<String, dynamic>> returns;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> products;
  final double totalQuantity;
  final double totalPrice;
  final String? selectedProductName;
  final int? selectedCustomerId;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<Customer> allCustomers;

  ReturnsTableScreen({
    required this.returns, 
    required this.customers, 
    required this.products,
    required this.totalQuantity,
    required this.totalPrice,
    this.selectedProductName,
    this.selectedCustomerId,
    this.startDate,
    this.endDate,
    required this.allCustomers,
  });

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

  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportToCSV(BuildContext context) async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    String csvData = '退货统计 - 用户: $username\n';
    csvData += '导出时间: ${DateTime.now().toString().substring(0, 19)}\n';
    
    // 添加筛选信息
    if (selectedProductName != null) {
      csvData += '筛选产品: $selectedProductName\n';
    }
    if (selectedCustomerId != null) {
      final customer = allCustomers.firstWhere(
        (c) => c.id == selectedCustomerId,
        orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      csvData += '筛选客户: ${customer.name}\n';
    }
    if (startDate != null || endDate != null) {
      String dateRange = '日期范围: ';
      if (startDate != null) {
        dateRange += _formatDate(startDate!);
      } else {
        dateRange += '无限制';
      }
      dateRange += ' 至 ';
      if (endDate != null) {
        dateRange += _formatDate(endDate!);
      } else {
        dateRange += '无限制';
      }
      csvData += '$dateRange\n';
    }
    
    csvData += '\n';
    csvData += '日期,产品,数量,单位,客户,总退款,备注\n';
    
    for (var returnItem in returns) {
      final customer = customers.firstWhere(
            (c) => c['id'] == returnItem['customerId'],
        orElse: () => {'name': '未知客户'},
      );
      final product = products.firstWhere(
            (p) => p['name'] == returnItem['productName'],
        orElse: () => {'unit': ''},
      );
      csvData += '${returnItem['returnDate']},${returnItem['productName']},${_formatNumber(returnItem['quantity'])},${product['unit']},${customer['name']},${returnItem['totalReturnPrice']},${returnItem['note'] ?? ''}\n';
    }
    
    // 添加统计信息
    csvData += '\n总计,,,,,\n';
    csvData += '记录数,${returns.length}\n';
    csvData += '总数量,${_formatNumber(totalQuantity)}\n';
    csvData += '总退款,${totalPrice.toStringAsFixed(2)}\n';

    // 生成文件名
    String baseFileName;
    if (selectedProductName != null && selectedCustomerId != null) {
      final customer = allCustomers.firstWhere(
        (c) => c.id == selectedCustomerId,
        orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      baseFileName = '${selectedProductName}_${customer.name}_退货统计';
    } else if (selectedProductName != null) {
      baseFileName = '${selectedProductName}_退货统计';
    } else if (selectedCustomerId != null) {
      final customer = allCustomers.firstWhere(
        (c) => c.id == selectedCustomerId,
        orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      baseFileName = '${customer.name}_退货统计';
    } else {
      baseFileName = '退货统计';
    }

    // 使用统一的导出服务
    await ExportService.showExportOptions(
      context: context,
      csvData: csvData,
      baseFileName: baseFileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('退货统计表格', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            tooltip: '导出 CSV',
            onPressed: () => _exportToCSV(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.red[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.red[700], size: 16),
                SizedBox(width: 8),
          Expanded(
                  child: Text(
                    '横向和纵向滑动可查看完整表格，点击右上角图标可导出CSV/PDF文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 添加统计摘要
          if (returns.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              color: Colors.red[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('记录数', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('${returns.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('总数量', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                              Text('${_formatNumber(totalQuantity)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('总退款', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('¥${totalPrice.toStringAsFixed(2)}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[700])),
                    ],
                  ),
                ],
              ),
            ),
          
          returns.isEmpty 
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无退货数据',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.grey[300],
                          dataTableTheme: DataTableThemeData(
                            headingRowColor: MaterialStateProperty.all(Colors.red[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.red[100]!;
                                return states.contains(MaterialState.hovered)
                                    ? Colors.grey[100]!
                                    : Colors.white;
                              },
                            ),
                          ),
                        ),
              child: DataTable(
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red[800],
                          ),
                          dataTextStyle: TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                          ),
                          horizontalMargin: 16,
                          columnSpacing: 20,
                          showCheckboxColumn: false,
                          dividerThickness: 1,
                columns: [
                  DataColumn(label: Text('日期')),
                  DataColumn(label: Text('产品')),
                  DataColumn(label: Text('数量')),
                  DataColumn(label: Text('单位')),
                  DataColumn(label: Text('客户')),
                            DataColumn(label: Text('总退款')),
                  DataColumn(label: Text('备注')),
                ],
                rows: returns.map((returnItem) {
                  final customer = customers.firstWhere(
                        (c) => c['id'] == returnItem['customerId'],
                    orElse: () => {'name': '未知客户'},
                  );
                  final product = products.firstWhere(
                        (p) => p['name'] == returnItem['productName'],
                    orElse: () => {'unit': ''},
                  );
                            return DataRow(
                              cells: [
                    DataCell(Text(returnItem['returnDate'])),
                    DataCell(Text(returnItem['productName'])),
                    DataCell(
                      Text(
                        _formatNumber(returnItem['quantity']),
                        style: TextStyle(
                          color: Colors.red[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(Text(product['unit'])),
                    DataCell(Text(customer['name'])),
                                DataCell(
                                  Text(
                                    returnItem['totalReturnPrice'].toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red[700],
                                    ),
                                  ),
                                ),
                    DataCell(Text(returnItem['note'] ?? '')),
                              ],
                            );
                }).toList(),
              ),
            ),
          ),
                  ),
                ),
          FooterWidget(),
        ],
      ),
    );
  }
}