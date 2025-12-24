/// 应用版本信息常量
/// 
/// 注意：此文件中的版本号应该与 pubspec.yaml 中的 version 保持一致
/// 但实际运行时，建议使用 PackageInfo.fromPlatform().version 获取真实版本号
/// 
/// 此文件主要用于：
/// 1. 服务器端需要版本号时（通过代码生成或脚本同步）
/// 2. 编译时需要的版本号常量
/// 3. 作为版本号的单一来源（Single Source of Truth）

import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  /// 应用版本号（主版本号.次版本号.修订号）
  /// 此值应该与 pubspec.yaml 中的 version 字段保持一致
  /// 格式：主版本号.次版本号.修订号（例如：1.1.0）
  /// 
  /// ⚠️ 重要：修改版本号时，只需修改此处的值，然后同步到 pubspec.yaml
  static const String version = '1.0.0';
  
  /// 版本号前缀（用于显示，例如：v1.1.0）
  static String get versionWithPrefix => 'v$version';
  
  /// 获取应用版本号（推荐使用此方法，从 package_info_plus 获取真实版本）
  /// 
  /// 此方法会从 PackageInfo 获取实际版本号，确保与 pubspec.yaml 一致
  /// 如果无法获取，则返回常量中的版本号作为后备
  static Future<String> getVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      // 如果无法获取，返回常量版本号
      return version;
    }
  }
  
  /// 获取带前缀的版本号（例如：v1.1.0）
  static Future<String> getVersionWithPrefix() async {
    final v = await getVersion();
    return 'v$v';
  }
  
  /// 用于 User-Agent 的版本号（去除特殊字符，仅保留版本号）
  static String get versionForUserAgent => version.replaceAll(RegExp(r'[^\w.]'), '');
}

