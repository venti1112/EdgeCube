import 'dart:convert';

import 'package:http/http.dart' as http;

import 'frp_models.dart';

/// SakuraFrp（api.natfrp.com/v4）API 客户端。
///
/// GET 用 token 查询参数，POST 用 `Authorization: Bearer`。隧道列表直接
/// 返回数组（无包络）；创建成功为 HTTP 201。
///
/// 注意：SakuraFrp 官方客户端为闭源魔改 frpc；EdgeCube 用标准配置运行，
/// 兼容性标记为实验性（见 FrpProvider.experimental）。
class SakuraFrpApi {
  SakuraFrpApi._();

  static const String _base = 'https://api.natfrp.com/v4';
  static const Duration _timeout = Duration(seconds: 15);

  static dynamic _decode(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String message = 'HTTP ${resp.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        if (body is Map && body['msg'] is String) message = body['msg'] as String;
      } catch (_) {}
      throw FrpApiException(message);
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static Future<dynamic> _get(String pathWithQuery) async {
    final resp =
        await http.get(Uri.parse('$_base$pathWithQuery')).timeout(_timeout);
    return _decode(resp);
  }

  static Future<dynamic> _post(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final resp = await http
        .post(
          Uri.parse('$_base$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(resp);
  }

  /// 验证 token 并获取用户信息。
  static Future<FrpAccount> userInfo(String token) async {
    final json = (await _get('/user/info?token=$token')) as Map<String, dynamic>;
    final group = (json['group'] as Map?)?.cast<String, dynamic>() ?? {};
    return FrpAccount(
      username: json['name'] as String? ?? '',
      group: group['name'] as String? ?? '',
    );
  }

  /// 用户等级（过滤 vip 节点用）。
  static Future<int> userLevel(String token) async {
    final json = (await _get('/user/info?token=$token')) as Map<String, dynamic>;
    final group = (json['group'] as Map?)?.cast<String, dynamic>() ?? {};
    return group['level'] as int? ?? 0;
  }

  /// 我的隧道列表（API 直接返回数组）。
  static Future<List<FrpRemoteTunnel>> tunnelList(String token) async {
    final json = await _get('/tunnels?token=$token');
    final list = json is List ? json : <dynamic>[];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      final remote = '${m['remote'] ?? ''}';
      return FrpRemoteTunnel(
        id: '${m['id']}',
        name: m['name'] as String? ?? '',
        nodeId: '${m['node']}',
        type: m['type'] as String? ?? 'tcp',
        localIp: m['local_ip'] as String? ?? '127.0.0.1',
        localPort: (m['local_port'] as int?) ?? 25565,
        remotePort: int.tryParse(remote),
        remoteAddress: remote.contains(':') ? remote : '',
        online: frpParseBool(m['online']),
      );
    }).toList();
  }

  /// 节点列表（API 返回以节点 id 为 key 的对象）。
  static Future<List<FrpNode>> nodeList(String token, {int userLevel = 0}) async {
    final json = await _get('/nodes?token=$token');
    if (json is! Map) return [];
    final nodes = <FrpNode>[];
    json.cast<String, dynamic>().forEach((id, raw) {
      if (raw is! Map) return;
      final m = raw.cast<String, dynamic>();
      final vip = m['vip'] as int? ?? 0;
      if (vip > userLevel) return; // 等级不足的节点不展示
      nodes.add(FrpNode(
        id: id,
        name: m['name'] as String? ?? '',
        hostname: m['host'] as String? ?? '',
        description: m['description'] as String? ?? '',
        vip: vip > 0,
      ));
    });
    return nodes;
  }

  /// 创建隧道（成功为 HTTP 201，_decode 已按 2xx 放行）。
  static Future<void> createTunnel(
    String token, {
    required int node,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
  }) async {
    await _post('/tunnels', token, {
      'node': node,
      'name': name,
      'type': type,
      'note': 'Create By EdgeCube',
      'extra': '',
      'local_ip': localIp,
      'local_port': localPort,
      'remote': remotePort,
    });
  }

  /// 删除隧道。
  static Future<void> deleteTunnel(String token, String tunnelId) async {
    await _post('/tunnel/delete', token, {
      'ids': int.tryParse(tunnelId) ?? tunnelId,
    });
  }
}
