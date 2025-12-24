// lib/screens/financial_statistics_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../widgets/footer_widget.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/product_repository.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import '../utils/snackbar_helper.dart';
import '../services/export_service.dart';

class FinancialStatisticsScreen extends StatefulWidget {
  @override
  _FinancialStatisticsScreenState createState() => _FinancialStatisticsScreenState();
}

class _FinancialStatisticsScreenState extends State<FinancialStatisticsScreen> {
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final ProductRepository _productRepo = ProductRepository();
  
  List<Map<String, dynamic>> _dailyStatistics = [];
  List<Map<String, dynamic>> _monthlyStatistics = [];
  List<Product> _products = [];
  String? _selectedProduct = '所有产品'; // 默认选择"所有产品"
  bool _isDescending = true; // 默认按时间倒序排列
  int _currentIndex = 0; // 当前选中的Tab索引
  Set<String> _datesWithRecords = {}; // 存储有记录的日期
  Set<String> _monthsWithRecords = {}; // 存储有记录的月份
  ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    setState(() {
      _isLoading = true;
    });
    _fetchStatistics();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDescending = prefs.getBool('financial_sort_descending') ?? true;
    });
  }

  Future<void> _saveSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('financial_sort_descending', _isDescending);
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

  Future<void> _fetchStatistics() async {
    try {
      // 并行获取所有数据（包括产品数据）
      final results = await Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 10000),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
      ]);
      
      // 先设置产品数据，确保后续处理可以使用
      final productsResponse = results[0] as PaginatedResponse<Product>;
      setState(() {
        _products = productsResponse.items;
      });
      
      final salesResponse = results[1] as PaginatedResponse<Sale>;
      final returnsResponse = results[2] as PaginatedResponse<Return>;
      final purchasesResponse = results[3] as PaginatedResponse<Purchase>;
      
      // 应用产品筛选
      List<Sale> sales = salesResponse.items;
      List<Return> returns = returnsResponse.items;
      List<Purchase> purchases = purchasesResponse.items;
      
      if (_selectedProduct != null && _selectedProduct != '所有产品') {
        sales = sales.where((s) => s.productName == _selectedProduct).toList();
        returns = returns.where((r) => r.productName == _selectedProduct).toList();
        purchases = purchases.where((p) => p.productName == _selectedProduct).toList();
      }

        // 清空记录日期和月份集合
        _datesWithRecords.clear();
        _monthsWithRecords.clear();

      // 处理每日统计
      final dailyMap = <String, Map<String, double>>{};
      
      // 处理销售数据
      for (var sale in sales) {
        if (sale.saleDate == null) continue;
        final date = sale.saleDate!.split('T')[0];
        final month = date.substring(0, 7);
        _datesWithRecords.add(date);
        _monthsWithRecords.add(month);
        
        dailyMap[date] = dailyMap[date] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
        dailyMap[date]!['totalSales'] = (dailyMap[date]!['totalSales'] ?? 0.0) + (sale.totalSalePrice ?? 0.0);
      }
      
      // 处理退货数据（从销售额中减去）
      for (var returnItem in returns) {
        if (returnItem.returnDate == null) continue;
        final date = returnItem.returnDate!.split('T')[0];
        final month = date.substring(0, 7);
        _datesWithRecords.add(date);
        _monthsWithRecords.add(month);
        
        dailyMap[date] = dailyMap[date] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
        dailyMap[date]!['totalSales'] = (dailyMap[date]!['totalSales'] ?? 0.0) - (returnItem.totalReturnPrice ?? 0.0);
    }
      
      // 处理采购数据
      for (var purchase in purchases) {
        if (purchase.purchaseDate == null) continue;
        final date = purchase.purchaseDate!.split('T')[0];
        final month = date.substring(0, 7);
        _datesWithRecords.add(date);
        _monthsWithRecords.add(month);
        
      dailyMap[date] = dailyMap[date] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
        dailyMap[date]!['totalPurchases'] = (dailyMap[date]!['totalPurchases'] ?? 0.0) + (purchase.totalPurchasePrice ?? 0.0);
      }

      // 创建每日统计列表并排序
    final dailyEntries = dailyMap.entries.map((entry) {
      return {
        'date': entry.key,
        'totalSales': entry.value['totalSales'],
        'totalPurchases': entry.value['totalPurchases']
      };
    }).toList();
    
    dailyEntries.sort((a, b) {
      int compareResult = (a['date'] as String).compareTo(b['date'] as String);
      return _isDescending ? -compareResult : compareResult;
    });
    
    _dailyStatistics = dailyEntries;

      // 处理每月统计
    final monthlyMap = <String, Map<String, double>>{};
      
      // 处理销售数据
      for (var sale in sales) {
        if (sale.saleDate == null) continue;
        final month = sale.saleDate!.substring(0, 7);
        monthlyMap[month] = monthlyMap[month] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
        monthlyMap[month]!['totalSales'] = (monthlyMap[month]!['totalSales'] ?? 0.0) + (sale.totalSalePrice ?? 0.0);
    }
      
      // 处理退货数据（从销售额中减去）
      for (var returnItem in returns) {
        if (returnItem.returnDate == null) continue;
        final month = returnItem.returnDate!.substring(0, 7);
      monthlyMap[month] = monthlyMap[month] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
        monthlyMap[month]!['totalSales'] = (monthlyMap[month]!['totalSales'] ?? 0.0) - (returnItem.totalReturnPrice ?? 0.0);
    }
      
      // 处理采购数据
      for (var purchase in purchases) {
        if (purchase.purchaseDate == null) continue;
        final month = purchase.purchaseDate!.substring(0, 7);
      monthlyMap[month] = monthlyMap[month] ?? {'totalSales': 0.0, 'totalPurchases': 0.0};
        monthlyMap[month]!['totalPurchases'] = (monthlyMap[month]!['totalPurchases'] ?? 0.0) + (purchase.totalPurchasePrice ?? 0.0);
    }

      // 创建每月统计列表并排序
    final monthlyEntries = monthlyMap.entries.map((entry) {
      return {
        'month': entry.key,
        'totalSales': entry.value['totalSales'],
        'totalPurchases': entry.value['totalPurchases']
      };
    }).toList();
    
    monthlyEntries.sort((a, b) {
      int compareResult = (a['month'] as String).compareTo(b['month'] as String);
      return _isDescending ? -compareResult : compareResult;
    });
    
        _monthlyStatistics = monthlyEntries;

      setState(() {
        _isLoading = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载统计数据失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('加载统计数据失败: ${e.toString()}');
      }
    }
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _saveSortPreference();
      _fetchStatistics();
    });
  }

  // 格式化金额方法：保留两位小数，去除不必要的零
  String _formatAmount(dynamic amount) {
    if (amount == null) return '0.00';
    double value = amount is double ? amount : double.tryParse(amount.toString()) ?? 0.0;
    return value.toStringAsFixed(2);
  }

  Future<void> _exportToCSV() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['财务统计报告 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['产品筛选: ${_selectedProduct ?? '所有产品'}']);
    rows.add([]); // 空行
    // 修改表头为中文
    rows.add(['日期/月份', '总销售额', '总采购额', '利润']);

    List<Map<String, dynamic>> statistics = _currentIndex == 0 ? _dailyStatistics : _monthlyStatistics;
    String dateKey = _currentIndex == 0 ? 'date' : 'month';

    for (var stat in statistics) {
      final totalSales = stat['totalSales'] as double;
      final totalPurchases = stat['totalPurchases'] as double;
      final profit = totalSales - totalPurchases;
      
      List<dynamic> row = [];
      row.add(stat[dateKey]);
      row.add(_formatAmount(totalSales));
      row.add(_formatAmount(totalPurchases));
      row.add(_formatAmount(profit));
      rows.add(row);
    }

    String csv = const ListToCsvConverter().convert(rows);

    // 使用统一的导出服务
    await ExportService.showExportOptions(
      context: context,
      csvData: csv,
      baseFileName: '财务统计',
      );
  }

  // 显示日历对话框
  void _showCalendarDialog() {
    DateTime focusedDay = DateTime.now();
    DateTime? selectedDay;
    CalendarFormat calendarFormat = _currentIndex == 0 ? CalendarFormat.month : CalendarFormat.month;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(_currentIndex == 0 ? '选择日期' : '选择月份'),
            content: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_currentIndex == 0)
                    // 每日统计使用常规日历
                    TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: focusedDay,
                    locale: 'zh_CN', // 设置为中文
                    selectedDayPredicate: (day) {
                      return selectedDay != null && isSameDay(selectedDay!, day);
                    },
                    onDaySelected: (selected, focused) {
                      setState(() {
                        selectedDay = selected;
                        focusedDay = focused;
                      });
                    },
                    calendarFormat: calendarFormat,
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        // 将日期格式化为 "yyyy-MM-dd" 格式
                        String formattedDate = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
                        
                        // 检查是否有记录
                        bool hasRecord = _datesWithRecords.contains(formattedDate);
                        
                        return Container(
                          margin: const EdgeInsets.all(4.0),
                          alignment: Alignment.center,
                          decoration: hasRecord 
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.green, width: 1.5),
                                  shape: BoxShape.circle,
                                ) 
                              : null,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: hasRecord ? Colors.green : null,
                              fontWeight: hasRecord ? FontWeight.bold : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_currentIndex == 1)
                  // 每月统计使用月份选择器
                  Container(
                    height: 300,
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: 36, // 显示3年的月份
                      itemBuilder: (context, index) {
                        // 从当前年份往前推1年，往后推1年
                        final now = DateTime.now();
                        final year = now.year - 1 + (index ~/ 12);
                        final month = (index % 12) + 1; // 1-12月
                        
                        final formattedMonth = "$year-${month.toString().padLeft(2, '0')}";
                        final hasRecord = _monthsWithRecords.contains(formattedMonth);
                        
                        // 检查是否是被选中的月份
                        final isSelected = selectedDay != null && 
                            selectedDay!.year == year && 
                            selectedDay!.month == month;
                            
                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedDay = DateTime(year, month, 1);
                              focusedDay = selectedDay!;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? Colors.amber
                                  : hasRecord 
                                      ? Colors.amber.withOpacity(0.1)
                                      : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: hasRecord
                                  ? Border.all(color: Colors.green, width: 1.5)
                                  : Border.all(color: Colors.grey[300]!, width: 1),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$year年',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.white : Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  '$month月',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected 
                                        ? Colors.white 
                                        : hasRecord 
                                            ? Colors.green
                                            : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                    SizedBox(height: 16),
                    Text(
                      _currentIndex == 0 
                          ? '绿色边框表示有交易记录'
                          : '绿色边框表示该月有交易记录',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (selectedDay != null) {
                    Navigator.of(context).pop();
                    _jumpToDate(selectedDay!);
                  } else {
                    context.showSnackBar('请先选择一个${_currentIndex == 0 ? '日期' : '月份'}');
                  }
                },
                child: Text('跳转'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 跳转到指定日期的记录
  void _jumpToDate(DateTime selectedDate) {
    String formattedDate = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
    String formattedMonth = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}";

    // 根据当前标签页选择日期或月份
    String targetDate = _currentIndex == 0 ? formattedDate : formattedMonth;
    List<Map<String, dynamic>> statistics = _currentIndex == 0 ? _dailyStatistics : _monthlyStatistics;
    String dateKey = _currentIndex == 0 ? 'date' : 'month';

    // 查找目标日期的索引
    int targetIndex = -1;
    for (int i = 0; i < statistics.length; i++) {
      if (statistics[i][dateKey] == targetDate) {
        targetIndex = i;
        break;
      }
    }

    // 如果找到记录，滚动到该位置
    if (targetIndex != -1) {
      // 延迟执行，确保界面已经构建完成
      Future.delayed(Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          targetIndex * 160.0, // 估计每个卡片高度约为160
          duration: Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
      
      context.showSnackBar('已跳转到 $targetDate 的记录');
    } else {
      context.showSnackBar('未找到 $targetDate 的记录');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('财务统计', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
          bottom: TabBar(
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            indicatorColor: Colors.amber,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
            tabs: [
              Tab(
                icon: Icon(Icons.calendar_today, size: 18),
                text: '每日统计',
              ),
              Tab(
                icon: Icon(Icons.date_range, size: 18),
                text: '每月统计',
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_isDescending ? Icons.arrow_downward : Icons.arrow_upward),
              tooltip: _isDescending ? '最新在前' : '最早在前',
              onPressed: _toggleSortOrder,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.amber[50],
              child: Row(
                children: [
                  Icon(Icons.filter_alt, color: Colors.amber[700], size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber[300]!),
                          color: Colors.white,
                        ),
                        child: DropdownButton<String>(
                          hint: Text('选择产品', style: TextStyle(color: Colors.black87)),
                          value: _selectedProduct,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.amber[700]),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedProduct = newValue;
                              _fetchStatistics();
                            });
                          },
                          style: TextStyle(color: Colors.black87, fontSize: 15),
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
                  // 添加日历按钮
                  Material(
                    color: Colors.amber[100],
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _showCalendarDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.amber[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.calendar_month,
                          color: Colors.amber[800],
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(
                    _currentIndex == 0 
                        ? Icons.calendar_today 
                        : Icons.date_range,
                    color: Colors.amber[800],
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    _currentIndex == 0 ? '每日财务统计' : '每月财务统计',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[800],
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
              child: TabBarView(
                children: [
                  _buildStatisticsView(_dailyStatistics, 'date', '日期'),
                  _buildStatisticsView(_monthlyStatistics, 'month', '月份'),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: FooterWidget(),
      ),
    );
  }

  Widget _buildStatisticsView(List<Map<String, dynamic>> statistics, String dateKey, String dateLabel) {
    if (_isLoading && statistics.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (statistics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentIndex == 0 ? Icons.calendar_today : Icons.date_range,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              '暂无${_currentIndex == 0 ? '每日' : '每月'}统计数据',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              _selectedProduct == '所有产品'
                  ? '添加销售或采购记录后会显示在这里'
                  : '当前筛选: $_selectedProduct，可能没有相关记录',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: statistics.length,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemBuilder: (context, index) {
        final stat = statistics[index];
        final totalSales = stat['totalSales'] as double;
        final totalPurchases = stat['totalPurchases'] as double;
        final profit = totalSales - totalPurchases;
        
        return Card(
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber[200]!),
                          ),
                          child: Icon(
                            _currentIndex == 0
                                ? Icons.calendar_today
                                : Icons.date_range,
                            size: 16,
                            color: Colors.amber[700],
                          ),
                        ),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat[dateKey] as String,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${_currentIndex == 0 ? '日' : '月'}度统计',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: profit >= 0 ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: profit >= 0 ? Colors.green[300]! : Colors.red[300]!,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '利润: ¥ ${profit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: profit >= 0 ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.shopping_bag,
                                    size: 12,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '总销售额',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 6),
                              child: Text(
                                '¥ ${totalSales.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey[300],
                        margin: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.inventory,
                                    size: 12,
                                    color: Colors.green[700],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '总采购额',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 6),
                              child: Text(
                                '¥ ${totalPurchases.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: totalSales > 0 ? (profit / totalSales).clamp(0.0, 1.0) : 0,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  profit >= 0
                      ? '利润率: ${totalSales > 0 ? ((profit / totalSales) * 100).toStringAsFixed(1) : 0}%'
                      : '亏损率: ${totalSales > 0 ? ((-profit / totalSales) * 100).toStringAsFixed(1) : 0}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: profit >= 0 ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}