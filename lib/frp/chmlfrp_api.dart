import 'dart:convert';

import 'package:http/http.dart' as http;

import 'frp_models.dart';
import 'frp_provider.dart';
import 'frp_token_store.dart';

/// ChmlFrp（cf-v2.uapis.cn）API 客户端。
///
/// 鉴权走 QZhua 账号（account-api.qzhua.net）OAuth 设备码授权：
/// 设备端申请 device_code → 用户浏览器授权 → 设备端轮询拿 access_token。
/// 拿到 access_token 后直接作 `Authorization: Bearer` 调 cf-v2.uapis.cn，
/// 无需换取 ChmlFrp 自有 token（后端会校验 QZhua access_token）。
///
/// access_token 有时效（expires_in），到期前用 refresh_token 自动刷新。
/// FrpTokenStore 中存的是 JSON 字符串：`{at, rt, exp}`。
class ChmlFrpApi {
  ChmlFrpApi._();

  static const String _base = 'https://cf-v2.uapis.cn';

  /// QZhua 统一认证发行者。
  static const String _oauthIssuer = 'https://account-api.qzhua.net';

  /// Client ID
  static const String _clientId = '019f997e3360710b931fcd6d81aad92a';

  /// scope：profile/email 标准 OIDC，offline_access 取 refresh_token，
  /// chmlfrp_api 是 ChmlFrp 自定义 scope（不可省略，否则后端不认）。
  static const String _scope = 'profile email offline_access chmlfrp_api';

  static const Duration _timeout = Duration(seconds: 15);

  /// access_token 到期前 60 秒视为即将过期，触发自动刷新。
  static const Duration _refreshSkew = Duration(seconds: 60);

  // ── QZhua OAuth 设备码流程 ─────────────────────────────────────

  /// 申请设备码：返回用户应访问的授权页 URL 与轮询所需的 device_code。
  static Future<FrpBrowserLoginSession> createDeviceLogin() async {
    final resp = await http
        .post(
          Uri.parse('$_oauthIssuer/oauth2/device_authorization'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'client_id': _clientId,
            'scope': _scope,
          },
        )
        .timeout(_timeout);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    // device_authorization 失败时返回 {error, error_description}，无 code 字段。
    if (json.containsKey('error')) {
      throw FrpApiException(
        json['error_description'] as String? ?? json['error'] as String? ?? '设备码申请失败',
      );
    }
    final deviceCode = json['device_code'] as String? ?? '';
    final userCode = json['user_code'] as String? ?? '';
    // verification_uri_complete 自动带入 user_code，优先用；否则用 verification_uri。
    final url = (json['verification_uri_complete'] as String?) ??
        (json['verification_uri'] as String? ?? '');
    final interval = (json['interval'] as int?) ?? 5;
    final expiresIn = (json['expires_in'] as int?) ?? 300;
    if (deviceCode.isEmpty || url.isEmpty) {
      throw const FrpApiException('设备码响应缺少 device_code 或 verification_uri');
    }
    return FrpBrowserLoginSession(
      url: url,
      userCode: userCode,
      state: {
        'device_code': deviceCode,
        'interval': interval,
        'expires_at': DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
      },
    );
  }

  /// 轮询设备码授权结果：
  /// - 未完成（authorization_pending / slow_down）返回 null；
  /// - 成功返回可存入 FrpTokenStore 的 JSON token 字符串；
  /// - 致命错误（expired_token / access_denied / 其他）抛 FrpApiException。
  static Future<String?> pollDeviceLogin(FrpBrowserLoginSession session) async {
    final deviceCode = session.state['device_code'] as String;

    // device_code 过期则直接失败，不再轮询。
    final expiresAt = session.state['expires_at'] as int;
    if (DateTime.now().millisecondsSinceEpoch >= expiresAt) {
      throw const FrpApiException('设备码已过期，请重新发起登录');
    }

    final resp = await http
        .post(
          Uri.parse('$_oauthIssuer/oauth2/token'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': _clientId,
            'device_code': deviceCode,
          },
        )
        .timeout(_timeout);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final error = json['error'] as String?;
    if (error != null) {
      // authorization_pending / slow_down：继续轮询。
      if (error == 'authorization_pending' || error == 'slow_down') {
        // slow_down 时服务端要求放慢，这里返回 null 让上层按 interval 等待；
        // 上层固定 5s 间隔，与 QZhua 默认 interval 一致，足够保守。
        return null;
      }
      // expired_token / access_denied / invalid_grant 等：致命，停止轮询。
      throw FrpApiException(
        json['error_description'] as String? ?? error,
      );
    }
    final accessToken = json['access_token'] as String?;
    final refreshToken = json['refresh_token'] as String?;
    final expiresIn = json['expires_in'] as int?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const FrpApiException('token 响应缺少 access_token');
    }
    return _encodeToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
    );
  }

  /// 用 refresh_token 刷新 access_token；返回新的 JSON token 字符串。
  /// 失败（refresh_token 过期等）抛 FrpApiException。
  static Future<String> refreshChmlToken(String encodedToken) async {
    final parsed = _decodeToken(encodedToken);
    final refreshToken = parsed['rt'] as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const FrpApiException('无 refresh_token，请重新登录');
    }
    final resp = await http
        .post(
          Uri.parse('$_oauthIssuer/oauth2/token'),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'grant_type': 'refresh_token',
            'client_id': _clientId,
            'refresh_token': refreshToken,
          },
        )
        .timeout(_timeout);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw FrpApiException(
        json['error_description'] as String? ?? json['error'] as String? ?? '刷新 token 失败',
      );
    }
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const FrpApiException('刷新响应缺少 access_token');
    }
    final newToken = _encodeToken(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String? ?? refreshToken,
      expiresIn: json['expires_in'] as int?,
    );
    // 持久化刷新后的 token，避免下次启动用旧 refresh_token。
    await FrpTokenStore.saveToken(FrpProvider.chmlFrp, newToken);
    return newToken;
  }

  /// 解析存入 FrpTokenStore 的 JSON token，返回有效的 access_token。
  /// 即将过期（< 60s）则自动刷新并持久化；刷新失败抛异常由上层引导重新登录。
  static Future<String> _resolveAccessToken(String encodedToken) async {
    final parsed = _decodeToken(encodedToken);
    final accessToken = parsed['at'] as String? ?? '';
    final exp = parsed['exp'] as int?;
    // 无过期时间或未即将过期：直接用。
    if (exp == null ||
        DateTime.now().millisecondsSinceEpoch + _refreshSkew.inMilliseconds < exp) {
      return accessToken;
    }
    // 即将过期：刷新。刷新后返回新 access_token。
    final newToken = await refreshChmlToken(encodedToken);
    return _decodeToken(newToken)['at'] as String;
  }

  /// 编码 token JSON：`{at, rt, exp}`，exp 为到期毫秒时间戳。
  static String _encodeToken({
    required String accessToken,
    String? refreshToken,
    int? expiresIn,
  }) {
    final exp = expiresIn != null
        ? DateTime.now().millisecondsSinceEpoch + expiresIn * 1000
        : null;
    return jsonEncode({
      'at': accessToken,
      if (refreshToken != null && refreshToken.isNotEmpty) 'rt': refreshToken,
      // ignore: use_null_aware_elements
      if (exp != null) 'exp': exp,
    });
  }

  static Map<String, dynamic> _decodeToken(String encoded) {
    try {
      return jsonDecode(encoded) as Map<String, dynamic>;
    } catch (_) {
      // 兼容旧的纯 usertoken（未走 OAuth）：当作无刷新能力的 access_token。
      return {'at': encoded};
    }
  }

  // ── ChmlFrp 业务接口（Bearer 鉴权） ────────────────────────────

  static Future<Map<String, dynamic>> _get(
    String pathWithQuery,
    String encodedToken,
  ) async {
    final accessToken = await _resolveAccessToken(encodedToken);
    final resp = await http
        .get(
          Uri.parse('$_base$pathWithQuery'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        )
        .timeout(_timeout);
    return _envelope(resp);
  }

  static Map<String, dynamic> _envelope(http.Response resp) {
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final state = json['state'] as String?;
    final code = json['code'] as int?;
    final ok = state == 'success' || code == 200;
    if (!ok) {
      throw FrpApiException(json['msg'] as String? ?? 'HTTP ${resp.statusCode}');
    }
    return json;
  }

  /// 验证 token 并获取用户信息（含 frpc usertoken）。
  static Future<FrpAccount> userInfo(String encodedToken) async {
    final json = await _get('/userinfo', encodedToken);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    return FrpAccount(
      username: data['username'] as String? ?? '',
      group: data['usergroup'] as String? ?? '',
      usedTunnels: data['tunnel'] as int?,
      maxTunnels: data['tunnnelCount'] as int? ?? data['tunnelCount'] as int?,
      frpToken: data['usertoken'] as String?,
    );
  }

  /// 我的隧道列表。dorp 为远程端口（数字）或域名（http/https）。
  static Future<List<FrpRemoteTunnel>> tunnelList(String encodedToken) async {
    final json = await _get('/tunnel', encodedToken);
    final list = json['data'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      final dorp = '${m['dorp'] ?? ''}';
      final remotePort = int.tryParse(dorp);
      return FrpRemoteTunnel(
        id: '${m['id']}',
        name: m['name'] as String? ?? '',
        nodeName: m['node'] as String? ?? '',
        type: m['type'] as String? ?? 'tcp',
        localIp: m['localip'] as String? ?? '127.0.0.1',
        localPort: (m['nport'] as int?) ?? 25565,
        remotePort: remotePort,
        remoteAddress:
            remotePort != null ? '${m['ip'] ?? ''}:$remotePort' : dorp,
      );
    }).toList();
  }

  /// 节点列表（无需鉴权）。
  static Future<List<FrpNode>> nodeList() async {
    final resp = await http.get(Uri.parse('$_base/node')).timeout(_timeout);
    final json = _envelope(resp);
    final list = json['data'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      final group = m['nodegroup'] as String? ?? '';
      return FrpNode(
        id: m['name'] as String? ?? '',
        name: m['name'] as String? ?? '',
        description: '${m['area'] ?? ''} ${m['notes'] ?? ''}'.trim(),
        vip: group == 'vip',
      );
    }).toList();
  }

  /// 创建隧道。
  static Future<void> createTunnel(
    String encodedToken, {
    required String node,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
  }) async {
    final accessToken = await _resolveAccessToken(encodedToken);
    final resp = await http
        .post(
          Uri.parse('$_base/create_tunnel'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'tunnelname': name,
            'node': node,
            'porttype': type,
            'localip': localIp,
            'localport': localPort,
            'encryption': false,
            'compression': false,
            'extraparams': '',
            'remoteport': remotePort,
          }),
        )
        .timeout(_timeout);
    _envelope(resp);
  }

  /// 删除隧道。
  static Future<void> deleteTunnel(String encodedToken, String tunnelId) async {
    await _get('/delete_tunnel?tunnelId=$tunnelId', encodedToken);
  }

  /// 获取隧道的成品 frpc 配置（ini 文本，可直接运行——上游 frpc 兼容 ini）。
  static Future<String> tunnelConfig(
    String encodedToken, {
    required String node,
    required String tunnelName,
  }) async {
    final json = await _get(
      '/tunnel_config?node=${Uri.encodeComponent(node)}'
      '&tunnelName=${Uri.encodeComponent(tunnelName)}',
      encodedToken,
    );
    final config = json['data'] as String? ?? '';
    if (config.isEmpty) throw const FrpApiException('配置内容为空');
    return config;
  }
}
