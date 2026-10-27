/// STUN 打洞隧道的线上模型。
///
/// 形状与 daemon 的 `stun.status` / `stun.evt` 一一对应（snake_case）。三块：
///
/// * [StunSettings] —— 全局调参（服务器列表 / 保活间隔 / 并发上限 / 日志开关）；
/// * [StunTunnelRow] —— **每个实例**一行：开关 / 在不在跑 / 隧道相位与统计；
/// * [StunStatus] —— 前两者 + 计数与时间戳。
///
/// 提醒：隧道的配置（开关、PROXY protocol、目标端口覆盖）存在**实例自己的
/// 元数据**里（见 `instance/models.dart` 的 `stun*` 字段），这里只是它在
/// daemon 侧的投影。
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

/// STUN 全局设置（`stun.status` 的 `settings`）。
class StunSettings {
  const StunSettings({
    this.servers = const [],
    this.keepAliveSeconds = 20,
    this.maxConnections = 128,
    this.keepaliveHttp = 'www.baidu.com:80',
    this.showConnectionLog = true,
  });

  factory StunSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StunSettings();
    final keepaliveHttp = _str(json['keepalive_http']).trim();
    return StunSettings(
      servers: [
        for (final item in (json['servers'] as List? ?? const [])) ?_some(item),
      ],
      keepAliveSeconds: _int(json['keep_alive_seconds']) ?? 20,
      maxConnections: _int(json['max_connections']) ?? 128,
      keepaliveHttp: keepaliveHttp.isEmpty ? 'www.baidu.com:80' : keepaliveHttp,
      showConnectionLog: _bool(json['show_connection_log'], orElse: true),
    );
  }

  /// **生效的**服务器列表（daemon 已做过「空 = 内置 8 台」的回退，
  /// 拿到的一定非空；顺序即尝试顺序）。
  final List<String> servers;

  /// 保活 / 探测间隔（秒）。daemon 侧 clamp 到 5-300。
  final int keepAliveSeconds;

  /// 并发转发连接数上限。daemon 侧 clamp 到 1-1024。
  final int maxConnections;

  /// TCP 保活用的 HTTP 目标（`host:port`）。高级项，不上界面。
  final String keepaliveHttp;

  /// 是否把每条入站连接的建立 / 断开写进隧道日志。
  final bool showConnectionLog;

  static const empty = StunSettings();
}

/// 一条隧道的相位（`tunnels[].state`）。
enum StunTunnelState {
  /// 未启用 / 已停止（开关关着、实例没跑、或隧道还没启动）。
  idle,

  /// 正在探测公网映射，或失败后的等待重试间隙。
  probing,

  /// 隧道已就绪，正在转发。
  running,

  /// 多轮尝试后仍拿不到隧道（通常是 NAT 类型不支持），
  /// 等实例重启或配置变更 —— 不会自动重试。
  failed;

  static StunTunnelState parse(Object? raw) => switch (_str(raw)) {
    'probing' => StunTunnelState.probing,
    'running' => StunTunnelState.running,
    'failed' => StunTunnelState.failed,
    _ => StunTunnelState.idle,
  };

  String get label => switch (this) {
    StunTunnelState.idle => '未启动',
    StunTunnelState.probing => '探测中…',
    StunTunnelState.running => '运行中',
    StunTunnelState.failed => '启动失败',
  };
}

/// 一个实例的隧道行（`stun.status` 的 `tunnels[]`）。
class StunTunnelRow {
  const StunTunnelRow({
    required this.instanceId,
    required this.instanceName,
    this.enabled = false,
    this.running = false,
    this.state = StunTunnelState.idle,
    this.publicAddress,
    this.localPort,
    this.targetPort,
    this.activeConnections = 0,
    this.maxConnections = 128,
    this.totalUp = 0,
    this.totalDown = 0,
    this.upSpeed = 0,
    this.downSpeed = 0,
    this.error,
    this.server,
  });

  factory StunTunnelRow.fromJson(Map<String, dynamic> json) => StunTunnelRow(
    instanceId: _str(json['instance_id']),
    instanceName: _str(json['instance_name']),
    enabled: _bool(json['enabled']),
    running: _bool(json['running']),
    state: StunTunnelState.parse(json['state']),
    publicAddress: _some(json['public_address']),
    localPort: _int(json['local_port']),
    targetPort: _int(json['target_port']),
    activeConnections: _int(json['active_connections']) ?? 0,
    maxConnections: _int(json['max_connections']) ?? 128,
    totalUp: _int(json['total_up']) ?? 0,
    totalDown: _int(json['total_down']) ?? 0,
    upSpeed: _int(json['up_speed']) ?? 0,
    downSpeed: _int(json['down_speed']) ?? 0,
    error: _some(json['error']),
    server: _some(json['server']),
  );

  final String instanceId;
  final String instanceName;

  /// 实例设置里开关开着吗。
  final bool enabled;

  /// 实例在运行吗。
  final bool running;
  final StunTunnelState state;

  /// 公网直连地址（`1.2.3.4:25565`）；隧道没起来时没有。
  final String? publicAddress;

  /// 本机监听端口（探测拿到的）；隧道没起来时没有。
  final int? localPort;

  /// 转发目标端口（服务端实际端口，或实例里配的覆盖值）。
  final int? targetPort;

  /// 当前活跃的入站转发连接数。
  final int activeConnections;
  final int maxConnections;

  /// 累计流量（字节）。
  final int totalUp;
  final int totalDown;

  /// 瞬时速率（字节 / 秒），daemon 每秒采样。
  final int upSpeed;
  final int downSpeed;

  /// 失败原因（启动失败终态或最后一轮的错误）。
  final String? error;

  /// 最近一次探测成功的 STUN 服务器。
  final String? server;

  bool get isRunning => state == StunTunnelState.running;

  /// 正在探测 / 转发（失败终态与未启动都不算）——「要不要轮询」的判据。
  bool get isActive =>
      state == StunTunnelState.probing || state == StunTunnelState.running;
}

/// `stun.status` / `stun.evt` 的完整返回体。
class StunStatus {
  const StunStatus({
    this.settings = StunSettings.empty,
    this.tunnels = const [],
    this.ts,
  });

  factory StunStatus.fromJson(Map<String, dynamic> json) => StunStatus(
    settings: StunSettings.fromJson(
      (json['settings'] as Map?)?.cast<String, dynamic>(),
    ),
    tunnels: [
      for (final item in (json['tunnels'] as List? ?? const []))
        if (item is Map) StunTunnelRow.fromJson(item.cast<String, dynamic>()),
    ],
    ts: _int(json['ts']),
  );

  final StunSettings settings;
  final List<StunTunnelRow> tunnels;
  final int? ts;

  static const empty = StunStatus();

  int get count => tunnels.length;

  /// 有没有行。**为空不代表功能关着** —— 只是还没有实例开过开关。
  bool get isEmpty => tunnels.isEmpty;

  /// 有没有隧道在探测 / 转发（速度统计要重拉时才用得上）。
  bool get hasActive => tunnels.any((row) => row.isActive);
}

/// 一行隧道日志（`stun.logs` 的 `lines[]`）。
class StunLogLine {
  const StunLogLine({
    this.timeMs,
    this.instanceId,
    this.instanceName,
    this.text = '',
  });

  factory StunLogLine.fromJson(Map<String, dynamic> json) => StunLogLine(
    timeMs: _int(json['time_ms']),
    instanceId: _some(json['instance_id']),
    instanceName: _some(json['instance_name']),
    text: _str(json['text']),
  );

  /// Unix 毫秒。
  final int? timeMs;

  /// 日志归属的实例（同一实例的隧道日志标出实例名，界面不分实例混排）。
  final String? instanceId;
  final String? instanceName;
  final String text;
}

/// `stun.logs` 的返回体（环形缓冲快照，最多 500 行，旧 → 新）。
class StunLogs {
  const StunLogs({this.lines = const [], this.count = 0});

  factory StunLogs.fromJson(Map<String, dynamic> json) => StunLogs(
    lines: [
      for (final item in (json['lines'] as List? ?? const []))
        if (item is Map) StunLogLine.fromJson(item.cast<String, dynamic>()),
    ],
    count: _int(json['count']) ?? 0,
  );

  final List<StunLogLine> lines;
  final int count;

  static const empty = StunLogs();
}
