// lib/screens/supplier_records_screen.dart

import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/product_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class SupplierRecordsScreen extends StatefulWidget {
  final int supplierId;
  final String supplierName;

  SupplierRecordsScreen({required this.supplierId, required this.supplierName});

  @override
  _SupplierRecordsScreenState createState() => _SupplierRecordsScreenState();
}

class _SupplierRecordsScreenState extends State<SupplierRecordsScreen> {
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final ProductRepository _productRepo = ProductRepository();
  
  List<Map<String, dynamic>> _purchases = [];
  List<Product> _products = [];
  bool _isDescending = true;
  bool _purchaseFirst = true; // 控制采购在前还是退货在前
  String? _selectedProduct = '所有产品'; // 产品筛选
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  bool _isLoading = false;
  
  // 日期筛选相关变量
  DateTimeRange? _selectedDateRange;
  
  // 滚动控制器和指示器
  ScrollController? _summaryScrollController;
  double _summaryScrollPosition = 0.0;
  double _summaryScrollMaxExtent = 0.0;
  
  // 汇总数据
  int _totalRecordCount = 0; // 总记录数
  int _purchaseRecordCount = 0; // 采购记录数（只包含正的）
  int _returnRecordCount = 0; // 退货记录数
  double _totalPurchaseQuantity = 0.0; // 采购总量（只包含正数）
  double _totalReturnQuantity = 0.0; // 退货总量（只包含负数）
  double _netQuantity = 0.0; // 净数量
  double _totalPurchaseAmount = 0.0; // 采购总额（只包含正数）
  double _totalReturnAmount = 0.0; // 退货总额（只包含负数）
  double _netAmount = 0.0; // 净采购额

  @override
  void initState() {
    super.initState();
    _summaryScrollController = ScrollController();
    _summaryScrollController!.addListener(_onSummaryScroll);
    _fetchRecords();
  }

  void _onSummaryScroll() {
    if (_summaryScrollController != null && _summaryScrollController!.hasClients) {
      setState(() {
        _summaryScrollPosition = _summaryScrollController!.offset;
        _summaryScrollMaxExtent = _summaryScrollController!.position.maxScrollExtent;
      });
    }
  }

  @override
  void dispose() {
    _summaryScrollController?.removeListener(_onSummaryScroll);
    _summaryScrollController?.dispose();
    super.dispose();
  }

  // 格式化数字方法：整数显示为整数，小数显示为小数
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }

  Future<void> _fetchProducts() async {
    try {
      final productsResponse = await _productRepo.getProducts(page: 1, pageSize: 10000);
      setState(() {
        _products = productsResponse.items;
      });
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载产品数据失败: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载产品数据失败: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 并行获取所有数据（包括产品数据）
      final results = await Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 10000),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
      ]);
      
      // 先设置产品数据，确保后续处理可以使用
      final productsResponse = results[0] as PaginatedResponse<Product>;
      setState(() {
        _products = productsResponse.items;
      });
      
      final purchasesResponse = results[1] as PaginatedResponse<Purchase>;
      
      // 按供应商ID筛选
      List<Purchase> purchases = purchasesResponse.items.where((p) => p.supplierId == widget.supplierId).toList();
      
      // 应用产品筛选
      if (_selectedProduct != null && _selectedProduct != '所有产品') {
        purchases = purchases.where((p) => p.productName == _selectedProduct).toList();
      }
      
      // 应用日期筛选
      if (_selectedDateRange != null) {
        final startDate = _selectedDateRange!.start.toIso8601String().split('T')[0];
        final endDate = _selectedDateRange!.end.toIso8601String().split('T')[0];
        purchases = purchases.where((p) => p.purchaseDate != null && p.purchaseDate!.compareTo(startDate) >= 0 && p.purchaseDate!.compareTo(endDate) <= 0).toList();
      }

        // 将单位信息添加到采购记录中
        final purchasesWithUnits = purchases.map((purchase) {
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
          return {
          'id': purchase.id,
          'purchaseDate': purchase.purchaseDate,
          'productName': purchase.productName,
          'quantity': purchase.quantity,
          'unit': product.unit.value,
          'totalPurchasePrice': purchase.totalPurchasePrice,
          'note': purchase.note,
          'type': purchase.quantity >= 0 ? '采购' : '退货',
          };
        }).toList();

        // 按日期和类型排序
        purchasesWithUnits.sort((a, b) {
          int dateComparison = _isDescending
              ? (b['purchaseDate'] as String? ?? '').compareTo(a['purchaseDate'] as String? ?? '')
              : (a['purchaseDate'] as String? ?? '').compareTo(b['purchaseDate'] as String? ?? '');
          if (dateComparison != 0) return dateComparison;

          // 如果日期相同，根据类型排序
          if (_purchaseFirst) {
            return a['type'] == '采购' ? -1 : 1;
          } else {
            return a['type'] == '退货' ? -1 : 1;
          }
        });

      // 计算汇总数据
      _calculateSummary(purchasesWithUnits);

        setState(() {
          _purchases = purchasesWithUnits;
        _isLoading = false;
        });
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载记录失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载记录失败: ${e.toString()}');
      }
    }
  }

  void _calculateSummary(List<Map<String, dynamic>> purchases) {
    int purchaseRecordCount = 0;
    int returnRecordCount = 0;
    double purchaseQuantity = 0.0;
    double returnQuantity = 0.0;
    double purchaseAmount = 0.0;
    double returnAmount = 0.0;

    for (var purchase in purchases) {
      final quantity = (purchase['quantity'] as num).toDouble();
      final amount = (purchase['totalPurchasePrice'] as num?)?.toDouble() ?? 0.0;
      
      if (quantity >= 0) {
        // 采购（正数）
        purchaseRecordCount++;
        purchaseQuantity += quantity;
        purchaseAmount += amount;
      } else {
        // 退货（负数）
        returnRecordCount++;
        returnQuantity += quantity.abs(); // 存储为绝对值
        returnAmount += amount.abs(); // 存储为绝对值
      }
    }

    setState(() {
      _totalRecordCount = purchases.length;
      _purchaseRecordCount = purchaseRecordCount;
      _returnRecordCount = returnRecordCount;
      _totalPurchaseQuantity = purchaseQuantity;
      _totalReturnQuantity = returnQuantity;
      _netQuantity = purchaseQuantity - returnQuantity;
      _totalPurchaseAmount = purchaseAmount;
      _totalReturnAmount = returnAmount;
      _netAmount = purchaseAmount - returnAmount;
    });
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['供应商采购记录 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['供应商: ${widget.supplierName}']);
    rows.add(['产品筛选: $_selectedProduct']);
    
    // 添加日期筛选信息
    String dateFilterInfo;
    if (_selectedDateRange != null) {
      dateFilterInfo = '日期筛选: 日期范围 (${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')})';
    } else {
      dateFilterInfo = '日期筛选: 所有日期';
    }
    rows.add([dateFilterInfo]);
    
    rows.add([]); // 空行
    // 修改表头为中文
    rows.add(['日期', '类型', '产品', '数量', '单位', '金额', '备注']);

    for (var purchase in _purchases) {
      final quantity = (purchase['quantity'] as num).toDouble();
      final isPurchase = quantity >= 0;
      final type = isPurchase ? '采购' : '退货';
      
      // 根据类型决定数量正负
      final quantityText = isPurchase
          ? _formatNumber(quantity)
          : '-${_formatNumber(quantity.abs())}';
      
      // 根据类型决定金额正负
      final amount = (purchase['totalPurchasePrice'] as num?)?.toDouble() ?? 0.0;
      final amountText = isPurchase
          ? amount.toStringAsFixed(2)
          : '-${amount.abs().toStringAsFixed(2)}';
      
      rows.add([
        purchase['purchaseDate'],
        type,
        purchase['productName'],
        quantityText,
        purchase['unit'] ?? '',
        amountText,
        purchase['note'] ?? ''
      ]);
    }

    // 添加总计行
    rows.add([]);
    rows.add(['总计', '', '', 
              '${_netQuantity >= 0 ? '+' : ''}${_formatNumber(_netQuantity)}', 
              _selectedProduct != '所有产品' 
                  ? (_products.firstWhere((p) => p.name == _selectedProduct, orElse: () => Product(id: -1, userId: -1, name: '', unit: ProductUnit.kilogram, stock: 0.0, version: 1)).unit.value)
                  : '', 
              _netAmount.toStringAsFixed(2), 
              '']);
    
    // 添加汇总信息
    rows.add([]);
    rows.add(['汇总信息']);
    rows.add(['总记录数', '$_totalRecordCount']);
    rows.add(['采购记录数', '$_purchaseRecordCount']);
    rows.add(['退货记录数', '$_returnRecordCount']);
    rows.add(['采购总量', _formatNumber(_totalPurchaseQuantity)]);
    rows.add(['退货总量', _formatNumber(_totalReturnQuantity)]);
    rows.add(['净数量', _formatNumber(_netQuantity)]);
    rows.add(['采购总额', _totalPurchaseAmount.toStringAsFixed(2)]);
    rows.add(['退货总额', _totalReturnAmount.toStringAsFixed(2)]);
    // 正数不显示+号，避免Excel将其识别为公式
    rows.add(['净采购额', _netAmount >= 0 
        ? _netAmount.toStringAsFixed(2) 
        : '-${_netAmount.abs().toStringAsFixed(2)}']);

    String csv = const ListToCsvConverter().convert(rows);

    // 生成文件名：如果筛选了产品，格式为"{供应商名}_{产品名}_采购记录"，否则为"{供应商名}_采购记录"
    String baseFileName;
    if (_selectedProduct != null && _selectedProduct != '所有产品') {
      baseFileName = '${widget.supplierName}_${_selectedProduct}_采购记录';
    } else {
      baseFileName = '${widget.supplierName}_采购记录';
    }

    // 使用统一的导出服务
    await ExportService.showExportOptions(
      context: context,
      csvData: csv,
      baseFileName: baseFileName,
      );
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _fetchRecords();
    });
  }

  void _togglePurchaseFirst() {
    setState(() {
      _purchaseFirst = !_purchaseFirst;
      _fetchRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.supplierName}的记录', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(_isDescending ? Icons.arrow_downward : Icons.arrow_upward),
            tooltip: _isDescending ? '最新在前' : '最早在前',
            onPressed: _toggleSortOrder,
          ),
          IconButton(
            icon: Icon(_purchaseFirst ? Icons.swap_vert : Icons.swap_vert),
            tooltip: _purchaseFirst ? '采购在前' : '退货在前',
            onPressed: _togglePurchaseFirst,
          ),
          IconButton(
            icon: Icon(Icons.share),
            tooltip: '导出 CSV',
            onPressed: _exportToCSV,
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选条件 - 产品和日期在同一行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue[50],
            child: Row(
              children: [
                // 产品筛选
                Icon(Icons.filter_alt, color: Colors.blue[700], size: 20),
                SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonHideUnderline(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[300]!),
                        color: Colors.white,
                      ),
                      child: DropdownButton<String>(
                        hint: Text('选择产品', style: TextStyle(color: Colors.black87)),
                        value: _selectedProduct,
                        isExpanded: true,
                        icon: Icon(Icons.arrow_drop_down, color: Colors.blue[700]),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedProduct = newValue;
                            _fetchRecords();
                          });
                        },
                        style: TextStyle(color: Colors.black87, fontSize: 14),
                        items: [
                          DropdownMenuItem<String>(
                            value: '所有产品',
                            child: Text('所有产品'),
                          ),
                          ..._products.map<DropdownMenuItem<String>>((product) {
                            return DropdownMenuItem<String>(
                              value: product.name,
                              child: Text(product.name),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                // 日期范围选择器
                Icon(Icons.date_range, color: Colors.blue[700], size: 20),
                SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: InkWell(
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
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(primary: Colors.blue),
                            ),
                            child: child!,
                          );
                        },
                      );
                      
                      if (pickedRange != null) {
                        setState(() {
                          _selectedDateRange = pickedRange;
                          _fetchRecords();
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[300]!),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDateRange != null
                                  ? '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}'
                                  : '日期范围',
                              style: TextStyle(
                                color: _selectedDateRange != null ? Colors.black87 : Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (_selectedDateRange != null)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDateRange = null;
                                  _fetchRecords();
                                });
                              },
                              child: Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.clear, color: Colors.blue[700], size: 18),
                              ),
                            ),
                          Icon(Icons.arrow_drop_down, color: Colors.blue[700]),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 汇总信息卡片
          _buildSummaryCard(),

          Container(
            padding: EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                SizedBox(width: 8),
          Expanded(
                  child: Text(
                    '横向和纵向滑动可查看完整表格，采购以绿色显示，退货以红色显示',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  radius: 14,
                  child: Text(
                    widget.supplierName.isNotEmpty 
                        ? widget.supplierName[0].toUpperCase() 
                        : '?',
                    style: TextStyle(
                    color: Colors.blue[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '供应商采购记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${_purchases.length} 条记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          _isLoading && _purchases.isEmpty
              ? Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _purchases.isEmpty
              ? Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              '暂无采购记录',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              _selectedProduct == '所有产品' 
                                  ? '该供应商还没有采购记录'
                                  : '该供应商还没有采购 $_selectedProduct 的记录',
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
              : Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.grey[300],
                          dataTableTheme: DataTableThemeData(
                            headingRowColor: MaterialStateProperty.all(Colors.blue[50]),
                            dataRowColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected))
                                  return Colors.blue[100]!;
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
                            color: Colors.blue[800],
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
                  DataColumn(label: Text('金额')),
                  DataColumn(label: Text('备注')),
                ],
                          rows: [
                            // 数据行
                            ..._purchases.map((purchase) {
                              final quantity = (purchase['quantity'] as num).toDouble();
                              final isPurchase = quantity >= 0;
                              final textColor = isPurchase ? Colors.green : Colors.red;
                              
                              // 根据类型决定数量显示格式
                              final quantityText = isPurchase
                                  ? _formatNumber(quantity)
                                  : '-${_formatNumber(quantity.abs())}';
                              
                              // 根据类型决定金额显示格式
                              final amount = (purchase['totalPurchasePrice'] as num?)?.toDouble() ?? 0.0;
                              final amountText = isPurchase
                                  ? amount.toStringAsFixed(2)
                                  : '-${amount.abs().toStringAsFixed(2)}';
                              
                              return DataRow(cells: [
                                DataCell(Text(purchase['purchaseDate'] ?? '')),
                                DataCell(
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPurchase ? Colors.green[50] : Colors.red[50],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isPurchase ? Colors.green[300]! : Colors.red[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      isPurchase ? '采购' : '退货',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(purchase['productName'] ?? '')),
                                DataCell(
                                  Text(
                                    quantityText,
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                  DataCell(Text(purchase['unit'] ?? '')),
                            DataCell(
                              Text(
                                    amountText,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                      color: textColor,
                                ),
                                  ),
                            ),
                            DataCell(
                              purchase['note'] != null && purchase['note'].toString().isNotEmpty
                                  ? Text(
                                      purchase['note'],
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey[700],
                                      ),
                                    )
                                  : Text(''),
                            ),
                              ]);
                            }).toList(),
                            
                            // 总计行
                            if (_purchases.isNotEmpty)
                              DataRow(
                                color: MaterialStateProperty.all(Colors.grey[100]),
                                cells: [
                                  DataCell(Text('')), // 日期列
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue[300]!, width: 1),
                                      ),
                                      child: Text(
                                        '总计',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text('')), // 产品列
                                  DataCell(
                                    Text(
                                      '${_netQuantity >= 0 ? '+' : ''}${_formatNumber(_netQuantity)}',
                                      style: TextStyle(
                                        color: _netQuantity >= 0 ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _selectedProduct != '所有产品' 
                                          ? (_products.firstWhere((p) => p.name == _selectedProduct, orElse: () => Product(id: -1, userId: -1, name: '', unit: ProductUnit.kilogram, stock: 0.0, version: 1)).unit.value)
                                          : '',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${_netAmount >= 0 ? '+' : '-'}¥${_netAmount.abs().toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: _netAmount >= 0 ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text('')), // 备注列
                                ],
                              ),
                          ],
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

  // 汇总信息卡片
  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 供应商信息和汇总信息标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.business, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '${widget.supplierName}    ${_selectedProduct ?? '所有产品'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSummaryExpanded = !_isSummaryExpanded;
                    });
                  },
                  child: Row(
                    children: [
                      Text(
                        '汇总信息',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 16,
                        color: Colors.blue[800],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(height: 16, thickness: 1),
              
              // 单行显示，支持左右滑动
              Builder(
                builder: (context) {
                  // 在布局完成后检查滚动状态
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_summaryScrollController != null && _summaryScrollController!.hasClients) {
                      final newMaxExtent = _summaryScrollController!.position.maxScrollExtent;
                      final newPosition = _summaryScrollController!.offset;
                      if (newMaxExtent != _summaryScrollMaxExtent || newPosition != _summaryScrollPosition) {
                        setState(() {
                          _summaryScrollPosition = newPosition;
                          _summaryScrollMaxExtent = newMaxExtent;
                        });
                      }
                    }
                  });
                  
                  return SingleChildScrollView(
                    controller: _summaryScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                children: [
                        SizedBox(width: 8),
                        _buildSummaryItem('总记录数', '$_totalRecordCount', Colors.purple),
                        SizedBox(width: 16),
                        _buildSummaryItem('采购记录数', '$_purchaseRecordCount', Colors.green),
                        SizedBox(width: 16),
                        _buildSummaryItem('退货记录数', '$_returnRecordCount', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('采购总量', '+${_formatNumber(_totalPurchaseQuantity)}', Colors.green),
                        SizedBox(width: 16),
                        _buildSummaryItem('退货总量', '-${_formatNumber(_totalReturnQuantity)}', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('净数量', '${_netQuantity >= 0 ? '+' : ''}${_formatNumber(_netQuantity)}', _netQuantity >= 0 ? Colors.green : Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('采购总额', '+¥${_totalPurchaseAmount.toStringAsFixed(2)}', Colors.green),
                        SizedBox(width: 16),
                        _buildSummaryItem('退货总额', '-¥${_totalReturnAmount.toStringAsFixed(2)}', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('净采购额', '${_netAmount >= 0 ? '+' : '-'}¥${_netAmount.abs().toStringAsFixed(2)}', _netAmount >= 0 ? Colors.green : Colors.red),
                        SizedBox(width: 8),
                ],
              ),
                  );
                },
              ),
              
              // 滚动指示器
              SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final containerWidth = constraints.maxWidth - 24;
                  // 计算可见区域比例和滚动位置
                  final visibleRatio = _summaryScrollMaxExtent > 0 
                      ? containerWidth / (_summaryScrollMaxExtent + containerWidth)
                      : 0.0; // 如果内容不能滚动，不显示彩色条
                  final scrollRatio = _summaryScrollMaxExtent > 0 ? _summaryScrollPosition / _summaryScrollMaxExtent : 0.0;
                  final indicatorLeft = _summaryScrollMaxExtent > 0
                      ? scrollRatio * (containerWidth - containerWidth * visibleRatio)
                      : 0.0;
                  
                  return Container(
                    height: 4,
                    margin: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.grey[300],
                    ),
                    child: Stack(
                children: [
                        // 进度条（显示可见区域）- 只在内容可滚动时显示
                        if (_summaryScrollMaxExtent > 0)
                          Positioned(
                            left: indicatorLeft.clamp(0.0, containerWidth - containerWidth * visibleRatio),
                            child: Container(
                              width: containerWidth * visibleRatio,
                              height: 4,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}