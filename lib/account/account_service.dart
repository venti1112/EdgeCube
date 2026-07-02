import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/network_store.dart';
import '../i18n/i18n_service.dart';
import '../online/cloud_headers.dart';
import 'account_models.dart';

/// 账号认证的无状态 HTTP 客户端。
///
/// 对接后端 `POST /api/auth/{register,verify,resend_verification,login,refresh,logout}`，
/// 请求 / 响应均为 JSON，统一响应体 `{code, message, data}`。
///
/// 所有方法都返回 [AuthResult]：
/// - 后端返回成功码（2xx）→ `success == true`，附带 `message` 与可选 `data`；
/// - 后端返回业务错误（4xx/5xx）→ `success == false`，`message` 优先取后端 `message`；
/// - 网络异常 / 超时 / 解析失败 → `success == false`，`message` 为本地化的错误提示。
///
/// 本服务只做「一次请求」，不持有登录态；登录态由 [AccountController] 管理。
class AccountService {
  AccountService._();

  static const Duration _timeout = Duration(seconds: 20);

  /// 用户注册。成功后后端会向邮箱发送验证码，需再调用 [verify] 完成验证。
  static Future<AuthResult<AccountUser>> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
  }) async {
    final res = await _post('/api/auth/register', {
      'username': username,
      'email': email,
      'password': password,
      if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
    });
    if (!res.success) return res.withData<AccountUser>(null);
    final data = res.data;
    final user = data is Map<String, dynamic>
        ? AccountUser.fromJson(data)
        : null;
    return res.withData<AccountUser>(user);
  }

  /// 使用邮箱验证码完成账号验证。
  static Future<AuthResult<void>> verify({
    required String account,
    required String password,
    required String code,
  }) async {
    final res = await _post('/api/auth/verify', {
      'account': account,
      'password': password,
      'code': code,
    });
    return res.withData<void>(null);
  }

  /// 重新发送邮箱验证码。
  static Future<AuthResult<void>> resendVerification({
    required String account,
    required String password,
  }) async {
    final res = await _post('/api/auth/resend_verification', {
      'account': account,
      'password': password,
    });
    return res.withData<void>(null);
  }

  /// 使用邮箱或用户名登录。
  ///
  /// [device] / [deviceId] 为可选设备信息：前者为设备型号（如 "Xiaomi 14"），
  /// 后者为在线服务生成的设备 ID（可能为空）。
  static Future<AuthResult<AuthSession>> login({
    required String account,
    required String password,
    String? device,
    String? deviceId,
  }) async {
    final res = await _post('/api/auth/login', {
      'account': account,
      'password': password,
      if (device != null && device.isNotEmpty) 'device': device,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    });
    return _toSessionResult(res);
  }

  /// 使用 refresh_token 换取新的 session_token。
  static Future<AuthResult<AuthSession>> refresh(String refreshToken) async {
    final res = await _post('/api/auth/refresh', {
      'refresh_token': refreshToken,
    });
    return _toSessionResult(res);
  }

  /// 登出：销毁后端当前会话。
  static Future<AuthResult<void>> logout(String sessionToken) async {
    final res = await _post('/api/auth/logout', {
      'session_token': sessionToken,
    });
    return res.withData<void>(null);
  }

  /// 将「登录 / 刷新」的原始结果转为携带 [AuthSession] 的结果。
  static AuthResult<AuthSession> _toSessionResult(AuthResult<dynamic> res) {
    if (!res.success) return res.withData<AuthSession>(null);
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      return AuthResult<AuthSession>(
        success: false,
        message: tr('account.error.badResponse'),
        code: res.code,
      );
    }
    return res.withData<AuthSession>(AuthSession.fromAuthData(data));
  }

  /// 发送一个 JSON POST 请求并解析统一响应体。
  ///
  /// 返回的 [AuthResult.data] 为后端 `data` 字段的原始动态值（可能为 Map / null）；
  /// 各方法据此进一步构造强类型数据。
  static Future<AuthResult<dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final baseUrl = await NetworkStore.loadBackendApiBaseUrl();
      final uri = Uri.parse('$baseUrl$path');
      final headers = await CloudHeaders.base();
      headers['Content-Type'] = 'application/json';
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);

      Map<String, dynamic>? parsed;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {
        // 响应非 JSON：交由下方按 HTTP 状态码兜底。
      }

      final int code =
          (parsed?['code'] as num?)?.toInt() ?? response.statusCode;
      final String? serverMessage = parsed?['message'] as String?;
      final dynamic data = parsed?['data'];

      final bool ok = response.statusCode >= 200 && response.statusCode < 300;
      if (ok) {
        return AuthResult<dynamic>(
          success: true,
          message: serverMessage ?? tr('account.msg.ok'),
          code: code,
          data: data,
        );
      }

      return AuthResult<dynamic>(
        success: false,
        message:
            serverMessage ??
            tr('account.error.httpStatus', {
              'status': '${response.statusCode}',
            }),
        code: code,
      );
    } catch (e) {
      return AuthResult<dynamic>(
        success: false,
        message: tr('account.error.network', {'error': '$e'}),
      );
    }
  }
}
