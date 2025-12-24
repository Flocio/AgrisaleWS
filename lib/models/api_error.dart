/// API 错误模型
/// 统一处理 API 错误

class ApiError implements Exception {
  /// 错误消息
  final String message;

  /// 错误代码
  final String? errorCode;

  /// HTTP 状态码
  final int? statusCode;

  /// 错误详情
  final Map<String, dynamic>? details;

  /// 原始错误
  final dynamic originalError;

  ApiError({
    required this.message,
    this.errorCode,
    this.statusCode,
    this.details,
    this.originalError,
  });

  /// 从 HTTP 响应创建 ApiError
  factory ApiError.fromHttpResponse(int statusCode, Map<String, dynamic>? json) {
    // FastAPI 的 HTTPException 返回 {"detail": "错误信息"}
    // 我们的 BaseResponse 返回 {"message": "错误信息"}
    // 优先使用 message，如果没有则使用 detail
    String errorMessage = '请求失败';
    if (json != null) {
      if (json['message'] != null) {
        errorMessage = json['message'].toString();
      } else if (json['detail'] != null) {
        errorMessage = json['detail'].toString();
      }
    }
    
    return ApiError(
      message: errorMessage,
      errorCode: json?['error_code'] as String?,
      statusCode: statusCode,
      details: json?['details'] as Map<String, dynamic>?,
    );
  }

  /// 网络错误
  factory ApiError.network(String message, [dynamic originalError]) {
    return ApiError(
      message: message,
      errorCode: 'NETWORK_ERROR',
      originalError: originalError,
    );
  }

  /// 超时错误
  factory ApiError.timeout([String? message]) {
    return ApiError(
      message: message ?? '请求超时，请检查网络连接',
      errorCode: 'TIMEOUT_ERROR',
    );
  }

  /// 认证错误
  factory ApiError.unauthorized([String? message]) {
    return ApiError(
      message: message ?? '未授权，请重新登录',
      errorCode: 'UNAUTHORIZED',
      statusCode: 401,
    );
  }

  /// 服务器错误
  factory ApiError.server(int statusCode, [String? message]) {
    return ApiError(
      message: message ?? '服务器错误',
      errorCode: 'SERVER_ERROR',
      statusCode: statusCode,
    );
  }

  /// 未知错误
  factory ApiError.unknown([String? message, dynamic originalError]) {
    return ApiError(
      message: message ?? '未知错误',
      errorCode: 'UNKNOWN_ERROR',
      originalError: originalError,
    );
  }

  @override
  String toString() {
    if (errorCode != null) {
      return 'ApiError($errorCode): $message';
    }
    return 'ApiError: $message';
  }

  /// 是否为网络错误
  bool get isNetworkError => errorCode == 'NETWORK_ERROR';

  /// 是否为超时错误
  bool get isTimeoutError => errorCode == 'TIMEOUT_ERROR';

  /// 是否为认证错误
  bool get isUnauthorized => errorCode == 'UNAUTHORIZED' || statusCode == 401;

  /// 是否为服务器错误
  bool get isServerError {
    final code = statusCode;
    return code != null && code >= 500;
  }
}


