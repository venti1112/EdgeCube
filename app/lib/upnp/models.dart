/// 路由器端口映射（UPnP）的线上模型。
///
/// 形状与 daemon 的 `upnp.status` / `upnp.evt` 一一对应（snake_case）。
/// 两块：
///
/// * [UpnpGateway] —— **路由器 / 网关**的状态（发现到没有、公网 IP、CGNAT）；
/// * [UpnpMappingRow] —— **每个实例**一行：开关 / 在不在跑 / 映射到哪。
///
/// 提醒：映射的配置（开关、协议、外部端口）存在**实例自己的元数据**里
/// （见 `instance/models.dart` 的 `upnp*` 字段），这里只是它在路由器上的投影。
library;

/// 宽松取字符串（缺失 / null → 空串）。
String _str(Object? value) => switch (value) {
  null => '',
  String() => value,
  _ => '$value',
};

/// 宽松取整数（数字、数字字符串都收）。
int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value.trim()),
  _ => null,
};

bool _bool(Object? value, {bool orElse = false}) => switch (value) {
  bool() => value,
  num() => value != 0,
  String() => const {
    'true',
    '1',
    'yes',
    'on',
  }.contains(value.trim().toLowerCase()),
  _ => orElse,
};

/// 非空字符串才要（daemon 用 null 表示「没有」）。
String? _some(Object? value) {
  final text = _str(value).trim();
  return text.isEmpty ? null : text;
}

/// 网关状态（`gateway.state`）。
enum UpnpGatewayState {
  /// 还没探测过（没有实例开着 UPnP，或者 daemon 刚起来）。
  unknown,

  /// 正在发现网关。
  searching,

  /// 找到可用网关了。
  ready,

  /// 发现失败（超时 / 路由器不支持）。
  error;

  static UpnpGatewayState parse(Object? raw) => switch (_str(raw)) {
    'searching' => UpnpGatewayState.searching,
    'ready' => UpnpGatewayState.ready,
    'error' => UpnpGatewayState.error,
    _ => UpnpGatewayState.unknown,
  };

  String get label => switch (this) {
    UpnpGatewayState.unknown => '未探测',
    UpnpGatewayState.searching => '正在发现…',
    UpnpGatewayState.ready => '已连接网关',
    UpnpGatewayState.error => '发现失败',
  };
}

/// 网关 / 路由器状态（`upnp.status` 的 `gateway`）。
class UpnpGateway {
  const UpnpGateway({
    this.state = UpnpGatewayState.unknown,
    this.externalIp,
    this.cgnat = false,
    this.address,
    this.error,
    this.probedAtMs,
  });

  factory UpnpGateway.fromJson(Map<String, dynamic>? json) => json == null
      ? const UpnpGateway()
      : UpnpGateway(
          state: UpnpGatewayState.parse(json['state']),
          externalIp: _some(json['external_ip']),
          cgnat: _bool(json['cgnat']),
          address: _some(json['address']),
          error: _some(json['error']),
          probedAtMs: _int(json['probed_at_ms']),
        );

  final UpnpGatewayState state;

  /// 路由器上报的公网 IP；拿不到就是 `null`（不影响映射，只是显示不了）。
  final String? externalIp;

  /// 公网 IP 落在私网 / 运营商级 NAT 段（CGNAT）—— 即使映射成功，
  /// 外网也连不进来。
  final bool cgnat;

  /// 网关地址（`192.168.1.1:1900`）。
  final String? address;

  /// 发现失败的原因。
  final String? error;

  /// 最近一次探测时间（Unix 毫秒）。
  final int? probedAtMs;

  bool get isReady => state == UpnpGatewayState.ready;

  static const empty = UpnpGateway();
}

/// 一行映射的状态（`mappings[].state`）。
enum UpnpMapState {
  /// 开关开着、实例没跑（或在等它启动）。
  idle,

  /// 正在往路由器上加映射。
  mapping,

  /// 映射在位。
  mapped,

  /// 加映射失败（网关不可用 / 端口被占）。
  failed;

  static UpnpMapState parse(Object? raw) => switch (_str(raw)) {
    'mapping' => UpnpMapState.mapping,
    'mapped' => UpnpMapState.mapped,
    'failed' => UpnpMapState.failed,
    _ => UpnpMapState.idle,
  };

  String get label => switch (this) {
    UpnpMapState.idle => '未映射',
    UpnpMapState.mapping => '映射中…',
    UpnpMapState.mapped => '已映射',
    UpnpMapState.failed => '映射失败',
  };
}

/// 一个实例的映射行（`upnp.status` 的 `mappings[]`）。
class UpnpMappingRow {
  const UpnpMappingRow({
    required this.instanceId,
    required this.instanceName,
    this.enabled = false,
    this.running = false,
    this.state = UpnpMapState.idle,
    this.protocol = 'tcp',
    this.internalPort,
    this.externalPort,
    this.publicAddress,
    this.error,
  });

  factory UpnpMappingRow.fromJson(Map<String, dynamic> json) => UpnpMappingRow(
    instanceId: _str(json['instance_id']),
    instanceName: _str(json['instance_name']),
    enabled: _bool(json['enabled']),
    running: _bool(json['running']),
    state: UpnpMapState.parse(json['state']),
    protocol: _str(json['protocol']).isEmpty ? 'tcp' : _str(json['protocol']),
    internalPort: _int(json['internal_port']),
    externalPort: _int(json['external_port']),
    publicAddress: _some(json['public_address']),
    error: _some(json['error']),
  );

  final String instanceId;
  final String instanceName;

  /// 实例设置里开关开着吗。
  final bool enabled;

  /// 实例在运行吗。
  final bool running;
  final UpnpMapState state;

  /// `tcp` / `udp`。
  final String protocol;

  /// 服务端实际听的端口（`server.properties` 等读出来的）。
  final int? internalPort;

  /// 路由器上对外的端口（没配自定义就与内部端口相同）。
  final int? externalPort;

  /// 外网用来连进来的地址（`1.2.3.4:25565`）；没映射上时没有。
  final String? publicAddress;

  /// 上一次失败的原因。
  final String? error;

  /// 端口那一列的文案：`25565 → 25565/TCP`。
  String get portText {
    if (internalPort == null) return '端口读取中…';
    final external = externalPort ?? internalPort!;
    final arrow = external == internalPort ? '' : ' → $external';
    return '$internalPort$arrow/${protocol.toUpperCase()}';
  }
}

/// `upnp.status` / `upnp.evt` 的完整返回体。
class UpnpStatus {
  const UpnpStatus({
    this.gateway = UpnpGateway.empty,
    this.mappings = const [],
    this.ts,
  });

  factory UpnpStatus.fromJson(Map<String, dynamic> json) => UpnpStatus(
    gateway: UpnpGateway.fromJson(
      (json['gateway'] as Map?)?.cast<String, dynamic>(),
    ),
    mappings: [
      for (final item in (json['mappings'] as List? ?? const []))
        if (item is Map) UpnpMappingRow.fromJson(item.cast<String, dynamic>()),
    ],
    ts: _int(json['ts']),
  );

  final UpnpGateway gateway;
  final List<UpnpMappingRow> mappings;
  final int? ts;

  static const empty = UpnpStatus();

  int get count => mappings.length;

  /// 有没有行。**为空不代表功能关着** —— 只是还没有实例开过开关。
  bool get isEmpty => mappings.isEmpty;
}
