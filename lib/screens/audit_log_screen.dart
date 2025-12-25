// lib/screens/audit_log_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/footer_widget.dart';
import '../repositories/audit_log_repository.dart';
import '../models/audit_log.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class AuditLogScreen extends StatefulWidget {
  @override
  _AuditLogScreenState createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AuditLogRepository _auditLogRepo = AuditLogRepository();
  
  List<AuditLog> _logs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isLoadingMore = false; // 是否正在加载更多
  int _currentPage = 1;
  final int _pageSize = 20;
  int _total = 0; // 总记录数
  
  // 筛选条件
  OperationType? _selectedOperationType;
  EntityType? _selectedEntityType;
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchLogs();
  }
  
  
  Timer? _searchTimer;
  
  void _onSearchChanged() {
    // 取消之前的定时器
    _searchTimer?.cancel();
    
    // 延迟搜索，避免频繁请求
    _searchTimer = Timer(Duration(milliseconds: 500), () {
      if (mounted && _searchController.text != _searchText) {
        setState(() {
          _searchText = _searchController.text;
          _currentPage = 1;
        });
        _fetchLogs();
      }
    });
  }
  
  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _fetchLogs({bool isRefresh = false}) async {
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      // 构建时间参数
      String? startTime;
      String? endTime;
      
      if (_startDate != null) {
        startTime = '${_startDate!.toIso8601String().split('T')[0]}T00:00:00';
      }
      
      if (_endDate != null) {
        endTime = '${_endDate!.toIso8601String().split('T')[0]}T23:59:59';
      }
      
      final response = await _auditLogRepo.getAuditLogs(
        page: _currentPage,
        pageSize: _pageSize,
        operationType: _selectedOperationType?.value,
        entityType: _selectedEntityType?.value,
        startTime: startTime,
        endTime: endTime,
        search: _searchText.isEmpty ? null : _searchText,
      );
      
      setState(() {
        if (_currentPage == 1) {
          _logs = response.items;
          _total = response.total; // 更新总数
        } else {
          _logs.addAll(response.items);
        }
        _hasMore = response.hasNextPage;
        _isLoading = false;
        _isLoadingMore = false; // 确保加载更多标志被重置
      });
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false; // 重置加载更多标志
      });
      if (mounted) {
        context.showErrorSnackBar('加载日志失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false; // 重置加载更多标志
      });
      if (mounted) {
        context.showErrorSnackBar('加载日志失败: ${e.toString()}');
      }
    }
  }
  
  Future<void> _loadMore() async {
    // 防止重复加载
    if (_isLoadingMore || _isLoading || !_hasMore) {
      return;
    }
    
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    
    try {
      await _fetchLogs();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }
  
  void _resetFilters() {
    setState(() {
      _selectedOperationType = null;
      _selectedEntityType = null;
      _startDate = null;
      _endDate = null;
      _searchText = '';
      _searchController.clear();
      _currentPage = 1;
    });
    _fetchLogs();
  }
  
  bool _hasFilters() {
    return _selectedOperationType != null ||
           _selectedEntityType != null ||
           _startDate != null ||
           _endDate != null ||
           _searchText.isNotEmpty;
  }
  
  Future<void> _showFilterDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterBottomSheet(
        selectedOperationType: _selectedOperationType,
        selectedEntityType: _selectedEntityType,
        startDate: _startDate,
        endDate: _endDate,
        onApply: (operationType, entityType, startDate, endDate) {
          setState(() {
            _selectedOperationType = operationType;
            _selectedEntityType = entityType;
            _startDate = startDate;
            _endDate = endDate;
            _currentPage = 1;
          });
          _fetchLogs();
        },
        onReset: () {
          _resetFilters();
          Navigator.pop(context);
        },
      ),
    );
  }
  
  void _showLogDetail(AuditLog log) {
    showDialog(
      context: context,
      builder: (context) => _LogDetailDialog(log: log),
    );
  }
  
  Color _getOperationTypeColor(OperationType type) {
    switch (type) {
      case OperationType.create:
        return Colors.green;
      case OperationType.update:
        return Colors.blue;
      case OperationType.delete:
        return Colors.red;
      case OperationType.cover:
        return Colors.purple;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '日志',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list),
            tooltip: '筛选',
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索实体名称、备注...',
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[600]),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchText = '';
                            _currentPage = 1;
                          });
                          _fetchLogs();
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
              textInputAction: TextInputAction.search,
              onEditingComplete: () {
                FocusScope.of(context).unfocus();
              },
            ),
          ),
          
          // 筛选条件指示器
          if (_hasFilters())
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Icon(Icons.filter_alt, size: 16, color: Colors.grey[700]),
                  SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_selectedOperationType != null)
                            Chip(
                              label: Text('操作: ${_selectedOperationType!.displayName}'),
                              onDeleted: () {
                                setState(() {
                                  _selectedOperationType = null;
                                  _currentPage = 1;
                                });
                                _fetchLogs();
                              },
                            ),
                          if (_selectedEntityType != null) ...[
                            SizedBox(width: 4),
                            Chip(
                              label: Text('实体: ${_selectedEntityType!.displayName}'),
                              onDeleted: () {
                                setState(() {
                                  _selectedEntityType = null;
                                  _currentPage = 1;
                                });
                                _fetchLogs();
                              },
                            ),
                          ],
                          if (_startDate != null || _endDate != null) ...[
                            SizedBox(width: 4),
                            Chip(
                              label: Text(
                                _startDate != null && _endDate != null
                                    ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 至 ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                                    : _startDate != null
                                        ? '从 ${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                                        : '至 ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                              ),
                              onDeleted: () {
                                setState(() {
                                  _startDate = null;
                                  _endDate = null;
                                  _currentPage = 1;
                                });
                                _fetchLogs();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _resetFilters,
                    child: Text('清除全部'),
                  ),
                ],
              ),
            ),
          
          // 列表标题
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.grey[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '操作记录 ($_total)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          
          // 日志列表
          Expanded(
            child: _isLoading && _logs.isEmpty
                ? Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                '暂无日志',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '进行创建、修改、删除操作后会显示在这里',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          setState(() {
                            _currentPage = 1;
                          });
                          await _fetchLogs(isRefresh: true);
                        },
                        child: ListView.builder(
                          itemCount: _logs.length + (_hasMore ? 1 : 0),
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          itemBuilder: (context, index) {
                            if (index == _logs.length) {
                              // 加载更多指示器
                              // 延迟调用，避免在构建时立即触发
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _loadMore();
                              });
                              return Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            
                            final log = _logs[index];
                            return _buildLogItem(log);
                          },
                        ),
                      ),
          ),
          
          FooterWidget(),
        ],
      ),
    );
  }
  
  Widget _buildLogItem(AuditLog log) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: () => _showLogDetail(log),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    log.formattedTime,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 操作人名字标签
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          log.username,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      // 操作类型标签（创建/修改/删除/覆盖）
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getOperationTypeColor(log.operationType).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          log.operationType.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: _getOperationTypeColor(log.operationType),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      log.entityType.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.entityName ?? '未知',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              if (log.changesSummary.isNotEmpty) ...[
                SizedBox(height: 6),
                Text(
                  log.changesSummary,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (log.note != null && log.note!.isNotEmpty) ...[
                SizedBox(height: 4),
                Text(
                  log.note!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选底部表单
class _FilterBottomSheet extends StatefulWidget {
  final OperationType? selectedOperationType;
  final EntityType? selectedEntityType;
  final DateTime? startDate;
  final DateTime? endDate;
  final Function(OperationType?, EntityType?, DateTime?, DateTime?) onApply;
  final VoidCallback onReset;

  _FilterBottomSheet({
    required this.selectedOperationType,
    required this.selectedEntityType,
    required this.startDate,
    required this.endDate,
    required this.onApply,
    required this.onReset,
  });

  @override
  _FilterBottomSheetState createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late OperationType? _operationType;
  late EntityType? _entityType;
  late DateTime? _startDate;
  late DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _operationType = widget.selectedOperationType;
    _entityType = widget.selectedEntityType;
    _startDate = widget.startDate;
    _endDate = widget.endDate;
  }


  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
              onPrimary: Colors.white,
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
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '筛选条件',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: widget.onReset,
                child: Text('重置'),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // 操作类型筛选
          Text('操作类型', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showOperationTypePicker(),
                  child: Text(_operationType?.displayName ?? '全部'),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // 实体类型筛选
          Text('实体类型', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showEntityTypePicker(),
                  child: Text(_entityType?.displayName ?? '全部'),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // 时间范围筛选
          Text('时间范围', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.date_range),
                  label: Text(
                    _startDate != null && _endDate != null
                        ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 至 ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                        : '选择时间范围',
                  ),
                  onPressed: _selectDateRange,
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消'),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(_operationType, _entityType, _startDate, _endDate);
                    Navigator.pop(context);
                  },
                  child: Text('应用'),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  Future<void> _showOperationTypePicker() async {
    final options = ['全部', ...OperationType.values.map((e) => e.displayName)];
    int currentIndex = _operationType != null
        ? OperationType.values.indexOf(_operationType!) + 1
        : 0;

    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择操作类型'),
          content: SizedBox(
            height: 200,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                return CupertinoPicker(
                  scrollController: FixedExtentScrollController(initialItem: currentIndex),
                  itemExtent: 32,
                  magnification: 1.1,
                  useMagnifier: true,
                  onSelectedItemChanged: (index) {
                    setStateDialog(() {
                      tempIndex = index;
                    });
                  },
                  children: options.map((text) => Center(child: Text(text))).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null) {
      setState(() {
        _operationType = selectedIndex == 0
            ? null
            : OperationType.values[selectedIndex - 1];
      });
    }
  }

  Future<void> _showEntityTypePicker() async {
    final options = ['全部', ...EntityType.values.map((e) => e.displayName)];
    final currentIndex = _entityType != null
        ? EntityType.values.indexOf(_entityType!) + 1
        : 0;

    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择实体类型'),
          content: SizedBox(
            height: 200,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                return CupertinoPicker(
                  scrollController: FixedExtentScrollController(initialItem: currentIndex),
                  itemExtent: 32,
                  magnification: 1.1,
                  useMagnifier: true,
                  onSelectedItemChanged: (index) {
                    setStateDialog(() {
                      tempIndex = index;
                    });
                  },
                  children: options.map((text) => Center(child: Text(text))).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null) {
      setState(() {
        _entityType = selectedIndex == 0
            ? null
            : EntityType.values[selectedIndex - 1];
      });
    }
  }
}

/// 日志详情对话框
class _LogDetailDialog extends StatelessWidget {
  final AuditLog log;

  _LogDetailDialog({required this.log});

  /// 格式化时间字符串（处理时区问题）
  String _formatTimeValue(dynamic value) {
    if (value == null) return 'null';
    
    final valueStr = value.toString();
    
    // 检查是否是时间字段（created_at, updated_at, operation_time等）
    // 格式：YYYY-MM-DD HH:MM:SS 或 YYYY-MM-DDTHH:MM:SS
    if (valueStr.length >= 19 && 
        (valueStr.contains('-') && valueStr.contains(':'))) {
      try {
        // 如果格式是 "YYYY-MM-DD HH:MM:SS"（没有时区信息）
        if (valueStr.length == 19 && 
            valueStr.contains(' ') && 
            !valueStr.contains('T') && 
            !valueStr.contains('+') && 
            !valueStr.contains('Z')) {
          // 手动解析为本地时间
          final parts = valueStr.split(' ');
          if (parts.length == 2) {
            final dateParts = parts[0].split('-');
            final timeParts = parts[1].split(':');
            
            if (dateParts.length == 3 && timeParts.length == 3) {
              final year = int.parse(dateParts[0]);
              final month = int.parse(dateParts[1]);
              final day = int.parse(dateParts[2]);
              final hour = int.parse(timeParts[0]);
              final minute = int.parse(timeParts[1]);
              final second = int.parse(timeParts[2]);
              
              // 创建本地时间的 DateTime 对象
              final dateTime = DateTime(year, month, day, hour, minute, second);
              
              return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
            }
          }
        }
        
        // 标准 ISO8601 格式解析
        final dateTime = DateTime.parse(valueStr);
        return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
      } catch (e) {
        // 解析失败，返回原值
        return valueStr;
      }
    }
    
    return valueStr;
  }

  Color _getOperationTypeColor(OperationType type) {
    switch (type) {
      case OperationType.create:
        return Colors.green;
      case OperationType.update:
        return Colors.blue;
      case OperationType.delete:
        return Colors.red;
      case OperationType.cover:
        return Colors.purple;
    }
  }

  String _getOldDataTitle(AuditLog log) {
    if (log.operationType == OperationType.cover) {
      // 根据 entityName 判断是"备份恢复"还是"数据导入"
      if (log.entityName == '备份恢复') {
        return '恢复前数据';
      } else {
        return '导入前数据';
      }
    }
    return '修改前数据';
  }

  String _getNewDataTitle(AuditLog log) {
    if (log.operationType == OperationType.cover) {
      // 根据 entityName 判断是"备份恢复"还是"数据导入"
      if (log.entityName == '备份恢复') {
        return '恢复后数据';
      } else {
        return '导入后数据';
      }
    }
    return '修改后数据';
  }

  Widget _buildDataTable(Map<String, dynamic>? data, String title) {
    if (data == null || data.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            columnWidths: {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(3),
            },
            children: data.entries.map((entry) {
              // 检查是否是时间字段
              final isTimeField = entry.key.toLowerCase().contains('time') || 
                                  entry.key.toLowerCase().contains('date') ||
                                  entry.key.toLowerCase().contains('created_at') ||
                                  entry.key.toLowerCase().contains('updated_at');
              
              return TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      isTimeField ? _formatTimeValue(entry.value) : (entry.value?.toString() ?? 'null'),
                      style: TextStyle(color: Colors.grey[800]),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChangesTable() {
    if (log.changes == null || log.changes!.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '变更详情',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            columnWidths: {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('字段', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('旧值', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('新值', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('变化', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              ...log.changes!.entries.map((entry) {
                final change = entry.value as Map<String, dynamic>;
                final oldValue = change['old'];
                final newValue = change['new'];
                final delta = change['delta'];
                
                Color? rowColor;
                if (delta != null) {
                  final deltaValue = delta is double ? delta : (delta as num).toDouble();
                  if (deltaValue > 0) {
                    rowColor = Colors.green[50];
                  } else if (deltaValue < 0) {
                    rowColor = Colors.red[50];
                  }
                }
                
                return TableRow(
                  decoration: rowColor != null
                      ? BoxDecoration(color: rowColor)
                      : null,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        entry.key,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(_formatTimeValue(oldValue)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(_formatTimeValue(newValue)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: delta != null
                          ? Text(
                              delta > 0 ? '+$delta' : '$delta',
                              style: TextStyle(
                                color: delta > 0 ? Colors.green[700] : Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Text('-'),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getOperationTypeColor(log.operationType).withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getOperationTypeColor(log.operationType),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          log.operationType.displayName,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        log.entityType.displayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 基本信息
                    _buildInfoRow('操作时间', log.formattedTime),
                    _buildInfoRow('操作人', log.username),
                    _buildInfoRow('实体名称', log.entityName ?? '未知'),
                    if (log.entityId != null)
                      _buildInfoRow('实体ID', log.entityId.toString()),
                    if (log.ipAddress != null)
                      _buildInfoRow('IP地址', log.ipAddress!),
                    if (log.deviceInfo != null)
                      _buildInfoRow('设备信息', log.deviceInfo!),
                    if (log.note != null && log.note!.isNotEmpty)
                      _buildInfoRow('备注', log.note!),
                    
                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 16),
                    
                    // 变更详情（仅UPDATE操作）
                    if (log.operationType == OperationType.update)
                      _buildChangesTable(),
                    
                    // 旧数据（UPDATE、DELETE和COVER操作）
                    if (log.operationType == OperationType.update ||
                        log.operationType == OperationType.delete ||
                        log.operationType == OperationType.cover)
                      _buildDataTable(log.oldData, _getOldDataTitle(log)),
                    
                    // 新数据（CREATE、UPDATE和COVER操作）
                    if (log.operationType == OperationType.create ||
                        log.operationType == OperationType.update ||
                        log.operationType == OperationType.cover)
                      _buildDataTable(log.newData, _getNewDataTitle(log)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

