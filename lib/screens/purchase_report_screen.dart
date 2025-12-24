// lib/screens/purchase_report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/product_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class PurchaseReportScreen extends StatefulWidget {
  @override
  _PurchaseReportScreenState createState() => _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends State<PurchaseReportScreen> {
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final ProductRepository _productRepo = ProductRepository();
  
  List<Purchase> _allPurchases = []; // 存储所有采购记录
  List<Purchase> _purchases = []; // 存储筛选后的采购记录
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  bool _isDescending = true; // 默认按时间倒序排列
  bool _isLoading = false;
  
  // 筛选条件
  String? _selectedProductName;
  int? _selectedSupplierId;
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
      _isDescending = prefs.getBool('purchases_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('purchases_sort_descending', _isDescending);
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 并行获取所有数据
      final results = await Future.wait([
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _supplierRepo.getAllSuppliers(),
        _productRepo.getProducts(page: 1, pageSize: 10000),
      ]);
      
      final purchasesResponse = results[0] as PaginatedResponse<Purchase>;
      final suppliers = results[1] as List<Supplier>;
      final productsResponse = results[2] as PaginatedResponse<Product>;
      
      // 按日期排序
      List<Purchase> purchases = purchasesResponse.items;
      purchases.sort((a, b) {
        final dateA = a.purchaseDate != null ? DateTime.parse(a.purchaseDate!) : DateTime(1970);
        final dateB = b.purchaseDate != null ? DateTime.parse(b.purchaseDate!) : DateTime(1970);
        return _isDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });
      
        setState(() {
          _allPurchases = purchases;
          _suppliers = suppliers;
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
    List<Purchase> filteredPurchases = List.from(_allPurchases);
    
    // 按产品名称筛选
    if (_selectedProductName != null) {
      filteredPurchases = filteredPurchases.where(
        (purchase) => purchase.productName == _selectedProductName
      ).toList();
    }
    
    // 按供应商筛选
    if (_selectedSupplierId != null) {
      filteredPurchases = filteredPurchases.where(
        (purchase) => purchase.supplierId == _selectedSupplierId
      ).toList();
    }
    
    // 按日期范围筛选
    if (_startDate != null) {
      filteredPurchases = filteredPurchases.where((purchase) {
        if (purchase.purchaseDate == null) return false;
        final purchaseDate = DateTime.parse(purchase.purchaseDate!);
        return purchaseDate.isAfter(_startDate!) || 
               purchaseDate.isAtSameMomentAs(_startDate!);
      }).toList();
    }
    
    if (_endDate != null) {
      final endDatePlusOne = _endDate!.add(Duration(days: 1)); // 包含结束日期
      filteredPurchases = filteredPurchases.where((purchase) {
        if (purchase.purchaseDate == null) return false;
        final purchaseDate = DateTime.parse(purchase.purchaseDate!);
        return purchaseDate.isBefore(endDatePlusOne);
      }).toList();
    }
    
    // 计算总量和总进价
    _calculateTotals(filteredPurchases);
    
    setState(() {
      _purchases = filteredPurchases;
    });
  }
  
  // 计算总量和总进价
  void _calculateTotals(List<Purchase> filteredPurchases) {
    double totalQuantity = 0.0;
    double totalPrice = 0.0;
    
    for (var purchase in filteredPurchases) {
      totalQuantity += purchase.quantity;
      totalPrice += purchase.totalPurchasePrice ?? 0.0;
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
      _selectedSupplierId = null;
      _startDate = null;
      _endDate = null;
      _purchases = _allPurchases;
      _calculateTotals(_purchases);
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
        builder: (context) => PurchaseTableScreen(
          purchases: _purchases.map((p) => p.toJson()).toList(),
          suppliers: _suppliers.map((s) => s.toJson()).toList(),
          products: _products.map((p) => p.toJson()).toList(),
          totalQuantity: _totalQuantity,
          totalPrice: _totalPrice,
          selectedProductName: _selectedProductName,
          selectedSupplierId: _selectedSupplierId,
          startDate: _startDate,
          endDate: _endDate,
          allSuppliers: _suppliers,
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
                leading: Icon(Icons.business, color: Colors.orange),
                title: Text('按供应商筛选'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _showSupplierSelectionDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.date_range, color: Colors.blue),
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
           _selectedSupplierId != null || 
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
  
  // 选择供应商对话框
  Future<void> _showSupplierSelectionDialog() async {
    // 创建选项列表：第一个是"所有供应商"，后面是所有供应商
    final List<MapEntry<int?, String>> supplierOptions = [
      MapEntry<int?, String>(null, '所有供应商'),
      ..._suppliers.map((s) => MapEntry<int?, String>(s.id, s.name)),
    ];
    
    // 找到当前选中项的索引
    int currentIndex = supplierOptions.indexWhere((entry) => entry.key == _selectedSupplierId);
    if (currentIndex < 0) {
      currentIndex = 0; // 默认选中"所有供应商"
    }
    
    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择供应商'),
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
                        children: supplierOptions
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

    if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < supplierOptions.length) {
      final selectedEntry = supplierOptions[selectedIndex];
      if (selectedEntry.key != _selectedSupplierId) {
        setState(() {
          _selectedSupplierId = selectedEntry.key;
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
              primary: Colors.green,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('采购统计', style: TextStyle(
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
          if (_purchases.isNotEmpty && _hasFilters())
            _buildSummaryCard(),
            
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.date_range, color: Colors.green[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '采购记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
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
            child: _isLoading && _allPurchases.isEmpty
                ? Center(child: CircularProgressIndicator())
                : _purchases.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assessment, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _allPurchases.isEmpty ? '暂无采购记录' : '没有符合条件的记录',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _allPurchases.isEmpty ? '添加采购记录后会显示在这里' : '请尝试更改筛选条件',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (!_allPurchases.isEmpty)
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
              itemCount: _purchases.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                final purchase = _purchases[index];
                final supplier = _suppliers.firstWhere(
                      (s) => s.id == purchase.supplierId,
                  orElse: () => Supplier(id: -1, userId: -1, name: '未知供应商'),
                );
                final product = _products.firstWhere(
                      (p) => p.name == purchase.productName,
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
                                      purchase.purchaseDate ?? '未知日期',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '${(-(purchase.totalPurchasePrice ?? 0.0)) >= 0 ? '+' : '-'}¥${(-(purchase.totalPurchasePrice ?? 0.0)).abs().toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: (-(purchase.totalPurchasePrice ?? 0.0)) >= 0 ? Colors.red[700] : Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    // 添加采购/退货标识
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: purchase.quantity >= 0 ? Colors.green[100] : Colors.red[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        purchase.quantity >= 0 ? '采购' : '退货',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: purchase.quantity >= 0 ? Colors.green[800] : Colors.red[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                  purchase.productName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                      ),
                                    ),
                                  ],
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
                                      '${purchase.quantity >= 0 ? '+' : '-'}${_formatNumber(purchase.quantity.abs())}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: purchase.quantity >= 0 ? Colors.green[700] : Colors.red[700],
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
                                    Icon(Icons.business, 
                                         size: 14, 
                                         color: Colors.orange[700]),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '供应商: ${supplier.name}',
                                        style: TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (purchase.note != null && purchase.note!.isNotEmpty)
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
                                            purchase.note ?? '',
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
      color: Colors.blue[50],
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
                if (_selectedSupplierId != null)
                  Chip(
                    label: Text('供应商: ${_suppliers.firstWhere(
                      (s) => s.id == _selectedSupplierId,
                      orElse: () => Supplier(id: -1, userId: -1, name: '未知')
                    ).name}'),
                    deleteIcon: Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedSupplierId = null;
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
                    backgroundColor: Colors.blue[100],
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
      color: Colors.green[50],
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
                color: Colors.green[800],
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('总记录数: ${_purchases.length}'),
                Text(
                  '净数量: ${_totalQuantity >= 0 ? '+' : ''}${_formatNumber(_totalQuantity)} ${_selectedProductName != null ? productUnit : ""}',
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '总采购额: ${(-_totalPrice) >= 0 ? '+' : '-'}¥${(-_totalPrice).abs().toStringAsFixed(2)}',
                ),
                if (_selectedProductName != null && _totalQuantity != 0)
                  Text('平均单价: ¥${(_totalPrice / _totalQuantity).abs().toStringAsFixed(2)}/${productUnit}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
}

class PurchaseTableScreen extends StatelessWidget {
  final List<Map<String, dynamic>> purchases;
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> products;
  final double totalQuantity;
  final double totalPrice;
  final String? selectedProductName;
  final int? selectedSupplierId;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<Supplier> allSuppliers;

  PurchaseTableScreen({
    required this.purchases,
    required this.suppliers,
    required this.products,
    required this.totalQuantity,
    required this.totalPrice,
    this.selectedProductName,
    this.selectedSupplierId,
    this.startDate,
    this.endDate,
    required this.allSuppliers,
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
    
    String csvData = '采购统计 - 用户: $username\n';
    csvData += '导出时间: ${DateTime.now().toString().substring(0, 19)}\n';
    
    // 添加筛选信息
    if (selectedProductName != null) {
      csvData += '筛选产品: $selectedProductName\n';
    }
    if (selectedSupplierId != null) {
      final supplier = allSuppliers.firstWhere(
        (s) => s.id == selectedSupplierId,
        orElse: () => Supplier(id: -1, userId: -1, name: '未知供应商'),
      );
      csvData += '筛选供应商: ${supplier.name}\n';
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
    csvData += '日期,类型,产品,数量,单位,供应商,总进价,备注\n';
    for (var purchase in purchases) {
      final supplier = suppliers.firstWhere(
            (s) => s['id'] == purchase['supplierId'],
        orElse: () => {'name': '未知供应商'},
      );
      final product = products.firstWhere(
            (p) => p['name'] == purchase['productName'],
        orElse: () => {'unit': ''},
      );
      final type = (purchase['quantity'] as double) >= 0 ? '采购' : '退货';
      final quantity = (purchase['quantity'] as double) >= 0 ? _formatNumber(purchase['quantity']) : '-${_formatNumber((purchase['quantity'] as double).abs())}';
      csvData += '${purchase['purchaseDate']},$type,${purchase['productName']},$quantity,${product['unit']},${supplier['name']},${purchase['totalPurchasePrice']},${purchase['note'] ?? ''}\n';
    }
    
    // 添加统计信息
    csvData += '\n总计,,,,,,\n';
    csvData += '记录数,${purchases.length}\n';
    csvData += '净数量,${_formatNumber(totalQuantity)}\n';
    csvData += '总进价,${totalPrice.toStringAsFixed(2)}\n';

    // 生成文件名
    String baseFileName;
    if (selectedProductName != null && selectedSupplierId != null) {
      final supplier = allSuppliers.firstWhere(
        (s) => s.id == selectedSupplierId,
        orElse: () => Supplier(id: -1, userId: -1, name: '未知供应商'),
      );
      baseFileName = '${selectedProductName}_${supplier.name}_采购统计';
    } else if (selectedProductName != null) {
      baseFileName = '${selectedProductName}_采购统计';
    } else if (selectedSupplierId != null) {
      final supplier = allSuppliers.firstWhere(
        (s) => s.id == selectedSupplierId,
        orElse: () => Supplier(id: -1, userId: -1, name: '未知供应商'),
      );
      baseFileName = '${supplier.name}_采购统计';
    } else {
      baseFileName = '采购统计';
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
        title: Text('采购统计表格', style: TextStyle(
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
            color: Colors.green[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green[700], size: 16),
                SizedBox(width: 8),
          Expanded(
                  child: Text(
                    '横向和纵向滑动可查看完整表格，点击右上角图标可导出CSV/PDF文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 添加统计摘要
          if (purchases.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              color: Colors.green[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('记录数', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('${purchases.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                        Text('净数量', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                        Text(
                          '${totalQuantity >= 0 ? '+' : '-'}${_formatNumber(totalQuantity.abs())}', 
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold,
                            color: totalQuantity >= 0 ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                    ],
                  ),
                  Column(
                    children: [
                      Text('总采购额', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      Text('${(-totalPrice) >= 0 ? '+' : '-'}¥${(-totalPrice).abs().toStringAsFixed(2)}', 
                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: (-totalPrice) >= 0 ? Colors.red[700] : Colors.green[700])),
                    ],
                  ),
                ],
              ),
            ),
          
          purchases.isEmpty 
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '暂无采购数据',
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
                            headingRowColor: MaterialStateProperty.all(Colors.green[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.green[100]!;
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
                            color: Colors.green[800],
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
                  DataColumn(label: Text('供应商')),
                  DataColumn(label: Text('金额')),
                  DataColumn(label: Text('备注')),
                ],
                rows: purchases.map((purchase) {
                  final supplier = suppliers.firstWhere(
                        (s) => s['id'] == purchase['supplierId'],
                    orElse: () => {'name': '未知供应商'},
                  );
                  final product = products.firstWhere(
                        (p) => p['name'] == purchase['productName'],
                    orElse: () => {'unit': ''},
                  );
                            return DataRow(
                              cells: [
                    DataCell(Text(purchase['purchaseDate'])),
                    DataCell(
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (purchase['quantity'] as double) >= 0 ? Colors.green[100] : Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (purchase['quantity'] as double) >= 0 ? '采购' : '退货',
                          style: TextStyle(
                            fontSize: 10,
                            color: (purchase['quantity'] as double) >= 0 ? Colors.green[800] : Colors.red[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(purchase['productName'])),
                    DataCell(
                      Text(
                        '${(purchase['quantity'] as double) >= 0 ? '' : '-'}${_formatNumber((purchase['quantity'] as double).abs())}',
                        style: TextStyle(
                          color: (purchase['quantity'] as double) >= 0 ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(Text(product['unit'])),
                    DataCell(Text(supplier['name'])),
                                DataCell(
                                  Text(
                                    '${(-(purchase['totalPurchasePrice'] as num).toDouble()) >= 0 ? '+' : '-'}¥${(-(purchase['totalPurchasePrice'] as num).toDouble()).abs().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: (-(purchase['totalPurchasePrice'] as num).toDouble()) >= 0 ? Colors.red[700] : Colors.green[700],
                                    ),
                                  ),
                                ),
                    DataCell(Text(purchase['note'] ?? '')),
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