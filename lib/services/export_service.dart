import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../utils/snackbar_helper.dart';

enum ExportAction {
  saveToLocal,
  share,
}

class ExportService {
  /// 对外统一调用的方法
  static Future<void> exportCSV({
    required BuildContext context,
    required String csvData,
    required String baseFileName, // 不含 .csv，中文名称
    required ExportAction action,
  }) async {
    try {
      final fileName = _generateFileName(baseFileName);

      // 1️⃣ 先生成临时 CSV 文件（绝对安全）
      final tempFile = await _createTempCSV(
        csvData: csvData,
        fileName: fileName,
      );

      // 2️⃣ 根据用户选择执行动作
      switch (action) {
        case ExportAction.saveToLocal:
          await _saveToLocal(context, tempFile, fileName);
          break;
        case ExportAction.share:
          await _shareFile(context, tempFile);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('导出失败：$e');
      }
    }
  }

  /// 生成带时间戳的文件名（中文）
  static String _generateFileName(String base, {String extension = 'csv'}) {
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '${base}_$ts.$extension';
  }

  /// 创建临时 CSV 文件
  static Future<File> _createTempCSV({
    required String csvData,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvData);
    return file;
  }

  /// 保存到本地（可选目录 + 改名）
  static Future<void> _saveToLocal(
    BuildContext context,
    File tempFile,
    String fileName, {
    String fileType = 'CSV',
  }) async {
    final extension = fileName.split('.').last;
    
    // 在 Android 和 iOS 上，需要传递 bytes 参数
    Uint8List? bytes;
    if (Platform.isAndroid || Platform.isIOS) {
      bytes = await tempFile.readAsBytes();
    }
    
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存 $fileType 文件',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );

    if (savePath == null) {
      if (context.mounted) {
        context.showSnackBar('已取消保存');
      }
      return;
    }

    // 在 macOS 上，需要手动复制文件（Android/iOS 上 saveFile 已经保存了）
    if (Platform.isMacOS) {
      await tempFile.copy(savePath);
    }
    
    if (context.mounted) {
      context.showSuccessSnackBar('导出成功');
    }
  }

  /// 保存 PDF 到本地（使用特殊处理确保在 macOS 上正常工作）
  static Future<void> _savePDFToLocal(
    BuildContext context,
    File tempFile,
    String fileName,
  ) async {
    try {
      // 读取文件字节数据（Android 和 iOS 需要）
      final bytes = await tempFile.readAsBytes();
      
      if (Platform.isMacOS) {
        // 在 macOS 上，使用 Completer 确保在主线程上执行
        final completer = Completer<String?>();
        
        SchedulerBinding.instance.addPostFrameCallback((_) async {
          try {
            // 等待一小段时间确保 UI 完全更新
            await Future.delayed(const Duration(milliseconds: 200));
            
            final savePath = await FilePicker.platform.saveFile(
              dialogTitle: '保存 PDF 文件',
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: ['pdf'],
            );
            
            completer.complete(savePath);
          } catch (e) {
            completer.completeError(e);
          }
        });
        
        final savePath = await completer.future;

        if (savePath == null) {
          if (context.mounted) {
            context.showSnackBar('已取消保存');
          }
          return;
        }

        await tempFile.copy(savePath);
      } else {
        // Android 和 iOS：需要传递 bytes 参数
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: '保存 PDF 文件',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: bytes,
        );

        if (savePath == null) {
          if (context.mounted) {
            context.showSnackBar('已取消保存');
          }
          return;
        }
      }
      
      if (context.mounted) {
        context.showSuccessSnackBar('导出成功');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('保存失败：$e');
      }
    }
  }

  /// 分享给其他 App
  static Future<void> _shareFile(BuildContext context, File file, {String fileType = 'CSV'}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '导出的 $fileType 文件',
    );
  }

  /// 显示导出选项对话框（先选择格式，再选择保存方式）
  static Future<void> showExportOptions({
    required BuildContext context,
    required String csvData,
    required String baseFileName,
  }) async {
    // 保存原始 context 的引用，避免被 builder 中的 context 遮蔽
    final parentContext = context;
    await showModalBottomSheet(
      context: parentContext,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '选择导出格式',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart, color: Colors.blue),
            title: const Text('CSV 文件'),
            onTap: () {
              Navigator.pop(parentContext);
              _showCSVExportOptions(parentContext, csvData, baseFileName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
            title: const Text('PDF 文件'),
            onTap: () {
              Navigator.pop(parentContext);
              _showPDFExportOptions(parentContext, csvData, baseFileName);
            },
          ),
        ],
      ),
    );
  }

  /// 显示 CSV 导出选项（保存方式）
  static Future<void> _showCSVExportOptions(
    BuildContext context,
    String csvData,
    String baseFileName,
  ) async {
    final parentContext = context;
    await showModalBottomSheet(
      context: parentContext,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('保存到本地'),
            onTap: () {
              Navigator.pop(parentContext);
              exportCSV(
                context: parentContext,
                csvData: csvData,
                baseFileName: baseFileName,
                action: ExportAction.saveToLocal,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('分享给其他应用'),
            onTap: () {
              Navigator.pop(parentContext);
              exportCSV(
                context: parentContext,
                csvData: csvData,
                baseFileName: baseFileName,
                action: ExportAction.share,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 显示 PDF 导出选项（保存方式）
  static Future<void> _showPDFExportOptions(
    BuildContext context,
    String csvData,
    String baseFileName,
  ) async {
    final parentContext = context;
    await showModalBottomSheet(
      context: parentContext,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('保存到本地'),
            onTap: () {
              Navigator.pop(parentContext);
              // 等待对话框完全关闭后再执行导出
              SchedulerBinding.instance.addPostFrameCallback((_) {
                exportPDF(
                  context: parentContext,
                  csvData: csvData,
                  baseFileName: baseFileName,
                  action: ExportAction.saveToLocal,
                );
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('分享给其他应用'),
            onTap: () {
              Navigator.pop(parentContext);
              // 等待对话框完全关闭后再执行导出
              SchedulerBinding.instance.addPostFrameCallback((_) {
                exportPDF(
                  context: parentContext,
                  csvData: csvData,
                  baseFileName: baseFileName,
                  action: ExportAction.share,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  /// 导出 PDF 文件
  static Future<void> exportPDF({
    required BuildContext context,
    required String csvData,
    required String baseFileName,
    required ExportAction action,
  }) async {
    try {
      final fileName = _generateFileName(baseFileName, extension: 'pdf');
      
      // 1️⃣ 将 CSV 数据转换为 PDF
      final pdf = await _createPDFFromCSV(csvData, baseFileName);
      
      // 2️⃣ 生成临时 PDF 文件
      final tempFile = await _createTempPDF(pdf: pdf, fileName: fileName);
      
      // 检查 context 是否仍然有效
      if (!context.mounted) {
        return;
      }
      
      // 3️⃣ 根据用户选择执行动作
      switch (action) {
        case ExportAction.saveToLocal:
          await _savePDFToLocal(context, tempFile, fileName);
          break;
        case ExportAction.share:
          await _shareFile(context, tempFile, fileType: 'PDF');
          break;
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('导出失败：$e');
      }
    }
  }

  /// 解析 CSV 行（处理引号内的逗号）
  static List<String> _parseCSVLine(String line) {
    List<String> result = [];
    String current = '';
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    result.add(current.trim());
    return result;
  }

  /// 加载中文字体（Noto Sans SC）
  static Future<pw.Font> _loadChineseFont({bool bold = false}) async {
    try {
      // 方法1: 优先尝试从本地 assets 加载字体文件
      try {
        final fontPath = bold
            ? 'assets/fonts/NotoSansSC-Bold.ttf'
            : 'assets/fonts/NotoSansSC-Regular.ttf';
        
        final fontData = await rootBundle.load(fontPath);
        final font = pw.Font.ttf(fontData);
        return font;
      } catch (e) {
        // 本地字体加载失败，尝试从网络下载
      }
      
      // 方法2: 如果本地字体不存在，尝试从国内可访问的 CDN 下载
      // 使用 jsDelivr CDN，通常可以在国内访问
      final fontUrls = [
        // jsDelivr CDN（通常可以在国内访问）
        bold
            ? 'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC%5Bwdth%2Cwght%5D.ttf'
            : 'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC%5Bwdth%2Cwght%5D.ttf',
        // 备用：使用 unpkg CDN
        bold
            ? 'https://unpkg.com/@fontsource/noto-sans-sc@latest/files/noto-sans-sc-chinese-simplified-700-normal.woff2'
            : 'https://unpkg.com/@fontsource/noto-sans-sc@latest/files/noto-sans-sc-chinese-simplified-400-normal.woff2',
      ];
      
      for (final fontUrl in fontUrls) {
        try {
          final response = await http.get(Uri.parse(fontUrl)).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('字体下载超时');
            },
          );
          
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            final fontData = ByteData.view(response.bodyBytes.buffer);
            final font = pw.Font.ttf(fontData);
            return font;
          }
        } catch (e) {
          continue;
        }
      }
      
      throw Exception(
        '字体加载失败。请将 Noto Sans SC 字体文件（Regular 和 Bold）放到 assets/fonts/ 目录下。\n'
        '下载地址：https://fonts.google.com/noto/specimen/Noto+Sans+SC\n'
        '文件名：NotoSansSC-Regular.ttf 和 NotoSansSC-Bold.ttf'
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 从 CSV 数据创建 PDF 文档
  static Future<pw.Document> _createPDFFromCSV(String csvData, String title) async {
    // 加载中文字体
    pw.Font font;
    pw.Font fontBold;
    try {
      font = await _loadChineseFont(bold: false);
      fontBold = await _loadChineseFont(bold: true);
    } catch (e) {
      throw Exception('无法加载中文字体，PDF 导出失败。请将字体文件放到 assets/fonts/ 目录。');
    }
    
    final pdf = pw.Document();
    final lines = csvData.split('\n');
    
    // 解析 CSV 数据
    List<List<String>> rows = [];
    List<String> header = [];
    bool isHeader = true;
    bool isSummary = false;
    List<String> summaryRows = [];
    List<String> metadata = [];
    
    // 常见的表头关键词（用于识别表头）
    final headerKeywords = ['日期', '类型', '产品', '数量', '单位', '客户', '供应商', '客户/供应商', '金额', '优惠', '付款方式', '备注', '进价', '售价', '交易方', '总售价', '总进价'];
    
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      // 解析 CSV 行
      final cells = _parseCSVLine(line);
      
      // 收集元数据（报告标题、用户信息等）- 更精确的匹配
      if (!isSummary && isHeader && cells.length == 1) {
        // 单列数据，可能是元数据
        final cell = cells[0].trim();
        if (cell.contains('报告') || cell.contains('用户:') || cell.contains('导出时间:') || 
            cell.contains('产品名称:') || cell.contains('关联供应商:') || cell.contains('客户:') ||
            cell.contains('供应商:') || cell.contains('日期范围:') || cell.contains('日期筛选:') ||
            cell.contains('类型筛选:') || cell.contains('员工:') || cell.contains('筛选')) {
          metadata.add(cell);
          continue;
        }
      }
      
      // 识别表头：包含表头关键词且列数 >= 2
      if (isHeader && cells.length >= 2) {
        // 检查是否包含表头关键词
        final lineText = cells.join(' ');
        bool hasHeaderKeyword = headerKeywords.any((keyword) => lineText.contains(keyword));
        
        // 检查是否看起来像表头（不包含冒号，因为元数据通常有冒号）
        bool looksLikeHeader = !lineText.contains(':') && cells.length >= 2;
        
        // 不是总计行
        bool isNotTotal = !cells[0].trim().contains('总计');
        
        if (hasHeaderKeyword && looksLikeHeader && isNotTotal) {
          header = cells;
          isHeader = false;
          continue;
        } else if (cells.length >= 3 && looksLikeHeader && !lineText.contains('报告') && isNotTotal) {
          // 如果没有关键词但列数>=3，且不包含元数据特征，也可能是表头（用于兼容）
          header = cells;
          isHeader = false;
          continue;
        }
      }
      
      // 检查是否是汇总信息部分（包括总计行）
      if (cells.isNotEmpty && (cells[0].trim() == '总计' || cells[0].trim().contains('总计') || 
          line.contains('汇总信息') || line.contains('汇总统计'))) {
        isSummary = true;
        // 将总计行也添加到汇总信息中
        summaryRows.add(line);
        continue;
      }
      
      // 数据行处理
      if (!isHeader && !isSummary && cells.length > 1) {
        // 确保数据行与表头列数匹配
        if (header.isEmpty) {
          // 如果没有表头，使用第一行作为表头
          header = cells;
          isHeader = false;
        } else if (cells.length == header.length) {
          rows.add(cells);
        } else if (cells.length > header.length) {
          // 如果数据行列数多于表头，截断到表头长度
          rows.add(cells.sublist(0, header.length));
        } else {
          // 如果数据行列数少于表头，补齐空字符串
          final paddedRow = List<String>.from(cells);
          while (paddedRow.length < header.length) {
            paddedRow.add('');
          }
          rows.add(paddedRow);
        }
      } else if (isSummary && cells.length > 1) {
        // 汇总信息行（包括总计行）
        summaryRows.add(line);
      }
    }
    
    // 计算列宽（根据列数动态调整）
    final columnCount = header.isNotEmpty ? header.length : (rows.isNotEmpty ? rows[0].length : 0);
    final pageWidth = PdfPageFormat.a4.width - 80; // 减去左右边距
    final columnWidth = columnCount > 0 ? pageWidth / columnCount : 100.0;
    
    // 构建 PDF 页面
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
        build: (pw.Context context) {
          return [
            // 标题
            pw.Header(
              level: 0,
                child: pw.Text(
                  title.replaceAll('\n', ' ').replaceAll('\r', ''),
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                  ),
                ),
            ),
            pw.SizedBox(height: 10),
            
            // 元数据信息
            if (metadata.isNotEmpty) ...[
              ...metadata.map((meta) => pw.Padding(
                padding: pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  meta.replaceAll('\n', ' ').replaceAll('\r', ''),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                    font: font,
                  ),
                ),
              )).toList(),
              pw.SizedBox(height: 10),
            ],
            
            // 数据表格
            if (header.isNotEmpty && rows.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: Map.fromIterable(
                  List.generate(columnCount, (i) => i),
                  key: (i) => i,
                  value: (i) => pw.FlexColumnWidth(1),
                ),
                children: [
                  // 表头
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey200),
                    children: header.map((cell) => pw.Padding(
                      padding: pw.EdgeInsets.all(6),
                      child: pw.Text(
                        cell.replaceAll('\n', ' ').replaceAll('\r', ''),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                          font: fontBold,
                        ),
                        maxLines: 2,
                        overflow: pw.TextOverflow.clip,
                      ),
                    )).toList(),
                  ),
                  // 数据行
                  ...rows.map((row) {
                    // 确保行数据与表头列数匹配
                    final paddedRow = List<String>.from(row);
                    while (paddedRow.length < header.length) {
                      paddedRow.add('');
                    }
                    if (paddedRow.length > header.length) {
                      paddedRow.removeRange(header.length, paddedRow.length);
                    }
                    
                    return pw.TableRow(
                      children: paddedRow.map((cell) => pw.Padding(
                        padding: pw.EdgeInsets.all(4),
                        child: pw.Text(
                          cell.replaceAll('\n', ' ').replaceAll('\r', ''),
                          style: pw.TextStyle(
                            fontSize: 8,
                            font: font,
                          ),
                          maxLines: 2,
                          overflow: pw.TextOverflow.clip,
                        ),
                      )).toList(),
                    );
                  }).toList(),
                ],
              ),
            
            // 汇总信息
            if (summaryRows.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Header(
                level: 1,
                child: pw.Text(
                  '汇总信息'.replaceAll('\n', ' ').replaceAll('\r', ''),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              // 检查是否有总计行（第一列是"总计"且列数与表头匹配）
              if (header.isNotEmpty) ...[
                // 查找总计行
                ...summaryRows.map((row) {
                  final cells = _parseCSVLine(row);
                  // 如果是总计行且列数与表头匹配，显示为表格行
                  if (cells.isNotEmpty && cells[0].trim() == '总计' && cells.length == header.length) {
                    return pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                      columnWidths: Map.fromIterable(
                        List.generate(header.length, (i) => i),
                        key: (i) => i,
                        value: (i) => pw.FlexColumnWidth(1),
                      ),
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColors.grey100),
                          children: cells.map((cell) => pw.Padding(
                            padding: pw.EdgeInsets.all(6),
                            child: pw.Text(
                              cell.replaceAll('\n', ' ').replaceAll('\r', ''),
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                font: fontBold,
                              ),
                              maxLines: 2,
                              overflow: pw.TextOverflow.clip,
                            ),
                          )).toList(),
                        ),
                      ],
                    );
                  } else if (cells.length >= 2) {
                    // 其他汇总行，显示为两列格式
                    return pw.Padding(
                      padding: pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              cells[0].replaceAll('\n', ' ').replaceAll('\r', ''),
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                font: fontBold,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              (cells.length > 1 ? cells[1] : '').replaceAll('\n', ' ').replaceAll('\r', ''),
                              style: pw.TextStyle(
                                fontSize: 10,
                                font: font,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return pw.Padding(
                      padding: pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text(
                        row.replaceAll('\n', ' ').replaceAll('\r', ''),
                        style: pw.TextStyle(
                          fontSize: 10,
                          font: font,
                        ),
                      ),
                    );
                  }
                }).toList(),
              ] else ...[
                // 如果没有表头，使用原来的简单格式
                ...summaryRows.map((row) {
                  final cells = _parseCSVLine(row);
                  if (cells.length >= 2) {
                    return pw.Padding(
                      padding: pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              cells[0].replaceAll('\n', ' ').replaceAll('\r', ''),
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                font: fontBold,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              (cells.length > 1 ? cells[1] : '').replaceAll('\n', ' ').replaceAll('\r', ''),
                              style: pw.TextStyle(
                                fontSize: 10,
                                font: font,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return pw.Padding(
                      padding: pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text(
                        row.replaceAll('\n', ' ').replaceAll('\r', ''),
                        style: pw.TextStyle(
                          fontSize: 10,
                          font: font,
                        ),
                      ),
                    );
                  }
                }).toList(),
              ],
            ],
          ];
        },
      ),
    );
    
    return pdf;
  }

  /// 创建临时 PDF 文件
  static Future<File> _createTempPDF({
    required pw.Document pdf,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    final bytes = await pdf.save();
    await file.writeAsBytes(bytes);
    return file;
  }


  /// 导出 JSON 文件（用于数据备份）
  static Future<void> exportJSON({
    required BuildContext context,
    required String jsonData,
    required String fileName, // 完整的文件名（包含扩展名）
    required ExportAction action,
  }) async {
    try {
      // 1️⃣ 先生成临时 JSON 文件（绝对安全）
      final tempFile = await _createTempJSON(
        jsonData: jsonData,
        fileName: fileName,
      );

      // 2️⃣ 根据用户选择执行动作
      switch (action) {
        case ExportAction.saveToLocal:
          await _saveJSONToLocal(context, tempFile, fileName);
          break;
        case ExportAction.share:
          await _shareJSONFile(context, tempFile);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('导出失败：$e');
      }
    }
  }

  /// 创建临时 JSON 文件
  static Future<File> _createTempJSON({
    required String jsonData,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonData);
    return file;
  }

  /// 保存 JSON 到本地（可选目录 + 改名）
  static Future<void> _saveJSONToLocal(
    BuildContext context,
    File tempFile,
    String fileName,
  ) async {
    // 在 Android 和 iOS 上，需要传递 bytes 参数
    Uint8List? bytes;
    if (Platform.isAndroid || Platform.isIOS) {
      bytes = await tempFile.readAsBytes();
    }
    
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存数据备份',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (savePath == null) {
      if (context.mounted) {
        context.showSnackBar('已取消保存');
      }
      return;
    }

    // 在 macOS 上，需要手动复制文件（Android/iOS 上 saveFile 已经保存了）
    if (Platform.isMacOS) {
      await tempFile.copy(savePath);
    }
    
    if (context.mounted) {
      context.showSuccessSnackBar('数据导出成功');
    }
  }

  /// 分享 JSON 文件给其他 App
  static Future<void> _shareJSONFile(BuildContext context, File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'AgrisaleWS数据备份文件',
    );
  }

  /// 显示 JSON 导出选项对话框
  static Future<void> showJSONExportOptions({
    required BuildContext context,
    required String jsonData,
    required String fileName,
  }) async {
    final parentContext = context;
    await showModalBottomSheet(
      context: parentContext,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('保存到本地'),
            onTap: () {
              Navigator.pop(parentContext);
              exportJSON(
                context: parentContext,
                jsonData: jsonData,
                fileName: fileName,
                action: ExportAction.saveToLocal,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('分享给其他应用'),
            onTap: () {
              Navigator.pop(parentContext);
              exportJSON(
                context: parentContext,
                jsonData: jsonData,
                fileName: fileName,
                action: ExportAction.share,
              );
            },
          ),
        ],
      ),
    );
  }
}

