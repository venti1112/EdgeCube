import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../online/cloud_headers.dart';
import 'frp_models.dart';

/// MSL Frp（user.mslmc.net）API 客户端。
///
/// 响应包络 `{code, data, msg}`，code == 200 为成功（HTTP 恒为 200）；
/// 鉴权为 `Authorization: Bearer <token>`。
///
/// 登录：官方已下线密码登录（POST /user/login 传 {email,password} 返回
/// `缺少参数!`），现改用浏览器授权登录（OAuth，见 createAppLogin/pollAppLogin）。
class MslFrpApi {
  MslFrpApi._();

  static const String _base = 'https://user.mslmc.net/api';
  static const Duration _timeout = Duration(seconds: 15);

  /// OAuth 应用标识。
  static const String _appId = '3JAza1AwWgOQeBj2C2j7OODOPOv';

  static Future<Map<String, String>> _headers(String? token) async => {
    'Content-Type': 'application/json',
    'User-Agent': await CloudHeaders.userAgent,
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// 本地生成 32 位十六进制 csrf（授权与轮询需前后一致）。
  static String _randomCsrf() {
    final rand = Random.secure();
    return List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  static Future<Map<String, dynamic>> _get(String path, String token) async {
    final resp = await http
        .get(Uri.parse('$_base$path'), headers: await _headers(token))
        .timeout(_timeout);
    return _envelope(resp);
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$_base$path'),
          headers: await _headers(token),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _envelope(resp);
  }

  /// 解析包络：code != 200 抛 [FrpApiException]。
  static Map<String, dynamic> _envelope(http.Response resp) {
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final code = json['code'] as int? ?? -1;
    if (code != 200) {
      throw FrpApiException(
        json['msg'] as String? ?? 'HTTP ${resp.statusCode}',
      );
    }
    return json;
  }

  /// 发起浏览器授权登录：向 /oauth/createAppLogin 提交 csrf+appid，
  /// 返回授权页 URL 与轮询所需的会话状态（ssid + csrf）。
  static Future<FrpBrowserLoginSession> createAppLogin() async {
    final csrf = _randomCsrf();
    final resp = await http
        .post(
          Uri.parse('$_base/oauth/createAppLogin'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': await CloudHeaders.userAgent,
          },
          body: {'csrf': csrf, 'appid': _appId},
        )
        .timeout(_timeout);
    final json = _envelope(resp);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final url = data['url'] as String? ?? '';
    final ssid = data['ssid'] as String? ?? '';
    if (url.isEmpty || ssid.isEmpty) {
      throw const FrpApiException('授权会话创建失败');
    }
    return FrpBrowserLoginSession(
      url: url,
      state: {'ssid': ssid, 'csrf': csrf},
    );
  }

  /// 轮询浏览器授权结果：未完成返回 null；完成返回（续期后的）登录 token。
  static Future<String?> pollAppLogin(FrpBrowserLoginSession session) async {
    final ssid = session.state['ssid'] as String;
    final csrf = session.state['csrf'] as String;
    final resp = await http
        .get(
          Uri.parse('$_base/oauth/appLogin?ssid=$ssid&csrf=$csrf'),
          headers: {'User-Agent': await CloudHeaders.userAgent},
        )
        .timeout(_timeout);
    final json = _envelope(resp);
    final data = json['data'];
    final token = data is Map
        ? data['token'] as String?
        : (data is String ? data : null);
    if (token == null || token.isEmpty) return null;
    // 授权完成，顺带续期以延长有效期（失败则回退原 token）。
    return await renewToken(token) ?? token;
  }

  /// 续期 token（best-effort）；返回新 token，失败或无返回则 null。
  static Future<String?> renewToken(String token) async {
    try {
      final json = await _post('/user/renewToken', const {}, token: token);
      final data = json['data'];
      final t = data is Map
          ? data['token'] as String?
          : (data is String ? data : null);
      return (t != null && t.isNotEmpty) ? t : null;
    } catch (_) {
      return null;
    }
  }

  /// 验证 token 并获取用户信息。
  static Future<FrpAccount> userInfo(String token) async {
    final json = await _get('/frp/userInfo', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    return FrpAccount(
      username: data['name'] as String? ?? '',
      group: data['user_group_name'] as String? ?? '',
      maxTunnels: data['maxTunnelCount'] as int?,
    );
  }

  /// 节点列表。
  static Future<List<FrpNode>> nodeList(String token) async {
    final json = await _get('/frp/nodeList', token);
    final list = json['data'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      return FrpNode(
        id: '${m['id']}',
        name: m['node'] as String? ?? '',
        hostname: m['ip'] as String? ?? '',
        minPort: m['min_open_port'] as int?,
        maxPort: m['max_open_port'] as int?,
        description: m['remarks'] as String? ?? '',
        online: (m['status'] as int? ?? 1) != 0,
        vip: (m['allow_user_group'] as int? ?? 0) > 0,
        udpSupport: (m['udp_support'] as int? ?? 1) != 0,
      );
    }).toList();
  }

  /// 我的隧道列表。
  static Future<List<FrpRemoteTunnel>> tunnelList(String token) async {
    final json = await _get('/frp/getTunnelList', token);
    final list = json['data'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      return FrpRemoteTunnel(
        id: '${m['id']}',
        name: m['name'] as String? ?? '',
        nodeId: '${m['node_id']}',
        localIp: m['local_ip'] as String? ?? '127.0.0.1',
        localPort: (m['local_port'] as int?) ?? 25565,
        remotePort: m['remote_port'] as int?,
        online: frpParseBool(m['status']),
      );
    }).toList();
  }

  /// 创建隧道。
  static Future<void> addTunnel(
    String token, {
    required int nodeId,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
    String? bindDomain,
  }) async {
    await _post('/frp/addTunnel', {
      'id': nodeId,
      'name': name,
      'type': type,
      'remarks': 'Create By EdgeCube',
      'local_ip': localIp,
      'local_port': localPort,
      'remote_port': remotePort,
      'use_kcp': false,
      if (bindDomain != null && bindDomain.isNotEmpty)
        'bind_domain': bindDomain,
    }, token: token);
  }

  /// 删除隧道。
  static Future<void> deleteTunnel(String token, String tunnelId) async {
    await _post('/frp/deleteTunnel', {
      'id': int.tryParse(tunnelId) ?? tunnelId,
    }, token: token);
  }

  /// 重置 Frp 系统用户 Token。
  static Future<void> resetToken(String token) async {
    await _get('/frp/resetToken', token);
  }

  /// 获取隧道的成品 frpc 配置（TOML 文本，可直接运行）。
  static Future<String> tunnelConfig(
    String token,
    String tunnelId, {
    String? userToken,
  }) async {
    final params = StringBuffer(
      '/frp/getTunnelConfig?id=$tunnelId&format=toml',
    );
    if (userToken != null && userToken.isNotEmpty) {
      params.write('&userToken=$userToken');
    }
    final json = await _get(params.toString(), token);
    final config = json['data'] as String? ?? '';
    if (config.isEmpty) throw const FrpApiException('配置内容为空');
    return config;
  }
}
