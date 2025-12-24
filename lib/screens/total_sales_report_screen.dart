import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/product_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class TotalSalesReportScreen extends StatefulWidget {
  @override
  _TotalSalesReportScreenState createState() => _TotalSalesReportScreenState();
}

class _TotalSalesReportScreenState extends State<TotalSalesReportScreen> {
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final ProductRepository _productRepo = ProductRepository();
  
  List<Map<String, dynamic>> _allCombinedRecords = []; // 存储所有合并记录
  List<Map<String, dynamic>> _combinedRecords = []; // 存储筛选后的合并记录
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
      _isDescending = prefs.getBool('total_sales_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('total_sales_sort_descending', _isDescending);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 并行获取所有数据
      final results = await Future.wait([
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _customerRepo.getAllCustomers(),
        _productRepo.getProducts(page: 1, pageSize: 10000),
      ]);
      
      final salesResponse = results[0] as PaginatedResponse<Sale>;
      final returnsResponse = results[1] as PaginatedResponse<Return>;
      final customers = results[2] as List<Customer>;
      final productsResponse = results[3] as PaginatedResponse<Product>;

    // 合并销售和退货数据
    List<Map<String, dynamic>> combinedRecords = [];
    
    // 添加销售数据（正值）
      for (var sale in salesResponse.items) {
      combinedRecords.add({
          'date': sale.saleDate,
          'productName': sale.productName,
          'quantity': sale.quantity,
          'customerId': sale.customerId,
          'totalPrice': sale.totalSalePrice,
          'note': sale.note,
        'type': '销售',
        'value': 1 // 正值标记
      });
    }
    
    // 添加退货数据（负值）
      for (var returnItem in returnsResponse.items) {
      combinedRecords.add({
          'date': returnItem.returnDate,
          'productName': returnItem.productName,
          'quantity': returnItem.quantity,
          'customerId': returnItem.customerId,
          'totalPrice': returnItem.totalReturnPrice,
          'note': returnItem.note,
        'type': '退货',
        'value': -1 // 负值标记
      });
    }

    // 按日期排序
    combinedRecords.sort((a, b) {
        final dateA = a['date'] != null ? DateTime.parse(a['date']) : DateTime(1970);
        final dateB = b['date'] != null ? DateTime.parse(b['date']) : DateTime(1970);
        return _isDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

        setState(() {
          _allCombinedRecords = combinedRecords;
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
    List<Map<String, dynamic>> filteredRecords = List.from(_allCombinedRecords);
    
    // 按产品名称筛选
    if (_selectedProductName != null) {
      filteredRecords = filteredRecords.where(
        (record) => record['productName'] == _selectedProductName
      ).toList();
    }
    
    // 按客户筛选
    if (_selectedCustomerId != null) {
      filteredRecords = filteredRecords.where(
        (record) => record['customerId'] == _selectedCustomerId
      ).toList();
    }
    
    // 按日期范围筛选
    if (_startDate != null) {
      filteredRecords = filteredRecords.where((record) {
        final recordDate = DateTime.parse(record['date']);
        return recordDate.isAfter(_startDate!) || 
               recordDate.isAtSameMomentAs(_startDate!);
      }).toList();
    }
    
    if (_endDate != null) {
      final endDatePlusOne = _endDate!.add(Duration(days: 1)); // 包含结束日期
      filteredRecords = filteredRecords.where((record) {
        final recordDate = DateTime.parse(record['date']);
        return recordDate.isBefore(endDatePlusOne);
      }).toList();
    }
    
    // 计算总量和总金额
    _calculateTotals(filteredRecords);
    
    setState(() {
      _combinedRecords = filteredRecords;
    });
  }
  
  // 计算总量和总金额
  void _calculateTotals(List<Map<String, dynamic>> filteredRecords) {
    double totalQuantity = 0.0;
    double totalPrice = 0.0;
    
    for (var record in filteredRecords) {
      // 净销量口径：
      // - 销售：库存减少 → 计为负数（取相反数）
      // - 退货：库存增加 → 计为正数（不取反）
      if (record['type'] == '销售') {
        totalQuantity -= (record['quantity'] as num).toDouble();
        totalPrice += (record['totalPrice'] as num).toDouble();
      } else {
        totalQuantity += (record['quantity'] as num).toDouble();
        totalPrice -= (record['totalPrice'] as num).toDouble();
      }
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
      _combinedRecords = _allCombinedRecords;
      _calculateTotals(_combinedRecords);
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
        builder: (context) => TotalSalesTableScreen(
          records: _combinedRecords,
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
                  leading: Icon(Icons.date_range, color: Colors.purple),
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
              primary: Colors.purple,
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
        title: Text('销售汇总', style: TextStyle(
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
          if (_combinedRecords.isNotEmpty && _hasFilters())
            _buildSummaryCard(),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.assessment, color: Colors.purple[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '销售与退货综合记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[800],
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
            child: _isLoading && _allCombinedRecords.isEmpty
                ? Center(child: CircularProgressIndicator())
                : _combinedRecords.isEmpty
                    ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assessment, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          _allCombinedRecords.isEmpty ? '暂无交易记录' : '没有符合条件的记录',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _allCombinedRecords.isEmpty ? '添加销售或退货记录后会显示在这里' : '请尝试更改筛选条件',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (!_allCombinedRecords.isEmpty)
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
                    itemCount: _combinedRecords.length,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemBuilder: (context, index) {
                      final record = _combinedRecords[index];
                      final customer = _customers.firstWhere(
                        (c) => c.id == record['customerId'],
                        orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
                      );
                      final product = _products.firstWhere(
                        (p) => p.name == record['productName'],
                        orElse: () => Product(
                          id: -1,
                          userId: -1,
                          name: '',
                          stock: 0,
                          unit: ProductUnit.kilogram,
                          version: 1,
                        ),
                      );
                      
                      // 设置颜色，销售为绿色，退货为红色
                      Color textColor = record['type'] == '销售' ? Colors.green : Colors.red;
                      
                      // 根据类型决定金额正负
                      double priceValue = (record['totalPrice'] as num).toDouble();
                      String amount = record['type'] == '销售' 
                          ? '+¥${priceValue.toStringAsFixed(2)}' 
                          : '-¥${priceValue.toStringAsFixed(2)}';
                      
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
                                  Row(
                                    children: [
                                      Text(
                                        record['date'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: record['type'] == '销售' 
                                              ? Colors.green[50] 
                                              : Colors.red[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: record['type'] == '销售' 
                                                ? Colors.green[300]! 
                                                : Colors.red[300]!,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          record['type'],
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    amount,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                record['productName'],
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
                                       color: Colors.blue[700]),
                                  SizedBox(width: 4),
                                  Text(
                                    '数量: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    () {
                                      final double q = (record['quantity'] as num).toDouble();
                                      if (record['type'] == '销售') {
                                        // 销售显示为负数
                                        return '-${_formatNumber(q.abs())}';
                                      }
                                      // 退货显示原值；若为正数则加 +
                                      return '${q >= 0 ? '+' : '-'}${_formatNumber(q.abs())}';
                                    }(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: record['type'] == '销售' ? Colors.green[700] : Colors.red[700],
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
                              if (record['note'] != null && record['note'].toString().isNotEmpty)
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
                                          record['note'].toString(),
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
      color: Colors.purple[50],
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
                    backgroundColor: Colors.purple[100],
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

    final String priceSign = _totalPrice >= 0 ? '+' : '-';
    
    final String quantitySign = _totalQuantity >= 0 ? '+' : '';
    
    return Card(
      margin: EdgeInsets.all(8),
      color: Colors.purple[50],
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
                color: Colors.purple[800],
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总记录数: ${_combinedRecords.length}'),
                Text(
                  '净销量: $quantitySign${_formatNumber(_totalQuantity)} ${_selectedProductName != null ? productUnit : ""}',
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '净销售额: $priceSign¥${_totalPrice.abs().toStringAsFixed(2)}',
                ),
                if (_selectedProductName != null && _totalQuantity != 0 && _totalPrice != 0)
                  Text('平均单价: ¥${(_totalPrice / _totalQuantity).abs().toStringAsFixed(2)}/${productUnit}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TotalSalesTableScreen extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> products;
  final double totalQuantity;
  final double totalPrice;
  final String? selectedProductName;
  final int? selectedCustomerId;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<Customer> allCustomers;

  TotalSalesTableScreen({
    required this.records,
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
    
    String csvData = '销售汇总 - 用户: $username\n';
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
    csvData += '日期,类型,产品,数量,单位,客户,总金额,备注\n';
    for (var record in records) {
      final customer = customers.firstWhere(
        (c) => c['id'] == record['customerId'],
        orElse: () => {'name': '未知客户', 'id': -1},
      );
      final product = products.firstWhere(
        (p) => p['name'] == record['productName'],
        orElse: () => {'unit': '', 'name': ''},
      );
      
      // 根据类型决定金额正负
      String amount = record['type'] == '销售' 
          ? record['totalPrice'].toString() 
          : '-${record['totalPrice']}';
      
      // 数量显示口径同页面：
      // 销售：显示为负数；退货：显示原值（正数带 +）
      final double q = (record['quantity'] as num).toDouble();
      String quantity = record['type'] == '销售'
          ? '-${_formatNumber(q.abs())}'
          : '${q >= 0 ? '+' : '-'}${_formatNumber(q.abs())}';
      
      csvData += '${record['date']},${record['type']},${record['productName']},$quantity,${product['unit']},${customer['name']},$amount,${record['note'] ?? ''}\n';
    }
    
    // 添加统计信息
    csvData += '\n总计,,,,,\n';
    csvData += '记录数,${records.length}\n';
    csvData += '净销量,${_formatNumber(totalQuantity)}\n';
    csvData += '净销售额,${totalPrice.toStringAsFixed(2)}\n';

    // 生成文件名
    String baseFileName;
    if (selectedProductName != null && selectedCustomerId != null) {
      final customer = allCustomers.firstWhere(
        (c) => c.id == selectedCustomerId,
        orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      baseFileName = '${selectedProductName}_${customer.name}_销售汇总';
    } else if (selectedProductName != null) {
      baseFileName = '${selectedProductName}_销售汇总';
    } else if (selectedCustomerId != null) {
      final customer = allCustomers.firstWhere(
        (c) => c.id == selectedCustomerId,
        orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      baseFileName = '${customer.name}_销售汇总';
    } else {
      baseFileName = '销售汇总';
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
    // 处理正负符号和颜色
    // 净销量：负数(销售更多)为绿；正数(退货更多)为红；显示必须带正负号
    final String quantitySign = totalQuantity >= 0 ? '+' : '-';
    final Color quantityColor = totalQuantity < 0 ? Colors.green : Colors.red;
    final String priceSign = totalPrice >= 0 ? '+' : '-';
    final Color priceColor = totalPrice >= 0 ? Colors.green : Colors.red;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('销售汇总表格', style: TextStyle(
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
            color: Colors.purple[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.purple[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '横向和纵向滑动可查看完整表格，点击右上角图标可导出CSV/PDF文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 添加统计摘要
          if (records.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              color: Colors.purple[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('记录数', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('${records.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('净销量', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('$quantitySign${_formatNumber(totalQuantity.abs())}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: quantityColor)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('净销售额', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('$priceSign¥${totalPrice.abs().toStringAsFixed(2)}',
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: priceColor)),
                    ],
                  ),
                ],
              ),
            ),
          
          records.isEmpty 
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无交易数据',
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
                            headingRowColor: MaterialStateProperty.all(Colors.purple[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.purple[100]!;
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
                            color: Colors.purple[800],
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
                            DataColumn(label: Text('类型')),
                            DataColumn(label: Text('产品')),
                            DataColumn(label: Text('数量')),
                            DataColumn(label: Text('单位')),
                            DataColumn(label: Text('客户')),
                            DataColumn(label: Text('金额')),
                            DataColumn(label: Text('备注')),
                          ],
                          rows: records.map((record) {
                            final customer = customers.firstWhere(
                              (c) => c['id'] == record['customerId'],
                              orElse: () => {'name': '未知客户'},
                            );
                            final product = products.firstWhere(
                              (p) => p['name'] == record['productName'],
                              orElse: () => {'unit': ''},
                            );
                            
                            // 设置颜色，销售为绿色，退货为红色
                            Color textColor = record['type'] == '销售' ? Colors.green : Colors.red;
                            
                            // 根据类型决定金额正负
                            double priceValue = (record['totalPrice'] as num).toDouble();
                            String amount = record['type'] == '销售' 
                                ? '+¥${priceValue.toStringAsFixed(2)}' 
                                : '-¥${priceValue.toStringAsFixed(2)}';
                            
                            // 根据类型决定数量正负
                            final double q = (record['quantity'] as num).toDouble();
                            String quantity = record['type'] == '销售'
                                ? '-${_formatNumber(q.abs())}'
                                : '${q >= 0 ? '+' : '-'}${_formatNumber(q.abs())}';
                            
                            return DataRow(
                              cells: [
                                DataCell(Text(record['date'])),
                                DataCell(
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: record['type'] == '销售' 
                                          ? Colors.green[50] 
                                          : Colors.red[50],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: record['type'] == '销售' 
                                            ? Colors.green[300]! 
                                            : Colors.red[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      record['type'],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(record['productName'])),
                                DataCell(
                                  Text(
                                    quantity,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                ),
                                DataCell(Text(product['unit'])),
                                DataCell(Text(customer['name'])),
                                DataCell(
                                  Text(
                                    amount,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataCell(Text(record['note'] ?? '')),
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