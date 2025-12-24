import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/customer_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product; // 保持 Map 格式以兼容现有调用

  ProductDetailScreen({required this.product});

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  
  List<Map<String, dynamic>> _allRecords = []; // 存储所有记录
  List<Map<String, dynamic>> _filteredRecords = []; // 存储筛选后的记录
  List<Supplier> _suppliers = [];
  List<Customer> _customers = [];
  String? _productSupplierName; // 产品关联的供应商名称
  bool _isDescending = true; // 默认按时间倒序排列
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  bool _isLoading = false;
  
  // 交易类型排序顺序，数字越小越靠前
  Map<String, int> _typeOrderMap = {
    '采购': 1,
    '销售': 2,
    '退货': 3,
  };

  // 滚动控制器和指示器
  ScrollController? _summaryScrollController;
  double _summaryScrollPosition = 0.0;
  double _summaryScrollMaxExtent = 0.0;

  // 汇总数据
  double _purchaseQuantity = 0.0; // 采购总量（所有采购记录数量的绝对值相加）
  double _purchaseAmount = 0.0; // 采购总额（所有采购记录金额相加的负数）
  double _saleQuantity = 0.0;
  double _saleAmount = 0.0;
  double _returnQuantity = 0.0;
  double _returnAmount = 0.0;
  double _currentStock = 0.0;
  double _totalChange = 0.0; // 总量变化
  double _netProfit = 0.0; // 净利润

  @override
  void initState() {
    super.initState();
    _summaryScrollController = ScrollController();
    _summaryScrollController!.addListener(_onSummaryScroll);
    _loadSortPreference();
    _fetchData();
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

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDescending = prefs.getBool('product_detail_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('product_detail_sort_descending', _isDescending);
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _saveSortPreference();
      _sortRecords();
    });
  }

  void _sortRecords() {
    _filteredRecords.sort((a, b) {
      int result;
      
      // 一级排序：按日期
      result = _isDescending
          ? b['date'].toString().compareTo(a['date'].toString())
          : a['date'].toString().compareTo(b['date'].toString());
      
      // 如果日期相同，则按交易类型排序
      if (result == 0) {
        final aTypeOrder = _typeOrderMap[a['recordType']] ?? 99;
        final bTypeOrder = _typeOrderMap[b['recordType']] ?? 99;
        result = aTypeOrder.compareTo(bTypeOrder);
      }
      
      return result;
    });
    setState(() {});
  }

  // 更改交易类型排序顺序
  void _showTypeOrderDialog() {
    final List<String> types = ['采购', '销售', '退货'];
    final List<int> positions = [1, 2, 3]; // 可选位置：第一、第二、第三
    Map<String, int> tempTypeOrderMap = Map.from(_typeOrderMap);
    
    // 为选择器准备当前位置数据
    Map<String, int> currentPositions = {};
    types.forEach((type) {
      currentPositions[type] = tempTypeOrderMap[type] ?? 99;
    });
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('设置交易类型顺序'),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('请为每种交易类型选择显示顺序：', style: TextStyle(fontSize: 14)),
                  SizedBox(height: 16),
                  ...types.map((type) {
                    Color typeColor = type == '采购' 
                      ? Colors.blue 
                      : (type == '销售' ? Colors.green : Colors.red);
                    IconData typeIcon = type == '采购' 
                      ? Icons.arrow_downward 
                      : (type == '销售' ? Icons.arrow_upward : Icons.compare_arrows);
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Icon(typeIcon, color: typeColor),
                          SizedBox(width: 8),
                          Text(type, style: TextStyle(fontWeight: FontWeight.bold)),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: DropdownButton<int>(
                              value: currentPositions[type],
                              underline: SizedBox(),
                              items: positions.map((position) {
                                return DropdownMenuItem<int>(
                                  value: position,
                                  child: Text('第$position位'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    // 如果有其他类型已经占用了这个位置，交换它们的位置
                                    String? typeAtSamePosition;
                                    currentPositions.forEach((t, p) {
                                      if (p == value && t != type) {
                                        typeAtSamePosition = t;
                                      }
                                    });
                                    
                                    if (typeAtSamePosition != null) {
                                      currentPositions[typeAtSamePosition!] = currentPositions[type]!;
                                    }
                                    
                                    currentPositions[type] = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  // 应用新的排序顺序
                  setState(() {
                    types.forEach((type) {
                      tempTypeOrderMap[type] = currentPositions[type]!;
                    });
                    _typeOrderMap = tempTypeOrderMap;
                  });
                  Navigator.of(context).pop();
                  _sortRecords(); // 重新排序
                },
                child: Text('确定'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final productName = widget.product['name'] as String;
        
      // 并行获取所有数据
      final results = await Future.wait([
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _supplierRepo.getAllSuppliers(),
        _customerRepo.getAllCustomers(),
      ]);
      
      final purchasesResponse = results[0] as PaginatedResponse<Purchase>;
      final salesResponse = results[1] as PaginatedResponse<Sale>;
      final returnsResponse = results[2] as PaginatedResponse<Return>;
      final suppliers = results[3] as List<Supplier>;
      final customers = results[4] as List<Customer>;
      
      // 按产品名称筛选
      final purchases = purchasesResponse.items.where((p) => p.productName == productName).toList();
      final sales = salesResponse.items.where((s) => s.productName == productName).toList();
      final returns = returnsResponse.items.where((r) => r.productName == productName).toList();

      // 获取产品关联的供应商名称
      String? productSupplierName;
      final productSupplierId = widget.product['supplierId'] as int?;
      if (productSupplierId != null) {
        final productSupplier = suppliers.firstWhere(
          (s) => s.id == productSupplierId,
          orElse: () => Supplier(id: -1, userId: -1, name: '未知供应商'),
        );
        productSupplierName = productSupplier.name;
      }

    // 合并所有记录
    List<Map<String, dynamic>> allRecords = [];
    
    // 添加采购数据
    for (var purchase in purchases) {
      final supplier = suppliers.firstWhere(
          (s) => s.id == purchase.supplierId,
          orElse: () => Supplier(id: -1, userId: -1, name: '未知供应商'),
      );
      
      allRecords.add({
          'date': purchase.purchaseDate ?? '',
          'productName': purchase.productName,
          'quantity': purchase.quantity,
          'partnerId': purchase.supplierId,
          'partnerName': supplier.name,
        'partnerType': 'supplier',
        'totalPrice': purchase.totalPurchasePrice ?? 0.0, // 正数代表采购，负数代表采购退货
          'note': purchase.note ?? '',
        'recordType': '采购',
        'valueSign': 1, // 正值
      });
    }
    
    // 添加销售数据
    for (var sale in sales) {
      final customer = customers.firstWhere(
          (c) => c.id == sale.customerId,
          orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      
      allRecords.add({
          'date': sale.saleDate ?? '',
          'productName': sale.productName,
          'quantity': sale.quantity,
          'partnerId': sale.customerId,
          'partnerName': customer.name,
        'partnerType': 'customer',
        'totalPrice': sale.totalSalePrice ?? 0.0, // 正数代表销售
          'note': sale.note ?? '',
        'recordType': '销售',
        'valueSign': -1, // 负值
      });
    }
    
    // 添加退货数据
    for (var returnItem in returns) {
      final customer = customers.firstWhere(
          (c) => c.id == returnItem.customerId,
          orElse: () => Customer(id: -1, userId: -1, name: '未知客户'),
      );
      
      allRecords.add({
          'date': returnItem.returnDate ?? '',
          'productName': returnItem.productName,
          'quantity': returnItem.quantity,
          'partnerId': returnItem.customerId,
          'partnerName': customer.name,
        'partnerType': 'customer',
        'totalPrice': returnItem.totalReturnPrice ?? 0.0, // 正数代表退货
          'note': returnItem.note ?? '',
        'recordType': '退货',
        'valueSign': 1, // 正值
      });
    }

    // 按日期和交易类型排序
    allRecords.sort((a, b) {
      int result;
      
      // 一级排序：按日期
      result = _isDescending
          ? b['date'].toString().compareTo(a['date'].toString())
          : a['date'].toString().compareTo(b['date'].toString());
      
      // 如果日期相同，则按交易类型排序
      if (result == 0) {
        final aTypeOrder = _typeOrderMap[a['recordType']] ?? 99;
        final bTypeOrder = _typeOrderMap[b['recordType']] ?? 99;
        result = aTypeOrder.compareTo(bTypeOrder);
      }
      
      return result;
    });

    // 计算汇总数据
    _calculateSummary(allRecords);

        setState(() {
          _allRecords = allRecords;
          _filteredRecords = allRecords;
          _suppliers = suppliers;
          _customers = customers;
        _productSupplierName = productSupplierName;
        _currentStock = (widget.product['stock'] as num?)?.toDouble() ?? 0.0;
        _isLoading = false;
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

  void _calculateSummary(List<Map<String, dynamic>> records) {
    double purchaseQuantity = 0.0; // 采购总量：所有采购记录数量相加（包括正数和负数）
    double purchaseAmountSum = 0.0; // 采购金额总和（用于计算采购总额）
    double saleQuantity = 0.0;
    double saleAmount = 0.0;
    double returnQuantity = 0.0;
    double returnAmount = 0.0;

    for (var record in records) {
      if (record['recordType'] == '采购') {
        // 采购总量：数量直接相加（包括正数和负数）
        purchaseQuantity += (record['quantity'] as num).toDouble();
        // 采购金额：直接相加（后面会取负数）
        purchaseAmountSum += (record['totalPrice'] as num).toDouble();
      } else if (record['recordType'] == '销售') {
        saleQuantity += (record['quantity'] as num).toDouble();
        saleAmount += (record['totalPrice'] as num).toDouble();
      } else if (record['recordType'] == '退货') {
        returnQuantity += (record['quantity'] as num).toDouble();
        returnAmount += (record['totalPrice'] as num).toDouble();
      }
    }

    // 采购总额：金额相加后取负数（正数代表花出去的钱，用负号显示）
    double purchaseAmount = -purchaseAmountSum;
    // 总量变化：采购总量 + 销售总量（负数显示） + 退货总量（正数显示）
    // 其中：采购总量 = purchaseQuantity（正负混合）、
    //       销售总量显示为 -saleQuantity、
    //       退货总量显示为 +returnQuantity
    // 因此总量变化应为：purchaseQuantity - saleQuantity + returnQuantity
    double totalChange = purchaseQuantity - saleQuantity + returnQuantity;
    // 净利润：销售总额 - 采购总额（负数） - 退货总额 = 销售总额 + 采购总额 - 退货总额
    double netProfit = saleAmount + purchaseAmount - returnAmount;

    setState(() {
      _purchaseQuantity = purchaseQuantity;
      _purchaseAmount = purchaseAmount;
      _saleQuantity = saleQuantity;
      _saleAmount = saleAmount;
      _returnQuantity = returnQuantity;
      _returnAmount = returnAmount;
      _totalChange = totalChange;
      _netProfit = netProfit;
    });
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

  // 导出为CSV文件
  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    String csvData = '产品详情报告 - 用户: $username\n';
    csvData += '导出时间: ${DateTime.now().toString().substring(0, 19)}\n';
    csvData += '产品名称: ${widget.product['name']}\n';
    if (_productSupplierName != null) {
      csvData += '关联供应商: $_productSupplierName\n';
    }
    csvData += '\n';
    csvData += '日期,类型,产品,数量,单位,交易方,金额,备注\n';
    
    for (var record in _filteredRecords) {
      // 对于采购 / 退货记录，数量和金额需要特殊处理
      String quantityText;
      String amountText;

      if (record['recordType'] == '采购') {
        // 采购记录：数量直接显示，金额取负数
        final quantity = (record['quantity'] as num).toDouble();
        final amount = (record['totalPrice'] as num).toDouble();
        quantityText = '${quantity >= 0 ? '+' : ''}${_formatNumber(quantity)}';
        amountText = (-amount).toStringAsFixed(2);
      } else if (record['recordType'] == '销售') {
        // 销售记录：数量显示负号，金额显示正数
        quantityText = '-${_formatNumber(record['quantity'])}';
        amountText = (record['totalPrice'] as num).toDouble().toStringAsFixed(2);
      } else {
        // 退货记录：数量为正（显示+号），金额为负
        final quantity = (record['quantity'] as num).toDouble();
        final amount = (record['totalPrice'] as num).toDouble();
        quantityText = '+${_formatNumber(quantity)}';
        amountText = (-amount).toStringAsFixed(2);
      }
      
      csvData += '${record['date']},${record['recordType']},${record['productName']},$quantityText,${widget.product['unit']},${record['partnerName']},$amountText,${record['note'] ?? ''}\n';
    }
    
    // 添加汇总信息
    csvData += '\n汇总信息\n';
    csvData += '当前库存,${_formatNumber(_currentStock)},${widget.product['unit']}\n';
    csvData += '总记录数,${_filteredRecords.length}\n';
    csvData += '采购总量,${_formatNumber(_purchaseQuantity)},${widget.product['unit']}\n';
    csvData += '销售总量,${_formatNumber(_saleQuantity)},${widget.product['unit']}\n';
    csvData += '退货总量,${_formatNumber(_returnQuantity)},${widget.product['unit']}\n';
    csvData += '总量变化,${_formatNumber(_totalChange)},${widget.product['unit']}\n';
    csvData += '采购总额,${_purchaseAmount.toStringAsFixed(2)}\n';
    csvData += '销售总额,${_saleAmount.toStringAsFixed(2)}\n';
    csvData += '退货总额,${_returnAmount.toStringAsFixed(2)}\n';
    csvData += '净利润,${_netProfit.toStringAsFixed(2)}\n';

    // 使用统一的导出服务（时间戳由 ExportService 统一追加）
    await ExportService.showExportOptions(
      context: context,
      csvData: csvData,
      baseFileName: '${widget.product['name']}_库存记录',
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.product['name']}的记录', 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )
        ),
        actions: [
          // 时间排序按钮（放在前面）
          IconButton(
            icon: Icon(_isDescending ? Icons.arrow_downward : Icons.arrow_upward),
            tooltip: '切换排序',
            onPressed: _toggleSortOrder,
          ),
          // 添加类型排序按钮
          IconButton(
            icon: Icon(Icons.swap_vert),
            tooltip: '设置交易类型排序',
            onPressed: _showTypeOrderDialog,
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
          // 产品信息和汇总信息合并卡片
          _buildCombinedInfoCard(),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green[100],
                  radius: 14,
                  child: Text(
                    widget.product['name'] != null && widget.product['name'].toString().isNotEmpty
                        ? widget.product['name'].toString()[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '产品交易记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
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
                    '共 ${_filteredRecords.length} 条记录',
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
          
          _isLoading && _filteredRecords.isEmpty
            ? Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            : _filteredRecords.isEmpty 
            ? Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            '暂无交易记录',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
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
                          DataColumn(label: Text('数量')),
                          DataColumn(label: Text('单位')),
                          DataColumn(label: Text('交易方')),
                          DataColumn(label: Text('金额')),
                          DataColumn(label: Text('备注')),
                        ],
                        rows: _filteredRecords.map((record) {
                          // 设置颜色
                          Color typeColor;
                          if (record['recordType'] == '采购') {
                            typeColor = Colors.blue;
                          } else if (record['recordType'] == '销售') {
                            typeColor = Colors.green;
                          } else { // 退货
                            typeColor = Colors.red;
                          }
                          
                          // 对于采购 / 退货记录，数量和金额需要特殊处理
                          String quantityText;
                          String amountText;

                          if (record['recordType'] == '采购') {
                            // 采购记录：数量直接显示，金额取负数
                            final quantity = (record['quantity'] as num).toDouble();
                            final amount = (record['totalPrice'] as num).toDouble();
                            quantityText = '${quantity >= 0 ? '+' : ''}${_formatNumber(quantity)}';
                            final negAmount = -amount;
                            amountText = '${negAmount >= 0 ? '+' : '-'}¥${negAmount.abs().toStringAsFixed(2)}';
                          } else if (record['recordType'] == '销售') {
                            // 销售记录：数量显示负号，金额显示正号
                            quantityText = '-${_formatNumber(record['quantity'])}';
                            amountText = '+¥${(record['totalPrice'] as num).toDouble().toStringAsFixed(2)}';
                          } else {
                            // 退货记录：数量为正（显示+号），金额为负
                            final quantity = (record['quantity'] as num).toDouble();
                            final amount = (record['totalPrice'] as num).toDouble();
                            quantityText = '+${_formatNumber(quantity)}';
                            amountText = '-¥${amount.abs().toStringAsFixed(2)}';
                          }
                          
                          return DataRow(
                            cells: [
                              DataCell(Text(record['date'])),
                              DataCell(
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: typeColor.withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    record['recordType'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: typeColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  quantityText,
                                  style: TextStyle(
                                    color: typeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              ),
                              DataCell(
                                Text(
                                  widget.product['unit'],
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                  ),
                                )
                              ),
                              DataCell(Text(record['partnerName'])),
                              DataCell(
                                Text(
                                  amountText,
                                  style: TextStyle(
                                    color: typeColor,
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

  // 合并产品信息和汇总信息卡片
  Widget _buildCombinedInfoCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      color: Colors.green[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 产品基本信息和汇总信息标题放在同一行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 产品信息
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2, color: Colors.green, size: 16),
                    SizedBox(width: 8),
                          Flexible(
                            child: Text(
                          _productSupplierName != null
                              ? '${widget.product['name']} (${widget.product['unit']})    $_productSupplierName'
                              : '${widget.product['name']} (${widget.product['unit']})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                      ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                  ),
                ),
                // 汇总信息标题和折叠按钮
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
                          color: Colors.green[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 16,
                        color: Colors.green[800],
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
                        _buildSummaryItem('当前库存', '${_formatNumber(_currentStock)} ${widget.product['unit']}', Colors.purple),
                        SizedBox(width: 16),
                        _buildSummaryItem('总记录数', '${_filteredRecords.length}', Colors.purple),
                        SizedBox(width: 16),
                        _buildSummaryItem('采购总量', '${_purchaseQuantity >= 0 ? '+' : ''}${_formatNumber(_purchaseQuantity)} ${widget.product['unit']}', Colors.blue),
                        SizedBox(width: 16),
                  _buildSummaryItem('销售总量', '-${_formatNumber(_saleQuantity)} ${widget.product['unit']}', Colors.green),
                        SizedBox(width: 16),
                  _buildSummaryItem('退货总量', '+${_formatNumber(_returnQuantity)} ${widget.product['unit']}', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('总量变化', '${_totalChange >= 0 ? '+' : ''}${_formatNumber(_totalChange)} ${widget.product['unit']}', _totalChange >= 0 ? Colors.green : Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('采购总额', '${_purchaseAmount >= 0 ? '+' : '-'}¥${_purchaseAmount.abs().toStringAsFixed(2)}', Colors.blue),
                        SizedBox(width: 16),
                  _buildSummaryItem('销售总额', '+¥${_saleAmount.toStringAsFixed(2)}', Colors.green),
                        SizedBox(width: 16),
                  _buildSummaryItem('退货总额', '-¥${_returnAmount.toStringAsFixed(2)}', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('净利润', '${_netProfit >= 0 ? '+' : '-'}¥${_netProfit.abs().toStringAsFixed(2)}', _netProfit >= 0 ? Colors.green : Colors.red),
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
                                color: Colors.green[700],
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