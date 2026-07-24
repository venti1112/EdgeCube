import 'dart:convert';

import 'package:http/http.dart' as http;

import 'frp_models.dart';

/// ME Frp（api.mefrp.com）API 客户端。
///
/// 鉴权 `Authorization: Bearer <token>`；包络 `{code, message, data}`，
/// code == 200 为成功。`/auth/user/frpToken` 返回 frpc 鉴权 token。
///
/// 注意：ME Frp 官方客户端为闭源魔改 frpc；EdgeCube 用标准配置运行，
/// 兼容性标记为实验性（见 FrpProvider.experimental）。
class MeFrpApi {
  MeFrpApi._();

  static const String _base = 'https://api.mefrp.com/api';
  static const Duration _timeout = Duration(seconds: 15);

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  static Future<Map<String, dynamic>> _get(String path, String token) async {
    final resp = await http
        .get(Uri.parse('$_base$path'), headers: _headers(token))
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
          headers: _headers(token),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _envelope(resp);
  }

  static Map<String, dynamic> _envelope(http.Response resp) {
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final code = json['code'] as int? ?? resp.statusCode;
    if (code != 200) {
      throw FrpApiException(
        json['message'] as String? ?? 'HTTP ${resp.statusCode}',
      );
    }
    return json;
  }

  /// 用户名 + 密码登录，返回登录 token。
  ///
  /// MSL 中该接口带 vaptcha 人机验证参数（需浏览器辅助获取）；此处直接
  /// 尝试无验证登录，服务端要求验证时会返回错误信息，UI 引导改用 token 粘贴。
  static Future<String> login(String username, String password) async {
    final json = await _post('/public/login', {
      'username': username,
      'password': password,
    });
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final token = data['token'] as String? ?? '';
    if (token.isEmpty) throw const FrpApiException('登录响应缺少 token');
    return token;
  }

  /// 验证 token 并获取用户信息。
  static Future<FrpAccount> userInfo(String token) async {
    final json = await _get('/auth/user/info', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    return FrpAccount(
      username: data['username'] as String? ?? '',
      group: data['friendlyGroup'] as String? ?? '',
      usedTunnels: data['usedProxies'] as int?,
      maxTunnels: data['maxProxies'] as int?,
    );
  }

  /// frpc 鉴权 token（拼配置用）。
  static Future<String> frpToken(String token) async {
    final json = await _get('/auth/user/frpToken', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final t = data['token'] as String? ?? '';
    if (t.isEmpty) throw const FrpApiException('frpToken 为空');
    return t;
  }

  /// 我的隧道列表。
  static Future<List<FrpRemoteTunnel>> proxyList(String token) async {
    final json = await _get('/auth/proxy/list', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final nodes = <String, String>{
      for (final n in (data['nodes'] as List? ?? []).whereType<Map>())
        '${n['nodeId']}': n['name'] as String? ?? '',
    };
    final list = data['proxies'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      final nodeId = '${m['nodeId']}';
      return FrpRemoteTunnel(
        id: '${m['proxyId']}',
        name: m['proxyName'] as String? ?? '',
        nodeId: nodeId,
        nodeName: nodes[nodeId] ?? '',
        type: m['proxyType'] as String? ?? 'tcp',
        localIp: m['localIp'] as String? ?? '127.0.0.1',
        localPort: (m['localPort'] as int?) ?? 25565,
        remotePort: m['remotePort'] as int?,
        online: frpParseBool(m['isOnline']),
      );
    }).toList();
  }

  /// 节点列表。
  static Future<List<FrpNode>> nodeList(String token) async {
    final json = await _get('/auth/node/list', token);
    final list = json['data'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      return FrpNode(
        id: '${m['nodeId']}',
        name: m['name'] as String? ?? '',
        hostname: m['hostname'] as String? ?? '',
        description: m['description'] as String? ?? '',
      );
    }).toList();
  }

  /// 创建隧道。
  static Future<void> createProxy(
    String token, {
    required int nodeId,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
  }) async {
    await _post('/auth/proxy/create', {
      'accessKey': '',
      'headerXFromWhere': '',
      'hostHeaderRewrite': '',
      'proxyProtocolVersion': '',
      'nodeId': nodeId,
      'proxyName': name,
      'proxyType': type,
      'localIp': localIp,
      'localPort': localPort,
      'remotePort': remotePort,
      'domain': '',
      'useCompression': false,
      'useEncryption': false,
    }, token: token);
  }

  /// 删除隧道。
  static Future<void> deleteProxy(String token, String proxyId) async {
    await _post('/auth/proxy/delete', {
      'proxyId': int.tryParse(proxyId) ?? proxyId,
    }, token: token);
  }
}
