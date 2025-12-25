import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/return_repository.dart';
import '../repositories/income_repository.dart';
import '../repositories/remittance_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/workspace_repository.dart';
import '../services/auth_service.dart';
import '../database_helper.dart';
import 'package:sqflite/sqflite.dart';
import '../models/api_error.dart';
import '../models/api_response.dart';
import 'api_service.dart';
import 'local_audit_log_service.dart';
import '../models/audit_log.dart';

class AutoBackupService {
  static final AutoBackupService _instance = AutoBackupService._internal();
  factory AutoBackupService() => _instance;
  AutoBackupService._internal();

  final ProductRepository _productRepo = ProductRepository();
  final SupplierRepository _supplierRepo = SupplierRepository();
  final CustomerRepository _customerRepo = CustomerRepository();
  final EmployeeRepository _employeeRepo = EmployeeRepository();
  final PurchaseRepository _purchaseRepo = PurchaseRepository();
  final SaleRepository _saleRepo = SaleRepository();
  final ReturnRepository _returnRepo = ReturnRepository();
  final IncomeRepository _incomeRepo = IncomeRepository();
  final RemittanceRepository _remittanceRepo = RemittanceRepository();
  final SettingsRepository _settingsRepo = SettingsRepository();
  final WorkspaceRepository _workspaceRepo = WorkspaceRepository();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  Timer? _autoBackupTimer;
  bool _isBackupRunning = false;
  DateTime? _nextBackupTime; // 记录下次备份时间
  Duration? _interval; // 当前备份间隔
  int? _currentWorkspaceId; // 当前workspace ID

  /// 获取workspace级别的设置键
  String _getWorkspaceKey(String key) {
    final workspaceId = _currentWorkspaceId;
    if (workspaceId == null) {
      return key; // 如果没有workspace，使用全局键（向后兼容）
    }
    return '${key}_workspace_$workspaceId';
  }

  /// 将下次备份时间持久化到本地（workspace级别）
  Future<void> _saveNextBackupTime(DateTime? time) async {
    _nextBackupTime = time;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getWorkspaceKey('auto_backup_next_time');
      if (time == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, time.toIso8601String());
      }
    } catch (e) {
      // 持久化失败不影响备份逻辑
      print('保存下次自动备份时间失败（不影响备份）: $e');
    }
  }

  /// 从本地恢复下次备份时间（workspace级别）
  Future<DateTime?> _loadNextBackupTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getWorkspaceKey('auto_backup_next_time');
      final nextTimeStr = prefs.getString(key);
      if (nextTimeStr == null || nextTimeStr.isEmpty) {
        return null;
      }
      return DateTime.tryParse(nextTimeStr);
    } catch (e) {
      print('加载下次自动备份时间失败（不影响备份）: $e');
      return null;
    }
  }

  // 启动自动备份（workspace级别）
  Future<void> startAutoBackup(int intervalMinutes) async {
    await stopAutoBackup(); // 先停止现有的定时器
    
    // 获取当前workspace ID
    _currentWorkspaceId = await _apiService.getWorkspaceId();
    if (_currentWorkspaceId == null) {
      print('未选择workspace，无法启动自动备份');
      return;
    }
    
    _interval = Duration(minutes: intervalMinutes);
    print('启动workspace自动备份服务（workspace ID: $_currentWorkspaceId），间隔: $intervalMinutes 分钟');
    
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastBackupTimeKey = _getWorkspaceKey('last_backup_time');
    final lastBackupTimeStr = prefs.getString(lastBackupTimeKey);

    // 优先尝试从已记录的下一次备份时间恢复（对应本地版的 auto_backup_next_time）
    final storedNextTime = await _loadNextBackupTime();
    if (storedNextTime != null && storedNextTime.isAfter(now)) {
      _nextBackupTime = storedNextTime;
      _scheduleNextTimer();
      return;
    }

    if (lastBackupTimeStr != null) {
      try {
        final lastBackupTime = DateTime.parse(lastBackupTimeStr);
        final candidateNext = lastBackupTime.add(_interval!);
        if (candidateNext.isAfter(now)) {
          // 上次备份时间 + 间隔 仍在未来，按原计划时间继续
          await _saveNextBackupTime(candidateNext);
        } else {
          // 在应用关闭期间已经错过了计划备份，启动后尽快执行一次（例如 10 秒后）
          await _saveNextBackupTime(now.add(const Duration(seconds: 10)));
        }
      } catch (_) {
        // 解析失败时退回为从现在开始计算
        await _saveNextBackupTime(now.add(_interval!));
      }
    } else {
      // 从未备份过，从现在开始计算
      await _saveNextBackupTime(now.add(_interval!));
    }

    _scheduleNextTimer();
  }

  /// 使用新的间隔重新启动自动备份调度（从当前时间开始，不使用上次记录的下次备份时间）
  Future<void> restartWithNewInterval(int intervalMinutes) async {
    await stopAutoBackup();

    // 获取当前workspace ID
    _currentWorkspaceId = await _apiService.getWorkspaceId();
    if (_currentWorkspaceId == null) {
      print('未选择workspace，无法重新启动自动备份');
      return;
    }

    _interval = Duration(minutes: intervalMinutes);
    print('使用新间隔重新启动workspace自动备份服务（workspace ID: $_currentWorkspaceId），间隔: $intervalMinutes 分钟');

    final now = DateTime.now();
    await _saveNextBackupTime(now.add(_interval!));
    _scheduleNextTimer();
  }

  // 停止自动备份
  Future<void> stopAutoBackup() async {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    _nextBackupTime = null; // 清除内存中的下次备份时间（本地存储可保留，用于下次恢复）
    _interval = null;
    _currentWorkspaceId = null;
    print('停止自动备份服务');
  }

  // 安排下一次备份的定时器（单次定时，执行后再安排下一次）
  void _scheduleNextTimer() {
    if (_nextBackupTime == null || _interval == null) {
      return;
    }

    final now = DateTime.now();
    var delay = _nextBackupTime!.difference(now);
    if (delay.inSeconds <= 0) {
      delay = const Duration(seconds: 1);
    }

    _autoBackupTimer = Timer(delay, () async {
      await performAutoBackup();
      // 每次备份后更新下次备份时间
      await _saveNextBackupTime(DateTime.now().add(_interval!));
      _scheduleNextTimer();
    });
  }
  
  // 获取距离下一次备份的剩余时间（秒）
  int? getSecondsUntilNextBackup() {
    if (_nextBackupTime == null || _autoBackupTimer == null) {
      return null;
    }
    final now = DateTime.now();
    final difference = _nextBackupTime!.difference(now);
    return difference.inSeconds > 0 ? difference.inSeconds : 0;
  }
  
  // 格式化剩余时间为易读格式
  String formatTimeUntilNextBackup() {
    final seconds = getSecondsUntilNextBackup();
    if (seconds == null) {
      return '未启动';
    }
    
    if (seconds == 0) {
      return '即将备份...';
    }
    
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '$hours 小时 $minutes 分钟 $secs 秒';
    } else if (minutes > 0) {
      return '$minutes 分钟 $secs 秒';
    } else {
      return '$secs 秒';
    }
  }

  /// 如果开启了"退出时自动备份"，在workspace退出前调用一次
  Future<void> backupOnWorkspaceExitIfNeeded() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        return; // 没有workspace，不需要备份
      }

      // 确保 _currentWorkspaceId 已设置（用于 _getWorkspaceKey）
      _currentWorkspaceId = workspaceId;

      final prefs = await SharedPreferences.getInstance();
      final backupOnExitKey = _getWorkspaceKey('auto_backup_on_exit');
      final backupOnExit = prefs.getBool(backupOnExitKey) ?? false;
      final username = prefs.getString('current_username');

      if (!backupOnExit || username == null || username.isEmpty) {
        return;
      }

      // 标记退出时备份正在进行（用于检测异常退出后未完成的备份）
      final exitBackupKey = _getWorkspaceKey('exit_backup_in_progress');
      await prefs.setBool(exitBackupKey, true);

      final success = await performAutoBackup();
      print('workspace退出前自动备份结果: $success');

      // 备份完成后清除标记
      await prefs.setBool(exitBackupKey, false);
    } catch (e) {
      // 退出前自动备份失败不影响退出
      print('workspace退出前自动备份失败（不影响退出）: $e');
      // 尝试清除标记
      try {
        final prefs = await SharedPreferences.getInstance();
        final workspaceId = await _apiService.getWorkspaceId();
        if (workspaceId != null) {
          _currentWorkspaceId = workspaceId; // 确保设置
          final exitBackupKey = _getWorkspaceKey('exit_backup_in_progress');
          await prefs.setBool(exitBackupKey, false);
        }
      } catch (_) {}
    }
  }

  /// 检查上次workspace退出时的备份是否未完成，如果是，执行一次补充备份
  /// 应该在workspace启动时自动备份之前调用
  Future<void> checkAndRecoverWorkspaceExitBackup() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        return; // 没有workspace，不需要检查
      }

      // 确保 _currentWorkspaceId 已设置（用于 _getWorkspaceKey）
      _currentWorkspaceId = workspaceId;

      final prefs = await SharedPreferences.getInstance();
      final exitBackupKey = _getWorkspaceKey('exit_backup_in_progress');
      final exitBackupInProgress = prefs.getBool(exitBackupKey) ?? false;
      final backupOnExitKey = _getWorkspaceKey('auto_backup_on_exit');
      final backupOnExit = prefs.getBool(backupOnExitKey) ?? false;

      if (exitBackupInProgress && backupOnExit) {
        print('检测到上次workspace退出时的备份未完成，正在补充执行...');
        // 清除标记
        await prefs.setBool(exitBackupKey, false);
        // 执行补充备份
        final success = await performAutoBackup();
        print('补充workspace退出时备份结果: $success');
      } else if (exitBackupInProgress) {
        // 标记存在但退出备份未开启，只清除标记
        await prefs.setBool(exitBackupKey, false);
      }
    } catch (e) {
      print('检查workspace退出时备份状态失败: $e');
    }
  }

  // 执行一次备份（workspace级别）
  Future<bool> performAutoBackup() async {
    if (_isBackupRunning) {
      print('备份正在进行中，跳过本次');
      return false;
    }

    _isBackupRunning = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        print('未登录，跳过自动备份');
        _isBackupRunning = false;
        return false;
      }

      // 获取当前workspace信息
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        print('未选择workspace，跳过自动备份');
        _isBackupRunning = false;
        return false;
      }

      final workspace = await _apiService.getCurrentWorkspace();
      if (workspace == null) {
        print('无法获取workspace信息，跳过自动备份');
        _isBackupRunning = false;
        return false;
      }

      final workspaceName = workspace['name'] as String;
      _currentWorkspaceId = workspaceId;

      // 并行获取所有数据、应用版本号和备份目录（这些操作互不依赖）
      final allResults = await Future.wait([
        // 数据获取（只包含当前workspace的数据）
        Future.wait([
        _productRepo.getProducts(page: 1, pageSize: 10000),
        _supplierRepo.getAllSuppliers(),
        _customerRepo.getAllCustomers(),
        _employeeRepo.getAllEmployees(),
        _purchaseRepo.getPurchases(page: 1, pageSize: 10000),
        _saleRepo.getSales(page: 1, pageSize: 10000),
        _returnRepo.getReturns(page: 1, pageSize: 10000),
        _incomeRepo.getIncomes(page: 1, pageSize: 10000),
        _remittanceRepo.getRemittances(page: 1, pageSize: 10000),
        ]),
        // 应用版本号
        PackageInfo.fromPlatform(),
        // 备份目录
        getAutoBackupDirectory(),
      ]);
      
      final results = allResults[0] as List;
      final packageInfo = allResults[1] as PackageInfo;
      final backupDir = allResults[2] as Directory;
      final appVersion = packageInfo.version;
      
      // 转换为 Map 格式以保持兼容性
      final products = (results[0] as PaginatedResponse).items.map((p) => p.toJson()).toList();
      final suppliersList = (results[1] as List).map((s) => s.toJson()).toList();
      final customersList = (results[2] as List).map((c) => c.toJson()).toList();
      final employeesList = (results[3] as List).map((e) => e.toJson()).toList();
      final purchases = (results[4] as PaginatedResponse).items.map((p) => p.toJson()).toList();
      final sales = (results[5] as PaginatedResponse).items.map((s) => s.toJson()).toList();
      final returns = (results[6] as PaginatedResponse).items.map((r) => r.toJson()).toList();
      final income = (results[7] as PaginatedResponse).items.map((i) => i.toJson()).toList();
      final remittance = (results[8] as PaginatedResponse).items.map((r) => r.toJson()).toList();
      
      // 构建备份数据（包含workspace信息）
      final backupData = {
        'backupInfo': {
          'type': 'auto_backup',
          'username': username,
          'workspaceId': workspaceId,
          'workspaceName': workspaceName,
          'backupTime': DateTime.now().toIso8601String(),
          'version': appVersion, // 从 package_info_plus 获取版本号
        },
        'data': {
          'products': products,
          'suppliers': suppliersList,
          'customers': customersList,
          'employees': employeesList,
          'purchases': purchases,
          'sales': sales,
          'returns': returns,
          'income': income,
          'remittance': remittance,
        }
      };

      // 转换为JSON
      final jsonString = jsonEncode(backupData);
      
      // 生成文件名（包含workspace名称）
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'auto_backup_${workspaceName}_$timestamp.json';
      
      // 保存文件
      final file = File('${backupDir.path}/$fileName');
      await file.writeAsString(jsonString);
      
      print('workspace自动备份成功: $fileName');
      
      // 更新最后备份时间（workspace级别）
      try {
        final lastBackupTimeKey = _getWorkspaceKey('last_backup_time');
        await prefs.setString(lastBackupTimeKey, DateTime.now().toIso8601String());
      } catch (e) {
        print('更新备份时间失败: $e');
      }
      
      // 清理旧备份（异步执行，不阻塞返回）
      _cleanOldBackups().catchError((e) {
        print('清理旧备份失败: $e');
      });
      
      _isBackupRunning = false;
      return true;
      
    } on ApiError catch (e) {
      print('自动备份失败（API错误）: ${e.message}');
      _isBackupRunning = false;
      return false;
    } catch (e) {
      print('自动备份失败: $e');
      _isBackupRunning = false;
      return false;
    }
  }

  // 获取备份目录
  Future<Directory> getAutoBackupDirectory() async {
    Directory baseDir;
    
    if (Platform.isAndroid) {
      // Android: 使用应用文档目录（更可靠，不需要特殊权限）
      baseDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      // iOS: 使用 Documents 目录
      baseDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // 桌面平台: 使用 Application Support
      baseDir = await getApplicationSupportDirectory();
    } else {
      // 其他平台：后备方案
      baseDir = await getApplicationDocumentsDirectory();
    }
    
    final autoBackupDir = Directory('${baseDir.path}/AutoBackups');
    if (!await autoBackupDir.exists()) {
      await autoBackupDir.create(recursive: true);
    }
    
    return autoBackupDir;
  }

  // 获取所有备份文件列表
  Future<List<Map<String, dynamic>>> getBackupList() async {
    try {
      final backupDir = await getAutoBackupDirectory();
      final files = backupDir.listSync()
        .where((f) => f is File && f.path.endsWith('.json'))
        .map((f) => f as File)
        .toList();
      
      // 按修改时间排序（新 → 旧）
      files.sort((a, b) => 
        b.lastModifiedSync().compareTo(a.lastModifiedSync())
      );
      
      // 构建备份信息列表
      List<Map<String, dynamic>> backupList = [];
      for (var file in files) {
        final stat = await file.stat();
        backupList.add({
          'path': file.path,
          'fileName': file.path.split('/').last,
          'modifiedTime': stat.modified,
          'size': stat.size,
        });
      }
      
      return backupList;
    } catch (e) {
      print('获取备份列表失败: $e');
      return [];
    }
  }

  // 删除指定备份
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('删除备份成功: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      print('删除备份失败: $e');
      return false;
    }
  }

  // 删除所有备份
  Future<int> deleteAllBackups() async {
    try {
      final backupList = await getBackupList();
      int deletedCount = 0;
      
      for (var backup in backupList) {
        if (await deleteBackup(backup['path'])) {
          deletedCount++;
        }
      }
      
      return deletedCount;
    } catch (e) {
      print('删除所有备份失败: $e');
      return 0;
    }
  }

  // 清理旧备份（保留指定数量，workspace级别）
  Future<void> _cleanOldBackups() async {
    try {
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        return; // 没有workspace，不需要清理
      }

      // 获取最大保留数量设置（workspace级别）
      final prefs = await SharedPreferences.getInstance();
      final maxCountKey = _getWorkspaceKey('auto_backup_max_count');
      final maxCount = prefs.getInt(maxCountKey) ?? 20;
      
      // 获取当前workspace的所有备份（按workspace名称过滤）
      final workspace = await _apiService.getCurrentWorkspace();
      if (workspace == null) {
        return;
      }
      final workspaceName = workspace['name'] as String;
      
      final allBackups = await getBackupList();
      // 过滤出当前workspace的备份（文件名包含workspace名称）
      final workspaceBackups = allBackups.where((backup) {
        final fileName = backup['fileName'] as String;
        return fileName.contains('_${workspaceName}_');
      }).toList();
      
      // 按修改时间排序（新 → 旧）
      workspaceBackups.sort((a, b) => 
        (b['modifiedTime'] as DateTime).compareTo(a['modifiedTime'] as DateTime)
      );
      
      // 如果备份数量超过最大值，删除旧的
      if (workspaceBackups.length > maxCount) {
        for (var i = maxCount; i < workspaceBackups.length; i++) {
          await deleteBackup(workspaceBackups[i]['path']);
        }
        print('清理旧备份: 删除了 ${workspaceBackups.length - maxCount} 个');
      }
    } catch (e) {
      print('清理旧备份失败: $e');
    }
  }

  // 恢复备份（workspace级别，支持本地和云端workspace）
  Future<bool> restoreBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('备份文件不存在');
        return false;
      }

      // 获取当前workspace信息
      final workspaceId = await _apiService.getWorkspaceId();
      if (workspaceId == null) {
        print('未选择workspace，无法恢复备份');
        return false;
      }

      final workspace = await _apiService.getCurrentWorkspace();
      if (workspace == null) {
        print('无法获取workspace信息，无法恢复备份');
        return false;
      }

      final storageType = workspace['storage_type'] as String? ?? workspace['storageType'] as String?;
      final jsonString = await file.readAsString();
      final Map<String, dynamic> backupData = jsonDecode(jsonString);
      
      // 验证数据格式
      if (!backupData.containsKey('backupInfo') && !backupData.containsKey('exportInfo')) {
        print('备份文件格式错误：缺少 backupInfo 或 exportInfo');
        return false;
      }

      if (!backupData.containsKey('data')) {
        print('备份文件格式错误：缺少 data');
        return false;
      }

      // 转换备份格式为导入格式（兼容 exportInfo 和 backupInfo）
      final Map<String, dynamic> importData;
      if (backupData.containsKey('backupInfo')) {
        // 自动备份格式：backupInfo -> exportInfo
        final backupInfo = backupData['backupInfo'] as Map<String, dynamic>;
        importData = {
          'exportInfo': {
            'username': backupInfo['username'] ?? '未知',
            'exportTime': backupInfo['backupTime'] ?? backupInfo['exportTime'] ?? DateTime.now().toIso8601String(),
            'version': backupInfo['version'] ?? (await PackageInfo.fromPlatform()).version,
            'workspaceName': backupInfo['workspaceName'],
            'workspaceId': backupInfo['workspaceId'],
          },
          'data': backupData['data'],
        };
      } else {
        // 手动导出格式：直接使用，但确保有workspace信息
        importData = Map<String, dynamic>.from(backupData);
        if (!importData['exportInfo'].containsKey('workspaceName')) {
          importData['exportInfo']['workspaceName'] = workspace['name'];
        }
        if (!importData['exportInfo'].containsKey('workspaceId')) {
          importData['exportInfo']['workspaceId'] = workspaceId;
        }
      }

      // 根据workspace类型选择导入方式
      if (storageType == 'server') {
        // 服务器workspace：调用API导入
        // 标记为备份恢复，以便服务器端记录正确的日志
        importData['source'] = 'backup';
        await _workspaceRepo.importWorkspaceData(workspaceId, importData);
      } else {
        // 本地workspace：直接操作本地数据库
        await _importDataToLocal(workspaceId, importData['data'] as Map<String, dynamic>);
      }

      print('恢复备份成功');
      return true;
    } on ApiError catch (e) {
      print('恢复备份失败（API错误）: ${e.message}');
      return false;
    } catch (e) {
      print('恢复备份失败: $e');
      return false;
    }
  }

  /// 导入数据到本地workspace（与workspace_data_management_screen中的逻辑一致）
  Future<void> _importDataToLocal(int workspaceId, Map<String, dynamic> data) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    final username = await _authService.getCurrentUsername();
    
    if (username == null) {
      throw ApiError(message: '未登录');
    }
    
    final userId = await dbHelper.getCurrentUserId(username);
    if (userId == null) {
      throw ApiError(message: '用户不存在');
    }
    
    // 在事务中执行导入
    await db.transaction((txn) async {
      // 0. 在删除前，先获取当前数据作为 oldData（用于日志对比）
      final oldData = <String, dynamic>{
        'workspaceId': workspaceId,
        'import_counts': <String, int>{},
      };
      
      // 统计当前各表的数据量
      final tables = ['suppliers', 'customers', 'employees', 'products', 
                     'purchases', 'sales', 'returns', 'income', 'remittance'];
      for (final table in tables) {
        final result = await txn.rawQuery(
          'SELECT COUNT(*) as count FROM $table WHERE workspaceId = ?',
          [workspaceId]
        );
        final count = result.first['count'] as int? ?? 0;
        oldData['import_counts'][table] = count;
      }
      
      final oldTotalCount = (oldData['import_counts'] as Map<String, int>)
          .values
          .fold<int>(0, (sum, count) => sum + count);
      oldData['total_count'] = oldTotalCount;
      
      // 1. 删除该workspace的所有业务数据
      await txn.delete('remittance', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('income', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('returns', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('sales', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('purchases', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('products', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('employees', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('customers', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      await txn.delete('suppliers', where: 'workspaceId = ?', whereArgs: [workspaceId]);
      
      // 2. 创建ID映射表（旧ID -> 新ID）
      final supplierIdMap = <int, int>{};
      final customerIdMap = <int, int>{};
      final employeeIdMap = <int, int>{};
      final productIdMap = <int, int>{};
      
      // 3. 导入suppliers
      final suppliers = (data['suppliers'] as List?) ?? [];
      for (final supplierData in suppliers) {
        final originalId = supplierData['id'] as int?;
        final newId = await txn.insert('suppliers', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': supplierData['name'] as String? ?? '',
          'note': supplierData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          supplierIdMap[originalId] = newId;
        }
      }
      
      // 4. 导入customers
      final customers = (data['customers'] as List?) ?? [];
      for (final customerData in customers) {
        final originalId = customerData['id'] as int?;
        final newId = await txn.insert('customers', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': customerData['name'] as String? ?? '',
          'note': customerData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          customerIdMap[originalId] = newId;
        }
      }
      
      // 5. 导入employees
      final employees = (data['employees'] as List?) ?? [];
      for (final employeeData in employees) {
        final originalId = employeeData['id'] as int?;
        final newId = await txn.insert('employees', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': employeeData['name'] as String? ?? '',
          'note': employeeData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          employeeIdMap[originalId] = newId;
        }
      }
      
      // 6. 导入products
      final products = (data['products'] as List?) ?? [];
      for (final productData in products) {
        final originalId = productData['id'] as int?;
        // 处理supplierId映射
        int? supplierId = productData['supplierId'] as int?;
        if (supplierId == 0) {
          supplierId = null;
        } else if (supplierId != null && supplierIdMap.containsKey(supplierId)) {
          supplierId = supplierIdMap[supplierId];
        } else if (supplierId != null && !supplierIdMap.containsKey(supplierId)) {
          supplierId = null; // 如果映射不存在，设为null
        }
        
        // 处理unit
        String unit = productData['unit'] as String? ?? '公斤';
        if (unit != '斤' && unit != '公斤' && unit != '袋') {
          unit = '公斤';
        }
        
        final newId = await txn.insert('products', {
          'userId': userId,
          'workspaceId': workspaceId,
          'name': productData['name'] as String? ?? '',
          'description': productData['description'] as String?,
          'stock': (productData['stock'] as num?)?.toDouble() ?? 0.0,
          'unit': unit,
          'supplierId': supplierId,
          'version': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        if (originalId != null) {
          productIdMap[originalId] = newId;
        }
      }
      
      // 7. 导入purchases
      final purchases = (data['purchases'] as List?) ?? [];
      for (final purchaseData in purchases) {
        int? supplierId = purchaseData['supplierId'] as int?;
        if (supplierId == 0) {
          supplierId = null;
        } else if (supplierId != null && supplierIdMap.containsKey(supplierId)) {
          supplierId = supplierIdMap[supplierId];
        } else if (supplierId != null && !supplierIdMap.containsKey(supplierId)) {
          supplierId = null;
        }
        
        await txn.insert('purchases', {
          'userId': userId,
          'workspaceId': workspaceId,
          'productName': purchaseData['productName'] as String? ?? '',
          'quantity': (purchaseData['quantity'] as num?)?.toDouble() ?? 0.0,
          'purchaseDate': purchaseData['purchaseDate'] as String?,
          'supplierId': supplierId,
          'totalPurchasePrice': (purchaseData['totalPurchasePrice'] as num?)?.toDouble(),
          'note': purchaseData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 8. 导入sales
      final sales = (data['sales'] as List?) ?? [];
      for (final saleData in sales) {
        int? customerId = saleData['customerId'] as int?;
        if (customerId != null && customerIdMap.containsKey(customerId)) {
          customerId = customerIdMap[customerId];
        } else if (customerId != null && !customerIdMap.containsKey(customerId)) {
          customerId = null;
        }
        
        await txn.insert('sales', {
          'userId': userId,
          'workspaceId': workspaceId,
          'productName': saleData['productName'] as String? ?? '',
          'quantity': (saleData['quantity'] as num?)?.toDouble() ?? 0.0,
          'saleDate': saleData['saleDate'] as String?,
          'customerId': customerId,
          'totalSalePrice': (saleData['totalSalePrice'] as num?)?.toDouble(),
          'note': saleData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 9. 导入returns
      final returns = (data['returns'] as List?) ?? [];
      for (final returnData in returns) {
        int? customerId = returnData['customerId'] as int?;
        if (customerId != null && customerIdMap.containsKey(customerId)) {
          customerId = customerIdMap[customerId];
        } else if (customerId != null && !customerIdMap.containsKey(customerId)) {
          customerId = null;
        }
        
        await txn.insert('returns', {
          'userId': userId,
          'workspaceId': workspaceId,
          'productName': returnData['productName'] as String? ?? '',
          'quantity': (returnData['quantity'] as num?)?.toDouble() ?? 0.0,
          'returnDate': returnData['returnDate'] as String?,
          'customerId': customerId,
          'totalReturnPrice': (returnData['totalReturnPrice'] as num?)?.toDouble(),
          'note': returnData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 10. 导入income
      final income = (data['income'] as List?) ?? [];
      for (final incomeData in income) {
        int? customerId = incomeData['customerId'] as int?;
        if (customerId != null && customerIdMap.containsKey(customerId)) {
          customerId = customerIdMap[customerId];
        } else if (customerId != null && !customerIdMap.containsKey(customerId)) {
          customerId = null;
        }
        
        int? employeeId = incomeData['employeeId'] as int?;
        if (employeeId != null && employeeIdMap.containsKey(employeeId)) {
          employeeId = employeeIdMap[employeeId];
        } else if (employeeId != null && !employeeIdMap.containsKey(employeeId)) {
          employeeId = null;
        }
        
        String paymentMethod = incomeData['paymentMethod'] as String? ?? '现金';
        if (paymentMethod != '现金' && paymentMethod != '银行卡' && paymentMethod != '微信转账' && paymentMethod != '支付宝') {
          paymentMethod = '现金';
        }
        
        await txn.insert('income', {
          'userId': userId,
          'workspaceId': workspaceId,
          'incomeDate': incomeData['incomeDate'] as String?,
          'customerId': customerId,
          'amount': (incomeData['amount'] as num?)?.toDouble() ?? 0.0,
          'discount': (incomeData['discount'] as num?)?.toDouble() ?? 0.0,
          'employeeId': employeeId,
          'paymentMethod': paymentMethod,
          'note': incomeData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 11. 导入remittance
      final remittance = (data['remittance'] as List?) ?? [];
      for (final remittanceData in remittance) {
        int? supplierId = remittanceData['supplierId'] as int?;
        if (supplierId != null && supplierIdMap.containsKey(supplierId)) {
          supplierId = supplierIdMap[supplierId];
        } else if (supplierId != null && !supplierIdMap.containsKey(supplierId)) {
          supplierId = null;
        }
        
        int? employeeId = remittanceData['employeeId'] as int?;
        if (employeeId != null && employeeIdMap.containsKey(employeeId)) {
          employeeId = employeeIdMap[employeeId];
        } else if (employeeId != null && !employeeIdMap.containsKey(employeeId)) {
          employeeId = null;
        }
        
        String paymentMethod = remittanceData['paymentMethod'] as String? ?? '现金';
        if (paymentMethod != '现金' && paymentMethod != '银行卡' && paymentMethod != '微信转账' && paymentMethod != '支付宝') {
          paymentMethod = '现金';
        }
        
        await txn.insert('remittance', {
          'userId': userId,
          'workspaceId': workspaceId,
          'remittanceDate': remittanceData['remittanceDate'] as String?,
          'supplierId': supplierId,
          'amount': (remittanceData['amount'] as num?)?.toDouble() ?? 0.0,
          'employeeId': employeeId,
          'paymentMethod': paymentMethod,
          'note': remittanceData['note'] as String?,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // 统计导入的数据量
      final supplierCount = suppliers.length;
      final customerCount = customers.length;
      final employeeCount = employees.length;
      final productCount = products.length;
      final purchaseCount = purchases.length;
      final saleCount = sales.length;
      final returnCount = returns.length;
      final incomeCount = income.length;
      final remittanceCount = remittance.length;
      final totalCount = supplierCount + customerCount + employeeCount + productCount + 
                        purchaseCount + saleCount + returnCount + incomeCount + remittanceCount;
      
      // 记录操作日志（在事务内）
      try {
        await LocalAuditLogService().logOperation(
          operationType: OperationType.cover,
          entityType: EntityType.workspace_data,
          entityId: workspaceId,
          entityName: '备份恢复',
          oldData: oldData,
          newData: {
            'workspaceId': workspaceId,
            'import_counts': {
              'suppliers': supplierCount,
              'customers': customerCount,
              'employees': employeeCount,
              'products': productCount,
              'purchases': purchaseCount,
              'sales': saleCount,
              'returns': returnCount,
              'income': incomeCount,
              'remittance': remittanceCount,
            },
            'total_count': totalCount,
          },
          note: '恢复备份（覆盖）：供应商 $supplierCount，客户 $customerCount，员工 $employeeCount，产品 $productCount，采购 $purchaseCount，销售 $saleCount，退货 $returnCount，进账 $incomeCount，汇款 $remittanceCount，总计 $totalCount 条',
          transaction: txn,
          userId: userId,
          workspaceId: workspaceId,
          username: username,
        );
      } catch (e) {
        print('记录数据导入日志失败: $e');
        // 日志记录失败不影响业务
      }
    });
  }
}
