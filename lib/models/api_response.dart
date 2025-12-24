/// API 响应模型
/// 统一所有 API 响应的格式

class ApiResponse<T> {
  /// 操作是否成功
  final bool success;

  /// 响应消息
  final String message;

  /// 响应数据（泛型，可以是任何类型）
  final T? data;

  /// 错误代码（可选）
  final String? errorCode;

  /// 错误详情（可选）
  final Map<String, dynamic>? details;

  ApiResponse({
    required this.success,
    required this.message,
    this.data,
    this.errorCode,
    this.details,
  });

  /// 从 JSON 创建 ApiResponse
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T? Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'] as T?,
      errorCode: json['error_code'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'data': data,
      if (errorCode != null) 'error_code': errorCode,
      if (details != null) 'details': details,
    };
  }

  /// 判断是否成功
  bool get isSuccess => success;

  /// 判断是否失败
  bool get isError => !success;
}

/// 分页响应模型
class PaginatedResponse<T> {
  /// 数据列表
  final List<T> items;

  /// 总数
  final int total;

  /// 当前页码
  final int page;

  /// 每页数量
  final int pageSize;

  /// 总页数
  final int totalPages;

  PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  /// 从 JSON 创建 PaginatedResponse
  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return PaginatedResponse<T>(
      items: itemsJson.map((item) => fromJsonT(item as Map<String, dynamic>)).toList(),
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      pageSize: json['page_size'] ?? 20,
      totalPages: json['total_pages'] ?? 0,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson(T Function(T) toJsonT) {
    return {
      'items': items.map((item) => toJsonT(item)).toList(),
      'total': total,
      'page': page,
      'page_size': pageSize,
      'total_pages': totalPages,
    };
  }

  /// 是否有下一页
  bool get hasNextPage => page < totalPages;

  /// 是否有上一页
  bool get hasPreviousPage => page > 1;
}


