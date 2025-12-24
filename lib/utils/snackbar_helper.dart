import 'package:flutter/material.dart';

/// SnackBar 扩展方法
/// 
/// 提供显示 SnackBar 的扩展方法，新的 SnackBar 会自动顶替当前显示的 SnackBar
extension SnackBarExtension on BuildContext {
  /// 显示 SnackBar，新的会顶替旧的
  /// 
  /// [message] 提示信息
  /// [backgroundColor] 背景颜色，默认为绿色
  /// [duration] 显示时长，默认为 2 秒
  void showSnackBar(
    String message, {
    Color? backgroundColor,
    Duration? duration,
  }) {
    // 先隐藏当前显示的 SnackBar（如果有）
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    
    // 显示新的 SnackBar
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? Colors.green,
        duration: duration ?? Duration(seconds: 2),
      ),
    );
  }

  /// 显示错误信息的 SnackBar
  /// 
  /// [message] 错误信息
  /// [duration] 显示时长，默认为 3 秒
  void showErrorSnackBar(
    String message, {
    Duration? duration,
  }) {
    showSnackBar(
      message,
      backgroundColor: Colors.red,
      duration: duration ?? Duration(seconds: 3),
    );
  }

  /// 显示成功信息的 SnackBar
  /// 
  /// [message] 成功信息
  /// [duration] 显示时长，默认为 2 秒
  void showSuccessSnackBar(
    String message, {
    Duration? duration,
  }) {
    showSnackBar(
      message,
      backgroundColor: Colors.green,
      duration: duration ?? Duration(seconds: 2),
    );
  }

  /// 显示警告信息的 SnackBar
  /// 
  /// [message] 警告信息
  /// [duration] 显示时长，默认为 3 秒
  void showWarningSnackBar(
    String message, {
    Duration? duration,
  }) {
    showSnackBar(
      message,
      backgroundColor: Colors.orange,
      duration: duration ?? Duration(seconds: 3),
    );
  }
}
