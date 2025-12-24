// lib/screens/help_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';

class HelpScreen extends StatefulWidget {
  @override
  _HelpScreenState createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String? _helpContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    _loadHelp();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHelp() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = ApiService();
      // 获取 Markdown 格式的帮助文档
      final response = await http.get(
        Uri.parse('${apiService.baseUrl}/api/help'),
        headers: {
          'Accept': 'text/plain',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _helpContent = response.body;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = '加载帮助文档失败（状态码：${response.statusCode}）';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '加载帮助文档失败：$e';
        _isLoading = false;
      });
    }
  }

  // 滚动到指定章节
  void _scrollToSection(String anchor) {
    if (_helpContent == null || !_scrollController.hasClients) return;
    
    // 将中文锚点转换为可能的标题格式
    // 例如："快速开始" 可能对应 "## 快速开始"
    final lines = _helpContent!.split('\n');
    int targetLineIndex = -1;
    
    // 查找匹配的标题行
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      // 检查是否是目标标题（支持 ## 标题 或 ### 标题 格式）
      if (line.startsWith('## ') || line.startsWith('### ')) {
        final titleText = line.substring(3).trim();
        // 移除可能的链接格式，只比较文本
        final cleanTitle = titleText.replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '').trim();
        if (cleanTitle == anchor || titleText == anchor) {
          targetLineIndex = i;
          break;
        }
      }
    }
    
    if (targetLineIndex >= 0) {
      // 使用 Future.delayed 确保 Markdown 已经渲染完成
      Future.delayed(Duration(milliseconds: 100), () {
        if (!_scrollController.hasClients) return;
        
        // 估算目标位置（每行大约 20-25px，标题额外高度）
        double estimatedOffset = 0;
        for (int i = 0; i < targetLineIndex; i++) {
          final line = lines[i].trim();
          if (line.startsWith('## ')) {
            estimatedOffset += 40; // h2 标题高度
          } else if (line.startsWith('### ')) {
            estimatedOffset += 35; // h3 标题高度
          } else if (line.startsWith('# ')) {
            estimatedOffset += 50; // h1 标题高度
          } else if (line.isNotEmpty) {
            estimatedOffset += 22; // 普通行高度
          } else {
            estimatedOffset += 10; // 空行
          }
        }
        
        // 滚动到目标位置，留出一些顶部间距
        final targetOffset = estimatedOffset - 20;
        if (targetOffset >= 0 && targetOffset <= _scrollController.position.maxScrollExtent) {
          _scrollController.animateTo(
            targetOffset,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else if (targetOffset > _scrollController.position.maxScrollExtent) {
          // 如果目标位置超出范围，滚动到底部
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '帮助文档',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在加载帮助文档...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadHelp,
                        icon: Icon(Icons.refresh),
                        label: Text('重试'),
                      ),
                    ],
                  ),
                )
              : _helpContent != null
                  ? Markdown(
                      controller: _scrollController,
                      data: _helpContent!,
                      padding: EdgeInsets.all(16),
                      onTapLink: (text, href, title) {
                        // 处理锚点链接跳转
                        if (href != null && href.startsWith('#')) {
                          _scrollToSection(href.substring(1));
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        h1: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                        h2: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[600],
                        ),
                        h3: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                        h4: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                        p: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                        ),
                        listBullet: TextStyle(
                          fontSize: 14,
                        ),
                        strong: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                        a: TextStyle(
                          color: Colors.blue[700],
                          decoration: TextDecoration.underline,
                        ),
                        code: TextStyle(
                          backgroundColor: Colors.grey[200],
                          fontFamily: 'monospace',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    )
                  : Center(
                      child: Text('帮助文档为空'),
                    ),
    );
  }

}
