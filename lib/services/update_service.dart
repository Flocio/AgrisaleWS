import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_version.dart';

class UpdateService {
  // GitHub 仓库地址
  static const String GITHUB_REPO = 'Flocio/AgrisaleWS';
  static const String GITHUB_RELEASES_URL = 'https://github.com/$GITHUB_REPO/releases/latest';
  
  // 下载源配置（按优先级排序）
  static List<DownloadSource> get DOWNLOAD_SOURCES => [
    DownloadSource(
      name: 'GitHub 直连',
      apiUrl: 'https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: null,
    ),
    DownloadSource(
      name: 'GitHub 代理 1 (ghproxy.com)',
      apiUrl: 'https://ghproxy.com/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghproxy.com',
    ),
    DownloadSource(
      name: 'GitHub 代理 2 (ghps.cc)',
      apiUrl: 'https://ghps.cc/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghps.cc',
    ),
    DownloadSource(
      name: 'GitHub 代理 3 (mirror.ghproxy.com)',
      apiUrl: 'https://mirror.ghproxy.com/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://mirror.ghproxy.com',
    ),
    DownloadSource(
      name: 'GitHub 代理 4 (ghp.ci)',
      apiUrl: 'https://ghp.ci/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghp.ci',
    ),
    DownloadSource(
      name: 'GitHub 代理 5 (ghproxy.net)',
      apiUrl: 'https://ghproxy.net/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghproxy.net',
    ),
  ];
  
  // 检查更新（尝试多个源）
  static Future<UpdateInfo?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    
    // 按优先级尝试每个下载源
    for (var source in DOWNLOAD_SOURCES) {
      try {
        final updateInfo = await _checkFromSource(source, currentVersion);
        
        if (updateInfo != null) {
          return updateInfo;
        } else {
          return null; // 已是最新版本，不需要继续尝试其他源
        }
      } catch (e) {
        continue; // 尝试下一个源
      }
    }
    
    // 所有源都失败，返回 GitHub Releases 链接
    return UpdateInfo(
      version: '未知',
      currentVersion: currentVersion,
      releaseNotes: '无法连接到更新服务器，请手动访问 GitHub Releases 下载更新。',
      downloadUrl: null,
      githubReleasesUrl: GITHUB_RELEASES_URL,
    );
  }
  
  // 从指定源检查更新
  static Future<UpdateInfo?> _checkFromSource(DownloadSource source, String currentVersion) async {
    try {
      final response = await http.get(
        Uri.parse(source.apiUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AgrisaleWS-Update-Checker/${AppVersion.versionForUserAgent}',
        },
      ).timeout(Duration(seconds: 20)); // 增加到20秒超时
      
      if (response.statusCode == 200) {
        // 检查响应内容是否为JSON
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json') && 
            !contentType.contains('text/json')) {
          // 如果返回的不是JSON（可能是HTML错误页面）
          final preview = response.body.length > 200 
              ? response.body.substring(0, 200) 
              : response.body;
          throw Exception('服务器返回了非JSON内容: $preview...');
        }
        
        final data = jsonDecode(response.body);
        
        // 验证响应数据格式
        if (data is! Map || !data.containsKey('tag_name')) {
          throw Exception('无效的API响应格式');
        }
        
        final latestVersionTag = data['tag_name'] as String;
        final latestVersion = latestVersionTag.replaceAll('v', '');
        
        
        if (_compareVersions(latestVersion, currentVersion) > 0) {
          // 有新版本，获取下载链接
          final downloadUrl = _getDownloadUrl(
            data['assets'] as List,
            Platform.operatingSystem,
            source.proxyBase,
          );
          
          return UpdateInfo(
            version: latestVersionTag,
            currentVersion: currentVersion,
            releaseNotes: data['body'] ?? '',
            downloadUrl: downloadUrl,
            githubReleasesUrl: GITHUB_RELEASES_URL,
          );
        } else {
          // 已是最新版本
          return null;
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } on TimeoutException {
      throw Exception('连接超时（20秒）');
    } on FormatException catch (e) {
      throw Exception('响应格式错误: ${e.message}');
    } on SocketException catch (e) {
      throw Exception('网络连接失败: ${e.message}');
    } on HandshakeException catch (e) {
      throw Exception('SSL握手失败: ${e.message}');
    } catch (e) {
      throw Exception('未知错误: $e');
    }
  }
  
  // 获取下载链接（支持代理）
  static String? _getDownloadUrl(List assets, String platform, String? proxyBase) {
    if (platform == 'android') {
      // Android优先查找APK文件（可以直接安装），如果没有再查找AAB文件
      String? apkUrl;
      String? aabUrl;
      
      for (var asset in assets) {
        final assetName = asset['name'] as String;
        // 清理URL中的空格和特殊字符
        final originalUrl = (asset['browser_download_url'] as String).trim().replaceAll(' ', '');
        
        if (assetName.startsWith('agrisalews-android-') && assetName.endsWith('.apk')) {
          apkUrl = originalUrl;
        } else if (assetName.startsWith('agrisalews-android-') && assetName.endsWith('.aab')) {
          aabUrl = originalUrl;
        }
      }
      
      // 优先返回APK，如果没有APK则返回AAB（虽然不能直接安装，但至少可以提示用户）
      final selectedUrl = apkUrl ?? aabUrl;
      if (selectedUrl != null) {
        // 如果使用代理，添加代理前缀
        if (proxyBase != null) {
          final proxiedUrl = '$proxyBase/$selectedUrl';
          return proxiedUrl;
        } else {
          return selectedUrl;
        }
      }
      
      return null;
    } else {
      // 其他平台的处理
      String fileName;
      
      if (platform == 'ios') {
      fileName = 'agrisalews-ios-';
    } else if (platform == 'macos') {
      fileName = 'agrisalews-macos-';
    } else if (platform == 'windows') {
      fileName = 'agrisalews-windows-';
    } else {
      return null;
    }
    
    for (var asset in assets) {
      final assetName = asset['name'] as String;
      if (assetName.startsWith(fileName)) {
          // 清理URL中的空格和特殊字符
          final originalUrl = (asset['browser_download_url'] as String).trim().replaceAll(' ', '');
        
        // 如果使用代理，添加代理前缀
        if (proxyBase != null) {
          final proxiedUrl = '$proxyBase/$originalUrl';
          return proxiedUrl;
        } else {
          return originalUrl;
        }
      }
    }
    
    return null;
    }
  }
  
  // 版本号比较 (返回: 1=version1>version2, -1=version1<version2, 0=相等)
  static int _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final v2Parts = version2.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    
    // 补齐到3位
    while (v1Parts.length < 3) v1Parts.add(0);
    while (v2Parts.length < 3) v2Parts.add(0);
    
    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return 1;
      if (v1Parts[i] < v2Parts[i]) return -1;
    }
    return 0;
  }
  
  // 下载并安装更新（支持多个源重试）
  static Future<void> downloadAndInstall(
    String originalDownloadUrl,
    Function(int received, int total, String? downloadPath) onProgress,
  ) async {
    // Android: 预先检查并请求安装权限
    if (Platform.isAndroid) {
      await _checkAndRequestInstallPermission();
    }
    
    // 预先删除旧的APK文件（避免因文件存在导致下载失败）
    await _deleteOldApkFiles(originalDownloadUrl);
    
    // 构建多个下载源（原始链接 + 代理链接）
    final downloadUrls = _buildDownloadUrls(originalDownloadUrl);
    
    Exception? lastError;
    
    // 尝试从每个源下载
    for (var downloadUrl in downloadUrls) {
      try {
        
        // 配置Dio以允许不验证SSL证书（仅用于下载场景）
        final dio = Dio();
        
        // 创建自定义HttpClient，禁用SSL证书验证
        // 注意：这仅用于从GitHub下载更新文件，即使通过代理也是安全的
        if (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          final httpClient = HttpClient()
            ..badCertificateCallback = (X509Certificate cert, String host, int port) {
              // 允许所有证书（仅用于下载更新文件）
              return true;
            };
          
          // 配置Dio使用自定义HttpClient（dio 5.x方式）
          final adapter = IOHttpClientAdapter();
          adapter.createHttpClient = () {
            return httpClient;
          };
          dio.httpClientAdapter = adapter;
        }
        
        // 使用外部存储目录，确保安装程序可以访问
        Directory downloadDir;
        if (Platform.isAndroid) {
          // Android: 尝试使用外部存储的Download目录
          try {
            downloadDir = Directory('/storage/emulated/0/Download');
            if (!await downloadDir.exists()) {
              // 如果外部存储不可用，使用应用缓存目录
              downloadDir = await getTemporaryDirectory();
            }
          } catch (e) {
            // 如果外部存储访问失败，使用应用缓存目录
            downloadDir = await getTemporaryDirectory();
          }
        } else {
          downloadDir = await getTemporaryDirectory();
        }
        
        // 清理URL并提取文件名
        final cleanOriginalUrl = originalDownloadUrl.trim().replaceAll(' ', '');
        final fileName = cleanOriginalUrl.split('/').last;
        var filePath = '${downloadDir.path}/$fileName';
        
        
        // 检查是否是AAB文件（Android App Bundle不能直接安装）
        if (Platform.isAndroid && fileName.toLowerCase().endsWith('.aab')) {
          throw Exception('下载的文件是AAB格式（Android App Bundle），无法直接安装。\n\n'
              'AAB文件需要通过Google Play商店安装。\n'
              '请从GitHub Releases下载APK文件进行安装。');
        }
        
        // 检查并删除旧文件，如果无法删除则使用新文件名
        final oldFile = File(filePath);
        if (await oldFile.exists()) {
          try {
            await oldFile.delete();
          } catch (e) {
            // 使用带时间戳的文件名
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
            final baseName = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
            filePath = '${downloadDir.path}/${baseName}_$timestamp$ext';
          }
        }
        
        // 清理URL中的空格和特殊字符
        final cleanDownloadUrl = (downloadUrl['url'] as String).trim().replaceAll(' ', '');
        
        // 下载文件（30秒超时）
        await dio.download(
          cleanDownloadUrl,
          filePath,
          options: Options(
            receiveTimeout: Duration(seconds: 30),
            followRedirects: true,
            validateStatus: (status) => status! < 500, // 允许重定向和客户端错误
          ),
          onReceiveProgress: (received, total) {
            onProgress(received, total, filePath);
          },
        ).timeout(Duration(minutes: 10)); // 总超时10分钟
        
        
        // 验证下载的文件
        try {
          if (Platform.isAndroid) {
            await _validateApkFile(filePath);
          } else if (Platform.isWindows) {
            await _validateZipFile(filePath);
          } else if (Platform.isMacOS) {
            await _validateZipFile(filePath);
          }
        } catch (validationError) {
          // 验证失败，删除无效文件
          try {
            final file = File(filePath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (deleteError) {
          }
          // 重新抛出验证错误，让外层catch处理
          throw validationError;
        }
        
        // 根据平台安装
        if (Platform.isAndroid) {
          // 记录下载的APK文件名，用于验证
          
          await _installAndroid(filePath);
          
          // 安装启动后，等待一小段时间让安装完成
          await Future.delayed(Duration(seconds: 3));
          
          // 验证安装（注意：当前运行的进程还是旧版本，所以这里只是检查文件）
          final installedFile = File(filePath);
          if (await installedFile.exists()) {
          }
        } else if (Platform.isIOS) {
          await _installIOS();
        } else if (Platform.isWindows) {
          await _installWindows(filePath);
        } else if (Platform.isMacOS) {
          await _installMacOS(filePath);
        }
        
        // 下载成功，返回
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        continue; // 尝试下一个源
      }
    }
    
    // 所有源都失败
    throw lastError ?? Exception('所有下载源都失败');
  }
  
  // 构建多个下载源 URL
  static List<Map<String, String>> _buildDownloadUrls(String originalUrl) {
    final urls = <Map<String, String>>[];
    
    // 清理原始URL中的空格和特殊字符
    final cleanOriginalUrl = originalUrl.trim().replaceAll(' ', '');
    
    // 1. 原始链接（直连）
    urls.add({
      'name': 'GitHub 直连',
      'url': cleanOriginalUrl,
    });
    
    // 2-4. 代理链接
    final proxies = [
      'https://ghproxy.com',
      'https://ghps.cc',
      'https://mirror.ghproxy.com',
    ];
    
    for (var proxy in proxies) {
      urls.add({
        'name': '代理服务',
        'url': '$proxy/$cleanOriginalUrl',
      });
    }
    
    return urls;
  }
  
  // 检查并请求安装未知应用权限（Android专用）
  static Future<void> _checkAndRequestInstallPermission() async {
    try {
      // 检查是否有安装未知应用的权限
      final installStatus = await Permission.requestInstallPackages.status;
      
      if (!installStatus.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        
        if (!result.isGranted) {
        }
      } else {
      }
    } catch (e) {
      // 不抛出异常，继续流程（安装时系统会自动提示）
    }
  }
  
  // 预先删除旧的APK文件
  static Future<void> _deleteOldApkFiles(String downloadUrl) async {
    try {
      // 清理URL并提取文件名
      final cleanUrl = downloadUrl.trim().replaceAll(' ', '');
      final fileName = cleanUrl.split('/').last;
      
      // 检查所有可能的下载目录
      final possibleDirs = <Directory>[];
      
      if (Platform.isAndroid) {
        // 请求存储权限（用于访问外部Download目录）
        try {
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            await Permission.storage.request();
          }
          
          // Android 11+ 需要管理外部存储权限
          if (await Permission.manageExternalStorage.status.isDenied) {
            await Permission.manageExternalStorage.request();
          }
        } catch (e) {
        }
        
        // Android外部下载目录
        possibleDirs.add(Directory('/storage/emulated/0/Download'));
        // 应用临时目录
        try {
          possibleDirs.add(await getTemporaryDirectory());
        } catch (e) {
        }
      } else {
        try {
          possibleDirs.add(await getTemporaryDirectory());
        } catch (e) {
        }
      }
      
      for (var dir in possibleDirs) {
        if (await dir.exists()) {
          final filePath = '${dir.path}/$fileName';
          final file = File(filePath);
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (e) {
            }
          } else {
          }
        }
      }
    } catch (e) {
      // 不抛出异常，继续下载流程
    }
  }
  
  // 验证APK文件
  static Future<void> _validateApkFile(String filePath) async {
    final file = File(filePath);
    
    // 检查文件是否存在
    if (!await file.exists()) {
      throw Exception('下载的文件不存在');
    }
    
    // 检查文件大小（APK文件应该至少1MB）
    final fileSize = await file.length();
    if (fileSize < 1024 * 1024) {
      throw Exception('下载的文件太小（${(fileSize / 1024).toStringAsFixed(1)} KB），可能下载不完整');
    }
    
    // 检查文件扩展名
    if (!filePath.toLowerCase().endsWith('.apk')) {
      throw Exception('下载的文件不是APK格式: $filePath');
    }
    
    // 检查文件头（APK文件是ZIP格式，ZIP文件头是"PK"）
    final bytes = await file.openRead(0, 2).toList();
    if (bytes.isEmpty || bytes[0].isEmpty) {
      throw Exception('无法读取文件内容');
    }
    
    final fileHeader = String.fromCharCodes(bytes[0].take(2));
    if (fileHeader != 'PK') {
      // 检查是否是HTML错误页面
      final firstBytes = await file.openRead(0, 100).toList();
      if (firstBytes.isNotEmpty && firstBytes[0].isNotEmpty) {
        final content = String.fromCharCodes(firstBytes[0].take(50));
        if (content.trim().toLowerCase().startsWith('<!doctype') || 
            content.trim().toLowerCase().startsWith('<html')) {
          throw Exception('下载的文件是HTML错误页面，不是有效的APK文件。请检查网络连接或尝试手动下载。');
        }
      }
      throw Exception('下载的文件格式不正确（不是有效的APK/ZIP文件）。文件头: $fileHeader');
    }
    
  }
  
  // 验证ZIP文件
  static Future<void> _validateZipFile(String filePath) async {
    final file = File(filePath);
    
    // 检查文件是否存在
    if (!await file.exists()) {
      throw Exception('下载的文件不存在');
    }
    
    // 检查文件大小（ZIP文件应该至少1MB）
    final fileSize = await file.length();
    if (fileSize < 1024 * 1024) {
      throw Exception('下载的文件太小（${(fileSize / 1024).toStringAsFixed(1)} KB），可能下载不完整');
    }
    
    // 检查文件扩展名
    if (!filePath.toLowerCase().endsWith('.zip')) {
      throw Exception('下载的文件不是ZIP格式: $filePath');
    }
    
    // 检查文件头（ZIP文件头是"PK"）
    final bytes = await file.openRead(0, 2).toList();
    if (bytes.isEmpty || bytes[0].isEmpty) {
      throw Exception('无法读取文件内容');
    }
    
    final fileHeader = String.fromCharCodes(bytes[0].take(2));
    if (fileHeader != 'PK') {
      // 检查是否是HTML错误页面
      final firstBytes = await file.openRead(0, 100).toList();
      if (firstBytes.isNotEmpty && firstBytes[0].isNotEmpty) {
        final content = String.fromCharCodes(firstBytes[0].take(50));
        if (content.trim().toLowerCase().startsWith('<!doctype') || 
            content.trim().toLowerCase().startsWith('<html')) {
          throw Exception('下载的文件是HTML错误页面，不是有效的ZIP文件。请检查网络连接或尝试手动下载。');
        }
      }
      throw Exception('下载的文件格式不正确（不是有效的ZIP文件）。文件头: $fileHeader');
    }
    
  }
  
  // Android 安装
  static Future<void> _installAndroid(String apkPath) async {
    try {
      // 确保文件存在且可读
      final file = File(apkPath);
      if (!await file.exists()) {
        throw Exception('APK文件不存在: $apkPath');
      }
      
      // 检查文件权限
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('APK文件为空');
      }
      
      
      // 再次验证文件可读
      try {
        final testBytes = await file.openRead(0, 100).toList();
        if (testBytes.isEmpty || testBytes[0].isEmpty) {
          throw Exception('APK文件无法读取');
        }
      } catch (e) {
        throw Exception('APK文件无法读取: $e');
      }
      
      // 调用安装插件
      // install_plugin会自动处理权限请求和FileProvider
      
      try {
        // 注意：installApk 只是启动安装流程，不等待安装完成
        // 它不会返回安装是否成功，也不会抛出异常（即使安装失败）
        // 用户必须在系统安装界面中完成所有步骤
      await InstallPlugin.installApk(apkPath);
      } catch (installError) {
        rethrow;
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      // 提供更详细的错误信息
      if (errorStr.contains('permission denied') || 
          errorStr.contains('权限') ||
          errorStr.contains('install_denied') ||
          errorStr.contains('user restriction')) {
        throw Exception('需要安装权限');
      } else if (errorStr.contains('filenotfoundexception') ||
                 errorStr.contains('文件不存在')) {
        throw Exception('安装失败：找不到APK文件。\n\n错误详情: $e');
      } else if (errorStr.contains('package') && 
                 (errorStr.contains('signature') || 
                  errorStr.contains('签名') ||
                  errorStr.contains('conflicting') ||
                  errorStr.contains('newer') ||
                  errorStr.contains('older'))) {
        // 签名不匹配或版本冲突
        throw Exception('安装失败：签名不匹配。\n\n'
            '这可能是因为：\n'
            '1. 您当前运行的是通过 flutter run 安装的调试版本\n'
            '2. 而下载的APK是发布版本，签名不同\n\n'
            '解决方案：\n'
            '• 如果是开发测试：请使用 flutter build apk 构建发布版本后手动安装\n'
            '• 如果是正式使用：请先卸载当前应用，再安装新版本\n\n'
            '错误详情: $e');
      } else if (errorStr.contains('user_canceled') ||
                 errorStr.contains('用户取消')) {
        throw Exception('安装已取消');
      } else {
        throw Exception('安装失败：$e\n\n'
            '如果这是开发环境（通过 flutter run 运行），可能是签名不匹配问题。\n'
            '请尝试手动从GitHub Releases下载并安装。');
      }
    }
  }
  
  // 直接安装APK（用于权限授予后重试）
  static Future<void> installApkDirect(String apkPath) async {
    return _installAndroid(apkPath);
  }
  
  // iOS 安装（跳转到 App Store 或 TestFlight）
  static Future<void> _installIOS() async {
    // iOS 无法直接安装 IPA，需要跳转到 App Store
    // 这里可以打开 GitHub Releases 页面让用户手动安装
    final url = Uri.parse('https://github.com/$GITHUB_REPO/releases/latest');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
  
  // Windows 安装
  static Future<void> _installWindows(String zipPath) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final extractPath = '${appDir.path}/update';
      final extractDir = Directory(extractPath);
      
      // 清理旧文件
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      
      // 解压 ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (var file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(path.join(extractPath, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }
      
      // 查找并运行 agrisalews.exe
      final exeFile = File(path.join(extractPath, 'agrisalews.exe'));
      if (await exeFile.exists()) {
        await Process.start(exeFile.path, [], mode: ProcessStartMode.detached);
      } else {
        // 如果找不到 exe，打开文件夹让用户手动运行
        await Process.run('explorer', [extractPath]);
      }
    } catch (e) {
      rethrow;
    }
  }
  
  // macOS 安装
  static Future<void> _installMacOS(String zipPath) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final extractPath = '${appDir.path}/update';
      final extractDir = Directory(extractPath);
      
      // 清理旧文件
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      
      // 解压 ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (var file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(path.join(extractPath, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }
      
      // 查找并打开 .app 文件
      final appFiles = extractDir.listSync(recursive: true)
          .where((f) => f.path.endsWith('.app'))
          .toList();
      
      if (appFiles.isNotEmpty) {
        await Process.run('open', [appFiles.first.path]);
      } else {
        // 如果找不到 .app，打开文件夹让用户手动安装
        await Process.run('open', [extractPath]);
      }
    } catch (e) {
      rethrow;
    }
  }
}

class UpdateInfo {
  final String version;
  final String currentVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String? githubReleasesUrl; // GitHub Releases 链接（用于手动下载）
  
  UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.releaseNotes,
    this.downloadUrl,
    this.githubReleasesUrl,
  });
}

// 下载源配置
class DownloadSource {
  final String name;
  final String apiUrl;
  final String? proxyBase; // 代理服务地址（用于下载链接）
  
  const DownloadSource({
    required this.name,
    required this.apiUrl,
    this.proxyBase,
  });
}
