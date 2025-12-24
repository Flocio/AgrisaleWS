// lib/screens/product_screen.dart

import 'package:flutter/material.dart';
import '../widgets/footer_widget.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';

class ProductScreen extends StatefulWidget {
  @override
  _ProductScreenState createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final ProductRepository _productRepo = ProductRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  
  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;

  // 添加搜索相关的状态变量
  List<Product> _filteredProducts = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加供应商筛选
  String? _selectedSupplierFilter;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤产品的方法
  void _filterProducts() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      List<Product> result = List.from(_products);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchText.isNotEmpty) {
        hasFilters = true;
        result = result.where((product) {
          final name = product.name.toLowerCase();
          final description = (product.description ?? '').toLowerCase();
          return name.contains(searchText) || description.contains(searchText);
        }).toList();
      }
      
      // 供应商筛选
      if (_selectedSupplierFilter != null && _selectedSupplierFilter != '全部供应商') {
        hasFilters = true;
        final selectedSupplier = _suppliers.firstWhere(
          (s) => s.name == _selectedSupplierFilter,
          orElse: () => Supplier(id: -1, userId: 0, name: ''),
        );
        
        if (selectedSupplier.id == -1) {
          // "未分配供应商"
          result = result.where((product) => 
            product.supplierId == null || product.supplierId == 0).toList();
        } else {
          result = result.where((product) => 
            product.supplierId == selectedSupplier.id).toList();
        }
      }
      
      _isSearching = hasFilters;
      _filteredProducts = result;
    });
  }

  Future<void> _fetchProducts({bool isRefresh = false}) async {
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
      ]);
      
      final productsResponse = results[0] as PaginatedResponse<Product>;
      final suppliers = results[1] as List<Supplier>;
      
        setState(() {
          _products = productsResponse.items;
        _suppliers = suppliers;
        _isLoading = false;
      });
        
        // 重新应用过滤条件（初始加载和刷新都需要）
        _filterProducts();
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取产品列表失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取产品列表失败: ${e.toString()}');
      }
    }
  }

  Future<void> _addProduct() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductDialog(suppliers: _suppliers),
    );
    if (result != null) {
      try {
        final productCreate = ProductCreate(
          name: result['name'] as String,
          description: (result['description'] as String?)?.isEmpty == true 
              ? null 
              : result['description'] as String?,
          stock: result['stock'] as double,
          unit: ProductUnit.fromString(result['unit'] as String),
          supplierId: result['supplierId'] as int?,
        );
        
        await _productRepo.createProduct(productCreate);
        _fetchProducts();
        
        if (mounted) {
          context.showSuccessSnackBar('产品添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('添加产品失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editProduct(Product product) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductDialog(product: product, suppliers: _suppliers),
    );
    if (result != null) {
      try {
        final productUpdate = ProductUpdate(
          name: result['name'] as String,
          description: (result['description'] as String?)?.isEmpty == true 
              ? null 
              : result['description'] as String?,
          stock: result['stock'] as double,
          unit: ProductUnit.fromString(result['unit'] as String),
          supplierId: result['supplierId'] as int?,
          version: product.version, // 使用当前版本号
        );
        
        await _productRepo.updateProduct(product.id, productUpdate);
        _fetchProducts();
        
        if (mounted) {
            context.showSuccessSnackBar('产品更新成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          String errorMessage = e.message;
          if (e.statusCode == 409) {
            errorMessage = '产品已被其他操作修改，请刷新后重试';
            _fetchProducts(); // 刷新数据
          }
          context.showErrorSnackBar(errorMessage);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新产品失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text(
          '您确定要删除以下产品吗？\n\n'
              '产品名称: ${product.name}\n'
              '描述: ${product.description ?? '无描述'}\n'
              '库存: ${_formatNumber(product.stock)} ${product.unit.value}',
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
        await _productRepo.deleteProduct(product.id);
        _fetchProducts();
        
        if (mounted) {
          context.showSuccessSnackBar('产品删除成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('删除产品失败: ${e.toString()}');
        }
      }
    }
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
          title: Text('产品', style: TextStyle(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag, color: Colors.green[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '产品列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredProducts.length} 个品种',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 添加供应商筛选下拉框
            if (_suppliers.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.filter_list, size: 18, color: Colors.green[700]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSupplierFilter,
                            hint: Text('按供应商筛选', style: TextStyle(fontSize: 14)),
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: Colors.green),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedSupplierFilter = newValue;
                                _filterProducts();
                              });
                            },
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text('全部供应商'),
                              ),
                              DropdownMenuItem<String>(
                                value: '未分配供应商',
                                child: Text('未分配供应商', style: TextStyle(color: Colors.grey[600])),
                              ),
                              ..._suppliers.map<DropdownMenuItem<String>>((supplier) {
                                return DropdownMenuItem<String>(
                                  value: supplier.name,
                                  child: Text(supplier.name),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          Expanded(
              child: _isLoading && _products.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _fetchProducts(isRefresh: true),
                      child: _filteredProducts.isEmpty
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
                              Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                _isSearching ? '没有匹配的产品' : '暂无产品',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 8),
                              Text(
                                _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加产品',
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
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _filteredProducts.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Text(
                                            product.name.substring(0, 1),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[800],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                              product.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    '库存: ${_formatNumber(product.stock)} ${product.unit.value}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                                  if (product.supplierId != null && product.supplierId != 0) ...[
                                                    SizedBox(width: 8),
                                                    Icon(Icons.business, size: 12, color: Colors.blue[700]),
                                                    SizedBox(width: 2),
                                                    Expanded(
                                                      child: Text(
                                                        _getSupplierName(product.supplierId),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.blue[700],
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                        Container(
                                              height: 18,
                                              child: product.description != null && product.description!.isNotEmpty
                                            ? Text(
                                                      product.description!,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                      ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )
                                                  : null,
                                        ),
                                      ],
                                    ),
                                  ),
                      IconButton(
                                    icon: Icon(Icons.edit, color: Colors.green),
                                    tooltip: '编辑',
                                    onPressed: () => _editProduct(product),
                                    constraints: BoxConstraints(),
                                    padding: EdgeInsets.all(8),
                                  ),
                                  if (_showDeleteButtons)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        tooltip: '删除',
                        onPressed: () => _deleteProduct(product),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
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
              child: Row(
                children: [
                  // 搜索框
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索产品...',
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
                  SizedBox(width: 16),
                  // 添加按钮
                  FloatingActionButton(
        onPressed: _addProduct,
        child: Icon(Icons.add),
                    tooltip: '添加产品',
                    backgroundColor: Colors.green,
                    mini: false,
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
  
  // 获取供应商名称
  String _getSupplierName(int? supplierId) {
    if (supplierId == null || supplierId == 0) return '未分配';
    final supplier = _suppliers.firstWhere(
      (s) => s.id == supplierId,
      orElse: () => Supplier(id: -1, userId: 0, name: '未知'),
    );
    return supplier.name;
  }
}

class ProductDialog extends StatefulWidget {
  final Product? product;
  final List<Supplier> suppliers;

  ProductDialog({this.product, required this.suppliers});

  @override
  _ProductDialogState createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedUnit = '斤'; // 默认单位
  String? _selectedSupplierId; // 选中的供应商ID

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!.name;
      _descriptionController.text = widget.product!.description ?? '';
      _stockController.text = widget.product!.stock.toString();
      _selectedUnit = widget.product!.unit.value;
      // 加载供应商ID
      if (widget.product!.supplierId != null && widget.product!.supplierId != 0) {
        _selectedSupplierId = widget.product!.supplierId.toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.product == null ? '添加产品' : '编辑产品',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
              TextFormField(
              controller: _nameController,
                decoration: InputDecoration(
                  labelText: '产品名称',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.shopping_bag, color: Colors.green),
            ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入产品名称';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              // 添加供应商选择
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedSupplierId != null ? Colors.black : Colors.grey[400]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.business, color: Colors.green, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSupplierId,
                          hint: Text('选择供应商（可选）', style: TextStyle(fontSize: 14)),
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.green),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSupplierId = newValue;
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text('未分配供应商', style: TextStyle(color: Colors.grey[600])),
                            ),
                            ...widget.suppliers.map<DropdownMenuItem<String>>((supplier) {
                              return DropdownMenuItem<String>(
                                value: supplier.id.toString(),
                                child: Text(supplier.name),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
              controller: _stockController,
                      decoration: InputDecoration(
                        labelText: '库存',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.inventory, color: Colors.green),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入库存';
                        }
                        if (double.tryParse(value) == null) {
                          return '请输入有效数字';
                        }
                        if (double.parse(value) < 0) {
                          return '库存不能为负数';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
              value: _selectedUnit,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.green),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedUnit = newValue!;
                });
              },
              items: <String>['斤', '公斤', '袋']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
            ),
              SizedBox(height: 16),
              TextFormField(
              controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.description, color: Colors.green),
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
        // 保持原来的保存/取消按钮位置
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                final product = {
                    'name': _nameController.text.trim(),
                    'description': _descriptionController.text.trim(),
                  'stock': double.tryParse(_stockController.text) ?? 0.0,
                  'unit': _selectedUnit,
                  'supplierId': _selectedSupplierId != null ? int.tryParse(_selectedSupplierId!) : null,
                };
                  if (widget.product != null) {
                    product['id'] = widget.product!.id;
                  }
                Navigator.of(context).pop(product);
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
    _nameController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}