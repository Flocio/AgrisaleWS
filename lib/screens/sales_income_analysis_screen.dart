import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/customer_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class SalesIncomeAnalysisScreen extends StatefulWidget {
  @override
  _SalesIncomeAnalysisScreenState createState() => _SalesIncomeAnalysisScreenState();
}

class _SalesIncomeAnalysisScreenState extends State<SalesIncomeAnalysisScreen> {
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  
  List<Map<String, dynamic>> _analysisData = [];
  bool _isLoading = false;
  bool _isDescending = true;
  String _sortColumn = 'date';
  
  // 筛选条件
  DateTimeRange? _selectedDateRange;
  String? _selectedCustomer;
  List<Customer> _customers = [];
  
  // 汇总数据
  double _totalNetSales = 0.0;
  double _totalActualPayment = 0.0;
  double _totalDiscount = 0.0;
  double _totalDifference = 0.0;
  
  // 汇总统计卡片是否展开（默认展开）
  bool _isSummaryExpanded = true;
  
  // 表头固定时：需要两个横向滚动控制器（一个 controller 不能同时绑定两个 ScrollView）
  final ScrollController _headerHorizontalScrollController = ScrollController();
  final ScrollController _dataHorizontalScrollController = ScrollController();
  bool _isSyncingFromHeader = false;
  bool _isSyncingFromData = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // 同步表头和数据的水平滚动（保持对齐）
    _headerHorizontalScrollController.addListener(_onHeaderHorizontalScroll);
    _dataHorizontalScrollController.addListener(_onDataHorizontalScroll);
  }
  
  void _onHeaderHorizontalScroll() {
    if (_isSyncingFromData) return;
    if (!_dataHorizontalScrollController.hasClients) return;
    _isSyncingFromHeader = true;
    final max = _dataHorizontalScrollController.position.maxScrollExtent;
    final target = _headerHorizontalScrollController.offset.clamp(0.0, max);
    if (_dataHorizontalScrollController.offset != target) {
      _dataHorizontalScrollController.jumpTo(target);
    }
    _isSyncingFromHeader = false;
  }

  void _onDataHorizontalScroll() {
    if (_isSyncingFromHeader) return;
    if (!_headerHorizontalScrollController.hasClients) return;
    _isSyncingFromData = true;
    final max = _headerHorizontalScrollController.position.maxScrollExtent;
    final target = _dataHorizontalScrollController.offset.clamp(0.0, max);
    if (_headerHorizontalScrollController.offset != target) {
      _headerHorizontalScrollController.jumpTo(target);
    }
    _isSyncingFromData = false;
  }

  @override
  void dispose() {
    _headerHorizontalScrollController.removeListener(_onHeaderHorizontalScroll);
    _dataHorizontalScrollController.removeListener(_onDataHorizontalScroll);
    _headerHorizontalScrollController.dispose();
    _dataHorizontalScrollController.dispose();
    super.dispose();
  }

  /// 首次加载时先拉取客户列表，再加载分析数据，避免客户名称缺失显示为“未指定客户”
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });
    await _fetchAnalysisData();
  }

  Future<void> _fetchCustomers() async {
    try {
      final customers = await _customerRepo.getAllCustomers();
      setState(() {
        _customers = customers;
      });
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载客户数据失败: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载客户数据失败: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchAnalysisData() async {
    try {
      // 并行获取所有数据（包括客户数据）
      final results = await Future.wait([
        _customerRepo.getAllCustomers(),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
      ]);
      
      // 先设置客户数据，确保后续处理可以使用
      final customers = results[0] as List<Customer>;
      setState(() {
        _customers = customers;
      });
      
      final salesResponse = results[1] as PaginatedResponse<Sale>;
      final returnsResponse = results[2] as PaginatedResponse<Return>;
      final incomesResponse = results[3] as PaginatedResponse<Income>;
      
      // 应用日期筛选
      String? startDate = _selectedDateRange?.start.toIso8601String().split('T')[0];
      String? endDate = _selectedDateRange?.end.toIso8601String().split('T')[0];
      
      List<Sale> sales = salesResponse.items;
      List<Return> returns = returnsResponse.items;
      List<Income> incomes = incomesResponse.items;
      
      // 应用日期筛选
      if (startDate != null) {
        sales = sales.where((s) => s.saleDate != null && s.saleDate!.compareTo(startDate!) >= 0).toList();
        returns = returns.where((r) => r.returnDate != null && r.returnDate!.compareTo(startDate!) >= 0).toList();
        incomes = incomes.where((i) => i.incomeDate != null && i.incomeDate!.compareTo(startDate!) >= 0).toList();
      }
      if (endDate != null) {
        sales = sales.where((s) => s.saleDate != null && s.saleDate!.compareTo(endDate!) <= 0).toList();
        returns = returns.where((r) => r.returnDate != null && r.returnDate!.compareTo(endDate!) <= 0).toList();
        incomes = incomes.where((i) => i.incomeDate != null && i.incomeDate!.compareTo(endDate!) <= 0).toList();
      }
      
      // 应用客户筛选
      int? selectedCustomerId;
      if (_selectedCustomer != null && _selectedCustomer != '所有客户') {
        final customer = _customers.firstWhere(
          (c) => c.name == _selectedCustomer,
          orElse: () => Customer(id: -1, userId: -1, name: ''),
        );
        if (customer.id != -1) {
          selectedCustomerId = customer.id;
          sales = sales.where((s) => s.customerId == selectedCustomerId).toList();
          returns = returns.where((r) => r.customerId == selectedCustomerId).toList();
          incomes = incomes.where((i) => i.customerId == selectedCustomerId).toList();
        }
      }

      // 按日期和客户分组
      Map<String, Map<String, dynamic>> combinedData = {};
      
      // 处理销售数据
      for (var sale in sales) {
        if (sale.saleDate == null) continue;
        final date = sale.saleDate!.split('T')[0];
        final customerId = sale.customerId ?? -1;
        String key = '${date}_$customerId';
        
        final customerName = customerId != -1 
            ? _customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: -1, userId: -1, name: '未指定客户')).name
            : '未指定客户';
        
        if (combinedData.containsKey(key)) {
          combinedData[key]!['totalSales'] = (combinedData[key]!['totalSales'] as double) + (sale.totalSalePrice ?? 0.0);
        } else {
          combinedData[key] = {
            'date': date,
            'customerName': customerName,
            'customerId': customerId,
            'totalSales': sale.totalSalePrice ?? 0.0,
            'totalReturns': 0.0,
            'totalPayment': 0.0,
            'totalDiscount': 0.0,
          };
        }
      }
      
      // 处理退货数据
      for (var returnItem in returns) {
        if (returnItem.returnDate == null) continue;
        final date = returnItem.returnDate!.split('T')[0];
        final customerId = returnItem.customerId ?? -1;
        String key = '${date}_$customerId';
        
        final customerName = customerId != -1 
            ? _customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: -1, userId: -1, name: '未指定客户')).name
            : '未指定客户';
        
        if (combinedData.containsKey(key)) {
          combinedData[key]!['totalReturns'] = (combinedData[key]!['totalReturns'] as double) + (returnItem.totalReturnPrice ?? 0.0);
        } else {
          combinedData[key] = {
            'date': date,
            'customerName': customerName,
            'customerId': customerId,
            'totalSales': 0.0,
            'totalReturns': returnItem.totalReturnPrice ?? 0.0,
            'totalPayment': 0.0,
            'totalDiscount': 0.0,
          };
        }
      }
      
      // 处理进账数据
      for (var income in incomes) {
        if (income.incomeDate == null) continue;
        final date = income.incomeDate!.split('T')[0];
        final customerId = income.customerId ?? -1;
        String key = '${date}_$customerId';
        
        final customerName = customerId != -1 
            ? _customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: -1, userId: -1, name: '未指定客户')).name
            : '未指定客户';
        
        if (combinedData.containsKey(key)) {
          combinedData[key]!['totalPayment'] = (combinedData[key]!['totalPayment'] as double) + (income.amount ?? 0.0);
          combinedData[key]!['totalDiscount'] = (combinedData[key]!['totalDiscount'] as double) + (income.discount ?? 0.0);
        } else {
          combinedData[key] = {
            'date': date,
            'customerName': customerName,
            'customerId': customerId,
            'totalSales': 0.0,
            'totalReturns': 0.0,
            'totalPayment': income.amount ?? 0.0,
            'totalDiscount': income.discount ?? 0.0,
          };
        }
      }

      // 计算净销售额、理论应付、实际应付和差值
      List<Map<String, dynamic>> analysisData = [];
      for (var data in combinedData.values) {
        double netSales = data['totalSales'] - data['totalReturns'];
        double actualPayment = data['totalPayment'];
        double discount = data['totalDiscount'];
        double theoreticalPayable = netSales;
        double actualPayable = actualPayment + discount;
        double difference = theoreticalPayable - actualPayable;
        
        analysisData.add({
          'date': data['date'],
          'customerName': data['customerName'],
          'customerId': data['customerId'],
          'totalSales': data['totalSales'],
          'totalReturns': data['totalReturns'],
          'netSales': netSales,
          'actualPayment': actualPayment,
          'discount': discount,
          'theoreticalPayable': theoreticalPayable,
          'actualPayable': actualPayable,
          'difference': difference,
        });
      }

      // 排序
      _sortData(analysisData);
      
      // 计算汇总
      _calculateSummary(analysisData);

      setState(() {
        _analysisData = analysisData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('数据加载失败: ${e.toString()}');
      }
      print('销售进账分析数据加载错误: $e');
    }
  }

  void _sortData(List<Map<String, dynamic>> data) {
    data.sort((a, b) {
      dynamic aValue = a[_sortColumn];
      dynamic bValue = b[_sortColumn];
      
      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return _isDescending ? 1 : -1;
      if (bValue == null) return _isDescending ? -1 : 1;
      
      int comparison;
      if (aValue is String && bValue is String) {
        comparison = aValue.compareTo(bValue);
      } else if (aValue is num && bValue is num) {
        comparison = aValue.compareTo(bValue);
      } else {
        comparison = aValue.toString().compareTo(bValue.toString());
      }
      
      return _isDescending ? -comparison : comparison;
    });
  }

  void _calculateSummary(List<Map<String, dynamic>> data) {
    double totalNetSales = 0.0;
    double totalActualPayment = 0.0;
    double totalDiscount = 0.0;
    double totalDifference = 0.0;

    for (var item in data) {
      totalNetSales += item['netSales'];
      totalActualPayment += item['actualPayment'];
      totalDiscount += item['discount'];
      totalDifference += item['difference'];
    }

    setState(() {
      _totalNetSales = totalNetSales;
      _totalActualPayment = totalActualPayment;
      _totalDiscount = totalDiscount;
      _totalDifference = totalDifference;
    });
  }

  void _onSort(String columnName) {
    setState(() {
      if (_sortColumn == columnName) {
        _isDescending = !_isDescending;
      } else {
        _sortColumn = columnName;
        _isDescending = true;
      }
      _sortData(_analysisData);
    });
  }

  Future<void> _exportToCSV() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    rows.add(['总销售-进账明细分析 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    
    // 添加筛选条件
    String customerFilter = _selectedCustomer ?? '所有客户';
    rows.add(['客户筛选: $customerFilter']);
    
    String dateFilter = '所有日期';
    if (_selectedDateRange != null) {
      dateFilter = '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
    }
    rows.add(['日期范围: $dateFilter']);
    rows.add([]);
    
    // 表头
    rows.add(['日期', '客户', '销售总额', '退货总额', '净销售额', '应收', '优惠金额', '实际收款', '差值']);

    // 数据行
    for (var item in _analysisData) {
      rows.add([
        item['date'],
        item['customerName'],
        item['totalSales'].toStringAsFixed(2),
        item['totalReturns'].toStringAsFixed(2),
        item['netSales'].toStringAsFixed(2),
        item['actualPayable'].toStringAsFixed(2),
        item['discount'].toStringAsFixed(2),
        item['actualPayment'].toStringAsFixed(2),
        item['difference'].toStringAsFixed(2),
      ]);
    }

    // 总计行
    rows.add([]);
    rows.add([
      '总计', '', '', '',
      _totalNetSales.toStringAsFixed(2),
      (_totalActualPayment + _totalDiscount).toStringAsFixed(2), // 应收
      _totalDiscount.toStringAsFixed(2),
      _totalActualPayment.toStringAsFixed(2), // 实际收款
      _totalDifference.toStringAsFixed(2),
    ]);

    String csv = const ListToCsvConverter().convert(rows);

    // 导出文件名：默认“销售与进账统计”，如筛选客户则“{客户名}_销售与进账统计”
    String baseFileName = '销售与进账统计';
    if (_selectedCustomer != null && _selectedCustomer != '所有客户') {
      baseFileName = '${_selectedCustomer}_销售与进账统计';
    }

    // 使用统一的导出服务
    await ExportService.showExportOptions(
      context: context,
      csvData: csv,
      baseFileName: baseFileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('销售与进账', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _fetchAnalysisData,
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
          // 筛选条件
          _buildFilterSection(),
          
          // 汇总信息卡片
          _buildSummaryCard(),
          
          // 提示信息
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '每日的销售额（含退货）与实际收款的对应情况，差值为正表示欠款（赊账金额），差值为负表示超收（预收金额）',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 数据表格
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _analysisData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.analytics, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              '暂无分析数据',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildDataTable(),
          ),
          
          FooterWidget(),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            children: [
              // 客户筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('客户筛选', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    DropdownButtonHideUnderline(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButton<String>(
                          hint: Text('选择客户'),
                          value: _selectedCustomer,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCustomer = newValue;
                              _fetchAnalysisData();
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: '所有客户',
                              child: Text('所有客户'),
                            ),
                            ..._customers.map((customer) {
                              return DropdownMenuItem<String>(
                                value: customer.name,
                                child: Text(customer.name),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16),
              // 日期范围筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('日期范围', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          lastDate: DateTime.now(),
                        );
                        
                        if (pickedRange != null) {
                          setState(() {
                            _selectedDateRange = pickedRange;
                            _fetchAnalysisData();
                          });
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDateRange != null
                                    ? '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}'
                                    : '选择日期范围',
                                style: TextStyle(
                                  color: _selectedDateRange != null ? Colors.black87 : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_selectedDateRange != null || _selectedCustomer != null) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Text('清除筛选: ', style: TextStyle(color: Colors.grey[600])),
                if (_selectedDateRange != null)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDateRange = null;
                          _fetchAnalysisData();
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('日期范围', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Icon(Icons.close, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_selectedCustomer != null && _selectedCustomer != '所有客户')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCustomer = null;
                        _fetchAnalysisData();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                                              child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('客户: $_selectedCustomer', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Icon(Icons.close, size: 14),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '汇总统计',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSummaryExpanded = !_isSummaryExpanded;
                    });
                  },
                  child: Icon(
                    _isSummaryExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 20,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('净销售额', _formatMoney(_totalNetSales), Colors.blue),
                  _buildSummaryItem('实际收款', _formatMoney(_totalActualPayment), Colors.green),
                  _buildSummaryItem('优惠总额', _formatMoney(_totalDiscount), Colors.orange),
                  _buildSummaryItem('差值', _formatMoney(_totalDifference), _totalDifference >= 0 ? Colors.red : Colors.purple),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 4),
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

  // 负数金额显示为 -¥123.45，正数保持 ¥123.45
  String _formatMoney(double value) {
    final absText = value.abs().toStringAsFixed(2);
    return value < 0 ? '-¥$absText' : '¥$absText';
  }

  // 仅固定表头（上下滚动时可见），保持原 DataTable 的字体/间距/颜色/对齐
  Widget _buildDataTable() {
    // 原始列定义（保持原样）
    final columns = <DataColumn>[
      DataColumn(
        label: Text('日期'),
        onSort: (columnIndex, ascending) => _onSort('date'),
      ),
      DataColumn(
        label: Text('客户'),
        onSort: (columnIndex, ascending) => _onSort('customerName'),
      ),
      DataColumn(
        label: Text('销售总额'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('totalSales'),
      ),
      DataColumn(
        label: Text('退货总额'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('totalReturns'),
      ),
      DataColumn(
        label: Text('净销售额'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('netSales'),
      ),
      DataColumn(
        label: Text('应收'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('actualPayable'),
      ),
      DataColumn(
        label: Text('优惠金额'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('discount'),
      ),
      DataColumn(
        label: Text('实际收款'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('actualPayment'),
      ),
      DataColumn(
        label: Text('差值'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('difference'),
      ),
    ];

    // 构造用于“撑开列宽”的隐形行（保证表头与数据列宽一致）
    // 注意：表头 DataTable 没有真实数据行，所以必须用该隐形行把列宽撑到“数据区域的最大宽度”。
    String maxDate = '';
    String maxCustomer = '';
    String maxTotalSales = '¥0.00';
    String maxTotalReturns = '¥0.00';
    String maxNetSales = '¥0.00';
    String maxActualPayable = '¥0.00';
    String maxDiscount = '¥0.00';
    String maxActualPayment = '¥0.00';
    String maxDifference = '¥0.00';

    for (final item in _analysisData) {
      final String date = (item['date'] ?? '').toString();
      final String customer = (item['customerName'] ?? '').toString();
      final String totalSales = _formatMoney((item['totalSales'] as num).toDouble());
      final String totalReturns = _formatMoney((item['totalReturns'] as num).toDouble());
      final String netSales = _formatMoney((item['netSales'] as num).toDouble());
      final String actualPayable = _formatMoney((item['actualPayable'] as num).toDouble());
      final String discount = _formatMoney((item['discount'] as num).toDouble());
      final String actualPayment = _formatMoney((item['actualPayment'] as num).toDouble());
      final String difference = _formatMoney((item['difference'] as num).toDouble());

      if (date.length > maxDate.length) maxDate = date;
      if (customer.length > maxCustomer.length) maxCustomer = customer;
      if (totalSales.length > maxTotalSales.length) maxTotalSales = totalSales;
      if (totalReturns.length > maxTotalReturns.length) maxTotalReturns = totalReturns;
      if (netSales.length > maxNetSales.length) maxNetSales = netSales;
      if (actualPayable.length > maxActualPayable.length) maxActualPayable = actualPayable;
      if (discount.length > maxDiscount.length) maxDiscount = discount;
      if (actualPayment.length > maxActualPayment.length) maxActualPayment = actualPayment;
      if (difference.length > maxDifference.length) maxDifference = difference;
    }

    // 也考虑“总计行”的数值宽度（避免总计更宽导致对齐偏差）
    final String totalNetSalesText = _formatMoney(_totalNetSales);
    final String totalPayableText = _formatMoney(_totalActualPayment + _totalDiscount);
    final String totalDiscountText = _formatMoney(_totalDiscount);
    final String totalActualPaymentText = _formatMoney(_totalActualPayment);
    final String totalDifferenceText = _formatMoney(_totalDifference);

    if (totalNetSalesText.length > maxNetSales.length) maxNetSales = totalNetSalesText;
    if (totalPayableText.length > maxActualPayable.length) maxActualPayable = totalPayableText;
    if (totalDiscountText.length > maxDiscount.length) maxDiscount = totalDiscountText;
    if (totalActualPaymentText.length > maxActualPayment.length) maxActualPayment = totalActualPaymentText;
    if (totalDifferenceText.length > maxDifference.length) maxDifference = totalDifferenceText;

    final List<DataRow> headerSizerRows = [
      DataRow(
        cells: [
          DataCell(Opacity(opacity: 0, child: Text(maxDate))),
          DataCell(Opacity(opacity: 0, child: Text(maxCustomer))),
          DataCell(Opacity(opacity: 0, child: Text(maxTotalSales))),
          DataCell(Opacity(opacity: 0, child: Text(maxTotalReturns))),
          DataCell(Opacity(opacity: 0, child: Text(maxNetSales))),
          DataCell(Opacity(opacity: 0, child: Text(maxActualPayable))),
          DataCell(Opacity(opacity: 0, child: Text(maxDiscount))),
          DataCell(Opacity(opacity: 0, child: Text(maxActualPayment))),
          DataCell(Opacity(opacity: 0, child: Text(maxDifference))),
        ],
      ),
    ];

    final bodyRows = <DataRow>[
      ..._analysisData.map((item) {
        return DataRow(
          cells: [
            DataCell(Text(item['date'] ?? '')),
            DataCell(Text(item['customerName'] ?? '')),
            DataCell(Text(_formatMoney((item['totalSales'] as num).toDouble()))),
            DataCell(Text(_formatMoney((item['totalReturns'] as num).toDouble()))),
            DataCell(Text(_formatMoney((item['netSales'] as num).toDouble()),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            DataCell(Text(_formatMoney((item['actualPayable'] as num).toDouble()))),
            DataCell(item['discount'] > 0
                ? Text(_formatMoney((item['discount'] as num).toDouble()),
                    style: TextStyle(color: Colors.orange))
                : Text('')),
            DataCell(Text(_formatMoney((item['actualPayment'] as num).toDouble()),
                style: TextStyle(color: Colors.green))),
            DataCell(Text(_formatMoney((item['difference'] as num).toDouble()),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: item['difference'] >= 0 ? Colors.red : Colors.purple))),
          ],
        );
      }).toList(),
      if (_analysisData.isNotEmpty)
        DataRow(
          color: MaterialStateProperty.all(Colors.grey[100]),
          cells: [
            DataCell(Text('总计', style: TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text('')),
            DataCell(Text('')),
            DataCell(Text('')),
            DataCell(Text(_formatMoney(_totalNetSales),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            DataCell(Text(_formatMoney(_totalActualPayment + _totalDiscount),
                style: TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(_formatMoney(_totalDiscount),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
            DataCell(Text(_formatMoney(_totalActualPayment),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
            DataCell(Text(_formatMoney(_totalDifference),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _totalDifference >= 0 ? Colors.red : Colors.purple))),
          ],
        ),
    ];

    return Column(
      children: [
        // 固定表头（仅垂直方向固定；水平方向与数据同步）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _headerHorizontalScrollController,
          child: DataTable(
            sortColumnIndex: _getSortColumnIndex(),
            sortAscending: !_isDescending,
            horizontalMargin: 12,
            columnSpacing: 16,
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
              fontSize: 12,
            ),
            dataTextStyle: TextStyle(fontSize: 11),
            // 用 0 高度的数据行撑列宽，不改变视觉（只显示表头）
            dataRowMinHeight: 0,
            dataRowMaxHeight: 0,
            columns: columns,
            rows: headerSizerRows,
          ),
        ),
        // 数据区域（可上下滚动；左右滚动与表头共用 controller 保持对齐）
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _dataHorizontalScrollController,
              child: DataTable(
                horizontalMargin: 12,
                columnSpacing: 16,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                  fontSize: 12,
                ),
                dataTextStyle: TextStyle(fontSize: 11),
                // 隐藏表头（仅显示数据），但列定义保持一致以确保对齐
                headingRowHeight: 0,
                columns: columns,
                rows: bodyRows,
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _getSortColumnIndex() {
    switch (_sortColumn) {
      case 'date': return 0;
      case 'customerName': return 1;
      case 'totalSales': return 2;
      case 'totalReturns': return 3;
      case 'netSales': return 4;
      case 'actualPayable': return 5;
      case 'discount': return 6;
      case 'actualPayment': return 7;
      case 'difference': return 8;
      default: return 0;
    }
  }
}
 