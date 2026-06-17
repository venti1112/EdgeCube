import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// 错误报告上传服务：将崩溃日志上传到 EdgeCube 服务器。
class ErrorReportService {
  static const String _endpoint =
      'https://edgecube-api.ventichat.com/api/error_report';

  /// 日志大小上限：5 MB。超过此大小的日志不允许上传。
  static const int maxUploadBytes = 5 * 1024 * 1024;

  /// 上传崩溃日志。
  ///
  /// [logContent] 为拼接好设备信息的完整日志文本。
  /// [deviceId] 为设备唯一标识，放入请求头 `X-Device-Id`。
  /// 返回 [UploadResult]，包含成功标志与具体信息。
  static Future<UploadResult> upload({
    required String logContent,
    required String deviceId,
  }) async {
    final bodyBytes = utf8.encode(logContent);
    if (bodyBytes.length > maxUploadBytes) {
      return const UploadResult(
        success: false,
        message: '日志超过 5 MB，无法上传',
      );
    }

    try {
      final uri = Uri.parse(_endpoint);
      final request = http.MultipartRequest('POST', uri)
        ..headers['X-Device-Id'] = deviceId
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bodyBytes,
          filename: 'crash_${DateTime.now().millisecondsSinceEpoch}.log',
          contentType: MediaType('text', 'plain'),
        ));

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      // 解析服务端返回的 JSON message。
      String serverMessage;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        serverMessage = (body['message'] as String?) ?? '未知错误';
      } catch (_) {
        serverMessage = 'HTTP ${response.statusCode}';
      }

      if (response.statusCode == 200) {
        return const UploadResult(success: true, message: '上传成功');
      }
      return UploadResult(success: false, message: serverMessage);
    } catch (e) {
      return UploadResult(success: false, message: '网络错误: $e');
    }
  }
}

/// 上传操作的结果。
class UploadResult {
  const UploadResult({required this.success, required this.message});

  /// 是否成功（HTTP 200）。
  final bool success;

  /// 具体描述信息（成功提示或失败原因）。
  final String message;
}
