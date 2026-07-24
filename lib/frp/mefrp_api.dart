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

  /// 我的隧道列表（同时返回节点信息，用于拼远程连接地址）。
  static Future<List<FrpRemoteTunnel>> proxyList(String token) async {
    final json = await _get('/auth/proxy/list', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    // nodes 同时含 name（显示名）与 hostname（连接地址），均按 nodeId 索引。
    final nodes = <String, Map<String, String>>{
      for (final n in (data['nodes'] as List? ?? []).whereType<Map>())
        '${n['nodeId']}': {
          'name': n['name'] as String? ?? '',
          'hostname': n['hostname'] as String? ?? '',
        },
    };
    final list = data['proxies'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      final nodeId = '${m['nodeId']}';
      final node = nodes[nodeId];
      final hostname = node?['hostname'] ?? '';
      final type = m['proxyType'] as String? ?? 'tcp';
      final remotePort = m['remotePort'] as int?;
      final domain = m['domain'] as String? ?? '';
      // tcp/udp: hostname:remotePort；http/https: 自定义 domain（可能为空）。
      final remoteAddress = (type == 'http' || type == 'https')
          ? domain
          : (hostname.isNotEmpty && remotePort != null
              ? '$hostname:$remotePort'
              : '');
      return FrpRemoteTunnel(
        id: '${m['proxyId']}',
        name: m['proxyName'] as String? ?? '',
        nodeId: nodeId,
        nodeName: node?['name'] ?? '',
        type: type,
        localIp: m['localIp'] as String? ?? '127.0.0.1',
        localPort: (m['localPort'] as int?) ?? 25565,
        remotePort: remotePort,
        remoteAddress: remoteAddress,
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

  /// 获取隧道的成品 frpc 配置（TOML 文本，可直接运行）。
  ///
  /// ME Frp 官方前端启动隧道即调用此接口，返回的 TOML 已含 serverAddr /
  /// serverPort / user / auth.token / remotePort 等全部启动所需信息，
  /// 无需再单独调 /auth/node/list 取节点地址。
  static Future<String> tunnelConfig(String token, String proxyId) async {
    final json = await _post('/auth/proxy/config', {
      'proxyId': int.tryParse(proxyId) ?? proxyId,
      'format': 'toml',
    }, token: token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final config = data['config'] as String? ?? '';
    if (config.isEmpty) throw const FrpApiException('配置内容为空');
    return config;
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
