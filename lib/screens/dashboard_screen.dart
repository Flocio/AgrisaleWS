// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../repositories/product_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/supplier_repository.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> 
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  // Repositories
  final ProductRepository _productRepo = ProductRepository();
  final SaleRepository _saleRepo = SaleRepository();
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();

  // State variables
  bool _isLoading = true;
  String _timeRange = '本月'; // 今日、本周、本月、自定义
  DateTime? _startDate;
  DateTime? _endDate;
  
  // KPI 数据
  double _totalStock = 0.0;
  double _totalSales = 0.0;
  double _totalPurchases = 0.0;
  double _totalProfit = 0.0;
  
  // 图表数据
  List<Product> _products = [];
  List<Sale> _sales = [];
  List<Purchase> _purchases = [];
  List<Return> _returns = [];
  List<Income> _incomes = [];
  List<Remittance> _remittances = [];
  List<Customer> _customers = [];
  List<Supplier> _suppliers = [];

  // Tab 控制器
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeTimeRange();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 初始化时间范围
  void _initializeTimeRange() {
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _startDate = DateTime(now.year, now.month, 1); // 本月第一天
  }

  // 加载所有数据
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 并行获取所有数据
      final results = await Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 10000),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
        _remittanceRepo.getRemittances(page: 1, pageSize: 10000),
        _customerRepo.getAllCustomers(),
        _supplierRepo.getAllSuppliers(),
      ]);

      setState(() {
        _products = (results[0] as PaginatedResponse<Product>).items;
        _sales = (results[1] as PaginatedResponse<Sale>).items;
        _purchases = (results[2] as PaginatedResponse<Purchase>).items;
        _returns = (results[3] as PaginatedResponse<Return>).items;
        _incomes = (results[4] as PaginatedResponse<Income>).items;
        _remittances = (results[5] as PaginatedResponse<Remittance>).items;
        _customers = results[6] as List<Customer>;
        _suppliers = results[7] as List<Supplier>;
      });

      _calculateKPIs();
      setState(() => _isLoading = false);
    } on ApiError catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载数据失败: ${e.message}');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('加载数据失败: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  // 计算 KPI 指标
  void _calculateKPIs() {
    // 计算库存总值（假设使用最近一次采购价格）
    _totalStock = 0.0;
    for (var product in _products) {
      final recentPurchase = _purchases
          .where((p) => p.productName == product.name)
          .toList()
        ..sort((a, b) => (b.purchaseDate ?? '').compareTo(a.purchaseDate ?? ''));
      
      if (recentPurchase.isNotEmpty && product.stock != null) {
        final purchase = recentPurchase.first;
        // 计算单价：总价 / 数量
        final unitPrice = (purchase.totalPurchasePrice ?? 0.0) / 
            (purchase.quantity != 0 ? purchase.quantity : 1.0);
        _totalStock += product.stock! * unitPrice;
      }
    }

    // 筛选时间范围内的数据
    final filteredSales = _filterByDateRange(_sales, (s) => s.saleDate);
    final filteredPurchases = _filterByDateRange(_purchases, (p) => p.purchaseDate);
    final filteredReturns = _filterByDateRange(_returns, (r) => r.returnDate);

    // 计算销售总额（扣除退货）
    _totalSales = filteredSales.fold(0.0, (sum, sale) => sum + (sale.totalSalePrice ?? 0.0));
    final returnAmount = filteredReturns.fold(0.0, (sum, ret) => sum + (ret.totalReturnPrice ?? 0.0));
    _totalSales -= returnAmount;

    // 计算采购总额
    _totalPurchases = filteredPurchases.fold(0.0, (sum, purchase) => sum + (purchase.totalPurchasePrice ?? 0.0));

    // 计算利润（销售额 - 采购成本）
    _totalProfit = _totalSales - _totalPurchases;
  }

  // 按时间范围筛选数据
  List<T> _filterByDateRange<T>(List<T> items, String? Function(T) dateGetter) {
    if (_startDate == null || _endDate == null) return items;
    
    return items.where((item) {
      final dateStr = dateGetter(item);
      if (dateStr == null) return false;
      
      try {
        final date = DateTime.parse(dateStr.split('T')[0]);
        return date.isAfter(_startDate!.subtract(Duration(days: 1))) && 
               date.isBefore(_endDate!.add(Duration(days: 1)));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  // 切换时间范围
  void _changeTimeRange(String range) {
    final now = DateTime.now();
    setState(() {
      _timeRange = range;
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      switch (range) {
        case '今日':
          _startDate = DateTime(now.year, now.month, now.day);
          break;
        case '本周':
          final weekday = now.weekday;
          _startDate = now.subtract(Duration(days: weekday - 1));
          _startDate = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
          break;
        case '本月':
          _startDate = DateTime(now.year, now.month, 1);
          break;
        case '自定义':
          _showDateRangePicker();
          return;
      }
      
      _calculateKPIs();
    });
  }

  // 显示日期范围选择器
  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime.now().subtract(Duration(days: 30)),
        end: _endDate ?? DateTime.now(),
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        _calculateKPIs();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin
    
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600; // 判断是否为小屏幕
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '数据仪表盘',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: isSmallScreen ? 18 : 20,
          ),
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: '刷新数据',
            ),
          if (!_isLoading)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'export') {
                  _showExportDialog();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.file_download, size: 20),
                      SizedBox(width: 8),
                      Text('导出数据'),
                    ],
                  ),
                ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isSmallScreen ? 44 : 48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.green[700],
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green,
              labelStyle: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
              ),
              tabs: [
                Tab(text: '基础统计'),
                Tab(text: '综合分析'),
                Tab(text: '智能洞察'),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    '正在加载数据...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: Colors.green,
              child: Column(
                children: [
                  _buildTimeRangeSelector(isSmallScreen),
                  _buildKPICards(isSmallScreen),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBasicStatistics(isSmallScreen),
                        _buildComprehensiveAnalysis(isSmallScreen),
                        _buildIntelligentInsights(isSmallScreen),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // 显示导出对话框
  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.file_download, color: Colors.green),
            SizedBox(width: 8),
            Text('导出数据'),
          ],
        ),
        content: Text('即将推出数据导出功能，敬请期待！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  // 构建时间范围选择器
  Widget _buildTimeRangeSelector(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 12 : 16,
        vertical: isSmallScreen ? 6 : 8,
      ),
      color: Colors.grey[100],
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            size: isSmallScreen ? 16 : 18,
            color: Colors.green[700],
          ),
          SizedBox(width: isSmallScreen ? 6 : 8),
          if (!isSmallScreen)
            Text(
              '时间范围：',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (!isSmallScreen) SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['今日', '本周', '本月', '自定义'].map((range) {
                  final isSelected = _timeRange == range;
                  return Padding(
                    padding: EdgeInsets.only(right: isSmallScreen ? 6 : 8),
                    child: ChoiceChip(
                      label: Text(
                        range,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 13,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) _changeTimeRange(range);
                      },
                      selectedColor: Colors.green[100],
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.green[700] : Colors.grey[700],
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 8 : 12,
                        vertical: isSmallScreen ? 4 : 6,
                      ),
                      visualDensity: isSmallScreen 
                          ? VisualDensity.compact 
                          : VisualDensity.standard,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建 KPI 卡片
  Widget _buildKPICards(bool isSmallScreen) {
    final kpiData = [
      {'title': '库存总值', 'value': _totalStock, 'icon': Icons.inventory, 'color': Colors.blue},
      {'title': '销售总额', 'value': _totalSales, 'icon': Icons.trending_up, 'color': Colors.green},
      {'title': '采购总额', 'value': _totalPurchases, 'icon': Icons.shopping_cart, 'color': Colors.orange},
      {'title': '净利润', 'value': _totalProfit, 'icon': Icons.attach_money, 'color': _totalProfit >= 0 ? Colors.green : Colors.red},
    ];

    if (isSmallScreen) {
      // 小屏幕：2x2 网格布局
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildKPICard(
                  kpiData[0]['title'] as String,
                  kpiData[0]['value'] as double,
                  kpiData[0]['icon'] as IconData,
                  kpiData[0]['color'] as Color,
                  isSmallScreen,
                )),
                SizedBox(width: 8),
                Expanded(child: _buildKPICard(
                  kpiData[1]['title'] as String,
                  kpiData[1]['value'] as double,
                  kpiData[1]['icon'] as IconData,
                  kpiData[1]['color'] as Color,
                  isSmallScreen,
                )),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildKPICard(
                  kpiData[2]['title'] as String,
                  kpiData[2]['value'] as double,
                  kpiData[2]['icon'] as IconData,
                  kpiData[2]['color'] as Color,
                  isSmallScreen,
                )),
                SizedBox(width: 8),
                Expanded(child: _buildKPICard(
                  kpiData[3]['title'] as String,
                  kpiData[3]['value'] as double,
                  kpiData[3]['icon'] as IconData,
                  kpiData[3]['color'] as Color,
                  isSmallScreen,
                )),
              ],
            ),
          ],
        ),
      );
    } else {
      // 大屏幕：1x4 横向布局
      return Container(
        padding: EdgeInsets.all(16),
        child: Row(
          children: kpiData.map((data) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: data == kpiData.last ? 0 : 8),
              child: _buildKPICard(
                data['title'] as String,
                data['value'] as double,
                data['icon'] as IconData,
                data['color'] as Color,
                isSmallScreen,
              ),
            ),
          )).toList(),
        ),
      );
    }
  }

  // 构建单个 KPI 卡片
  Widget _buildKPICard(String title, double value, IconData icon, Color color, bool isSmallScreen) {
    // 格式化金额显示
    String formattedValue;
    if (value.abs() >= 10000) {
      formattedValue = '¥${(value / 10000).toStringAsFixed(2)}万';
    } else {
      formattedValue = '¥${value.toStringAsFixed(2)}';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: isSmallScreen ? 18 : 20, color: color),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Text(
              formattedValue,
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  // 构建基础统计模块
  Widget _buildBasicStatistics(bool isSmallScreen) {
    return ListView(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      children: [
        _buildStockChart(isSmallScreen),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildPurchaseTrendChart(isSmallScreen),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildSalesTrendChart(isSmallScreen),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildReturnsTrendChart(isSmallScreen),
        SizedBox(height: 16), // 底部留白
      ],
    );
  }

  // 构建库存图表
  Widget _buildStockChart(bool isSmallScreen) {
    if (_products.isEmpty) {
      return _buildEmptyCard('暂无库存数据', isSmallScreen);
    }

    // 按库存数量排序，取前10个（小屏幕取前6个）
    final sortedProducts = List<Product>.from(_products)
      ..sort((a, b) => (b.stock ?? 0).compareTo(a.stock ?? 0));
    final topProducts = sortedProducts.take(isSmallScreen ? 6 : 10).toList();

    if (topProducts.isEmpty) {
      return _buildEmptyCard('暂无库存数据', isSmallScreen);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  color: Colors.blue[700],
                  size: isSmallScreen ? 20 : 24,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '库存概览 (Top ${topProducts.length})',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 12 : 20),
            SizedBox(
              height: isSmallScreen ? 200 : 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (topProducts.first.stock ?? 0) * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${topProducts[group.x.toInt()].name}\n${rod.toY.toStringAsFixed(1)} ${topProducts[group.x.toInt()].unit ?? ''}',
                          TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 11 : 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < topProducts.length) {
                            final product = topProducts[value.toInt()];
                            final maxLen = isSmallScreen ? 3 : 4;
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                product.name.length > maxLen
                                    ? product.name.substring(0, maxLen) + '..'
                                    : product.name,
                                style: TextStyle(fontSize: isSmallScreen ? 9 : 10),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return Text('');
                        },
                        reservedSize: isSmallScreen ? 35 : 40,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: isSmallScreen ? 35 : 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(0),
                            style: TextStyle(fontSize: isSmallScreen ? 9 : 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    topProducts.length,
                    (index) => BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: topProducts[index].stock ?? 0,
                          color: Colors.blue[400],
                          width: isSmallScreen ? 16 : 20,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建采购趋势图
  Widget _buildPurchaseTrendChart(bool isSmallScreen) {
    final filteredPurchases = _filterByDateRange(_purchases, (p) => p.purchaseDate);
    
    if (filteredPurchases.isEmpty) {
      return _buildEmptyCard('暂无采购数据', isSmallScreen);
    }

    // 按日期分组统计
    final dailyData = <String, double>{};
    for (var purchase in filteredPurchases) {
      if (purchase.purchaseDate != null) {
        final date = purchase.purchaseDate!.split('T')[0];
        dailyData[date] = (dailyData[date] ?? 0) + (purchase.totalPurchasePrice ?? 0);
      }
    }

    // 排序日期
    final sortedDates = dailyData.keys.toList()..sort();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shopping_cart,
                  color: Colors.orange[700],
                  size: isSmallScreen ? 20 : 24,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '采购趋势',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 12 : 20),
            SizedBox(
              height: isSmallScreen ? 180 : 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: isSmallScreen ? 35 : 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                            final date = sortedDates[value.toInt()];
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MM-dd').format(DateTime.parse(date)),
                                style: TextStyle(fontSize: isSmallScreen ? 9 : 10),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: isSmallScreen ? 45 : 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: isSmallScreen ? 9 : 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        sortedDates.length,
                        (index) => FlSpot(
                          index.toDouble(),
                          dailyData[sortedDates[index]]!,
                        ),
                      ),
                      isCurved: true,
                      color: Colors.orange,
                      barWidth: isSmallScreen ? 2.5 : 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: isSmallScreen ? 3 : 4,
                            color: Colors.orange,
                            strokeWidth: 0,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.orange.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final date = sortedDates[spot.x.toInt()];
                          return LineTooltipItem(
                            '${DateFormat('yyyy-MM-dd').format(DateTime.parse(date))}\n¥${spot.y.toStringAsFixed(2)}',
                            TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: isSmallScreen ? 11 : 12,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建销售趋势图
  Widget _buildSalesTrendChart(bool isSmallScreen) {
    final filteredSales = _filterByDateRange(_sales, (s) => s.saleDate);
    
    if (filteredSales.isEmpty) {
      return _buildEmptyCard('暂无销售数据', isSmallScreen);
    }

    // 按日期分组统计
    final dailyData = <String, double>{};
    for (var sale in filteredSales) {
      if (sale.saleDate != null) {
        final date = sale.saleDate!.split('T')[0];
        dailyData[date] = (dailyData[date] ?? 0) + (sale.totalSalePrice ?? 0);
      }
    }

    // 排序日期
    final sortedDates = dailyData.keys.toList()..sort();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.green[700]),
                SizedBox(width: 8),
                Text(
                  '销售趋势',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                            final date = sortedDates[value.toInt()];
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MM-dd').format(DateTime.parse(date)),
                                style: TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        sortedDates.length,
                        (index) => FlSpot(
                          index.toDouble(),
                          dailyData[sortedDates[index]]!,
                        ),
                      ),
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final date = sortedDates[spot.x.toInt()];
                          return LineTooltipItem(
                            '${DateFormat('yyyy-MM-dd').format(DateTime.parse(date))}\n¥${spot.y.toStringAsFixed(2)}',
                            TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建退货趋势图
  Widget _buildReturnsTrendChart(bool isSmallScreen) {
    final filteredReturns = _filterByDateRange(_returns, (r) => r.returnDate);
    
    if (filteredReturns.isEmpty) {
      return _buildEmptyCard('暂无退货数据', isSmallScreen);
    }

    // 按日期分组统计
    final dailyData = <String, double>{};
    for (var returnItem in filteredReturns) {
      if (returnItem.returnDate != null) {
        final date = returnItem.returnDate!.split('T')[0];
        dailyData[date] = (dailyData[date] ?? 0) + (returnItem.totalReturnPrice ?? 0);
      }
    }

    // 排序日期
    final sortedDates = dailyData.keys.toList()..sort();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_return, color: Colors.red[700]),
                SizedBox(width: 8),
                Text(
                  '退货趋势',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                            final date = sortedDates[value.toInt()];
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MM-dd').format(DateTime.parse(date)),
                                style: TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        sortedDates.length,
                        (index) => FlSpot(
                          index.toDouble(),
                          dailyData[sortedDates[index]]!,
                        ),
                      ),
                      isCurved: true,
                      color: Colors.red,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.red.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final date = sortedDates[spot.x.toInt()];
                          return LineTooltipItem(
                            '${DateFormat('yyyy-MM-dd').format(DateTime.parse(date))}\n¥${spot.y.toStringAsFixed(2)}',
                            TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建综合分析模块
  Widget _buildComprehensiveAnalysis(bool isSmallScreen) {
    return ListView(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      children: [
        _buildSalesVsIncomeChart(isSmallScreen),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildPurchaseVsRemittanceChart(isSmallScreen),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildProfitChart(isSmallScreen),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildSalesStructureChart(isSmallScreen),
        SizedBox(height: 16), // 底部留白
      ],
    );
  }

  // 构建销售 vs 进账对比图
  Widget _buildSalesVsIncomeChart(bool isSmallScreen) {
    final filteredSales = _filterByDateRange(_sales, (s) => s.saleDate);
    final filteredIncomes = _filterByDateRange(_incomes, (i) => i.incomeDate);
    
    if (filteredSales.isEmpty && filteredIncomes.isEmpty) {
      return _buildEmptyCard('暂无销售和进账数据', isSmallScreen);
    }

    // 按日期分组统计
    final allDates = <String>{};
    final salesData = <String, double>{};
    final incomeData = <String, double>{};
    
    for (var sale in filteredSales) {
      if (sale.saleDate != null) {
        final date = sale.saleDate!.split('T')[0];
        allDates.add(date);
        salesData[date] = (salesData[date] ?? 0) + (sale.totalSalePrice ?? 0);
      }
    }
    
    for (var income in filteredIncomes) {
      if (income.incomeDate != null) {
        final date = income.incomeDate!.split('T')[0];
        allDates.add(date);
        incomeData[date] = (incomeData[date] ?? 0) + income.amount;
      }
    }

    final sortedDates = allDates.toList()..sort();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: Colors.purple[700]),
                SizedBox(width: 8),
                Text(
                  '销售 vs 进账对比',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final date = sortedDates[group.x.toInt()];
                        final type = rodIndex == 0 ? '销售' : '进账';
                        return BarTooltipItem(
                          '$type\n${DateFormat('MM-dd').format(DateTime.parse(date))}\n¥${rod.toY.toStringAsFixed(2)}',
                          TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                            final date = sortedDates[value.toInt()];
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MM-dd').format(DateTime.parse(date)),
                                style: TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    sortedDates.length,
                    (index) {
                      final date = sortedDates[index];
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: salesData[date] ?? 0,
                            color: Colors.green[400],
                            width: 12,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                          BarChartRodData(
                            toY: incomeData[date] ?? 0,
                            color: Colors.blue[400],
                            width: 12,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('销售', Colors.green[400]!),
                SizedBox(width: 24),
                _buildLegendItem('进账', Colors.blue[400]!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 构建采购 vs 汇款对比图
  Widget _buildPurchaseVsRemittanceChart(bool isSmallScreen) {
    final filteredPurchases = _filterByDateRange(_purchases, (p) => p.purchaseDate);
    final filteredRemittances = _filterByDateRange(_remittances, (r) => r.remittanceDate);
    
    if (filteredPurchases.isEmpty && filteredRemittances.isEmpty) {
      return _buildEmptyCard('暂无采购和汇款数据', isSmallScreen);
    }

    // 按日期分组统计
    final allDates = <String>{};
    final purchaseData = <String, double>{};
    final remittanceData = <String, double>{};
    
    for (var purchase in filteredPurchases) {
      if (purchase.purchaseDate != null) {
        final date = purchase.purchaseDate!.split('T')[0];
        allDates.add(date);
        purchaseData[date] = (purchaseData[date] ?? 0) + (purchase.totalPurchasePrice ?? 0);
      }
    }
    
    for (var remittance in filteredRemittances) {
      if (remittance.remittanceDate != null) {
        final date = remittance.remittanceDate!.split('T')[0];
        allDates.add(date);
        remittanceData[date] = (remittanceData[date] ?? 0) + remittance.amount;
      }
    }

    final sortedDates = allDates.toList()..sort();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt, color: Colors.deepOrange[700]),
                SizedBox(width: 8),
                Text(
                  '采购 vs 汇款对比',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final date = sortedDates[group.x.toInt()];
                        final type = rodIndex == 0 ? '采购' : '汇款';
                        return BarTooltipItem(
                          '$type\n${DateFormat('MM-dd').format(DateTime.parse(date))}\n¥${rod.toY.toStringAsFixed(2)}',
                          TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                            final date = sortedDates[value.toInt()];
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MM-dd').format(DateTime.parse(date)),
                                style: TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    sortedDates.length,
                    (index) {
                      final date = sortedDates[index];
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: purchaseData[date] ?? 0,
                            color: Colors.orange[400],
                            width: 12,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                          BarChartRodData(
                            toY: remittanceData[date] ?? 0,
                            color: Colors.deepPurple[400],
                            width: 12,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('采购', Colors.orange[400]!),
                SizedBox(width: 24),
                _buildLegendItem('汇款', Colors.deepPurple[400]!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 构建利润分析图
  Widget _buildProfitChart(bool isSmallScreen) {
    final filteredSales = _filterByDateRange(_sales, (s) => s.saleDate);
    final filteredPurchases = _filterByDateRange(_purchases, (p) => p.purchaseDate);
    
    if (filteredSales.isEmpty && filteredPurchases.isEmpty) {
      return _buildEmptyCard('暂无利润数据', isSmallScreen);
    }

    // 按日期分组统计
    final allDates = <String>{};
    final salesData = <String, double>{};
    final purchaseData = <String, double>{};
    
    for (var sale in filteredSales) {
      if (sale.saleDate != null) {
        final date = sale.saleDate!.split('T')[0];
        allDates.add(date);
        salesData[date] = (salesData[date] ?? 0) + (sale.totalSalePrice ?? 0);
      }
    }
    
    for (var purchase in filteredPurchases) {
      if (purchase.purchaseDate != null) {
        final date = purchase.purchaseDate!.split('T')[0];
        allDates.add(date);
        purchaseData[date] = (purchaseData[date] ?? 0) + (purchase.totalPurchasePrice ?? 0);
      }
    }

    final sortedDates = allDates.toList()..sort();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: Colors.teal[700]),
                SizedBox(width: 8),
                Text(
                  '利润趋势',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                            final date = sortedDates[value.toInt()];
                            return Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MM-dd').format(DateTime.parse(date)),
                                style: TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        sortedDates.length,
                        (index) {
                          final date = sortedDates[index];
                          final profit = (salesData[date] ?? 0) - (purchaseData[date] ?? 0);
                          return FlSpot(index.toDouble(), profit);
                        },
                      ),
                      isCurved: true,
                      color: Colors.teal,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.teal.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final date = sortedDates[spot.x.toInt()];
                          return LineTooltipItem(
                            '利润\n${DateFormat('yyyy-MM-dd').format(DateTime.parse(date))}\n¥${spot.y.toStringAsFixed(2)}',
                            TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建销售结构分析图（饼图）
  Widget _buildSalesStructureChart(bool isSmallScreen) {
    final filteredSales = _filterByDateRange(_sales, (s) => s.saleDate);
    
    if (filteredSales.isEmpty) {
      return _buildEmptyCard('暂无销售结构数据', isSmallScreen);
    }

    // 按产品分组统计
    final productSales = <String, double>{};
    for (var sale in filteredSales) {
      productSales[sale.productName] = (productSales[sale.productName] ?? 0) + (sale.totalSalePrice ?? 0);
    }

    // 排序并取前5名
    final sortedProducts = productSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5Products = sortedProducts.take(5).toList();
    
    final totalSales = top5Products.fold(0.0, (sum, entry) => sum + entry.value);
    
    final colors = [
      Colors.blue[400]!,
      Colors.green[400]!,
      Colors.orange[400]!,
      Colors.purple[400]!,
      Colors.red[400]!,
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.indigo[700]),
                SizedBox(width: 8),
                Text(
                  '销售结构分析 (Top 5)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 60,
                  sections: List.generate(
                    top5Products.length,
                    (index) {
                      final percentage = (top5Products[index].value / totalSales * 100);
                      return PieChartSectionData(
                        value: top5Products[index].value,
                        title: '${percentage.toStringAsFixed(1)}%',
                        color: colors[index % colors.length],
                        radius: 80,
                        titleStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: List.generate(
                top5Products.length,
                (index) => _buildLegendItem(
                  top5Products[index].key,
                  colors[index % colors.length],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建智能洞察模块
  Widget _buildIntelligentInsights(bool isSmallScreen) {
    final insights = _generateInsights();
    
    return ListView(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb,
                      color: Colors.amber[700],
                      size: isSmallScreen ? 20 : 24,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '智能洞察',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(
                  '基于当前时间范围（$_timeRange）的数据分析：',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 13 : 14,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 16 : 20),
                ...insights.map((insight) => _buildInsightCard(insight, isSmallScreen)),
              ],
            ),
          ),
        ),
        SizedBox(height: 16), // 底部留白
      ],
    );
  }

  // 生成智能洞察
  List<Map<String, dynamic>> _generateInsights() {
    final insights = <Map<String, dynamic>>[];

    // 1. 利润分析
    if (_totalProfit > 0) {
      insights.add({
        'icon': Icons.trending_up,
        'color': Colors.green,
        'title': '盈利状况良好',
        'description': '当前净利润为 ¥${_totalProfit.toStringAsFixed(2)}，利润率为 ${(_totalProfit / _totalSales * 100).toStringAsFixed(1)}%',
      });
    } else if (_totalProfit < 0) {
      insights.add({
        'icon': Icons.trending_down,
        'color': Colors.red,
        'title': '出现亏损',
        'description': '当前净亏损为 ¥${(-_totalProfit).toStringAsFixed(2)}，建议优化采购成本或提高销售价格',
      });
    }

    // 2. 库存预警
    final lowStockProducts = _products.where((p) => (p.stock ?? 0) < 10).toList();
    if (lowStockProducts.isNotEmpty) {
      insights.add({
        'icon': Icons.warning,
        'color': Colors.orange,
        'title': '库存预警',
        'description': '有 ${lowStockProducts.length} 个产品库存不足10，建议及时补货：${lowStockProducts.take(3).map((p) => p.name).join('、')}${lowStockProducts.length > 3 ? ' 等' : ''}',
      });
    }

    // 3. 销售趋势
    final filteredSales = _filterByDateRange(_sales, (s) => s.saleDate);
    if (filteredSales.length >= 2) {
      final recentSales = filteredSales.reversed.take(7).toList();
      final avgRecent = recentSales.fold(0.0, (sum, s) => sum + (s.totalSalePrice ?? 0)) / recentSales.length;
      final olderSales = filteredSales.reversed.skip(7).take(7).toList();
      if (olderSales.isNotEmpty) {
        final avgOlder = olderSales.fold(0.0, (sum, s) => sum + (s.totalSalePrice ?? 0)) / olderSales.length;
        final change = ((avgRecent - avgOlder) / avgOlder * 100);
        if (change > 10) {
          insights.add({
            'icon': Icons.arrow_upward,
            'color': Colors.green,
            'title': '销售增长',
            'description': '近期销售额较之前增长了 ${change.toStringAsFixed(1)}%，保持良好势头',
          });
        } else if (change < -10) {
          insights.add({
            'icon': Icons.arrow_downward,
            'color': Colors.red,
            'title': '销售下滑',
            'description': '近期销售额较之前下降了 ${(-change).toStringAsFixed(1)}%，需要关注市场变化',
          });
        }
      }
    }

    // 4. 收款情况分析
    final filteredIncomes = _filterByDateRange(_incomes, (i) => i.incomeDate);
    final totalIncome = filteredIncomes.fold(0.0, (sum, i) => sum + i.amount);
    if (_totalSales > 0) {
      final collectionRate = (totalIncome / _totalSales * 100);
      if (collectionRate < 80) {
        insights.add({
          'icon': Icons.payment,
          'color': Colors.orange,
          'title': '收款率偏低',
          'description': '当前收款率为 ${collectionRate.toStringAsFixed(1)}%，建议加强应收账款管理',
        });
      } else if (collectionRate >= 95) {
        insights.add({
          'icon': Icons.check_circle,
          'color': Colors.green,
          'title': '收款情况良好',
          'description': '当前收款率为 ${collectionRate.toStringAsFixed(1)}%，资金回笼及时',
        });
      }
    }

    // 5. 付款情况分析
    final filteredRemittances = _filterByDateRange(_remittances, (r) => r.remittanceDate);
    final totalRemittance = filteredRemittances.fold(0.0, (sum, r) => sum + r.amount);
    if (_totalPurchases > 0) {
      final paymentRate = (totalRemittance / _totalPurchases * 100);
      if (paymentRate > 100) {
        insights.add({
          'icon': Icons.info,
          'color': Colors.blue,
          'title': '超额付款',
          'description': '付款金额超过采购金额 ${(paymentRate - 100).toStringAsFixed(1)}%，可能存在预付款或历史欠款',
        });
      }
    }

    // 6. 退货率分析
    final filteredReturns = _filterByDateRange(_returns, (r) => r.returnDate);
    final totalReturn = filteredReturns.fold(0.0, (sum, r) => sum + (r.totalReturnPrice ?? 0));
    if (_totalSales > 0) {
      final returnRate = (totalReturn / (_totalSales + totalReturn) * 100);
      if (returnRate > 5) {
        insights.add({
          'icon': Icons.assignment_return,
          'color': Colors.red,
          'title': '退货率偏高',
          'description': '当前退货率为 ${returnRate.toStringAsFixed(1)}%，建议关注产品质量和客户满意度',
        });
      }
    }

    // 如果没有生成任何洞察，添加一个默认消息
    if (insights.isEmpty) {
      insights.add({
        'icon': Icons.info,
        'color': Colors.grey,
        'title': '数据不足',
        'description': '当前时间范围内的数据不足以生成有效的洞察，请尝试调整时间范围或添加更多业务数据',
      });
    }

    return insights;
  }

  // 构建洞察卡片
  Widget _buildInsightCard(Map<String, dynamic> insight, bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: (insight['color'] as Color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (insight['color'] as Color).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            insight['icon'] as IconData,
            color: insight['color'] as Color,
            size: isSmallScreen ? 24 : 32,
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight['title'] as String,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  insight['description'] as String,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 13 : 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建图例项
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  // 构建空数据卡片
  Widget _buildEmptyCard(String message, bool isSmallScreen) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 24 : 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: isSmallScreen ? 40 : 48,
                color: Colors.grey[400],
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                '调整时间范围或添加数据后查看',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 13,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
