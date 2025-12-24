// lib/screens/supplier_screen.dart

import 'package:flutter/material.dart';
import '../widgets/footer_widget.dart';
import 'supplier_records_screen.dart';
import 'supplier_transactions_screen.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class SupplierScreen extends StatefulWidget {
  @override
  _SupplierScreenState createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  final SupplierRepository _supplierRepo = SupplierRepository();
  
  List<Supplier> _suppliers = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;

  // 添加搜索相关的状态变量
  List<Supplier> _filteredSuppliers = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterSuppliers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤供应商的方法
  void _filterSuppliers() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      if (searchText.isEmpty) {
        _filteredSuppliers = List.from(_suppliers);
        _isSearching = false;
      } else {
        _filteredSuppliers = _suppliers.where((supplier) {
          final name = supplier.name.toLowerCase();
          final note = (supplier.note ?? '').toLowerCase();
          return name.contains(searchText) || note.contains(searchText);
        }).toList();
        _isSearching = true;
      }
    });
  }

  Future<void> _fetchSuppliers({bool isRefresh = false}) async {
    if (!isRefresh) {
    setState(() {
      _isLoading = true;
    });
    }
    
    try {
      final suppliers = await _supplierRepo.getAllSuppliers();
      
      setState(() {
        _suppliers = suppliers;
        _isLoading = false;
      });
      
      // 刷新后重新应用过滤条件
      if (isRefresh) {
        _filterSuppliers();
      } else {
        // 初始加载时也应用过滤
        _filterSuppliers();
      }
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取供应商列表失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取供应商列表失败: ${e.toString()}');
      }
    }
  }

  Future<void> _addSupplier() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SupplierDialog(),
    );
    if (result != null) {
      try {
        final supplierCreate = SupplierCreate(
          name: result['name'] as String,
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _supplierRepo.createSupplier(supplierCreate);
        _fetchSuppliers();
        
        if (mounted) {
          context.showSuccessSnackBar('供应商添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('添加供应商失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editSupplier(Supplier supplier) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SupplierDialog(supplier: supplier),
    );
    if (result != null) {
      try {
        final supplierUpdate = SupplierUpdate(
          name: result['name'] as String,
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _supplierRepo.updateSupplier(supplier.id, supplierUpdate);
        _fetchSuppliers();
        
        if (mounted) {
          context.showSuccessSnackBar('供应商更新成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新供应商失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除供应商 "${supplier.name}" 吗？'),
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
        await _supplierRepo.deleteSupplier(supplier.id);
        _fetchSuppliers();
        
        if (mounted) {
          context.showSuccessSnackBar('供应商删除成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('删除供应商失败: ${e.toString()}');
        }
      }
    }
  }

  void _viewSupplierRecords(int supplierId, String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierRecordsScreen(supplierId: supplierId, supplierName: supplierName),
      ),
    );
  }

  void _viewSupplierTransactions(int supplierId, String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierTransactionsScreen(supplierId: supplierId, supplierName: supplierName),
      ),
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
          title: Text('供应商', style: TextStyle(
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
        children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.business, color: Colors.blue[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '供应商列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredSuppliers.length} 家供应商',
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
              child: _isLoading && _suppliers.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _fetchSuppliers(isRefresh: true),
                      child: _filteredSuppliers.isEmpty
                          ? SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: Container(
                                height: MediaQuery.of(context).size.height * 0.7,
                                child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  _isSearching ? '没有匹配的供应商' : '暂无供应商',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加供应商',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                                  ),
                            ),
                          ),
                        )
                      : ListView.builder(
                      // 让列表也能点击收起键盘
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _filteredSuppliers.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final supplier = _filteredSuppliers[index];
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
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Text(
                                        supplier.name.isNotEmpty 
                                            ? supplier.name[0].toUpperCase() 
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[800],
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
                                          supplier.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (supplier.note != null && supplier.note!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              supplier.note!,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                                        icon: Icon(Icons.account_balance_wallet, color: Colors.purple),
                                        tooltip: '往来记录',
                                        onPressed: () => _viewSupplierTransactions(
                                          supplier.id, 
                                          supplier.name
                                        ),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                      ),
                                      SizedBox(width: 4),
                      IconButton(
                                        icon: Icon(Icons.list_alt, color: Colors.blue),
                                        tooltip: '查看记录',
                                        onPressed: () => _viewSupplierRecords(
                                          supplier.id, 
                                          supplier.name
                                        ),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                      ),
                                      SizedBox(width: 4),
                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.blue),
                                        tooltip: '编辑',
                        onPressed: () => _editSupplier(supplier),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteSupplier(supplier),
                                          constraints: BoxConstraints(),
                                          padding: EdgeInsets.all(8),
                                        ),
                      ),
                    ],
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
                        hintText: '搜索供应商...',
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
                          borderSide: BorderSide(color: Colors.blue),
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
        onPressed: _addSupplier,
        child: Icon(Icons.add),
                    tooltip: '添加供应商',
                    backgroundColor: Colors.blue,
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
}

class SupplierDialog extends StatefulWidget {
  final Supplier? supplier;

  SupplierDialog({this.supplier});

  @override
  _SupplierDialogState createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      _nameController.text = widget.supplier!.name;
      _noteController.text = widget.supplier!.note ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.supplier == null ? '添加供应商' : '编辑供应商',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Form(
        key: _formKey,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            TextFormField(
            controller: _nameController,
              decoration: InputDecoration(
                labelText: '供应商名称',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.business, color: Colors.blue),
          ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入供应商名称';
                }
                return null;
              },
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
                prefixIcon: Icon(Icons.note, color: Colors.blue),
              ),
              maxLines: 2,
          ),
        ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final Map<String, dynamic> supplier = {
                    'name': _nameController.text.trim(),
                    'note': _noteController.text.trim().isEmpty 
                        ? null 
                        : _noteController.text.trim(),
                  };
                Navigator.of(context).pop(supplier);
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
    _noteController.dispose();
    super.dispose();
  }
}