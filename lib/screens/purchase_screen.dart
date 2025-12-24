// lib/screens/purchase_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/footer_widget.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';

class PurchaseScreen extends StatefulWidget {
  @override
  _PurchaseScreenState createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final ProductRepository _productRepo = ProductRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  
  List<Purchase> _purchases = [];
  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;
  
  // 添加搜索相关的状态变量
  List<Purchase> _filteredPurchases = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedProductFilter;
  String? _selectedSupplierFilter;
  DateTimeRange? _selectedDateRange;
  final ValueNotifier<List<String>> _activeFilters = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _fetchData();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterPurchases();
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _activeFilters.dispose();
    super.dispose();
  }

  // 格式化数字显示，如果是整数则不显示小数点，如果是小数则显示小数部分
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }

  // 重置所有过滤条件
  void _resetFilters() {
    setState(() {
      _selectedProductFilter = null;
      _selectedSupplierFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredPurchases = List.from(_purchases);
      _isSearching = false;
      _showAdvancedSearch = false;
    });
  }

  // 更新搜索条件并显示活跃的过滤条件
  void _updateActiveFilters() {
    List<String> filters = [];
    
    if (_selectedProductFilter != null) {
      filters.add('产品: $_selectedProductFilter');
    }
    
    if (_selectedSupplierFilter != null) {
      filters.add('供应商: $_selectedSupplierFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 添加过滤采购记录的方法 - 增强版
  void _filterPurchases() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      List<Purchase> result = List.from(_purchases);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((purchase) {
          final productName = purchase.productName.toLowerCase();
          final supplier = _suppliers.firstWhere(
            (s) => s.id == purchase.supplierId,
            orElse: () => Supplier(id: -1, userId: 0, name: ''),
          );
          final supplierName = supplier.name.toLowerCase();
          final date = (purchase.purchaseDate ?? '').toLowerCase();
          final note = (purchase.note ?? '').toLowerCase();
          final quantity = purchase.quantity.toString().toLowerCase();
          final price = (purchase.totalPurchasePrice ?? 0).toString().toLowerCase();
          
          return searchTerms.every((term) =>
            productName.contains(term) ||
            supplierName.contains(term) ||
            date.contains(term) ||
            note.contains(term) ||
            quantity.contains(term) ||
            price.contains(term)
          );
        }).toList();
      }
      
      // 产品筛选
      if (_selectedProductFilter != null) {
        hasFilters = true;
        result = result.where((purchase) => 
          purchase.productName == _selectedProductFilter).toList();
      }
      
      // 供应商筛选
      if (_selectedSupplierFilter != null) {
        hasFilters = true;
        final selectedSupplier = _suppliers.firstWhere(
          (s) => s.name == _selectedSupplierFilter,
          orElse: () => Supplier(id: -1, userId: 0, name: ''),
        );
        
        result = result.where((purchase) => 
          purchase.supplierId == selectedSupplier.id).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((purchase) {
          if (purchase.purchaseDate == null) return false;
          final purchaseDate = DateTime.parse(purchase.purchaseDate!);
          return purchaseDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 purchaseDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredPurchases = result;
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
      // 并行获取所有数据
      final results = await Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 1000),
        _supplierRepo.getAllSuppliers(),
        _purchaseRepo.getPurchases(page: 1, pageSize: 1000),
      ]);
      
      final productsResponse = results[0] as PaginatedResponse<Product>;
      final suppliers = results[1] as List<Supplier>;
      final purchasesResponse = results[2] as PaginatedResponse<Purchase>;
        
        setState(() {
          _products = productsResponse.items;
          _suppliers = suppliers;
          _purchases = purchasesResponse.items;
        _filteredPurchases = purchasesResponse.items;
        _isLoading = false;
        });
        
        // 刷新后重新应用过滤条件
        if (isRefresh) {
          _filterPurchases();
        }
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取数据失败: ${e.message}');
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

  Future<void> _addPurchase() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PurchaseDialog(products: _products, suppliers: _suppliers),
    );
    if (result != null) {
      try {
        final purchaseCreate = PurchaseCreate(
          productName: result['productName'] as String,
          quantity: result['quantity'] as double,
          purchaseDate: result['purchaseDate'] as String?,
          supplierId: result['supplierId'] as int?,
          totalPurchasePrice: result['totalPurchasePrice'] as double?,
          note: result['note'] as String?,
        );
        
        await _purchaseRepo.createPurchase(purchaseCreate);
        _fetchData();
      
        if (mounted) {
          context.showSuccessSnackBar('采购记录添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          String errorMessage = e.message;
          if (e.statusCode == 400 && e.message.contains('库存不足')) {
            errorMessage = e.message;
          }
          _showErrorDialog(errorMessage);
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('添加采购记录失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editPurchase(Purchase purchase) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PurchaseDialog(
        products: _products,
        suppliers: _suppliers,
        existingPurchase: purchase,
      ),
    );
    
    if (result != null) {
      try {
        final purchaseUpdate = PurchaseUpdate(
          productName: result['productName'] as String,
          quantity: result['quantity'] as double,
          purchaseDate: result['purchaseDate'] as String?,
          supplierId: result['supplierId'] as int?,
          totalPurchasePrice: result['totalPurchasePrice'] as double?,
          note: result['note'] as String?,
        );
        
        await _purchaseRepo.updatePurchase(purchase.id, purchaseUpdate);
          _fetchData();
        
        if (mounted) {
          context.showSuccessSnackBar('采购记录更新成功');
    }
      } on ApiError catch (e) {
        if (mounted) {
          String errorMessage = e.message;
          if (e.statusCode == 409) {
            errorMessage = '产品库存已被其他操作修改，请刷新后重试';
            _fetchData(); // 刷新数据
          } else if (e.statusCode == 400 && e.message.contains('库存不足')) {
            errorMessage = e.message;
          }
          _showErrorDialog(errorMessage);
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('更新采购记录失败: ${e.toString()}');
        }
      }
    }
  }

  void _showNoteDialog(Purchase purchase) {
    final _noteController = TextEditingController(text: purchase.note);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('备注'),
        content: TextField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: '编辑备注',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          maxLines: null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  try {
                    final purchaseUpdate = PurchaseUpdate(
                      note: _noteController.text.isEmpty ? null : _noteController.text,
                    );
                    await _purchaseRepo.updatePurchase(purchase.id, purchaseUpdate);
                      Navigator.of(context).pop();
                    _fetchData();
                  } on ApiError catch (e) {
                    if (mounted) {
                      context.showErrorSnackBar('更新备注失败: ${e.message}');
                    }
                  } catch (e) {
                    if (mounted) {
                      context.showErrorSnackBar('更新备注失败: ${e.toString()}');
                    }
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
      ),
    );
  }

  Future<void> _deletePurchase(Purchase purchase) async {
    final supplier = _suppliers.firstWhere(
      (s) => s.id == purchase.supplierId,
      orElse: () => Supplier(id: -1, userId: 0, name: '未知供应商'),
    );
    final product = _products.firstWhere(
      (p) => p.name == purchase.productName,
      orElse: () => Product(
        id: -1,
        userId: 0,
        name: '',
        stock: 0,
        unit: ProductUnit.kilogram,
        version: 1,
      ),
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text(
          '您确定要删除以下采购记录吗？\n\n'
              '产品名称: ${purchase.productName}\n'
              '数量: ${_formatNumber(purchase.quantity)} ${product.unit.value}\n'
              '供应商: ${supplier.name}\n'
              '日期: ${purchase.purchaseDate ?? '未知'}',
        ),
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
        await _purchaseRepo.deletePurchase(purchase.id);
        _fetchData();
        
        if (mounted) {
          context.showSuccessSnackBar('采购记录删除成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          String errorMessage = e.message;
          if (e.statusCode == 409) {
            errorMessage = '产品库存已被其他操作修改，请刷新后重试';
            _fetchData(); // 刷新数据
          }
          _showErrorDialog(errorMessage);
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('删除采购记录失败: ${e.toString()}');
        }
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('错误'),
        content: Text(message),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  // 显示高级搜索对话框
  void _showAdvancedSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,  // 添加此行以支持更大的高度
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(  // 添加滚动视图
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
                    
                    // 产品筛选
                    Text('按产品筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedProductFilter,
                        hint: Text('选择产品'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部产品'),
                          ),
                          ..._products.map((product) => DropdownMenuItem<String?>(
                            value: product.name,
                            child: Text(product.name),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedProductFilter = value;
                          });
                        },
                      ),
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
                                  primary: Colors.green,
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
                    Padding(  // 添加底部内边距
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,  // 设定按钮高度
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _filterPurchases();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
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
          title: Text('采购', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
        actions: [
          IconButton(
            icon: Icon(_showDeleteButtons ? Icons.cancel : Icons.delete),
              tooltip: _showDeleteButtons ? '取消' : '显示删除按钮',
            onPressed: () {
              setState(() {
                _showDeleteButtons = !_showDeleteButtons;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
              child: _isLoading && _purchases.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _fetchData(isRefresh: true),
                      child: _filteredPurchases.isEmpty
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
                              Icon(Icons.shopping_cart, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                _isSearching ? '没有匹配的采购记录' : '暂无采购记录',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 8),
                              Text(
                                _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加采购记录',
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
                      itemCount: _filteredPurchases.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final purchase = _filteredPurchases[index];
                final supplier = _suppliers.firstWhere(
                      (s) => s.id == purchase.supplierId,
                  orElse: () => Supplier(id: -1, userId: 0, name: '未知供应商'),
                );
                final product = _products.firstWhere(
                      (p) => p.name == purchase.productName,
                  orElse: () => Product(
                    id: -1,
                    userId: 0,
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
                            padding: EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
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
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          purchase.purchaseDate ?? '未知日期',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.edit, color: Colors.orange),
                                              tooltip: '编辑',
                                              onPressed: () => _editPurchase(purchase),
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(),
                                              iconSize: 18,
                                            ),
                                            if (_showDeleteButtons)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8),
                                                child: IconButton(
                                                  icon: Icon(Icons.delete, color: Colors.red),
                                                  tooltip: '删除',
                                                  onPressed: () => _deletePurchase(purchase),
                                                  padding: EdgeInsets.zero,
                                                  constraints: BoxConstraints(),
                                                  iconSize: 18,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.business, 
                                         size: 14, 
                                         color: Colors.blue[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '供应商: ${supplier.name}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2, 
                                         size: 14, 
                                         color: purchase.quantity >= 0 ? Colors.green[700] : Colors.red[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '数量: ${purchase.quantity >= 0 ? '' : '-'}${_formatNumber(purchase.quantity.abs())} ${product.unit.value}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.attach_money, 
                                         size: 14, 
                                         color: Colors.amber[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '总进价: ${purchase.totalPurchasePrice ?? 0}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                if (purchase.note != null && purchase.note!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      children: [
                                        Icon(Icons.note, 
                                             size: 14, 
                                             color: Colors.purple),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '备注: ${purchase.note}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(height: 4),
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
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[100]!)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.filter_list, size: 16, color: Colors.green),
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
                                        backgroundColor: Colors.green[100],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.clear, size: 16, color: Colors.green),
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
                            hintText: '搜索采购记录...',
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
                              borderSide: BorderSide(color: Colors.green),
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
                          color: _showAdvancedSearch ? Colors.green : Colors.grey[600],
                          size: 20,
                      ),
                        tooltip: '高级搜索',
                      ),
                      SizedBox(width: 8),
                      // 添加按钮
                      FloatingActionButton(
                        onPressed: _addPurchase,
                        child: Icon(Icons.add),
                        tooltip: '添加采购',
                        backgroundColor: Colors.green,
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

class PurchaseDialog extends StatefulWidget {
  final List<Product> products;
  final List<Supplier> suppliers;
  final Purchase? existingPurchase; // 添加此参数用于编辑模式

  PurchaseDialog({
    required this.products,
    required this.suppliers,
    this.existingPurchase,
  });

  @override
  _PurchaseDialogState createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  String? _selectedProduct;
  String? _selectedSupplier;
  final _quantityController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  double _totalPurchasePrice = 0.0;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    // 如果是编辑模式，预填充数据
    if (widget.existingPurchase != null) {
      _isEditMode = true;
      final purchase = widget.existingPurchase!;
      _selectedProduct = purchase.productName;
      _selectedSupplier = purchase.supplierId?.toString();
      _quantityController.text = purchase.quantity.toString();
      _noteController.text = purchase.note ?? '';
      if (purchase.purchaseDate != null) {
        _selectedDate = DateTime.parse(purchase.purchaseDate!);
      }
      
      // 根据总价和数量计算单价
      final quantity = purchase.quantity;
      final totalPrice = purchase.totalPurchasePrice;
      if (quantity != 0 && totalPrice != null) {
        final unitPrice = totalPrice / quantity;
        _purchasePriceController.text = unitPrice.abs().toString();
      }
      _totalPurchasePrice = totalPrice ?? 0.0;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _purchasePriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate)
      setState(() {
        _selectedDate = picked;
      });
  }

  void _calculateTotalPrice() {
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0.0;
    final quantity = double.tryParse(_quantityController.text) ?? 0.0;
    setState(() {
      _totalPurchasePrice = purchasePrice * quantity;
    });
  }

  @override
  Widget build(BuildContext context) {
    String unit = '';
    final int? selectedSupplierId = int.tryParse(_selectedSupplier ?? '');
    final List<Product> filteredProducts = selectedSupplierId != null
        ? widget.products.where((p) => p.supplierId == selectedSupplierId).toList()
        : widget.products;

    if (_selectedProduct != null) {
      final product = widget.products.firstWhere((p) => p.name == _selectedProduct);
      unit = product.unit.value;
    }

    return AlertDialog(
      title: Text(
        _isEditMode ? '编辑采购/退货' : '添加采购/退货',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 先选择供应商（可手动选择）
            DropdownButtonFormField<String>(
              value: _selectedSupplier,
              decoration: InputDecoration(
                labelText: '选择供应商',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.business, color: Colors.green),
              ),
              isExpanded: true,
              items: widget.suppliers.map((supplier) {
                return DropdownMenuItem<String>(
                  value: supplier.id.toString(),
                  child: Text(supplier.name),
                );
              }).toList(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请选择供应商';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _selectedSupplier = value;

                  // 如果当前已选产品不属于该供应商，则清空产品选择
                  if (_selectedProduct != null) {
                    final p = widget.products.firstWhere((p) => p.name == _selectedProduct);
                    final sid = p.supplierId;
                    final selectedSid = int.tryParse(_selectedSupplier ?? '');
                    if (selectedSid != null && sid != selectedSid) {
                      _selectedProduct = null;
                    }
                  }
                });
              },
            ),
            SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _selectedProduct,
                decoration: InputDecoration(
                  labelText: '选择产品',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.inventory, color: Colors.green),
                ),
                isExpanded: true,
              items: filteredProducts.map((product) {
                return DropdownMenuItem<String>(
                  value: product.name,
                  child: Text(product.name),
                );
              }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请选择产品';
                  }
                  return null;
                },
              onChanged: (value) {
                setState(() {
                  _selectedProduct = value;
                  // 如果用户还没选供应商，则根据产品自动同步供应商（保持原功能）
                  if (_selectedSupplier == null && value != null) {
                    final product = widget.products.firstWhere((p) => p.name == value);
                    if (product.supplierId != null && product.supplierId != 0) {
                      _selectedSupplier = product.supplierId.toString();
                    }
                  }
                });
              },
            ),
              SizedBox(height: 16),
              
              // 说明信息（放在供应商和数量/进价之间）
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '正数表示采购入库，负数表示采购退货',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _quantityController,
                          decoration: InputDecoration(
                            labelText: '数量',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            prefixIcon: Icon(Icons.format_list_numbered, color: Colors.green),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入数量';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效数字';
                            }
                            if (double.parse(value) == 0) {
                              return '数量不能为0';
                            }
                            return null;
                          },
                          onChanged: (value) => _calculateTotalPrice(),
                        ),
                        SizedBox(height: 4),
                        Center(
                          child: Text(
                            unit.isNotEmpty ? '单位: $unit' : '单位:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _purchasePriceController,
                          decoration: InputDecoration(
                            labelText: '进价',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入进价';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效数字';
                            }
                            if (double.parse(value) < 0) {
                              return '进价不能为负数';
                            }
                            return null;
                          },
                          onChanged: (value) => _calculateTotalPrice(),
                        ),
                        SizedBox(height: 4),
                        Center(
                          child: Text(
                            unit.isNotEmpty ? '元 / $unit' : '元 / 单位',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[100]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '总进价:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _totalPurchasePrice < 0
                          ? '-¥${_totalPurchasePrice.abs()}'
                          : '¥$_totalPurchasePrice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                ),
              ],
            ),
              ),
              SizedBox(height: 16),
              
              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '采购日期',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.green),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.note, color: Colors.green),
                ),
                maxLines: 2,
              ),
          ],
          ),
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  // 额外健壮性校验：产品与供应商必须匹配（每个产品只对应一个供应商）
                  if (_selectedProduct != null && _selectedSupplier != null) {
                    final product = widget.products.firstWhere((p) => p.name == _selectedProduct);
                    final selectedSupplierId = int.tryParse(_selectedSupplier!);
                    final productSupplierId = product.supplierId;

                    if (selectedSupplierId == null ||
                        productSupplierId == null ||
                        productSupplierId != selectedSupplierId) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('保存失败'),
                          content: Text('所选产品与供应商不匹配，请重新选择。'),
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
                  }

                final purchase = {
                  'productName': _selectedProduct,
                  'quantity': double.tryParse(_quantityController.text) ?? 0.0,
                    'supplierId': int.tryParse(_selectedSupplier ?? '') ?? 0,
                  'purchaseDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
                  'totalPurchasePrice': _totalPurchasePrice,
                    'note': _noteController.text,
                };
                Navigator.of(context).pop(purchase);
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