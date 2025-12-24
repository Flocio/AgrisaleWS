// lib/screens/employee_screen.dart

import 'package:flutter/material.dart';
import '../widgets/footer_widget.dart';
import 'employee_records_screen.dart';
import '../repositories/employee_repository.dart';
import '../models/api_error.dart';
import '../utils/snackbar_helper.dart';

class EmployeeScreen extends StatefulWidget {
  @override
  _EmployeeScreenState createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  
  List<Employee> _employees = [];
  bool _showDeleteButtons = false;
  bool _isLoading = false;

  // 添加搜索相关的状态变量
  List<Employee> _filteredEmployees = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterEmployees();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤员工的方法
  void _filterEmployees() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      if (searchText.isEmpty) {
        _filteredEmployees = List.from(_employees);
        _isSearching = false;
      } else {
        _filteredEmployees = _employees.where((employee) {
          final name = employee.name.toLowerCase();
          final note = (employee.note ?? '').toLowerCase();
          return name.contains(searchText) || note.contains(searchText);
        }).toList();
        _isSearching = true;
      }
    });
  }

  Future<void> _fetchEmployees({bool isRefresh = false}) async {
    if (!isRefresh) {
    setState(() {
      _isLoading = true;
    });
    }
    
    try {
      final employees = await _employeeRepo.getAllEmployees();
      
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
      
      // 刷新后重新应用过滤条件
      if (isRefresh) {
        _filterEmployees();
      } else {
        // 初始加载时也应用过滤
        _filterEmployees();
      }
    } on ApiError catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取员工列表失败: ${e.message}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        context.showErrorSnackBar('获取员工列表失败: ${e.toString()}');
      }
    }
  }

  Future<void> _addEmployee() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EmployeeDialog(),
    );
    if (result != null) {
      try {
        final employeeCreate = EmployeeCreate(
          name: result['name'] as String,
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _employeeRepo.createEmployee(employeeCreate);
        _fetchEmployees();
        
        if (mounted) {
          context.showSuccessSnackBar('员工添加成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('添加员工失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _editEmployee(Employee employee) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EmployeeDialog(employee: employee),
    );
    if (result != null) {
      try {
        final employeeUpdate = EmployeeUpdate(
          name: result['name'] as String,
          note: (result['note'] as String?)?.isEmpty == true 
              ? null 
              : result['note'] as String?,
        );
        
        await _employeeRepo.updateEmployee(employee.id, employeeUpdate);
        _fetchEmployees();
        
        if (mounted) {
          context.showSuccessSnackBar('员工更新成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('更新员工失败: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('您确定要删除员工 "${employee.name}" 吗？'),
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
        await _employeeRepo.deleteEmployee(employee.id);
        _fetchEmployees();
        
        if (mounted) {
          context.showSuccessSnackBar('员工删除成功');
        }
      } on ApiError catch (e) {
        if (mounted) {
          context.showErrorSnackBar(e.message);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('删除员工失败: ${e.toString()}');
        }
      }
    }
  }

  void _viewEmployeeRecords(int employeeId, String employeeName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeRecordsScreen(employeeId: employeeId, employeeName: employeeName),
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
          title: Text('员工', style: TextStyle(
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
                  Icon(Icons.badge, color: Colors.purple[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '员工列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredEmployees.length} 位员工',
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
              child: _isLoading && _employees.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _fetchEmployees(isRefresh: true),
                      child: _filteredEmployees.isEmpty
                          ? SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: Container(
                                height: MediaQuery.of(context).size.height * 0.7,
                                child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.badge_outlined, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  _isSearching ? '没有匹配的员工' : '暂无员工',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加员工',
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
                      itemCount: _filteredEmployees.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      itemBuilder: (context, index) {
                        final employee = _filteredEmployees[index];
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
                                  CircleAvatar(
                                    backgroundColor: Colors.purple[100],
                                    child: Text(
                                      employee.name.isNotEmpty 
                                          ? employee.name[0].toUpperCase() 
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.purple[800],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employee.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (employee.note != null && employee.note!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              employee.note!,
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
                                        icon: Icon(Icons.list_alt, color: Colors.blue),
                                        tooltip: '查看记录',
                                        onPressed: () => _viewEmployeeRecords(
                                          employee.id, 
                                          employee.name
                                        ),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      SizedBox(width: 4),
                                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.purple),
                                        tooltip: '编辑',
                                        onPressed: () => _editEmployee(employee),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 4),
                                          child: IconButton(
                                            icon: Icon(Icons.delete, color: Colors.red),
                                            tooltip: '删除',
                                            onPressed: () => _deleteEmployee(employee),
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
                        hintText: '搜索员工...',
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
                          borderSide: BorderSide(color: Colors.purple),
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
                    onPressed: _addEmployee,
                    child: Icon(Icons.add),
                    tooltip: '添加员工',
                    backgroundColor: Colors.purple,
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

class EmployeeDialog extends StatefulWidget {
  final Employee? employee;

  EmployeeDialog({this.employee});

  @override
  _EmployeeDialogState createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<EmployeeDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      _nameController.text = widget.employee!.name;
      _noteController.text = widget.employee!.note ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.employee == null ? '添加员工' : '编辑员工',
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
                labelText: '员工姓名',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.badge, color: Colors.purple),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入员工姓名';
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
                prefixIcon: Icon(Icons.note, color: Colors.purple),
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
                  final Map<String, dynamic> employee = {
                    'name': _nameController.text.trim(),
                    'note': _noteController.text.trim().isEmpty 
                        ? null 
                        : _noteController.text.trim(),
                  };
                  Navigator.of(context).pop(employee);
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
 