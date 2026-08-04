import 'dart:convert';

import 'package:http/http.dart' as http;

import 'frp_models.dart';

/// SakuraFrp（api.natfrp.com/v4）API 客户端。
///
/// 认证遵循 v4 API 定义：GET 用 `token` 查询参数（UserTokenPost），
/// POST 用 `Authorization: Bearer`（UserToken）。隧道列表直接返回数组
/// （无包络）；创建成功为 HTTP 201；204 响应无正文。
///
class SakuraFrpApi {
  SakuraFrpApi._();

  static const String _base = 'https://api.natfrp.com/v4';
  static const Duration _timeout = Duration(seconds: 15);

  /// 本应用自带的上游原版 frpc 版本（/tunnel/config 需声明目标版本）。
  static const String _frpcVersion = '0.69.1';

  static dynamic _decode(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String message = 'HTTP ${resp.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        if (body is Map && body['msg'] is String) {
          message = body['msg'] as String;
        }
      } catch (_) {}
      throw FrpApiException(message);
    }
    if (resp.bodyBytes.isEmpty) return null; // 204 等无正文响应
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  static Future<dynamic> _get(String pathWithQuery) async {
    final resp = await http
        .get(Uri.parse('$_base$pathWithQuery'))
        .timeout(_timeout);
    return _decode(resp);
  }

  static Future<dynamic> _post(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    return _decode(await _postRaw(path, token, body));
  }

  static Future<http.Response> _postRaw(
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
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String message = 'HTTP ${resp.statusCode}';
      try {
        final err = jsonDecode(utf8.decode(resp.bodyBytes));
        if (err is Map && err['msg'] is String) {
          message = err['msg'] as String;
        }
      } catch (_) {}
      throw FrpApiException(message);
    }
    return resp;
  }

  /// 获取隧道配置文件（`POST /tunnel/config`，响应为 text/plain 或
  /// text/toml，非 JSON）。
  ///
  /// `query` 为启动目标列表：隧道 ID（如 `114514`）或 `n` 前缀的节点 ID
  /// （如 `n233`），多个用逗号分隔。`frpc` 为目标 frpc 版本，支持
  /// SakuraFrp 分发版（如 `0.51.0-sakura-7.2`）与上游原版（最低 0.18.0）。
  static Future<String> tunnelConfig(String token, String query) async {
    final resp = await _postRaw('/tunnel/config', token, {
      'query': query,
      'frpc': _frpcVersion,
    });
    return utf8.decode(resp.bodyBytes);
  }

  /// 验证 token 并获取用户信息。
  static Future<FrpAccount> userInfo(String token) async {
    final json =
        (await _get('/user/info?token=$token')) as Map<String, dynamic>;
    final group = (json['group'] as Map?)?.cast<String, dynamic>() ?? {};
    return FrpAccount(
      username: json['name'] as String? ?? '',
      group: group['name'] as String? ?? '',
      maxTunnels: json['tunnels'] as int?,
    );
  }

  /// 用户等级（过滤 vip 节点用）。
  static Future<int> userLevel(String token) async {
    final json =
        (await _get('/user/info?token=$token')) as Map<String, dynamic>;
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
  ///
  /// `flag` 为位标记：`1 << 5` 允许 UDP 流量，`1 << 9` 节点离线。
  static Future<List<FrpNode>> nodeList(
    String token, {
    int userLevel = 0,
  }) async {
    const int flagUdp = 1 << 5;
    const int flagOffline = 1 << 9;
    final json = await _get('/nodes?token=$token');
    if (json is! Map) return [];
    final nodes = <FrpNode>[];
    json.cast<String, dynamic>().forEach((id, raw) {
      if (raw is! Map) return;
      final m = raw.cast<String, dynamic>();
      final vip = m['vip'] as int? ?? 0;
      if (vip > userLevel) return; // 等级不足的节点不展示
      final flag = m['flag'] as int? ?? 0;
      nodes.add(
        FrpNode(
          id: id,
          name: m['name'] as String? ?? '',
          hostname: m['host'] as String? ?? '',
          description: m['description'] as String? ?? '',
          online: (flag & flagOffline) == 0,
          vip: vip > 0,
          udpSupport: (flag & flagUdp) != 0,
        ),
      );
    });
    return nodes;
  }

  /// 创建隧道（成功为 HTTP 201，_decode 已按 2xx 放行）。
  ///
  /// `remote` 按 v4 定义传字符串（端口或绑定域名），http/https 类型必填，
  /// tcp 等类型留空由服务端分配。
  static Future<void> createTunnel(
    String token, {
    required int node,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    int? remotePort,
  }) async {
    await _post('/tunnels', token, {
      'node': node,
      'name': name,
      'type': type,
      'note': 'Create By EdgeCube',
      'local_ip': localIp,
      'local_port': localPort,
      if (remotePort != null) 'remote': '$remotePort',
    });
  }

  /// 删除隧道（`ids` 为逗号分隔的隧道 ID 字符串，最多 10 条）。
  static Future<void> deleteTunnel(String token, String tunnelId) async {
    await _post('/tunnel/delete', token, {'ids': tunnelId});
  }
}
