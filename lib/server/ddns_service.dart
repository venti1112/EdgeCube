import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/ddns_store.dart';
import '../net/network_address.dart';
import '../online/cloud_headers.dart';
import '../online/online_service.dart';

/// DDNS 更新过程中的业务错误（配置不完整、凭据无效、服务商拒绝等）。
class DdnsException implements Exception {
  DdnsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 单次 DDNS 更新的结果。
class DdnsUpdateResult {
  const DdnsUpdateResult({
    this.ipv4,
    this.ipv6,
    this.unchanged = false,
    this.error,
  });

  /// 当前检测到的公网 IPv4（未启用或检测失败为 null）。
  final String? ipv4;

  /// 当前检测到的公网 IPv6（未启用或检测失败为 null）。
  final String? ipv6;

  /// IP 与上次推送一致，本次未向服务商发起更新。
  final bool unchanged;

  /// 失败原因；null 表示成功。
  final String? error;

  bool get success => error == null;
}

/// DDNS 动态域名解析服务。
///
/// 检测本机公网 IP 并把域名的 A / AAAA 记录更新到 DNS 服务商，与 UPnP 端口
/// 映射配合后即可通过固定域名访问家庭宽带上的服务端。
///
/// 公网 IP 检测策略：
/// - IPv4：多个公共 API 并发竞速取第一个有效结果；全部失败时回退到路由器
///   网关（UPnP）上报的 WAN IP。
/// - IPv6：优先取本机稳定全局地址（IPv6 无 NAT，本机地址即公网地址，且避开
///   会轮换的临时隐私地址）；无则回退公共 API。
///
/// 支持服务商：Cloudflare、DuckDNS、DNSPod、阿里云 DNS，以及自定义更新 URL
/// （兼容 dyndns2 风格接口）。
class DdnsService {
  static const Duration _apiTimeout = Duration(seconds: 15);
  static const Duration _detectTimeout = Duration(seconds: 8);

  static const List<String> _ipv4Apis = [
    'https://api.ipify.org',
    'https://4.ipw.cn',
    'https://v4.ident.me',
    'https://ipv4.icanhazip.com',
  ];

  static const List<String> _ipv6Apis = [
    'https://api6.ipify.org',
    'https://6.ipw.cn',
    'https://v6.ident.me',
  ];

  /// 上次成功推送到服务商的公网 IP，用于跳过无变化的更新。
  String? _lastIpv4;
  String? _lastIpv6;

  String? get lastIpv4 => _lastIpv4;
  String? get lastIpv6 => _lastIpv6;

  /// 清空已推送 IP 缓存（停止 DDNS 时调用，下次启动强制推送一次）。
  void reset() {
    _lastIpv4 = null;
    _lastIpv6 = null;
  }

  /// 校验配置完整性；返回缺失说明（技术文本），完整返回 null。
  static String? validate(DdnsConfig c) {
    if (!c.ipv4Enabled && !c.ipv6Enabled) return 'no record type enabled';
    switch (c.provider) {
      case DdnsProvider.cloudflare:
        if (c.domain.trim().isEmpty || c.token.trim().isEmpty) {
          return 'domain and API token are required';
        }
      case DdnsProvider.duckdns:
        if (c.domain.trim().isEmpty || c.token.trim().isEmpty) {
          return 'domain and token are required';
        }
      case DdnsProvider.dnspod:
        if (c.domain.trim().isEmpty ||
            c.tokenId.trim().isEmpty ||
            c.token.trim().isEmpty) {
          return 'domain, token ID and token are required';
        }
      case DdnsProvider.aliyun:
        if (c.domain.trim().isEmpty ||
            c.tokenId.trim().isEmpty ||
            c.token.trim().isEmpty) {
          return 'domain, AccessKey ID and secret are required';
        }
      case DdnsProvider.custom:
        if (c.customUrl.trim().isEmpty) return 'update URL is required';
    }
    return null;
  }

  /// 对外展示用的完整域名（如 `mc.example.com`、`mysub.duckdns.org`）。
  static String displayDomain(DdnsConfig c) {
    final domain = c.domain.trim();
    if (c.provider == DdnsProvider.duckdns) {
      if (domain.isEmpty || domain.endsWith('.duckdns.org')) return domain;
      return '$domain.duckdns.org';
    }
    final host = c.host.trim();
    if (host.isEmpty || host == '@') return domain;
    return '$host.$domain';
  }

  /// 检测公网 IP 并更新 DNS 记录。
  ///
  /// [force] 为 true 时即使 IP 未变化也强制推送（用于手动「立即更新」）。
  /// [ipv4Fallback] 公共 API 全部失败时的 IPv4 回退来源（如 UPnP 网关 WAN IP）。
  Future<DdnsUpdateResult> update(
    DdnsConfig config, {
    bool force = false,
    Future<String?> Function()? ipv4Fallback,
  }) async {
    final invalid = validate(config);
    if (invalid != null) return DdnsUpdateResult(error: invalid);

    String? ipv4;
    String? ipv6;
    if (config.ipv4Enabled) {
      ipv4 = await detectPublicIpv4(fallback: ipv4Fallback);
    }
    if (config.ipv6Enabled) {
      ipv6 = await detectPublicIpv6();
    }
    if (ipv4 == null && ipv6 == null) {
      return const DdnsUpdateResult(error: 'failed to detect public IP');
    }
    if (!force && ipv4 == _lastIpv4 && ipv6 == _lastIpv6) {
      return DdnsUpdateResult(ipv4: ipv4, ipv6: ipv6, unchanged: true);
    }

    try {
      await _push(config, ipv4: ipv4, ipv6: ipv6);
      _lastIpv4 = ipv4;
      _lastIpv6 = ipv6;
      return DdnsUpdateResult(ipv4: ipv4, ipv6: ipv6);
    } on DdnsException catch (e) {
      return DdnsUpdateResult(ipv4: ipv4, ipv6: ipv6, error: e.message);
    } catch (e) {
      return DdnsUpdateResult(ipv4: ipv4, ipv6: ipv6, error: '$e');
    }
  }

  /// 删除域名当前的解析记录（「关闭服务器后删除解析」开启时调用）。
  ///
  /// 仅删除配置启用的记录类型（A / AAAA），不影响该域名的其它类型记录；
  /// DuckDNS 经 clear 参数清除；自定义 URL 无标准删除接口，静默跳过。
  Future<void> deleteRecords(DdnsConfig c) async {
    final invalid = validate(c);
    if (invalid != null) throw DdnsException(invalid);
    switch (c.provider) {
      case DdnsProvider.cloudflare:
        if (c.ipv4Enabled) await _deleteCloudflare(c, 'A');
        if (c.ipv6Enabled) await _deleteCloudflare(c, 'AAAA');
      case DdnsProvider.duckdns:
        await _deleteDuckdns(c);
      case DdnsProvider.dnspod:
        if (c.ipv4Enabled) await _deleteDnspod(c, 'A');
        if (c.ipv6Enabled) await _deleteDnspod(c, 'AAAA');
      case DdnsProvider.aliyun:
        if (c.ipv4Enabled) await _deleteAliyun(c, 'A');
        if (c.ipv6Enabled) await _deleteAliyun(c, 'AAAA');
      case DdnsProvider.custom:
        break;
    }
  }

  // —— 公网 IP 检测 ——

  /// 检测公网 IPv4：多 API 并发竞速，全部失败时尝试 [fallback]（须为公网地址）。
  Future<String?> detectPublicIpv4({
    Future<String?> Function()? fallback,
  }) async {
    final fromHttp = await _detectViaHttp(_ipv4Apis, InternetAddressType.IPv4);
    if (fromHttp != null) return fromHttp;
    if (fallback != null) {
      try {
        final ip = await fallback();
        if (ip != null &&
            InternetAddress.tryParse(ip)?.type == InternetAddressType.IPv4) {
          return ip;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 检测公网 IPv6：优先本机稳定全局地址，无则回退公共 API。
  Future<String?> detectPublicIpv6() async {
    final local = await NetworkAddress.detectStableIPv6();
    if (local != null) return local;
    return _detectViaHttp(_ipv6Apis, InternetAddressType.IPv6);
  }

  Future<String?> _detectViaHttp(
    List<String> urls,
    InternetAddressType family,
  ) async {
    try {
      return await OnlineService.fetchFirstValid<String?>(
        urls,
        (url) => _fetchIpText(url, family),
        (ip) => ip != null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchIpText(String url, InternetAddressType family) async {
    try {
      final resp = await http.get(Uri.parse(url)).timeout(_detectTimeout);
      if (resp.statusCode != 200) return null;
      final addr = InternetAddress.tryParse(resp.body.trim());
      if (addr == null || addr.type != family) return null;
      return addr.address;
    } catch (_) {
      return null;
    }
  }

  // —— 服务商推送 ——

  Future<void> _push(DdnsConfig c, {String? ipv4, String? ipv6}) async {
    switch (c.provider) {
      case DdnsProvider.cloudflare:
        if (ipv4 != null) await _pushCloudflare(c, ipv4, 'A');
        if (ipv6 != null) await _pushCloudflare(c, ipv6, 'AAAA');
      case DdnsProvider.duckdns:
        await _pushDuckdns(c, ipv4: ipv4, ipv6: ipv6);
      case DdnsProvider.dnspod:
        if (ipv4 != null) await _pushDnspod(c, ipv4, 'A');
        if (ipv6 != null) await _pushDnspod(c, ipv6, 'AAAA');
      case DdnsProvider.aliyun:
        if (ipv4 != null) await _pushAliyun(c, ipv4, 'A');
        if (ipv6 != null) await _pushAliyun(c, ipv6, 'AAAA');
      case DdnsProvider.custom:
        await _pushCustom(c, ipv4: ipv4, ipv6: ipv6);
    }
  }

  /// 主机记录（服务商 API 用），空表示根域名 `@`。
  static String _subDomain(DdnsConfig c) {
    final host = c.host.trim();
    return host.isEmpty ? '@' : host;
  }

  // —— Cloudflare ——

  static const String _cfBase = 'https://api.cloudflare.com/client/v4';

  Map<String, String> _cfHeaders(DdnsConfig c) => {
    'Authorization': 'Bearer ${c.token.trim()}',
    'Content-Type': 'application/json',
  };

  /// 查询 zone id 与该域名同类型的全部记录。
  Future<(String, List<Map<String, dynamic>>)> _cfListRecords(
    DdnsConfig c,
    String type,
  ) async {
    final headers = _cfHeaders(c);
    final domain = c.domain.trim();
    final fqdn = displayDomain(c);

    final zonesResp = await http
        .get(Uri.parse('$_cfBase/zones?name=$domain'), headers: headers)
        .timeout(_apiTimeout);
    final zones = _cfResult(zonesResp) as List<dynamic>;
    if (zones.isEmpty) {
      throw DdnsException('Cloudflare zone not found: $domain');
    }
    final zoneId = (zones.first as Map<String, dynamic>)['id'] as String;

    final recResp = await http
        .get(
          Uri.parse('$_cfBase/zones/$zoneId/dns_records?type=$type&name=$fqdn'),
          headers: headers,
        )
        .timeout(_apiTimeout);
    final records = (_cfResult(recResp) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return (zoneId, records);
  }

  Future<void> _pushCloudflare(DdnsConfig c, String ip, String type) async {
    final headers = _cfHeaders(c);
    final (zoneId, records) = await _cfListRecords(c, type);

    // MC 服务器走原始 TCP/UDP，必须关闭 Cloudflare 代理（仅 DNS 解析）。
    final body = jsonEncode({
      'type': type,
      'name': displayDomain(c),
      'content': ip,
      'ttl': 120,
      'proxied': false,
    });
    if (records.isEmpty) {
      final resp = await http
          .post(
            Uri.parse('$_cfBase/zones/$zoneId/dns_records'),
            headers: headers,
            body: body,
          )
          .timeout(_apiTimeout);
      _cfResult(resp);
    } else {
      // DNS 允许同域名并存多条不同 IP 的记录；只保留一条指向当前公网 IP，
      // 其余全部删除。优先保留已是目标值的记录，并先删后改，避免与同值
      // 记录冲突（Cloudflare 拒绝完全相同的重复记录）。
      final keepIndex = records.indexWhere((r) => r['content'] == ip);
      final keep = keepIndex >= 0 ? records[keepIndex] : records.first;
      for (final extra in records) {
        if (identical(extra, keep)) continue;
        final resp = await http
            .delete(
              Uri.parse('$_cfBase/zones/$zoneId/dns_records/${extra['id']}'),
              headers: headers,
            )
            .timeout(_apiTimeout);
        _cfResult(resp);
      }
      if (keep['content'] != ip) {
        final resp = await http
            .put(
              Uri.parse('$_cfBase/zones/$zoneId/dns_records/${keep['id']}'),
              headers: headers,
              body: body,
            )
            .timeout(_apiTimeout);
        _cfResult(resp);
      }
    }
  }

  /// 删除该域名同类型的全部记录。
  Future<void> _deleteCloudflare(DdnsConfig c, String type) async {
    final headers = _cfHeaders(c);
    final (zoneId, records) = await _cfListRecords(c, type);
    for (final record in records) {
      final resp = await http
          .delete(
            Uri.parse('$_cfBase/zones/$zoneId/dns_records/${record['id']}'),
            headers: headers,
          )
          .timeout(_apiTimeout);
      _cfResult(resp);
    }
  }

  /// 解析 Cloudflare 响应，失败时抛出带 message 的 [DdnsException]。
  dynamic _cfResult(http.Response resp) {
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    if (json == null) throw DdnsException('Cloudflare HTTP ${resp.statusCode}');
    if (json['success'] != true) {
      final errors = json['errors'] as List<dynamic>?;
      final msg = (errors != null && errors.isNotEmpty)
          ? (errors.first as Map<String, dynamic>)['message']
          : null;
      throw DdnsException('Cloudflare: ${msg ?? 'HTTP ${resp.statusCode}'}');
    }
    return json['result'];
  }

  // —— DuckDNS ——

  /// DuckDNS 子域名（去掉可能带上的 .duckdns.org 后缀）。
  static String _duckdnsSub(DdnsConfig c) {
    var sub = c.domain.trim();
    const suffix = '.duckdns.org';
    if (sub.endsWith(suffix)) {
      sub = sub.substring(0, sub.length - suffix.length);
    }
    return sub;
  }

  Future<void> _duckdnsCall(DdnsConfig c, Map<String, String> params) async {
    final uri = Uri.https('www.duckdns.org', '/update', {
      'domains': _duckdnsSub(c),
      'token': c.token.trim(),
      ...params,
    });
    final resp = await http.get(uri).timeout(_apiTimeout);
    if (resp.statusCode != 200 || !resp.body.trim().startsWith('OK')) {
      final detail = resp.statusCode == 200
          ? resp.body.trim()
          : 'HTTP ${resp.statusCode}';
      throw DdnsException('DuckDNS: $detail');
    }
  }

  /// DuckDNS 每个子域名固定单条记录，更新即覆盖，无需清理旧解析。
  Future<void> _pushDuckdns(DdnsConfig c, {String? ipv4, String? ipv6}) =>
      _duckdnsCall(c, {'ip': ?ipv4, 'ipv6': ?ipv6});

  /// 清除 DuckDNS 记录（官方 clear 参数）。
  Future<void> _deleteDuckdns(DdnsConfig c) =>
      _duckdnsCall(c, {'clear': 'true'});

  // —— DNSPod ——

  static Map<String, String> _dnspodCommon(DdnsConfig c) => {
    'login_token': '${c.tokenId.trim()},${c.token.trim()}',
    'format': 'json',
    'domain': c.domain.trim(),
  };

  /// 查询该域名同类型的全部记录（code 10 = 记录不存在，返回空列表）。
  Future<List<Map<String, dynamic>>> _dnspodListRecords(
    DdnsConfig c,
    String type,
  ) async {
    final listJson = await _dnspodCall('Record.List', {
      ..._dnspodCommon(c),
      'sub_domain': _subDomain(c),
      'record_type': type,
    }, allowCodes: const {'10'});
    return (listJson['records'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> _pushDnspod(DdnsConfig c, String ip, String type) async {
    final common = _dnspodCommon(c);
    final sub = _subDomain(c);
    final records = await _dnspodListRecords(c, type);

    if (records.isEmpty) {
      await _dnspodCall('Record.Create', {
        ...common,
        'sub_domain': sub,
        'record_type': type,
        'record_line': '默认',
        'value': ip,
      });
    } else {
      // DNS 允许同域名并存多条不同 IP 的记录；只保留一条指向当前公网 IP，
      // 其余全部删除。优先保留已是目标值的记录，并先删后改，避免与同值
      // 记录冲突（服务商会拒绝完全相同的重复记录）。
      final keepIndex = records.indexWhere((r) => r['value'] == ip);
      final keep = keepIndex >= 0 ? records[keepIndex] : records.first;
      for (final extra in records) {
        if (identical(extra, keep)) continue;
        await _dnspodCall('Record.Remove', {
          ...common,
          'record_id': '${extra['id']}',
        });
      }
      if (keep['value'] != ip) {
        await _dnspodCall('Record.Ddns', {
          ...common,
          'record_id': '${keep['id']}',
          'sub_domain': sub,
          'record_line': '默认',
          'value': ip,
        });
      }
    }
  }

  /// 删除该域名同类型的全部记录。
  Future<void> _deleteDnspod(DdnsConfig c, String type) async {
    final common = _dnspodCommon(c);
    for (final record in await _dnspodListRecords(c, type)) {
      await _dnspodCall('Record.Remove', {
        ...common,
        'record_id': '${record['id']}',
      });
    }
  }

  Future<Map<String, dynamic>> _dnspodCall(
    String action,
    Map<String, String> params, {
    Set<String> allowCodes = const {},
  }) async {
    final resp = await http
        .post(
          Uri.parse('https://dnsapi.cn/$action'),
          headers: {
            // DNSPod 要求 UA 携带程序名与联系方式，否则可能被限制。
            'User-Agent': 'EdgeCube-DDNS/${(await CloudHeaders.userAgent).split('/').last} (support@edgecubemc.com)',
          },
          body: params,
        )
        .timeout(_apiTimeout);
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    if (json == null) throw DdnsException('DNSPod HTTP ${resp.statusCode}');
    final status = json['status'] as Map<String, dynamic>?;
    final code = '${status?['code']}';
    if (code != '1' && !allowCodes.contains(code)) {
      throw DdnsException(
        'DNSPod: ${status?['message'] ?? 'HTTP ${resp.statusCode}'}',
      );
    }
    return json;
  }

  // —— 阿里云 DNS ——

  /// 查询该域名同类型的全部记录。
  Future<List<Map<String, dynamic>>> _aliyunListRecords(
    DdnsConfig c,
    String type,
  ) async {
    final rr = _subDomain(c);
    final domain = c.domain.trim();
    final list = await _aliyunCall(c, {
      'Action': 'DescribeSubDomainRecords',
      'SubDomain': rr == '@' ? domain : '$rr.$domain',
      'Type': type,
    });
    return (((list['DomainRecords'] as Map<String, dynamic>?)?['Record']
                as List<dynamic>?) ??
            const [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> _pushAliyun(DdnsConfig c, String ip, String type) async {
    final rr = _subDomain(c);
    final records = await _aliyunListRecords(c, type);

    if (records.isEmpty) {
      await _aliyunCall(c, {
        'Action': 'AddDomainRecord',
        'DomainName': c.domain.trim(),
        'RR': rr,
        'Type': type,
        'Value': ip,
      });
    } else {
      // DNS 允许同域名并存多条不同 IP 的记录；只保留一条指向当前公网 IP，
      // 其余全部删除。优先保留已是目标值的记录，并先删后改，避免与同值
      // 记录冲突（服务商会拒绝完全相同的重复记录）。
      final keepIndex = records.indexWhere((r) => r['Value'] == ip);
      final keep = keepIndex >= 0 ? records[keepIndex] : records.first;
      for (final extra in records) {
        if (identical(extra, keep)) continue;
        await _aliyunCall(c, {
          'Action': 'DeleteDomainRecord',
          'RecordId': '${extra['RecordId']}',
        });
      }
      if (keep['Value'] != ip) {
        await _aliyunCall(c, {
          'Action': 'UpdateDomainRecord',
          'RecordId': '${keep['RecordId']}',
          'RR': rr,
          'Type': type,
          'Value': ip,
        });
      }
    }
  }

  /// 删除该域名同类型的全部记录。
  Future<void> _deleteAliyun(DdnsConfig c, String type) async {
    for (final record in await _aliyunListRecords(c, type)) {
      await _aliyunCall(c, {
        'Action': 'DeleteDomainRecord',
        'RecordId': '${record['RecordId']}',
      });
    }
  }

  /// 调用阿里云 DNS RPC API（HMAC-SHA1 签名，GET 方式）。
  Future<Map<String, dynamic>> _aliyunCall(
    DdnsConfig c,
    Map<String, String> action,
  ) async {
    final params = <String, String>{
      ...action,
      'Format': 'JSON',
      'Version': '2015-01-09',
      'AccessKeyId': c.tokenId.trim(),
      'SignatureMethod': 'HMAC-SHA1',
      'SignatureVersion': '1.0',
      'SignatureNonce': '${DateTime.now().microsecondsSinceEpoch}',
      'Timestamp': _aliyunTimestamp(),
    };
    final keys = params.keys.toList()..sort();
    final canonical = keys
        .map((k) => '${_rfc3986(k)}=${_rfc3986(params[k]!)}')
        .join('&');
    final toSign = 'GET&${_rfc3986('/')}&${_rfc3986(canonical)}';
    final hmac = Hmac(sha1, utf8.encode('${c.token.trim()}&'));
    final signature = base64Encode(hmac.convert(utf8.encode(toSign)).bytes);
    final uri = Uri.parse(
      'https://alidns.aliyuncs.com/?$canonical&Signature=${_rfc3986(signature)}',
    );

    final resp = await http.get(uri).timeout(_apiTimeout);
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    if (json == null) throw DdnsException('Aliyun HTTP ${resp.statusCode}');
    if (resp.statusCode != 200) {
      throw DdnsException(
        'Aliyun: ${json['Message'] ?? 'HTTP ${resp.statusCode}'}',
      );
    }
    return json;
  }

  /// 阿里云要求的 ISO8601 UTC 时间戳（不含毫秒）。
  static String _aliyunTimestamp() {
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}'
        'T${two(now.hour)}:${two(now.minute)}:${two(now.second)}Z';
  }

  /// RFC 3986 严格百分号编码（阿里云签名规范：仅保留 A-Za-z0-9-_.~）。
  static String _rfc3986(String input) {
    final bytes = utf8.encode(input);
    final sb = StringBuffer();
    for (final b in bytes) {
      final unreserved =
          (b >= 0x41 && b <= 0x5A) || // A-Z
          (b >= 0x61 && b <= 0x7A) || // a-z
          (b >= 0x30 && b <= 0x39) || // 0-9
          b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E; // - . _ ~
      if (unreserved) {
        sb.writeCharCode(b);
      } else {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return sb.toString();
  }

  // —— 自定义更新 URL ——

  /// GET 自定义 URL，支持 `{ipv4}`、`{ipv6}`、`{domain}` 占位符；
  /// 兼容 dyndns2 风格响应（HTTP 200 但 body 报错码视为失败）。
  Future<void> _pushCustom(DdnsConfig c, {String? ipv4, String? ipv6}) async {
    final url = c.customUrl
        .trim()
        .replaceAll('{ipv4}', ipv4 ?? '')
        .replaceAll('{ipv6}', ipv6 ?? '')
        .replaceAll('{domain}', displayDomain(c));
    final resp = await http.get(Uri.parse(url)).timeout(_apiTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw DdnsException('HTTP ${resp.statusCode}');
    }
    final body = resp.body.trim();
    final lower = body.toLowerCase();
    const badWords = ['badauth', 'nohost', 'abuse', 'notfqdn', 'badagent', '911', 'ko'];
    if (badWords.any((w) => lower == w || lower.startsWith('$w '))) {
      throw DdnsException(body.length > 120 ? body.substring(0, 120) : body);
    }
  }
}
