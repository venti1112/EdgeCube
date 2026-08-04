/// 运行环境标识：Java 版（JVM 跑 .jar）、PHP 版（PocketMine 跑 .phar）
/// 与 proot 容器（rootfs 内跑任意服务端）。
const String kRuntimeJava = 'java';
const String kRuntimePhp = 'php';
const String kRuntimeProot = 'proot';

/// 命令尾换行符风格：Linux（\n）与 Windows（\r\n）。
const String kLineEndingLf = '\n';
const String kLineEndingCrlf = '\r\n';

/// 实例索引项：仅包含选择列表所需的 [id]、[name] 与可选的 [path]。
///
/// 实例选择列表只读取索引（`config/instances.json`），无需加载每个实例
/// 完整的启动配置（那些存在各自的 `config/instances/<id>.json` 中）。
/// [path] 为实例目录的完整路径；为 null 时使用默认路径 `<root>/<id>`。
/// Survivalcraft 等需要将文件放入 proot 容器 rootfs 的实例会设置此字段。
class InstanceSummary {
  const InstanceSummary({required this.id, required this.name, this.path});

  final String id;
  final String name;

  /// 实例目录的完整路径（Android 文件系统路径）。
  /// null 表示使用默认路径 `<instances-root>/<id>`。
  final String? path;

  InstanceSummary copyWith({
    String? name,
    String? path,
    bool clearPath = false,
  }) => InstanceSummary(
    id: id,
    name: name ?? this.name,
    path: clearPath ? null : (path ?? this.path),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (path != null) 'path': path,
  };

  factory InstanceSummary.fromJson(Map<String, dynamic> json) =>
      InstanceSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String?,
      );
}

/// 单个服务器实例的元数据。
///
/// [id] 同时是该实例在磁盘上的文件夹名（随机生成、不可变）；
/// [name] 是用户可编辑的名称；
/// [runtime] 运行环境（[kRuntimeJava] / [kRuntimePhp] / [kRuntimeProot]），
/// 决定用 JVM、PHP 还是 proot 容器启动，以及服务端文件取 .jar、.phar 还是任意入口文件；
/// [maxMemory]、[runtimeEnvId]、[serverFile] 为启动配置（PHP 版不使用
/// runtimeEnvId/maxMemory；proot 版的 runtimeEnvId 为 rootfs id）；
/// [customJvmArgs] 为用户自定义的 JVM 参数（以空白符/换行分隔，原样附加在内置参数之后，仅 Java 版）；
/// [compatMode] 兼容模式：开启后「准备中」完成、服务端进程起来后直接视为「运行中」，
/// 跳过「启动中」阶段（适配不输出 Done 标志的非标准服务端）。
/// [autoRestartOnExit] 关服自动重启：开启后服务端正常退出（非用户主动关闭/重启、
/// 非异常退出）时自动用相同参数重新拉起服务端。默认关闭。
/// [prootStartupCommand] 仅用于 proot 纯容器（generic）rootfs：用户须填写完整启动命令
/// （含主程序路径与所有参数，如 `/usr/bin/python3 /mnt/server/main.py`）。
/// 带元数据的 rootfs（java/php/node/python）不需要此字段，启动方式由清单声明。
/// [lineEnding] 命令尾换行符，Linux 风格 [kLineEndingLf]（"\n"，默认）或
/// Windows 风格 [kLineEndingCrlf]（"\r\n"）。创建生存战争服务端实例时自动配置为 Windows 风格。
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
  });

  final String id;
  final String name;
  final String runtime;
  final int? maxMemory;

  /// 运行环境标识：runtime=java 时为原生 JRE id（如 `jre21`）；
  /// runtime=proot 时为所选 rootfs id。历史上叫 `javaVersion`（JSON 兼容旧 key）。
  final String? runtimeEnvId;

  /// 所选服务端入口文件名：Java 为 .jar，PHP 为 .phar，proot 其他环境为任意
  /// 入口文件；现代 Forge/NeoForge 为 `@<argfile 相对路径>` 哨兵（见 ForgeLaunch）。
  /// 历史上叫 `selectedJar`（JSON 兼容旧 key）。
  final String? serverFile;
  final String? customJvmArgs;
  final bool compatMode;

  /// 关服自动重启：服务端正常退出（非用户主动关闭/重启、非异常退出）时自动重启。
  final bool autoRestartOnExit;

  /// proot 纯容器（generic rootfs）的完整启动命令。
  /// 仅当 runtime=proot 且所选 rootfs 无元数据（或 envType=generic）时使用。
  /// 带元数据的 rootfs 不使用此字段。
  final String? prootStartupCommand;

  /// 实例目录的完整路径（Android 文件系统路径）。
  /// null 表示使用默认路径 `<instances-root>/<id>`。
  /// Survivalcraft 等需要将文件放入 proot 容器 rootfs 的实例会设置此字段
  /// （如 `<filesDir>/proot_rootfs/<rootfsId>/opt/<id>`）。
  final String? path;

  /// 命令尾换行符，[kLineEndingLf]（"\n"）或 [kLineEndingCrlf]（"\r\n"）。
  /// 发送控制台命令时追加到命令尾部。默认为 Linux 风格。
  /// 创建生存战争（Survivalcraft）服务端实例时自动配置为 Windows 风格。
  final String lineEnding;

  /// 是否为 PHP（PocketMine）运行环境。
  bool get isPhp => runtime == kRuntimePhp;

  Instance copyWith({
    String? name,
    String? runtime,
    int? maxMemory,
    String? runtimeEnvId,
    String? serverFile,
    String? customJvmArgs,
    bool? compatMode,
    bool? autoRestartOnExit,
    String? prootStartupCommand,
    String? path,
    String? lineEnding,
    bool clearMaxMemory = false,
    bool clearRuntimeEnvId = false,
    bool clearServerFile = false,
    bool clearCustomJvmArgs = false,
    bool clearProotStartupCommand = false,
    bool clearPath = false,
  }) => Instance(
    id: id,
    name: name ?? this.name,
    runtime: runtime ?? this.runtime,
    maxMemory: clearMaxMemory ? null : (maxMemory ?? this.maxMemory),
    runtimeEnvId: clearRuntimeEnvId
        ? null
        : (runtimeEnvId ?? this.runtimeEnvId),
    serverFile: clearServerFile ? null : (serverFile ?? this.serverFile),
    customJvmArgs: clearCustomJvmArgs
        ? null
        : (customJvmArgs ?? this.customJvmArgs),
    compatMode: compatMode ?? this.compatMode,
    autoRestartOnExit: autoRestartOnExit ?? this.autoRestartOnExit,
    prootStartupCommand: clearProotStartupCommand
        ? null
        : (prootStartupCommand ?? this.prootStartupCommand),
    path: clearPath ? null : (path ?? this.path),
    lineEnding: lineEnding ?? this.lineEnding,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'runtime': runtime,
    if (maxMemory != null) 'maxMemory': maxMemory,
    if (runtimeEnvId != null) 'runtimeEnvId': runtimeEnvId,
    if (serverFile != null) 'serverFile': serverFile,
    if (customJvmArgs != null) 'customJvmArgs': customJvmArgs,
    if (compatMode) 'compatMode': true,
    if (autoRestartOnExit) 'autoRestartOnExit': true,
    if (prootStartupCommand != null) 'prootStartupCommand': prootStartupCommand,
    if (path != null) 'path': path,
    if (lineEnding != kLineEndingLf) 'lineEnding': lineEnding,
  };

  factory Instance.fromJson(Map<String, dynamic> json) => Instance(
    id: json['id'] as String,
    name: json['name'] as String,
    runtime: json['runtime'] as String? ?? kRuntimeJava,
    maxMemory: json['maxMemory'] as int?,
    // 新 key 优先，读不到时回退历史 key（javaVersion / selectedJar），
    // 保证旧版本写出的实例配置可直接加载。
    runtimeEnvId: (json['runtimeEnvId'] ?? json['javaVersion']) as String?,
    serverFile: (json['serverFile'] ?? json['selectedJar']) as String?,
    customJvmArgs: json['customJvmArgs'] as String?,
    compatMode: json['compatMode'] as bool? ?? false,
    autoRestartOnExit: json['autoRestartOnExit'] as bool? ?? false,
    prootStartupCommand: json['prootStartupCommand'] as String?,
    path: json['path'] as String?,
    lineEnding: json['lineEnding'] as String? ?? kLineEndingLf,
  );
}
