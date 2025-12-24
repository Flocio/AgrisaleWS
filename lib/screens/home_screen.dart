// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'workspace_dashboard_screen.dart';
import 'personal_center_screen.dart';

/// 主页面 - 包含底部导航栏，可在工作台和个人中心之间切换
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // 页面列表（延迟初始化）
  late final List<Widget> _pages;
  
  @override
  void initState() {
    super.initState();
    // 初始化页面列表，传递切换标签页的回调给 PersonalCenterScreen
    _pages = [
      WorkspaceDashboardScreen(),
      PersonalCenterScreen(
        onSwitchToWorkspace: () {
          setState(() {
            _currentIndex = 0; // 切换到工作台标签页
          });
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey[600],
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard, size: 24),
            activeIcon: Icon(Icons.dashboard, size: 28),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person, size: 24),
            activeIcon: Icon(Icons.person, size: 28),
            label: '',
          ),
        ],
      ),
    );
  }
}

