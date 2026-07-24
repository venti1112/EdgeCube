import 'dart:convert';

import 'package:http/http.dart' as http;

import 'frp_models.dart';

/// ChmlFrp（cf-v2.uapis.cn）API 客户端。
///
/// 鉴权用 access_token 查询参数；响应含 `state: "success"/"fail"` 与
/// `code`/`msg`。`userinfo` 返回的 `usertoken` 是 frpc 鉴权 token。
/// `tunnel_config` 直接返回成品 frpc ini 配置文本。
class ChmlFrpApi {
  ChmlFrpApi._();

  static const String _base = 'https://cf-v2.uapis.cn';
  static const Duration _timeout = Duration(seconds: 15);

  static Future<Map<String, dynamic>> _get(String pathWithQuery) async {
    final resp =
        await http.get(Uri.parse('$_base$pathWithQuery')).timeout(_timeout);
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

  /// 验证 access_token 并获取用户信息（含 frpc usertoken）。
  static Future<FrpAccount> userInfo(String accessToken) async {
    final json = await _get('/userinfo?access_token=$accessToken');
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
  static Future<List<FrpRemoteTunnel>> tunnelList(String accessToken) async {
    final json = await _get('/tunnel?access_token=$accessToken');
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
    final json = await _get('/node');
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
    String accessToken, {
    required String node,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$_base/create_tunnel'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': accessToken,
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
  static Future<void> deleteTunnel(String accessToken, String tunnelId) async {
    await _get('/delete_tunnel?tunnelId=$tunnelId&token=$accessToken');
  }

  /// 获取隧道的成品 frpc 配置（ini 文本，可直接运行——上游 frpc 兼容 ini）。
  static Future<String> tunnelConfig(
    String accessToken, {
    required String node,
    required String tunnelName,
  }) async {
    final json = await _get(
      '/tunnel_config?node=${Uri.encodeComponent(node)}'
      '&tunnelName=${Uri.encodeComponent(tunnelName)}&token=$accessToken',
    );
    final config = json['data'] as String? ?? '';
    if (config.isEmpty) throw const FrpApiException('配置内容为空');
    return config;
  }
}
