import 'config_store.dart';

/// DDNS 服务商。
enum DdnsProvider {
  cloudflare('cloudflare'),
  duckdns('duckdns'),
  dnspod('dnspod'),
  aliyun('aliyun'),
  custom('custom');

  const DdnsProvider(this.key);

  /// 持久化用的稳定标识。
  final String key;

  static DdnsProvider fromKey(String? key) => values.firstWhere(
        (p) => p.key == key,
        orElse: () => DdnsProvider.cloudflare,
      );
}

/// DDNS 动态域名解析的配置，持久化到 `config/ddns.json`。
///
/// 字段：
/// - [enabled]：是否启用（随服务器自动启停）；
/// - [provider]：DNS 服务商；
/// - [domain]：主域名（如 example.com；DuckDNS 时为其子域名名称）；
/// - [host]：主机记录（如 `mc`，`@` 或空表示根域名；DuckDNS 不使用）；
/// - [tokenId]：凭据 ID（DNSPod ID / 阿里云 AccessKey ID，其余服务商不使用）；
/// - [token]：凭据密钥（API Token / DNSPod Token / AccessKey Secret）；
/// - [customUrl]：自定义更新 URL（仅 provider 为 custom 时使用，支持
///   `{ipv4}`、`{ipv6}`、`{domain}` 占位符）；
/// - [ipv4Enabled] / [ipv6Enabled]：是否更新 A / AAAA 记录；
/// - [deleteOnStop]：服务器停止时是否删除远端解析记录（自定义 URL 无删除
///   接口，不适用）；
/// - [intervalMinutes]：公网 IP 变化的检查间隔（分钟）。
class DdnsConfig {
  const DdnsConfig({
    this.enabled = false,
    this.provider = DdnsProvider.cloudflare,
    this.domain = '',
    this.host = '',
    this.tokenId = '',
    this.token = '',
    this.customUrl = '',
    this.ipv4Enabled = true,
    this.ipv6Enabled = false,
    this.deleteOnStop = false,
    this.intervalMinutes = 10,
  });

  final bool enabled;
  final DdnsProvider provider;
  final String domain;
  final String host;
  final String tokenId;
  final String token;
  final String customUrl;
  final bool ipv4Enabled;
  final bool ipv6Enabled;
  final bool deleteOnStop;
  final int intervalMinutes;

  DdnsConfig copyWith({
    bool? enabled,
    DdnsProvider? provider,
    String? domain,
    String? host,
    String? tokenId,
    String? token,
    String? customUrl,
    bool? ipv4Enabled,
    bool? ipv6Enabled,
    bool? deleteOnStop,
    int? intervalMinutes,
  }) => DdnsConfig(
    enabled: enabled ?? this.enabled,
    provider: provider ?? this.provider,
    domain: domain ?? this.domain,
    host: host ?? this.host,
    tokenId: tokenId ?? this.tokenId,
    token: token ?? this.token,
    customUrl: customUrl ?? this.customUrl,
    ipv4Enabled: ipv4Enabled ?? this.ipv4Enabled,
    ipv6Enabled: ipv6Enabled ?? this.ipv6Enabled,
    deleteOnStop: deleteOnStop ?? this.deleteOnStop,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'provider': provider.key,
    'domain': domain,
    'host': host,
    'tokenId': tokenId,
    'token': token,
    'customUrl': customUrl,
    'ipv4Enabled': ipv4Enabled,
    'ipv6Enabled': ipv6Enabled,
    'deleteOnStop': deleteOnStop,
    'intervalMinutes': intervalMinutes,
  };

  factory DdnsConfig.fromJson(Map<String, dynamic> json) => DdnsConfig(
    enabled: json['enabled'] as bool? ?? false,
    provider: DdnsProvider.fromKey(json['provider'] as String?),
    domain: json['domain'] as String? ?? '',
    host: json['host'] as String? ?? '',
    tokenId: json['tokenId'] as String? ?? '',
    token: json['token'] as String? ?? '',
    customUrl: json['customUrl'] as String? ?? '',
    ipv4Enabled: json['ipv4Enabled'] as bool? ?? true,
    ipv6Enabled: json['ipv6Enabled'] as bool? ?? false,
    deleteOnStop: json['deleteOnStop'] as bool? ?? false,
    intervalMinutes: (json['intervalMinutes'] as int?) ?? 10,
  );
}

/// DDNS 配置的本地持久化读写，存于 `config/ddns.json`。
class DdnsStore {
  DdnsStore._();

  static const String _fileName = 'ddns.json';

  /// 读取已保存的 DDNS 配置；未保存过返回默认配置。
  static Future<DdnsConfig> load() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    if (configMap.isEmpty) return const DdnsConfig();
    return DdnsConfig.fromJson(configMap);
  }

  /// 持久化 DDNS 配置。
  static Future<void> save(DdnsConfig config) async {
    await ConfigStore.writeConfig(_fileName, config.toJson());
  }
}
