/// 运行环境标识：Java 版（JVM 跑 .jar）与 PHP 版（PocketMine 跑 .phar）。
const String kRuntimeJava = 'java';
const String kRuntimePhp = 'php';
const String kRuntimeProot = 'proot';

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

  InstanceSummary copyWith({String? name, String? path, bool clearPath = false}) =>
      InstanceSummary(
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
/// [runtime] 运行环境（[kRuntimeJava] / [kRuntimePhp]），决定用 JVM 还是 PHP 启动，
/// 以及服务端文件取 .jar 还是 .phar；
/// [maxMemory]、[javaVersion]、[selectedJar] 为启动配置（PHP 版不使用 javaVersion/maxMemory）；
/// [customJvmArgs] 为用户自定义的 JVM 参数（以空白符/换行分隔，原样附加在内置参数之后，仅 Java 版）；
/// [compatMode] 兼容模式：开启后「准备中」完成、服务端进程起来后直接视为「运行中」，
/// 跳过「启动中」阶段（适配不输出 Done 标志的非标准服务端）。
/// [prootStartupCommand] 仅用于 proot 纯容器（generic）rootfs：用户须填写完整启动命令
/// （含主程序路径与所有参数，如 `/usr/bin/python3 /mnt/server/main.py`）。
/// 带元数据的 rootfs（java/php/node/python）不需要此字段，启动方式由清单声明。
class Instance {
  const Instance({
    required this.id,
    required this.name,
    this.runtime = kRuntimeJava,
    this.maxMemory,
    this.javaVersion,
    this.selectedJar,
    this.customJvmArgs,
    this.compatMode = false,
    this.prootStartupCommand,
    this.path,
  });

  final String id;
  final String name;
  final String runtime;
  final int? maxMemory;
  final String? javaVersion;
  final String? selectedJar;
  final String? customJvmArgs;
  final bool compatMode;

  /// proot 纯容器（generic rootfs）的完整启动命令。
  /// 仅当 runtime=proot 且所选 rootfs 无元数据（或 envType=generic）时使用。
  /// 带元数据的 rootfs 不使用此字段。
  final String? prootStartupCommand;

  /// 实例目录的完整路径（Android 文件系统路径）。
  /// null 表示使用默认路径 `<instances-root>/<id>`。
  /// Survivalcraft 等需要将文件放入 proot 容器 rootfs 的实例会设置此字段
  /// （如 `<filesDir>/proot_rootfs/<rootfsId>/opt/<id>`）。
  final String? path;

  /// 是否为 PHP（PocketMine）运行环境。
  bool get isPhp => runtime == kRuntimePhp;

  Instance copyWith({
    String? name,
    String? runtime,
    int? maxMemory,
    String? javaVersion,
    String? selectedJar,
    String? customJvmArgs,
    bool? compatMode,
    String? prootStartupCommand,
    String? path,
    bool clearMaxMemory = false,
    bool clearJavaVersion = false,
    bool clearSelectedJar = false,
    bool clearCustomJvmArgs = false,
    bool clearProotStartupCommand = false,
    bool clearPath = false,
  }) => Instance(
    id: id,
    name: name ?? this.name,
    runtime: runtime ?? this.runtime,
    maxMemory: clearMaxMemory ? null : (maxMemory ?? this.maxMemory),
    javaVersion: clearJavaVersion ? null : (javaVersion ?? this.javaVersion),
    selectedJar: clearSelectedJar ? null : (selectedJar ?? this.selectedJar),
    customJvmArgs: clearCustomJvmArgs
        ? null
        : (customJvmArgs ?? this.customJvmArgs),
    compatMode: compatMode ?? this.compatMode,
    prootStartupCommand: clearProotStartupCommand
        ? null
        : (prootStartupCommand ?? this.prootStartupCommand),
    path: clearPath ? null : (path ?? this.path),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'runtime': runtime,
    if (maxMemory != null) 'maxMemory': maxMemory,
    if (javaVersion != null) 'javaVersion': javaVersion,
    if (selectedJar != null) 'selectedJar': selectedJar,
    if (customJvmArgs != null) 'customJvmArgs': customJvmArgs,
    if (compatMode) 'compatMode': true,
    if (prootStartupCommand != null) 'prootStartupCommand': prootStartupCommand,
    if (path != null) 'path': path,
  };

  factory Instance.fromJson(Map<String, dynamic> json) => Instance(
    id: json['id'] as String,
    name: json['name'] as String,
    runtime: json['runtime'] as String? ?? kRuntimeJava,
    maxMemory: json['maxMemory'] as int?,
    javaVersion: json['javaVersion'] as String?,
    selectedJar: json['selectedJar'] as String?,
    customJvmArgs: json['customJvmArgs'] as String?,
    compatMode: json['compatMode'] as bool? ?? false,
    prootStartupCommand: json['prootStartupCommand'] as String?,
    path: json['path'] as String?,
  );
}
