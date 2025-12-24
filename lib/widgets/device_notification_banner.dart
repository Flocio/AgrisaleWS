/// 设备通知横幅组件
/// 显示设备上线/下线通知

import 'package:flutter/material.dart';

class DeviceNotificationBanner {
  static OverlayEntry? _overlayEntry;
  static bool _isShowing = false;

  /// 显示设备上线通知
  static void showOnlineNotification(BuildContext context, String deviceName, String platform) {
    _showNotification(
      context: context,
      message: '新设备上线：$deviceName（$platform）',
      icon: Icons.devices,
      iconColor: Colors.green,
    );
  }

  /// 显示设备下线通知
  static void showOfflineNotification(BuildContext context, String deviceName, String platform) {
    _showNotification(
      context: context,
      message: '设备已下线：$deviceName（$platform）',
      icon: Icons.devices_other,
      iconColor: Colors.orange,
    );
  }

  /// 显示通知横幅
  static void _showNotification({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    // 如果已经有通知在显示，先移除
    if (_isShowing) {
      hide();
    }

    final overlay = Overlay.of(context);
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                // 检测向上滑动
                if (details.delta.dy < -5) {
                  hide();
                }
              },
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: iconColor,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    _isShowing = true;

    // 5秒后自动隐藏
    Future.delayed(Duration(seconds: 5), () {
      hide();
    });
  }

  /// 隐藏通知横幅
  static void hide() {
    if (_overlayEntry != null && _isShowing) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _isShowing = false;
    }
  }
}
