import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart';

import 'frp_models.dart';

/// OpenFrp（api.openfrp.net）API 客户端。
///
/// 登录走远程安全登录（Remote Login）：curve25519 密钥对 + 浏览器授权 +
/// NaCl Box 解密出 Authorization（见 access.openfrp.net/argoAccess）。
/// 原 Authorization 粘贴登录方式已被官方移除。
///
/// 业务接口鉴权为 `Authorization: <token>`（无 Bearer 前缀）；响应包络
/// `{flag: bool, data, msg}`。getUserInfo 返回的 `data.token` 是 frpc 用户
/// token（拼配置用），与登录 Authorization 不同。
class OpenFrpApi {
  OpenFrpApi._();

  static const String _base = 'https://api.openfrp.net';
  static const String _accessBase = 'https://access.openfrp.net';
  static const Duration _timeout = Duration(seconds: 15);

  /// OpenFrp 要求请求携带应用程序 UA，否则可能被防火墙拦截。
  static const String _userAgent = 'EdgeCube';

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        'User-Agent': _userAgent,
        if (token != null && token.isNotEmpty) 'Authorization': token,
      };

  static Future<Map<String, dynamic>> _post(String path, String token) async {
    final resp = await http.post(
      Uri.parse('$_base$path'),
      headers: _headers(token),
      body: '{}',
    ).timeout(_timeout);
    return _envelope(resp);
  }

  static Future<Map<String, dynamic>> _postBody(
    String path,
    String token,
    Map<String, dynamic> body,
  ) async {
    final resp = await http.post(
      Uri.parse('$_base$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _envelope(resp);
  }

  static Map<String, dynamic> _envelope(http.Response resp) {
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (json['flag'] != true) {
      throw FrpApiException(json['msg'] as String? ?? 'HTTP ${resp.statusCode}');
    }
    return json;
  }

  /// argoAccess 包络：`{code, msg, data}`，code == 200 为成功（code 复用
  /// HTTP 状态码：200 成功 / 204 未授权 / 400 参数错误 / 404 授权不存在）。
  static Map<String, dynamic> _accessEnvelope(http.Response resp) {
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final code = json['code'] as int? ?? -1;
    if (code != 200) {
      throw FrpApiException(json['msg'] as String? ?? 'HTTP ${resp.statusCode}');
    }
    return json;
  }

  /// 宽松 base64 解码：兼容标准与 URL-safe、自动补齐 padding。
  static Uint8List _b64Decode(String s) {
    final normalized = s.replaceAll('-', '+').replaceAll('_', '/');
    final pad = normalized.length % 4;
    final padded = pad == 0 ? normalized : normalized + '=' * (4 - pad);
    return base64.decode(padded);
  }

  // ── 远程安全登录（Remote Login） ───────────────────────────────

  /// 发起远程安全登录：生成 curve25519 密钥对，提交公钥换取授权页 URL。
  static Future<FrpBrowserLoginSession> createBrowserLogin() async {
    final sk = PrivateKey.generate();
    final pk = sk.publicKey;
    final publicKey = base64Url.encode(Uint8List.fromList(pk));

    final resp = await http
        .post(
          Uri.parse('$_accessBase/argoAccess/requestLogin'),
          headers: _headers(null),
          body: jsonEncode({'public_key': publicKey}),
        )
        .timeout(_timeout);
    final json = _accessEnvelope(resp);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final url = data['authorization_url'] as String? ?? '';
    final uuid = data['request_uuid'] as String? ?? '';
    if (url.isEmpty || uuid.isEmpty) {
      throw const FrpApiException('授权会话创建失败');
    }
    return FrpBrowserLoginSession(
      url: url,
      state: {
        'request_uuid': uuid,
        // curve25519 私钥（32 字节），轮询时用于解密 authorization_data。
        'private_key': Uint8List.fromList(sk),
      },
    );
  }

  /// 轮询远程安全登录结果：未完成返回 null；完成返回解密后的 Authorization。
  ///
  /// pollLogin 文档标注为 GET 且携带 JSON body（request_uuid），此处按文档
  /// 以 GET + body 发送。响应 header `x-request-public-key` 为服务端公钥
  /// （URL-safe base64），body `data.authorization_data` 为 NaCl Box 密文
  /// （标准 base64，格式 = nonce(24) + ciphertext）。
  static Future<String?> pollBrowserLogin(FrpBrowserLoginSession session) async {
    final uuid = session.state['request_uuid'] as String;
    final skBytes = session.state['private_key'] as Uint8List;

    final request =
        http.Request('GET', Uri.parse('$_accessBase/argoAccess/pollLogin'));
    request.headers['Content-Type'] = 'application/json';
    request.headers['User-Agent'] = _userAgent;
    request.body = jsonEncode({'request_uuid': uuid});
    final streamed = await request.send().timeout(_timeout);
    final resp = await http.Response.fromStream(streamed);

    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final code = json['code'] as int? ?? -1;
    // 非 200（204 未授权 / 429 限流等）视为未完成，继续轮询。
    if (code != 200) return null;

    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final authData = data['authorization_data'] as String?;
    if (authData == null || authData.isEmpty) return null;

    final serverPkB64 = resp.headers['x-request-public-key'];
    if (serverPkB64 == null || serverPkB64.isEmpty) return null;

    // 解密：authorization_data = nonce(24) + NaCl Box 密文。
    final combined = _b64Decode(authData);
    final sk = PrivateKey(Uint8List.fromList(skBytes));
    final serverPk = PublicKey(_b64Decode(serverPkB64));
    final box = Box(myPrivateKey: sk, theirPublicKey: serverPk);
    final plaintext = box.decrypt(EncryptedMessage.fromList(combined));
    return utf8.decode(plaintext);
  }

  /// 验证 Authorization 并获取用户信息（含 frpc user token）。
  static Future<FrpAccount> userInfo(String token) async {
    final json = await _post('/frp/api/getUserInfo', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    return FrpAccount(
      username: data['username'] as String? ?? '',
      group: data['friendlyGroup'] as String? ?? '',
      usedTunnels: data['used'] as int?,
      maxTunnels: data['proxies'] as int?,
      frpToken: data['token'] as String?,
    );
  }

  /// 我的隧道列表。
  static Future<List<FrpRemoteTunnel>> proxyList(String token) async {
    final json = await _post('/frp/api/getUserProxies', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = data['list'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      return FrpRemoteTunnel(
        id: '${m['id']}',
        name: m['proxyName'] as String? ?? '',
        nodeId: '${m['nid']}',
        nodeName: m['friendlyNode'] as String? ?? '',
        type: m['proxyType'] as String? ?? 'tcp',
        localIp: m['localIp'] as String? ?? '127.0.0.1',
        localPort: (m['localPort'] as int?) ?? 25565,
        remotePort: m['remotePort'] as int?,
        remoteAddress: m['connectAddress'] as String? ?? '',
        online: frpParseBool(m['online']),
      );
    }).toList();
  }

  /// 节点列表。allowPort 形如 "(min,max)"。
  static Future<List<FrpNode>> nodeList(String token) async {
    final json = await _post('/frp/api/getNodeList', token);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = data['list'] as List? ?? [];
    return list.whereType<Map>().map((raw) {
      final m = raw.cast<String, dynamic>();
      final ports = _parseAllowPort(m['allowPort'] as String?);
      final protocols =
          (m['protocolSupport'] as Map?)?.cast<String, dynamic>() ?? {};
      return FrpNode(
        id: '${m['id']}',
        name: m['name'] as String? ?? '',
        hostname: m['hostname'] as String? ?? '',
        minPort: ports?.$1,
        maxPort: ports?.$2,
        description: m['description'] as String? ?? '',
        online: (m['status'] as int? ?? 200) == 200,
        vip: !((m['group'] as String? ?? '').split(';').contains('normal')),
        udpSupport: frpParseBool(protocols['udp'], orElse: true),
      );
    }).toList();
  }

  static (int, int)? _parseAllowPort(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'\((\d+),\s*(\d+)\)').firstMatch(raw);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  /// 创建隧道。
  static Future<void> newProxy(
    String token, {
    required int nodeId,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
  }) async {
    await _postBody('/frp/api/newProxy', token, {
      'node_id': nodeId,
      'name': name,
      'type': type,
      'local_addr': localIp,
      'local_port': localPort,
      'remote_port': remotePort,
      'domain_bind': '',
      'dataGzip': false,
      'dataEncrypt': false,
      'url_route': '',
      'host_rewrite': '',
      'request_from': '',
      'request_pass': '',
      'custom': '',
    });
  }

  /// 删除隧道。
  static Future<void> removeProxy(String token, String proxyId) async {
    await _postBody('/frp/api/removeProxy', token, {
      'proxy_id': int.tryParse(proxyId) ?? proxyId,
    });
  }
}
