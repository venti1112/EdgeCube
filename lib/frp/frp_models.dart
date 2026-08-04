import 'frp_provider.dart';

/// 宽松解析各家 API 的布尔字段：类型不一（bool / int / 字符串），
/// 统一按「真值」判定（非 0、"true"/"1"/"yes"/"on"）。null 或无法识别返回 [orElse]。
///
/// MSL 等 /frp/getTunnelList 的 `status` 实为整数（0/1），直接 `as bool` 会抛
/// `type 'int' is not a subtype of type 'bool?'`，故统一经此函数转换。
bool frpParseBool(Object? value, {bool orElse = false}) {
  if (value == null) return orElse;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return orElse;
    return v == 'true' || v == '1' || v == 'yes' || v == 'on';
  }
  return orElse;
}

/// 供应商无关的账号信息视图模型（各家 API 的用户信息映射到统一字段）。
class FrpAccount {
  const FrpAccount({
    required this.username,
    this.group = '',
    this.usedTunnels,
    this.maxTunnels,
    this.frpToken,
  });

  /// 用户名 / 昵称。
  final String username;

  /// 用户组显示名（如「普通用户」「VIP」）。
  final String group;

  /// 已用 / 上限隧道数；API 未提供时为 null。
  final int? usedTunnels;
  final int? maxTunnels;

  /// frpc 侧鉴权 token（OpenFrp 的 user token、ChmlFrp 的 usertoken、
  /// ME Frp 的 frpToken）。与登录 token 不同，用于拼装 frpc 配置。
  final String? frpToken;

  /// 序列化为 JSON（用于本地缓存）。
  Map<String, dynamic> toJson() => {
    'username': username,
    'group': group,
    'usedTunnels': usedTunnels,
    'maxTunnels': maxTunnels,
    'frpToken': frpToken,
  };

  /// 从缓存的 JSON 反序列化。
  factory FrpAccount.fromJson(Map<String, dynamic> json) => FrpAccount(
    username: json['username'] as String? ?? '',
    group: json['group'] as String? ?? '',
    usedTunnels: json['usedTunnels'] as int?,
    maxTunnels: json['maxTunnels'] as int?,
    frpToken: json['frpToken'] as String?,
  );
}

/// 供应商节点。
class FrpNode {
  const FrpNode({
    required this.id,
    required this.name,
    this.hostname = '',
    this.serverPort = 7000,
    this.minPort,
    this.maxPort,
    this.description = '',
    this.online = true,
    this.vip = false,
    this.udpSupport = true,
  });

  /// 节点 ID（数字或字符串，统一存字符串）。
  final String id;
  final String name;

  /// frps 连接地址（域名/IP）；部分 API 不下发，运行时再取。
  final String hostname;

  /// frps 服务端口。
  final int serverPort;

  /// 允许的远程端口范围；null 表示未知。
  final int? minPort;
  final int? maxPort;

  final String description;
  final bool online;

  /// 是否付费/会员专属节点。
  final bool vip;

  /// 是否支持 UDP（基岩版需要）。
  final bool udpSupport;
}

/// 远端已存在的隧道（各家 API 的隧道/代理列表项）。
class FrpRemoteTunnel {
  const FrpRemoteTunnel({
    required this.id,
    required this.name,
    this.nodeId = '',
    this.nodeName = '',
    this.type = 'tcp',
    this.localIp = '127.0.0.1',
    this.localPort = 25565,
    this.remotePort,
    this.remoteAddress = '',
    this.online = false,
  });

  final String id;
  final String name;
  final String nodeId;
  final String nodeName;

  /// tcp / udp / http / https。
  final String type;
  final String localIp;
  final int localPort;

  /// 远程端口；http(s) 隧道可能没有。
  final int? remotePort;

  /// 完整公网连接地址（如 OpenFrp 的 connectAddress、Sakura 的 remote）；
  /// 为空时由节点 hostname + remotePort 组合。
  final String remoteAddress;

  final bool online;

  /// 展示用公网地址。
  String get displayAddress {
    if (remoteAddress.isNotEmpty) return remoteAddress;
    return remotePort != null ? '$nodeName:$remotePort' : nodeName;
  }
}

/// 已保存到本地注册表的隧道（可一键运行的条目）。
class SavedFrpTunnel {
  const SavedFrpTunnel({
    required this.localId,
    required this.provider,
    required this.name,
    this.remoteTunnelId = '',
    this.nodeId = '',
    this.nodeName = '',
    this.type = 'tcp',
    this.localIp = '127.0.0.1',
    this.localPort = 25565,
    this.remotePort,
    this.remoteAddress = '',
    this.customToml = '',
  });

  /// 本地唯一 ID（时间戳生成）。
  final String localId;
  final FrpProvider provider;

  /// 显示名。
  final String name;

  /// 远端隧道 ID（custom 为空）。
  final String remoteTunnelId;
  final String nodeId;
  final String nodeName;
  final String type;
  final String localIp;
  final int localPort;
  final int? remotePort;

  /// 公网连接地址（保存时已知则记录，运行页展示与复制）。
  final String remoteAddress;

  /// 自定义隧道的完整 TOML（仅 provider == custom）。
  final String customToml;

  /// 展示用公网地址；未知时回退节点名。
  String get displayAddress {
    if (remoteAddress.isNotEmpty) return remoteAddress;
    if (remotePort != null && nodeName.isNotEmpty) {
      return '$nodeName:$remotePort';
    }
    return nodeName;
  }

  SavedFrpTunnel copyWith({String? remoteAddress}) => SavedFrpTunnel(
    localId: localId,
    provider: provider,
    name: name,
    remoteTunnelId: remoteTunnelId,
    nodeId: nodeId,
    nodeName: nodeName,
    type: type,
    localIp: localIp,
    localPort: localPort,
    remotePort: remotePort,
    remoteAddress: remoteAddress ?? this.remoteAddress,
    customToml: customToml,
  );

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'provider': provider.key,
    'name': name,
    'remoteTunnelId': remoteTunnelId,
    'nodeId': nodeId,
    'nodeName': nodeName,
    'type': type,
    'localIp': localIp,
    'localPort': localPort,
    if (remotePort != null) 'remotePort': remotePort,
    'remoteAddress': remoteAddress,
    if (customToml.isNotEmpty) 'customToml': customToml,
  };

  factory SavedFrpTunnel.fromJson(Map<String, dynamic> json) => SavedFrpTunnel(
    localId: json['localId'] as String? ?? '',
    provider: FrpProvider.fromKey(json['provider'] as String?),
    name: json['name'] as String? ?? '',
    remoteTunnelId: json['remoteTunnelId'] as String? ?? '',
    nodeId: json['nodeId'] as String? ?? '',
    nodeName: json['nodeName'] as String? ?? '',
    type: json['type'] as String? ?? 'tcp',
    localIp: json['localIp'] as String? ?? '127.0.0.1',
    localPort: (json['localPort'] as int?) ?? 25565,
    remotePort: json['remotePort'] as int?,
    remoteAddress: json['remoteAddress'] as String? ?? '',
    customToml: json['customToml'] as String? ?? '',
  );
}

/// 浏览器授权登录会话（createBrowserLogin 返回，pollBrowserLogin 回传）。
///
/// 各供应商在 [state] 中存放轮询所需的私有状态：MSL 存 ssid/csrf，
/// OpenFrp 存 request_uuid 与 curve25519 私钥，ChmlFrp 存 device_code。
class FrpBrowserLoginSession {
  const FrpBrowserLoginSession({
    required this.url,
    required this.state,
    this.userCode = '',
  });

  /// 用户在浏览器中打开的授权页 URL。
  final String url;

  /// 轮询所需的供应商特定状态。
  final Map<String, dynamic> state;

  /// 设备码授权流程中用户需在浏览器输入的短码（仅 ChmlFrp 使用）；
  /// 其他供应商为空。当 [url] 已自带短码（verification_uri_complete）时，
  /// 此字段仅作展示备用，用户通常无需手动输入。
  final String userCode;
}

/// FRP API 调用失败（业务码非成功或网络异常）。
class FrpApiException implements Exception {
  const FrpApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
