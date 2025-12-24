import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../widgets/footer_widget.dart';
import '../repositories/income_repository.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class EmployeeRecordsScreen extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  EmployeeRecordsScreen({required this.employeeId, required this.employeeName});

  @override
  _EmployeeRecordsScreenState createState() => _EmployeeRecordsScreenState();
}

class _EmployeeRecordsScreenState extends State<EmployeeRecordsScreen> {
  final IncomeRepository _incomeRepo = IncomeRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  
  List<Map<String, dynamic>> _records = [];
  List<Customer> _customers = [];
  List<Supplier> _suppliers = [];
  bool _isDescending = true;
  bool _incomeFirst = true; // 控制进账在前还是汇款在前
  String? _selectedType = '所有类型'; // 类型筛选
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  bool _isLoading = false;
  
  // 添加日期筛选相关变量
  DateTimeRange? _selectedDateRange;
  
  // 滚动控制器和指示器
  ScrollController? _summaryScrollController;
  double _summaryScrollPosition = 0.0;
  double _summaryScrollMaxExtent = 0.0;
  
  // 汇总数据
  double _totalIncomeAmount = 0.0;
  double _totalRemittanceAmount = 0.0;
  double _totalDiscountAmount = 0.0; // 添加总优惠金额
  double _netAmount = 0.0;
  int _incomeCount = 0;
  int _remittanceCount = 0;

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

  Future<void> _fetchCustomersAndSuppliers() async {
    try {
      final results = await Future.wait([
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
      ]);
      
      setState(() {
        _customers = results[0] as List<Customer>;
        _suppliers = results[1] as List<Supplier>;
      });
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载数据失败: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载数据失败: ${e.toString()}');
      }
    }
  }

  Future<void> _fetchRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 并行获取所有数据（包括客户和供应商数据）
      final results = await Future.wait([
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
        _remittanceRepo.getRemittances(page: 1, pageSize: 10000),
      ]);
      
      // 先设置客户和供应商数据，确保后续处理可以使用
      final customers = results[0] as List<Customer>;
      final suppliers = results[1] as List<Supplier>;
      setState(() {
        _customers = customers;
        _suppliers = suppliers;
      });
      
      final incomesResponse = results[2] as PaginatedResponse<Income>;
      final remittancesResponse = results[3] as PaginatedResponse<Remittance>;
      
      // 按员工ID筛选
      List<Income> incomes = incomesResponse.items.where((i) => i.employeeId == widget.employeeId).toList();
      List<Remittance> remittances = remittancesResponse.items.where((r) => r.employeeId == widget.employeeId).toList();
      
      // 应用日期筛选
      if (_selectedDateRange != null) {
        final startDate = _selectedDateRange!.start.toIso8601String().split('T')[0];
        final endDate = _selectedDateRange!.end.toIso8601String().split('T')[0];
        incomes = incomes.where((i) => i.incomeDate != null && i.incomeDate!.compareTo(startDate) >= 0 && i.incomeDate!.compareTo(endDate) <= 0).toList();
        remittances = remittances.where((r) => r.remittanceDate != null && r.remittanceDate!.compareTo(startDate) >= 0 && r.remittanceDate!.compareTo(endDate) <= 0).toList();
      }
      
      List<Map<String, dynamic>> combinedRecords = [];

      // 处理进账记录
      if (_selectedType == '所有类型' || _selectedType == '进账') {
        for (var income in incomes) {
          final customer = _customers.firstWhere(
            (c) => c.id == income.customerId,
            orElse: () => Customer(id: -1, userId: -1, name: '未指定客户'),
          );
          
          combinedRecords.add({
            'date': income.incomeDate ?? '',
            'type': '进账',
            'relatedName': customer.name,
            'amount': income.amount ?? 0.0,
            'discount': income.discount ?? 0.0,
            'paymentMethod': income.paymentMethod?.value ?? '',
            'note': income.note ?? '',
            'id': income.id,
          });
        }
      }

      // 处理汇款记录
      if (_selectedType == '所有类型' || _selectedType == '汇款') {
        for (var remittance in remittances) {
          final supplier = _suppliers.firstWhere(
            (s) => s.id == remittance.supplierId,
            orElse: () => Supplier(id: -1, userId: -1, name: '未指定供应商'),
          );
          
          combinedRecords.add({
            'date': remittance.remittanceDate ?? '',
            'type': '汇款',
            'relatedName': supplier.name,
            'amount': remittance.amount ?? 0.0,
            'discount': 0.0, // 汇款没有优惠
            'paymentMethod': remittance.paymentMethod?.value ?? '',
            'note': remittance.note ?? '',
            'id': remittance.id,
          });
        }
      }

      // 按日期和类型排序
      combinedRecords.sort((a, b) {
        int dateComparison = _isDescending
            ? (b['date'] as String).compareTo(a['date'] as String)
            : (a['date'] as String).compareTo(b['date'] as String);
        if (dateComparison != 0) return dateComparison;

        // 如果日期相同，根据类型排序
        if (_incomeFirst) {
          return a['type'] == '进账' ? -1 : 1;
        } else {
          return a['type'] == '汇款' ? -1 : 1;
        }
      });

      // 计算汇总数据
      _calculateSummary(combinedRecords);

      setState(() {
        _records = combinedRecords;
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

  void _calculateSummary(List<Map<String, dynamic>> records) {
    double incomeAmount = 0.0;
    double remittanceAmount = 0.0;
    double discountAmount = 0.0; // 添加优惠金额计算
    int incomeCount = 0;
    int remittanceCount = 0;

    for (var record in records) {
      if (record['type'] == '进账') {
        incomeAmount += (record['amount'] as num).toDouble();
        discountAmount += (record['discount'] as num).toDouble(); // 累计优惠金额
        incomeCount++;
      } else if (record['type'] == '汇款') {
        remittanceAmount += (record['amount'] as num).toDouble();
        remittanceCount++;
      }
    }

    setState(() {
      _totalIncomeAmount = incomeAmount;
      _totalRemittanceAmount = remittanceAmount;
      _totalDiscountAmount = discountAmount; // 设置总优惠金额
      _netAmount = incomeAmount - remittanceAmount;
      _incomeCount = incomeCount;
      _remittanceCount = remittanceCount;
    });
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['员工业务记录 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['员工: ${widget.employeeName}']);
    rows.add(['类型筛选: $_selectedType']);
    
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
    rows.add(['日期', '类型', '客户/供应商', '金额', '优惠', '付款方式', '备注']);

    for (var record in _records) {
      // 根据类型决定金额正负
      String amount = record['type'] == '进账' 
          ? '+${record['amount']}' 
          : '-${record['amount']}';
      
      rows.add([
        record['date'],
        record['type'],
        record['relatedName'],
        amount,
        record['discount'] > 0 ? record['discount'].toString() : '',
        record['paymentMethod'],
        record['note']
      ]);
    }

    // 添加总计行
    rows.add([]);
    rows.add(['总计', '', '', 
              '${_netAmount >= 0 ? '+' : ''}${_netAmount.toStringAsFixed(2)}', 
              _totalDiscountAmount > 0 ? _totalDiscountAmount.toStringAsFixed(2) : '', 
              '', '']);

    String csv = const ListToCsvConverter().convert(rows);

    // 生成文件名：如果筛选了类型，格式为"{员工名}_{进账/汇款}_业务记录"，否则为"{员工名}_业务记录"
    String baseFileName;
    if (_selectedType != null && _selectedType != '所有类型') {
      baseFileName = '${widget.employeeName}_${_selectedType}_业务记录';
      } else {
      baseFileName = '${widget.employeeName}_业务记录';
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

  void _toggleIncomeFirst() {
    setState(() {
      _incomeFirst = !_incomeFirst;
      _fetchRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.employeeName}的记录', style: TextStyle(
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
            icon: Icon(_incomeFirst ? Icons.swap_vert : Icons.swap_vert),
            tooltip: _incomeFirst ? '进账在前' : '汇款在前',
            onPressed: _toggleIncomeFirst,
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
          // 筛选条件 - 类型和日期在同一行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.purple[50],
            child: Row(
                  children: [
                    // 类型筛选
                    Icon(Icons.filter_alt, color: Colors.purple[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonHideUnderline(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple[300]!),
                            color: Colors.white,
                          ),
                          child: DropdownButton<String>(
                            hint: Text('选择类型', style: TextStyle(color: Colors.black87)),
                            value: _selectedType,
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: Colors.purple[700]),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedType = newValue;
                                _fetchRecords();
                              });
                            },
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                            items: [
                              DropdownMenuItem<String>(
                                value: '所有类型',
                                child: Text('所有类型'),
                              ),
                              DropdownMenuItem<String>(
                                value: '进账',
                                child: Text('进账'),
                              ),
                              DropdownMenuItem<String>(
                                value: '汇款',
                                child: Text('汇款'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                // 日期范围选择器
                    Icon(Icons.date_range, color: Colors.purple[700], size: 20),
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
                              colorScheme: ColorScheme.light(primary: Colors.purple),
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
                        border: Border.all(color: Colors.purple[300]!),
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
                                child: Icon(Icons.clear, color: Colors.purple[700], size: 18),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.purple[700]),
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
            color: Colors.purple[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.purple[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '横向和纵向滑动可查看完整表格，进账以绿色显示，汇款以红色显示',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple[800],
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
                  backgroundColor: Colors.purple[100],
                  radius: 14,
                  child: Text(
                    widget.employeeName.isNotEmpty 
                        ? widget.employeeName[0].toUpperCase() 
                        : '?',
                    style: TextStyle(
                      color: Colors.purple[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '员工业务记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[800],
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
                    '共 ${_records.length} 条记录',
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
          _isLoading && _records.isEmpty
              ? Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _records.isEmpty 
              ? Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              '暂无业务记录',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              _selectedType == '所有类型' 
                                  ? '该员工还没有经办进账或汇款记录'
                                  : '该员工还没有经办 $_selectedType 记录',
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
                            DataColumn(label: Text('客户/供应商')),
                            DataColumn(label: Text('金额')),
                            DataColumn(label: Text('优惠')),
                            DataColumn(label: Text('付款方式')),
                            DataColumn(label: Text('备注')),
                          ],
                          rows: [
                            // 数据行
                            ..._records.map((record) {
                              // 设置颜色，进账为绿色，汇款为红色
                              Color textColor = record['type'] == '进账' ? Colors.green : Colors.red;
                              
                              // 根据类型决定金额正负
                              String amount = record['type'] == '进账' 
                                  ? '+${record['amount']}' 
                                  : '-${record['amount']}';
                                  
                              return DataRow(
                                cells: [
                                  DataCell(Text(record['date'])),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: record['type'] == '进账' 
                                            ? Colors.green[50] 
                                            : Colors.red[50],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: record['type'] == '进账' 
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
                                  DataCell(Text(record['relatedName'])),
                                  DataCell(
                                    Text(
                                      amount,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  ),
                                  DataCell(
                                    record['discount'] > 0 
                                        ? Text(
                                            '¥${record['discount'].toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.orange[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          )
                                        : Text(''),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      child: Text(
                                        record['paymentMethod'],
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    record['note'].toString().isNotEmpty
                                        ? Text(
                                            record['note'],
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: Colors.grey[700],
                                            ),
                                          )
                                        : Text(''),
                                  ),
                                ],
                              );
                            }).toList(),
                            
                            // 总计行
                            if (_records.isNotEmpty)
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
                                  DataCell(Text('')), // 客户/供应商列
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
                                  DataCell(
                                    _totalDiscountAmount > 0
                                        ? Text(
                                            '¥${_totalDiscountAmount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.orange[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          )
                                        : Text(''),
                                  ),
                                  DataCell(Text('')), // 付款方式列
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
      color: Colors.purple[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 员工信息和汇总信息标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge, color: Colors.purple, size: 16),
                    SizedBox(width: 8),
                    Text(
                      '${widget.employeeName}    ${_selectedType ?? '所有类型'}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[800],
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
                          color: Colors.purple[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 16,
                        color: Colors.purple[800],
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
                        _buildSummaryItem('业务记录数', '${_records.length}', Colors.blue),
                        SizedBox(width: 16),
                  _buildSummaryItem('进账记录数', '${_incomeCount}', Colors.green),
                        SizedBox(width: 16),
                  _buildSummaryItem('汇款记录数', '${_remittanceCount}', Colors.red),
                        SizedBox(width: 16),
                  _buildSummaryItem('进账总额', '+¥${_totalIncomeAmount.toStringAsFixed(2)}', Colors.green),
                        SizedBox(width: 16),
                  _buildSummaryItem('汇款总额', '-¥${_totalRemittanceAmount.toStringAsFixed(2)}', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('净收入', '${_netAmount >= 0 ? '+' : '-'}¥${_netAmount.abs().toStringAsFixed(2)}', _netAmount >= 0 ? Colors.green : Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('平均进账', _incomeCount > 0 ? '¥${(_totalIncomeAmount / _incomeCount).toStringAsFixed(2)}' : '¥0.00', Colors.green),
                        SizedBox(width: 16),
                        _buildSummaryItem('平均汇款', _remittanceCount > 0 ? '¥${(_totalRemittanceAmount / _remittanceCount).toStringAsFixed(2)}' : '¥0.00', Colors.red),
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
                                color: Colors.purple[700],
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