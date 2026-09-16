/// 实例的线上模型。
///
/// 字段名与 daemon 的**线上格式**一一对应（snake_case）——
/// 落盘文件用的是 V1 的 camelCase，那是 daemon 自己的事，前端不用管。
library;

/// 运行环境标识（与 daemon / V1 一致）。
const String kRuntimeJava = 'java';
const String kRuntimePhp = 'php';
const String kRuntimeProot = 'proot';

const List<String> kRuntimes = [kRuntimeJava, kRuntimePhp, kRuntimeProot];

/// 换行符：Linux（`\n`）/ Windows（`\r\n`）。
const String kLineEndingLf = '\n';
const String kLineEndingCrlf = '\r\n';

/// 运行环境的中文名（下拉里显示）。
String runtimeLabel(String runtime) => switch (runtime) {
  kRuntimeJava => 'Java（JVM 跑 .jar）',
  kRuntimePhp => 'PHP（PocketMine 跑 .phar）',
  kRuntimeProot => 'proot 容器',
  _ => runtime,
};

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

  factory InstanceSummary.fromJson(Map<String, dynamic> json) => InstanceSummary(
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
class Instance {
  const Instance({
    required this.id,
    required this.name,
    this.runtime = kRuntimeJava,
    this.maxMemory,
    this.runtimeEnvId,
    this.serverFile,
    this.customJvmArgs,
    this.compatMode = false,
    this.autoRestartOnExit = false,
    this.prootStartupCommand,
    this.path,
    this.lineEnding = kLineEndingLf,
    this.createdAtMs,
    this.updatedAtMs,
  });

  final String id;
  final String name;
  final String runtime;

  /// 最大内存（MB），仅 Java 环境使用。
  final int? maxMemory;

  /// 运行环境标识：Java 为 JRE id（如 `jre21`），proot 为 rootfs id。
  final String? runtimeEnvId;

  /// 服务端入口文件名（`.jar` / `.phar` / 任意）。
  final String? serverFile;

  /// 自定义 JVM 参数（仅 Java）。
  final String? customJvmArgs;

  /// 兼容模式：进程起来后跳过「启动中」阶段。
  final bool compatMode;

  /// 关服自动重启。
  final bool autoRestartOnExit;

  /// proot 纯容器的完整启动命令。
  final String? prootStartupCommand;

  /// 自定义实例目录；`null` = 用默认位置。
  final String? path;

  final String lineEnding;
  final int? createdAtMs;
  final int? updatedAtMs;

  bool get isPhp => runtime == kRuntimePhp;
  bool get isProot => runtime == kRuntimeProot;

  /// 内存的显示文案。
  String get memoryLabel => maxMemory == null ? '默认' : '$maxMemory MB';

  factory Instance.fromJson(Map<String, dynamic> json) => Instance(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    runtime: json['runtime'] as String? ?? kRuntimeJava,
    maxMemory: (json['max_memory'] as num?)?.toInt(),
    runtimeEnvId: json['runtime_env_id'] as String?,
    serverFile: json['server_file'] as String?,
    customJvmArgs: json['custom_jvm_args'] as String?,
    compatMode: json['compat_mode'] as bool? ?? false,
    autoRestartOnExit: json['auto_restart_on_exit'] as bool? ?? false,
    prootStartupCommand: json['proot_startup_command'] as String?,
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

/// 实例状态：磁盘视角 + 预留的进程阶段。
class InstanceStatus {
  const InstanceStatus({
    required this.id,
    required this.name,
    this.phase = ServerPhase.stopped,
    this.running = false,
    this.processManaged = false,
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

  /// 进程管理是否已接入。当前恒为 `false` —— 阶段还不会动。
  final bool processManaged;

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

/// 选中实例的「元数据 + 状态」组合，页面一次拿全。
class InstanceDetail {
  const InstanceDetail({required this.instance, required this.status});

  final Instance instance;
  final InstanceStatus status;
}
