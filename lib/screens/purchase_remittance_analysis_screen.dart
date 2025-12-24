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
import '../repositories/remittance_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class PurchaseRemittanceAnalysisScreen extends StatefulWidget {
  @override
  _PurchaseRemittanceAnalysisScreenState createState() => _PurchaseRemittanceAnalysisScreenState();
}

class _PurchaseRemittanceAnalysisScreenState extends State<PurchaseRemittanceAnalysisScreen> {
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  
  List<Map<String, dynamic>> _analysisData = [];
  bool _isLoading = false;
  bool _isDescending = true;
  String _sortColumn = 'date';
  
  // 筛选条件
  DateTimeRange? _selectedDateRange;
  String? _selectedSupplier;
  List<Supplier> _suppliers = [];
  
  // 汇总数据
  double _totalPurchases = 0.0;
  double _totalRemittances = 0.0;
  double _totalDifference = 0.0;
  
  // 汇总统计卡片是否展开（默认展开）
  bool _isSummaryExpanded = true;
  
  // 表头固定：水平滚动同步（保持原 DataTable 风格）
  final ScrollController _headerHorizontalScrollController = ScrollController();
  final ScrollController _dataHorizontalScrollController = ScrollController();
  bool _isSyncingFromHeader = false;
  bool _isSyncingFromData = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    
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

  /// 首次加载时先获取供应商列表，再加载分析数据，避免供应商名称缺失显示为“未指定供应商”
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });
    await _fetchAnalysisData();
  }

  Future<void> _fetchSuppliers() async {
    try {
      final suppliers = await _supplierRepo.getAllSuppliers();
      setState(() {
        _suppliers = suppliers;
      });
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载供应商数据失败: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载供应商数据失败: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchAnalysisData() async {
    try {
      // 并行获取所有数据（包括供应商数据）
      final results = await Future.wait([
        _supplierRepo.getAllSuppliers(),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _remittanceRepo.getRemittances(page: 1, pageSize: 10000),
      ]);
      
      // 先设置供应商数据，确保后续处理可以使用
      final suppliers = results[0] as List<Supplier>;
      setState(() {
        _suppliers = suppliers;
      });
      
      final purchasesResponse = results[1] as PaginatedResponse<Purchase>;
      final remittancesResponse = results[2] as PaginatedResponse<Remittance>;
      
      // 应用日期筛选
      String? startDate = _selectedDateRange?.start.toIso8601String().split('T')[0];
      String? endDate = _selectedDateRange?.end.toIso8601String().split('T')[0];
      
      List<Purchase> purchases = purchasesResponse.items;
      List<Remittance> remittances = remittancesResponse.items;
      
      // 应用日期筛选
      if (startDate != null) {
        purchases = purchases.where((p) => p.purchaseDate != null && p.purchaseDate!.compareTo(startDate!) >= 0).toList();
        remittances = remittances.where((r) => r.remittanceDate != null && r.remittanceDate!.compareTo(startDate!) >= 0).toList();
      }
      if (endDate != null) {
        purchases = purchases.where((p) => p.purchaseDate != null && p.purchaseDate!.compareTo(endDate!) <= 0).toList();
        remittances = remittances.where((r) => r.remittanceDate != null && r.remittanceDate!.compareTo(endDate!) <= 0).toList();
      }
      
      // 应用供应商筛选
      int? selectedSupplierId;
      if (_selectedSupplier != null && _selectedSupplier != '所有供应商') {
        final supplier = _suppliers.firstWhere(
          (s) => s.name == _selectedSupplier,
          orElse: () => Supplier(id: -1, userId: -1, name: ''),
        );
        if (supplier.id != -1) {
          selectedSupplierId = supplier.id;
          purchases = purchases.where((p) => p.supplierId == selectedSupplierId).toList();
          remittances = remittances.where((r) => r.supplierId == selectedSupplierId).toList();
        }
      }

      // 按日期和供应商分组
      Map<String, Map<String, dynamic>> combinedData = {};
      
      // 处理采购数据
      for (var purchase in purchases) {
        if (purchase.purchaseDate == null) continue;
        final date = purchase.purchaseDate!.split('T')[0];
        final supplierId = purchase.supplierId ?? -1;
        String key = '${date}_$supplierId';
        
        final supplierName = supplierId != -1 
            ? _suppliers.firstWhere((s) => s.id == supplierId, orElse: () => Supplier(id: -1, userId: -1, name: '未指定供应商')).name
            : '未指定供应商';
        
        if (combinedData.containsKey(key)) {
          combinedData[key]!['totalPurchases'] = (combinedData[key]!['totalPurchases'] as double) + (purchase.totalPurchasePrice ?? 0.0);
        } else {
          combinedData[key] = {
            'date': date,
            'supplierName': supplierName,
            'supplierId': supplierId,
            'totalPurchases': purchase.totalPurchasePrice ?? 0.0,
            'totalRemittances': 0.0,
          };
        }
      }
      
      // 处理汇款数据
      for (var remittance in remittances) {
        if (remittance.remittanceDate == null) continue;
        final date = remittance.remittanceDate!.split('T')[0];
        final supplierId = remittance.supplierId ?? -1;
        String key = '${date}_$supplierId';
        
        final supplierName = supplierId != -1 
            ? _suppliers.firstWhere((s) => s.id == supplierId, orElse: () => Supplier(id: -1, userId: -1, name: '未指定供应商')).name
            : '未指定供应商';
        
        if (combinedData.containsKey(key)) {
          combinedData[key]!['totalRemittances'] = (combinedData[key]!['totalRemittances'] as double) + (remittance.amount ?? 0.0);
        } else {
          combinedData[key] = {
            'date': date,
            'supplierName': supplierName,
            'supplierId': supplierId,
            'totalPurchases': 0.0,
            'totalRemittances': remittance.amount ?? 0.0,
          };
        }
      }

      // 计算差值
      List<Map<String, dynamic>> analysisData = [];
      for (var data in combinedData.values) {
        double totalPurchases = data['totalPurchases'];
        double totalRemittances = data['totalRemittances'];
        double difference = totalPurchases - totalRemittances;
        
        analysisData.add({
          'date': data['date'],
          'supplierName': data['supplierName'],
          'supplierId': data['supplierId'],
          'totalPurchases': totalPurchases,
          'totalRemittances': totalRemittances,
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
        context.showErrorSnackBar('数据加载失败: ${e.toString()}');
      }
      print('采购汇款分析数据加载错误: $e');
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
    double totalPurchases = 0.0;
    double totalRemittances = 0.0;
    double totalDifference = 0.0;

    for (var item in data) {
      totalPurchases += item['totalPurchases'];
      totalRemittances += item['totalRemittances'];
      totalDifference += item['difference'];
    }

    setState(() {
      _totalPurchases = totalPurchases;
      _totalRemittances = totalRemittances;
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
    rows.add(['采购-汇款明细分析 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    
    // 添加筛选条件
    String supplierFilter = _selectedSupplier ?? '所有供应商';
    rows.add(['供应商筛选: $supplierFilter']);
    
    String dateFilter = '所有日期';
    if (_selectedDateRange != null) {
      dateFilter = '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
    }
    rows.add(['日期范围: $dateFilter']);
    rows.add([]);
    
    // 表头
    rows.add(['日期', '供应商', '净采购额', '实际汇款', '差值']);

    // 数据行
    for (var item in _analysisData) {
      rows.add([
        item['date'],
        item['supplierName'],
        item['totalPurchases'].toStringAsFixed(2),
        item['totalRemittances'].toStringAsFixed(2),
        item['difference'].toStringAsFixed(2),
      ]);
    }

    // 总计行
    rows.add([]);
    rows.add([
      '总计', '',
      _totalPurchases.toStringAsFixed(2), // 净采购额
      _totalRemittances.toStringAsFixed(2),
      _totalDifference.toStringAsFixed(2),
    ]);

    String csv = const ListToCsvConverter().convert(rows);

    // 导出文件名：默认“采购与汇款统计”，如筛选供应商则“{供应商名}_采购与汇款统计”
    String baseFileName = '采购与汇款统计';
    if (_selectedSupplier != null && _selectedSupplier != '所有供应商') {
      baseFileName = '${_selectedSupplier}_采购与汇款统计';
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
        title: Text('采购与汇款', style: TextStyle(
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
                    '每日的采购额（含退货）与实际汇款的对应情况，差值为正表示欠款（赊账金额），差值为负表示超付（预付金额）',
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
              // 供应商筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('供应商筛选', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          hint: Text('选择供应商'),
                          value: _selectedSupplier,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSupplier = newValue;
                              _fetchAnalysisData();
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: '所有供应商',
                              child: Text('所有供应商'),
                            ),
                            ..._suppliers.map((supplier) {
                              return DropdownMenuItem<String>(
                                value: supplier.name,
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
          if (_selectedDateRange != null || _selectedSupplier != null) ...[
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
                if (_selectedSupplier != null && _selectedSupplier != '所有供应商')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSupplier = null;
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
                          Text('供应商: $_selectedSupplier', style: TextStyle(fontSize: 12)),
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
                  _buildSummaryItem('净采购额', _formatMoney(_totalPurchases), Colors.blue),
                  _buildSummaryItem('实际汇款', _formatMoney(_totalRemittances), Colors.orange),
                  _buildSummaryItem('差值', _formatMoney(_totalDifference), _totalDifference >= 0 ? Colors.red : Colors.green),
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

  Widget _buildDataTable() {
    final columns = <DataColumn>[
      DataColumn(
        label: Text('日期'),
        onSort: (columnIndex, ascending) => _onSort('date'),
      ),
      DataColumn(
        label: Text('供应商'),
        onSort: (columnIndex, ascending) => _onSort('supplierName'),
      ),
      DataColumn(
        label: Text('净采购额'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('totalPurchases'),
      ),
      DataColumn(
        label: Text('实际汇款'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('totalRemittances'),
      ),
      DataColumn(
        label: Text('差值'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('difference'),
      ),
    ];

    // 撑列宽隐形行（保证表头与数据列宽一致）
    String maxDate = '';
    String maxSupplier = '';
    String maxPurchases = _formatMoney(0);
    String maxRemittances = _formatMoney(0);
    String maxDiff = _formatMoney(0);

    for (final item in _analysisData) {
      final String date = (item['date'] ?? '').toString();
      final String supplier = (item['supplierName'] ?? '').toString();
      final String purchases = _formatMoney((item['totalPurchases'] as num).toDouble());
      final String remittances = _formatMoney((item['totalRemittances'] as num).toDouble());
      final String diff = _formatMoney((item['difference'] as num).toDouble());

      if (date.length > maxDate.length) maxDate = date;
      if (supplier.length > maxSupplier.length) maxSupplier = supplier;
      if (purchases.length > maxPurchases.length) maxPurchases = purchases;
      if (remittances.length > maxRemittances.length) maxRemittances = remittances;
      if (diff.length > maxDiff.length) maxDiff = diff;
    }

    // 也考虑总计行
    final totalPurchasesText = _formatMoney(_totalPurchases);
    final totalRemittancesText = _formatMoney(_totalRemittances);
    final totalDiffText = _formatMoney(_totalDifference);
    if (totalPurchasesText.length > maxPurchases.length) maxPurchases = totalPurchasesText;
    if (totalRemittancesText.length > maxRemittances.length) maxRemittances = totalRemittancesText;
    if (totalDiffText.length > maxDiff.length) maxDiff = totalDiffText;

    final headerSizerRows = <DataRow>[
      DataRow(
        cells: [
          DataCell(Opacity(opacity: 0, child: Text(maxDate))),
          DataCell(Opacity(opacity: 0, child: Text(maxSupplier))),
          DataCell(Opacity(opacity: 0, child: Text(maxPurchases))),
          DataCell(Opacity(opacity: 0, child: Text(maxRemittances))),
          DataCell(Opacity(opacity: 0, child: Text(maxDiff))),
        ],
      ),
    ];

    final bodyRows = <DataRow>[
      ..._analysisData.map((item) {
        return DataRow(
          cells: [
            DataCell(Text(item['date'] ?? '')),
            DataCell(Text(item['supplierName'] ?? '')),
            DataCell(Text(_formatMoney((item['totalPurchases'] as num).toDouble()),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            DataCell(Text(_formatMoney((item['totalRemittances'] as num).toDouble()),
                style: TextStyle(color: Colors.orange))),
            DataCell(Text(_formatMoney((item['difference'] as num).toDouble()),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (item['difference'] as num).toDouble() >= 0 ? Colors.red : Colors.green))),
          ],
        );
      }).toList(),
      if (_analysisData.isNotEmpty)
        DataRow(
          color: MaterialStateProperty.all(Colors.grey[100]),
          cells: [
            DataCell(Text('总计', style: TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text('')),
            DataCell(Text(_formatMoney(_totalPurchases),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            DataCell(Text(_formatMoney(_totalRemittances),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
            DataCell(Text(_formatMoney(_totalDifference),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _totalDifference >= 0 ? Colors.red : Colors.green))),
          ],
        ),
    ];

    return Column(
      children: [
        // 固定表头：上下滚动时可见；左右滚动与数据同步
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
            dataRowMinHeight: 0,
            dataRowMaxHeight: 0,
            columns: columns,
            rows: headerSizerRows,
          ),
        ),
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
                headingRowHeight: 0, // 隐藏数据区表头，避免重复
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
      case 'supplierName': return 1;
      case 'totalPurchases': return 2;
      case 'totalRemittances': return 3;
      case 'difference': return 4;
      default: return 0;
    }
  }
} 