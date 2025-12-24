// lib/screens/returns_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/footer_widget.dart';
import '../repositories/return_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';

class ReturnsScreen extends StatefulWidget {
  @override
  _ReturnsScreenState createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final ReturnRepository _returnRepo = ReturnRepository();
  final ProductRepository _productRepo = ProductRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  
  List<Return> _returns = [];
  List<Product> _products = [];
  List<Customer> _customers = [];
  List<Supplier> _suppliers = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;

  // 添加搜索相关的状态变量
  List<Return> _filteredReturns = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedProductFilter;
  String? _selectedCustomerFilter;
  DateTimeRange? _selectedDateRange;
  final ValueNotifier<List<String>> _activeFilters = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _fetchData();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterReturns();
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
      _selectedCustomerFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredReturns = List.from(_returns);
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
    
    if (_selectedCustomerFilter != null) {
      filters.add('客户: $_selectedCustomerFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 添加过滤退货记录的方法
  void _filterReturns() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      List<Return> result = List.from(_returns);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((returnItem) {
          final productName = returnItem.productName.toLowerCase();
          final customer = _customers.firstWhere(
            (c) => c.id == returnItem.customerId,
            orElse: () => Customer(id: -1, userId: 0, name: ''),
          );
          final customerName = customer.name.toLowerCase();
          final date = (returnItem.returnDate ?? '').toLowerCase();
          final note = (returnItem.note ?? '').toLowerCase();
          final quantity = returnItem.quantity.toString().toLowerCase();
          final price = (returnItem.totalReturnPrice ?? 0).toString().toLowerCase();
          
          return searchTerms.every((term) =>
            productName.contains(term) ||
            customerName.contains(term) ||
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
        result = result.where((returnItem) => 
          returnItem.productName == _selectedProductFilter).toList();
      }
      
      // 客户筛选
      if (_selectedCustomerFilter != null) {
        hasFilters = true;
        final selectedCustomer = _customers.firstWhere(
          (c) => c.name == _selectedCustomerFilter,
          orElse: () => Customer(id: -1, userId: 0, name: ''),
        );
        
        result = result.where((returnItem) => 
          returnItem.customerId == selectedCustomer.id).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((returnItem) {
          if (returnItem.returnDate == null) return false;
          final returnDate = DateTime.parse(returnItem.returnDate!);
          return returnDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 returnDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredReturns = result;
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
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
        _returnRepo.getReturns(page: 1, pageSize: 1000),
      ]);
      
      final productsResponse = results[0] as PaginatedResponse<Product>;
      final customers = results[1] as List<Customer>;
      final suppliers = results[2] as List<Supplier>;
      final returnsResponse = results[3] as PaginatedResponse<Return>;
      
      setState(() {
        _products = productsResponse.items;
        _customers = customers;
        _suppliers = suppliers;
        _returns = returnsResponse.items;
        _filteredReturns = returnsResponse.items;
        _isLoading = false;
      });
      
      // 刷新后重新应用过滤条件
      if (isRefresh) {
        _filterReturns();
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

  Future<void> _addReturn() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ReturnsDialog(products: _products, customers: _customers, suppliers: _suppliers),
    );
    if (result != null) {
      try {
        final returnCreate = ReturnCreate(
          productName: result['productName'] as String,
          quantity: result['quantity'] as double,
          returnDate: result['returnDate'] as String?,
          customerId: result['customerId'] as int?,
          totalReturnPrice: result['totalReturnPrice'] as double?,
          note: result['note'] as String?,
        );
        
        await _returnRepo.createReturn(returnCreate);
        _fetchData();
        
        if (mounted) {
          context.showSuccessSnackBar('退货记录添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          _showErrorDialog(e.message);
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('添加退货记录失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editReturn(Return returnItem) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ReturnsDialog(
        products: _products,
        customers: _customers,
        suppliers: _suppliers,
        existingReturn: returnItem,
      ),
    );
    
    if (result != null) {
      try {
        final returnUpdate = ReturnUpdate(
          productName: result['productName'] as String,
          quantity: result['quantity'] as double,
          returnDate: result['returnDate'] as String?,
          customerId: result['customerId'] as int?,
          totalReturnPrice: result['totalReturnPrice'] as double?,
          note: result['note'] as String?,
        );
        
        await _returnRepo.updateReturn(returnItem.id, returnUpdate);
        _fetchData();
        
        if (mounted) {
          context.showSuccessSnackBar('退货记录更新成功');
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
          _showErrorDialog('更新退货记录失败: ${e.toString()}');
        }
      }
    }
  }

  void _showNoteDialog(Return returnItem) {
    final _noteController = TextEditingController(text: returnItem.note);
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
                    final returnUpdate = ReturnUpdate(
                      note: _noteController.text.isEmpty ? null : _noteController.text,
                    );
                    await _returnRepo.updateReturn(returnItem.id, returnUpdate);
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

  Future<void> _deleteReturn(Return returnItem) async {
    final customer = _customers.firstWhere(
      (c) => c.id == returnItem.customerId,
      orElse: () => Customer(id: -1, userId: 0, name: '未知客户'),
    );
    final product = _products.firstWhere(
      (p) => p.name == returnItem.productName,
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
          '您确定要删除以下退货记录吗？\n\n'
              '产品名称: ${returnItem.productName}\n'
              '数量: ${_formatNumber(returnItem.quantity)} ${product.unit.value}\n'
              '客户: ${customer.name}\n'
              '日期: ${returnItem.returnDate ?? '未知'}',
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
        await _returnRepo.deleteReturn(returnItem.id);
        _fetchData();
        
        if (mounted) {
          context.showSuccessSnackBar('退货记录删除成功');
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
          _showErrorDialog('删除退货记录失败: ${e.toString()}');
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
                            _filterReturns();
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
        title: Text('退货', style: TextStyle(
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
            child: _isLoading && _returns.isEmpty
                ? Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _fetchData(isRefresh: true),
                    child: _filteredReturns.isEmpty
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
                                Icon(Icons.assignment_return, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  _isSearching ? '没有匹配的退货记录' : '暂无退货记录',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加退货记录',
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
                    itemCount: _filteredReturns.length,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                      final returnItem = _filteredReturns[index];
                final customer = _customers.firstWhere(
                      (c) => c.id == returnItem.customerId,
                  orElse: () => Customer(id: -1, userId: 0, name: '未知客户'),
                );
                final product = _products.firstWhere(
                      (p) => p.name == returnItem.productName,
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
                                    child: Text(
                                      returnItem.productName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        returnItem.returnDate ?? '未知日期',
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
                                            onPressed: () => _editReturn(returnItem),
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
                            onPressed: () => _deleteReturn(returnItem),
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
                                  Icon(Icons.person, 
                                       size: 14, 
                                       color: Colors.blue[700]),
                                  SizedBox(width: 4),
                                  Text(
                                    '客户: ${customer.name}',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.inventory_2, 
                                       size: 14, 
                                       color: Colors.green[700]),
                                  SizedBox(width: 4),
                                  Text(
                                    '数量: ${_formatNumber(returnItem.quantity)} ${product.unit.value}',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.attach_money, 
                                       size: 14, 
                                       color: Colors.red[700]),
                                  SizedBox(width: 4),
                                  Text(
                                    '总退款: ${returnItem.totalReturnPrice ?? 0}',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              if (returnItem.note != null && returnItem.note!.isNotEmpty)
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
                                          '备注: ${returnItem.note}',
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
                          hintText: '搜索退货记录...',
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
        onPressed: _addReturn,
        child: Icon(Icons.add),
                      tooltip: '添加退货',
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

class ReturnsDialog extends StatefulWidget {
  final List<Product> products;
  final List<Customer> customers;
  final List<Supplier> suppliers;
  final Return? existingReturn; // 添加此参数用于编辑模式

  ReturnsDialog({
    required this.products,
    required this.customers,
    required this.suppliers,
    this.existingReturn,
  });

  @override
  _ReturnsDialogState createState() => _ReturnsDialogState();
}

class _ReturnsDialogState extends State<ReturnsDialog> {
  String? _selectedProduct;
  String? _selectedSupplier;
  String? _selectedCustomer;
  final _quantityController = TextEditingController();
  final _returnPriceController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  double _totalReturnPrice = 0.0;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    // 如果是编辑模式，预填充数据
    if (widget.existingReturn != null) {
      _isEditMode = true;
      final returnItem = widget.existingReturn!;
      _selectedProduct = returnItem.productName;
      _selectedCustomer = returnItem.customerId?.toString();
      _quantityController.text = returnItem.quantity.toString();
      _noteController.text = returnItem.note ?? '';
      if (returnItem.returnDate != null) {
        _selectedDate = DateTime.parse(returnItem.returnDate!);
      }
      
      // 根据总价和数量计算单价
      final quantity = returnItem.quantity;
      final totalPrice = returnItem.totalReturnPrice;
      if (quantity != 0 && totalPrice != null) {
        final unitPrice = totalPrice / quantity;
        _returnPriceController.text = unitPrice.toString();
      }
      _totalReturnPrice = totalPrice ?? 0.0;

      // 根据产品反推供应商（用于供应商筛选下拉框的默认值）
      final product = widget.products.firstWhere(
        (p) => p.name == returnItem.productName,
        orElse: () => Product(id: -1, userId: 0, name: '', stock: 0, unit: ProductUnit.kilogram, version: 1),
      );
      if (product.supplierId != null && product.supplierId != 0) {
        _selectedSupplier = product.supplierId.toString();
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _returnPriceController.dispose();
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
    final returnPrice = double.tryParse(_returnPriceController.text) ?? 0.0;
    final quantity = double.tryParse(_quantityController.text) ?? 0.0;
    setState(() {
      _totalReturnPrice = returnPrice * quantity;
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
        _isEditMode ? '编辑退货' : '添加退货',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 供应商筛选（严格参考 sales_screen.dart：新增下拉框过滤产品）
            DropdownButtonFormField<String>(
              value: _selectedSupplier,
              decoration: InputDecoration(
                labelText: '供应商筛选',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.business, color: Colors.green),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('全部供应商'),
                ),
                ...widget.suppliers.map((supplier) {
                  return DropdownMenuItem<String>(
                    value: supplier.id.toString(),
                    child: Text(supplier.name),
                  );
                }).toList(),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedSupplier = value;
                  // 若已选产品不属于该供应商，则清空产品选择
                  if (_selectedProduct != null && _selectedSupplier != null) {
                    final p = widget.products.firstWhere((p) => p.name == _selectedProduct);
                    final sid = p.supplierId;
                    final selectedSid = int.tryParse(_selectedSupplier!);
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
                  // 若尚未选择供应商，则随产品自动带出供应商筛选（不影响旧用法）
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
              
            DropdownButtonFormField<String>(
              value: _selectedCustomer,
                decoration: InputDecoration(
                  labelText: '选择客户',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.person, color: Colors.green),
                ),
                isExpanded: true,
              items: widget.customers.map((customer) {
                return DropdownMenuItem<String>(
                  value: customer.id.toString(),
                  child: Text(customer.name),
                );
              }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请选择客户';
                  }
                  return null;
                },
              onChanged: (value) {
                setState(() {
                  _selectedCustomer = value;
                });
              },
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
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入数量';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效数字';
                            }
                            if (double.parse(value) <= 0) {
                              return '数量必须大于0';
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
                          controller: _returnPriceController,
                          decoration: InputDecoration(
                            labelText: '单价',
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
                              return '请输入单价';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效数字';
                            }
                            if (double.parse(value) < 0) {
                              return '单价不能为负数';
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

              // 总退款红色框（与备注位置互换：先显示总退款，再显示备注）
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[100]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '总退款:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '¥ $_totalReturnPrice',
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
                    labelText: '退货日期',
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

              // 备注（与总退款位置互换：总退款在上，备注在下）
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
                final returnItem = {
                  'productName': _selectedProduct,
                  'quantity': double.tryParse(_quantityController.text) ?? 0.0,
                  'customerId': int.tryParse(_selectedCustomer ?? '') ?? 0,
                  'returnDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
                  'totalReturnPrice': _totalReturnPrice,
                    'note': _noteController.text,
                };
                Navigator.of(context).pop(returnItem);
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