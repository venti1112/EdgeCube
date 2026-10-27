/// 实例的线上模型。
///
/// 字段名与 daemon 的**线上格式**一一对应（snake_case）。落盘文件用的是
/// camelCase，那是 daemon 自己的事，前端不用管。
///
/// # 两条启动配置路线（见 daemon 的 `instance/model.rs`）
///
/// * **表单模式**（默认）：填「运行环境 + 服务端 jar + 最大内存 +
///   自定义 JVM 参数」，命令由 daemon 现拼（[Instance.launchCommand]）；
/// * **手动模式**：自己写一整条 [Instance.startupCommand]，daemon 原样交给 shell。
///
/// 由 [Instance.manualCommand] 选。前端**只存字段、不拼命令** —— 运行环境装在
/// 哪、jar 叫什么，路径都在 daemon 那边，拼出来的命令它也会一并回给前端。
library;

/// 换行符：Linux（`\n`）/ Windows（`\r\n`）。
///
/// 这是「往服务端 stdin 写命令时补的换行」，与启动命令无关。
const String kLineEndingLf = '\n';
const String kLineEndingCrlf = '\r\n';

/// 启动命令的长度上限（字符数），与 daemon 的 `STARTUP_COMMAND_MAX_CHARS` 一致。
///
/// 前端先拦一道是为了给即时反馈；真正的把关在 daemon（它会以 `invalid_params` 拒绝）。
const int kStartupCommandMaxChars = 4096;

/// 停止命令的长度上限（字符数），与 daemon 的 `STOP_COMMAND_MAX_CHARS` 一致。
///
/// 停止命令就是「一行控制台命令」或一个 caret 记号，比启动命令短得多。
const int kStopCommandMaxChars = 512;

/// 自定义 JVM 参数的长度上限（字符数），与 daemon 的 `CUSTOM_JVM_ARGS_MAX_CHARS` 一致。
const int kCustomJvmArgsMaxChars = 1024;

/// UPnP 传输协议的两个取值（与 daemon 的 `upnp_protocol` 一致）。
const String kUpnpProtocolTcp = 'tcp';
const String kUpnpProtocolUdp = 'udp';

/// 「最大内存」的上限（MB），与 daemon 的 `MAX_MEMORY_MB_LIMIT` 一致（1 TiB）。
const int kMaxMemoryMbLimit = 1048576;

/// 没配停止命令时 daemon 用的默认值（与 daemon 的 `DEFAULT_STOP_COMMAND` 一致）。
///
/// 设置对话框里把它当**已生效的默认值**预填，用户改不改都行。
const String kDefaultStopCommand = 'stop';

/// caret 记号 → 控制字符，用于「停止命令」这类输入。
///
/// 只认整个值恰好是一个记号的写法（和 daemon 的 `caret_byte` 同规则）：
/// `^C` = 0x03（Ctrl+C / SIGINT）、`^D`、`^[`、`^?`…… 认不出就返回 `null`，
/// 调用方按普通命令处理。
int? caretByte(String text) {
  if (!text.startsWith('^') || text.length != 2) return null;
  final head = text[1].toUpperCase();
  final code = head.codeUnitAt(0);
  if (head == '?') return 0x7f;
  if (code >= 0x40 && code <= 0x5f) return code & 0x1f;
  return null;
}

/// 实例索引项：列表只需要这几个字段。
class InstanceSummary {
  const InstanceSummary({
    required this.id,
    required this.name,
    this.path,
    this.selected = false,
  });

  final String id;
  final String name;
  final String? path;

  /// 是否是当前选中项（daemon 在列表里标好的）。
  final bool selected;

  factory InstanceSummary.fromJson(Map<String, dynamic> json) =>
      InstanceSummary(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        path: json['path'] as String?,
        selected: json['selected'] as bool? ?? false,
      );
}

/// `instance.list` 的返回。
class InstanceList {
  const InstanceList({
    required this.instances,
    this.selected,
    this.dataDir = '',
  });

  final List<InstanceSummary> instances;

  /// 当前选中的实例 id；`null` = 没选。
  final String? selected;

  /// 数据根目录（显示用，排查问题时很有用）。
  final String dataDir;

  static const empty = InstanceList(instances: []);

  bool get isEmpty => instances.isEmpty;

  factory InstanceList.fromJson(Map<String, dynamic> json) => InstanceList(
    instances: [
      for (final item in (json['instances'] as List? ?? const []))
        if (item is Map) InstanceSummary.fromJson(item.cast<String, dynamic>()),
    ],
    selected: json['selected'] as String?,
    dataDir: json['data_dir'] as String? ?? '',
  );
}

/// 一个实例的完整元数据。
/// `eula.txt` 的状态（启动前那道 EULA 关卡的判据）。
///
/// 判定规则在 daemon（大小写不敏感的 `eula\s*=\s*true`），
/// 前端只拿结论 —— 文件在服务端机器上。
class EulaStatus {
  const EulaStatus({
    required this.exists,
    required this.agreed,
    required this.file,
  });

  factory EulaStatus.fromJson(Map<String, dynamic> json) => EulaStatus(
    exists: json['exists'] as bool? ?? false,
    agreed: json['agreed'] as bool? ?? false,
    file: json['file'] as String? ?? 'eula.txt',
  );

  /// 文件在不在这儿。服务端**第一次启动之后**才会自己生成一份 `eula=false` 的，
  /// 所以新实例上通常是 `false` —— 那正是要弹框的情形。
  final bool exists;

  /// 里面有没有 `eula=true`。
  final bool agreed;

  /// 文件名（daemon 给的，别在前端写死）。
  final String file;

  static const empty = EulaStatus(
    exists: false,
    agreed: false,
    file: 'eula.txt',
  );
}

class Instance {
  const Instance({
    required this.id,
    required this.name,
    this.startupCommand,
    this.launchCommand,
    this.manualCommand = false,
    this.runtimeEnvId,
    this.serverFile,
    this.maxMemory,
    this.customJvmArgs,
    this.stopCommand,
    this.compatMode = false,
    this.autoRestartOnExit = false,
    this.frpTunnelId,
    this.upnpEnabled = false,
    this.upnpProtocol = kUpnpProtocolTcp,
    this.upnpExternalPort,
    this.stunEnabled = false,
    this.stunProxyProtocol = false,
    this.stunTargetPort,
    this.path,
    this.lineEnding = kLineEndingLf,
    this.createdAtMs,
    this.updatedAtMs,
  });

  final String id;
  final String name;

  /// 手动模式里存的那条启动命令：怎么把服务端拉起来，用户自己写全。
  ///
  /// 例：`java -Xmx2G -jar server.jar nogui`、`/usr/bin/python3 main.py`。
  /// **表单模式下它不参与启动**（只是留档：切回手动模式时不用重写）。
  final String? startupCommand;

  /// daemon 算出来的「实际会跑的那条命令」。
  ///
  /// * 手动模式 = [startupCommand]；
  /// * 表单模式 = 按运行环境 + jar 现拼的 `java … -jar … nogui`。
  ///
  /// `null` = 现在起不来（没配全 / 运行环境不在了 / jar 不在实例目录里），
  /// 具体缺什么看 `instance.status.warnings` 与 `instance.get` 的 `lint`。
  final String? launchCommand;

  /// 是否手动命令模式（daemon 按「存过的值优先，没存过按字段推断」给的结果）。
  final bool manualCommand;

  /// 表单模式：用哪个运行环境（`zulu-jdk-21-linux-x64`）。
  final String? runtimeEnvId;

  /// 表单模式：服务端 jar 的**文件名**（相对实例目录）。
  final String? serverFile;

  /// 表单模式：最大内存（MB）；`null` = 不传 `-Xmx`（交给 JVM 自己定）。
  final int? maxMemory;

  /// 表单模式：自定义 JVM 参数（一段文本，空白分隔）。
  final String? customJvmArgs;

  /// 停止命令：怎么让服务端**优雅退出**。
  ///
  /// 普通文本（如 `stop`）= 往服务端控制台写这一行；caret 记号（如 `^C`）
  /// = 直接发那个控制字符（终端驱动会转成信号）。
  ///
  /// daemon 侧没配时会回落到 `stop`，并且**线上返回的就是生效值**，
  /// 所以这里通常不会是 `null`。
  final String? stopCommand;

  /// 兼容模式：进程起来后跳过「启动中」阶段。
  final bool compatMode;

  /// 关服自动重启。
  final bool autoRestartOnExit;

  /// **连带启动的映射隧道**（`SavedTunnel.localId`）。
  ///
  /// 起这个游戏实例时，顺便把那条 **FRP 实例**也拉起来。`null` / 空 = 不连带。
  ///
  /// 只是一个**引用**：用哪个 frpc、现在跑没跑，都在 FRP 那边
  /// （`frp.runtimes` / `frp.run.list`），这边不存第二份。
  final String? frpTunnelId;

  /// 配了连带启动的隧道吗。
  bool get hasFrpTunnel => frpTunnelId?.isNotEmpty ?? false;

  /// 路由器端口映射（UPnP）开关：起这个实例时自动在路由器上加一条映射，
  /// 停止时撤掉。要求路由器支持 UPnP。
  final bool upnpEnabled;

  /// UPnP 传输协议：`tcp` / `udp`（与 `kUpnpProtocolTcp` / `kUpnpProtocolUdp`）。
  final String upnpProtocol;

  /// UPnP 外部端口；`null` = 与内部端口（`server.properties` 等读出来的）相同。
  final int? upnpExternalPort;

  /// STUN 隧道开关：起这个实例时自动打洞，进程退出时关隧道。
  /// 仅在全锥形 NAT（NAT1）下建立得起来（CGNAT 等场景见「网络映射」页的说明）。
  final bool stunEnabled;

  /// STUN 隧道是否发送 PROXY protocol v2 头（让服务端拿到玩家真实 IP）。
  /// 需服务端已开启对应支持，否则玩家将无法进入。
  final bool stunProxyProtocol;

  /// STUN 隧道的转发目标端口；`null` = 用实例服务端自己的端口。
  final int? stunTargetPort;

  /// 自定义实例目录；`null` = 用 daemon 那边的默认位置。
  final String? path;

  final String lineEnding;
  final int? createdAtMs;
  final int? updatedAtMs;

  /// 是否配了可用的启动命令（空白串等同于没配）。
  bool get hasStartupCommand {
    final text = startupCommand?.trim() ?? '';
    return text.isNotEmpty;
  }

  /// 显示用的启动命令：没配时给一句提示文案。
  String get startupCommandLabel =>
      hasStartupCommand ? startupCommand!.trim() : '未配置';

  /// daemon 算出来的生效命令（空白串等同于没有）。
  String? get launchCommandOrNull {
    final text = launchCommand?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// 实例卡片上那一行「启动命令」：优先显示**实际会跑的**那条
  /// （表单模式下它与 [startupCommand] 不同）。
  String get launchCommandLabel => launchCommandOrNull ?? '未配置';

  factory Instance.fromJson(Map<String, dynamic> json) => Instance(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    startupCommand: json['startup_command'] as String?,
    launchCommand: json['launch_command'] as String?,
    manualCommand: json['manual_command'] as bool? ?? false,
    runtimeEnvId: json['runtime_env_id'] as String?,
    serverFile: json['server_file'] as String?,
    maxMemory: (json['max_memory'] as num?)?.toInt(),
    customJvmArgs: json['custom_jvm_args'] as String?,
    stopCommand: json['stop_command'] as String?,
    compatMode: json['compat_mode'] as bool? ?? false,
    autoRestartOnExit: json['auto_restart_on_exit'] as bool? ?? false,
    frpTunnelId: json['frp_tunnel_id'] as String?,
    upnpEnabled: json['upnp_enabled'] as bool? ?? false,
    upnpProtocol: json['upnp_protocol'] as String? ?? kUpnpProtocolTcp,
    upnpExternalPort: (json['upnp_external_port'] as num?)?.toInt(),
    stunEnabled: json['stun_enabled'] as bool? ?? false,
    stunProxyProtocol: json['stun_proxy_protocol'] as bool? ?? false,
    stunTargetPort: (json['stun_target_port'] as num?)?.toInt(),
    path: json['path'] as String?,
    lineEnding: json['line_ending'] as String? ?? kLineEndingLf,
    createdAtMs: (json['created_at_ms'] as num?)?.toInt(),
    updatedAtMs: (json['updated_at_ms'] as num?)?.toInt(),
  );
}

/// 服务端生命周期阶段（与 daemon 的 `ServerPhase` 对齐）。
enum ServerPhase {
  stopped('已停止'),
  preparing('准备中'),
  starting('启动中'),
  running('运行中'),
  stopping('停止中'),
  crashed('异常退出');

  const ServerPhase(this.label);

  final String label;

  static ServerPhase parse(String? raw) => switch (raw) {
    'preparing' => ServerPhase.preparing,
    'starting' => ServerPhase.starting,
    'running' => ServerPhase.running,
    'stopping' => ServerPhase.stopping,
    'crashed' => ServerPhase.crashed,
    _ => ServerPhase.stopped,
  };
}

/// 实例状态：磁盘视角 + 进程视角。
class InstanceStatus {
  const InstanceStatus({
    required this.id,
    required this.name,
    this.phase = ServerPhase.stopped,
    this.running = false,
    this.processManaged = false,
    this.pid,
    this.exitCode,
    this.startedAtMs,
    this.dir = '',
    this.dirExists = false,
    this.sizeBytes = 0,
    this.sizeHuman = '0 B',
    this.fileCount = 0,
    this.dirCount = 0,
    this.sizeTruncated = false,
    this.createdAtMs,
    this.updatedAtMs,
    this.warnings = const [],
  });

  final String id;
  final String name;
  final ServerPhase phase;
  final bool running;

  /// 进程管理是否已接入。现在恒为 `true` —— 阶段真的会动。
  final bool processManaged;

  /// 进程 id（在运行时才有）。
  final int? pid;

  /// 上一次退出的退出码。
  final int? exitCode;

  /// 本轮启动时刻（Unix 毫秒）。
  final int? startedAtMs;

  final String dir;
  final bool dirExists;
  final int sizeBytes;
  final String sizeHuman;
  final int fileCount;
  final int dirCount;
  final bool sizeTruncated;
  final int? createdAtMs;
  final int? updatedAtMs;

  /// 值得提醒用户的问题（目录丢了、入口文件不在……）。
  final List<String> warnings;

  factory InstanceStatus.fromJson(Map<String, dynamic> json) => InstanceStatus(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    phase: ServerPhase.parse(json['phase'] as String?),
    running: json['running'] as bool? ?? false,
    processManaged: json['process_managed'] as bool? ?? false,
    pid: (json['pid'] as num?)?.toInt(),
    exitCode: (json['exit_code'] as num?)?.toInt(),
    startedAtMs: (json['started_at_ms'] as num?)?.toInt(),
    dir: json['dir'] as String? ?? '',
    dirExists: json['dir_exists'] as bool? ?? false,
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    sizeHuman: json['size_human'] as String? ?? '0 B',
    fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
    dirCount: (json['dir_count'] as num?)?.toInt() ?? 0,
    sizeTruncated: json['size_truncated'] as bool? ?? false,
    createdAtMs: (json['created_at_ms'] as num?)?.toInt(),
    updatedAtMs: (json['updated_at_ms'] as num?)?.toInt(),
    warnings: [
      for (final w in (json['warnings'] as List? ?? const []))
        if (w is String) w,
    ],
  );
}

class InstanceDetail {
  const InstanceDetail({required this.instance, required this.status});

  final Instance instance;
  final InstanceStatus status;
}
