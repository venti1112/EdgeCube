import 'dart:convert';

import 'package:dio/dio.dart';

/// 将请求异常映射为用户可读提示:
/// 优先取后端错误体 { code, message } 中的 message,其次按状态码/网络类型兜底。
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final resp = error.response;
    if (resp?.statusCode == 401) return '登录已失效,请重新登录';
    if (resp?.statusCode == 403) return '当前来源被服务器拒绝';
    // 后端错误响应体:{ "code": "...", "message": "..." }
    final data = resp?.data;
    if (data != null) {
      try {
        final Map<String, dynamic> map = data is String
            ? jsonDecode(data) as Map<String, dynamic>
            : (data as Map).cast<String, dynamic>();
        final msg = map['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      } catch (_) {
        // 非 JSON 体,走下方兜底
      }
    }
    final status = resp?.statusCode;
    if (status != null) return '请求失败:$status';
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return '无法连接服务器';
      default:
        return '请求失败:${error.type.name}';
    }
  }
  return error.toString();
}