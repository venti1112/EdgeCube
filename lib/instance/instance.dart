/// 运行环境标识：Java 版（JVM 跑 .jar）与 PHP 版（PocketMine 跑 .phar）。
const String kRuntimeJava = 'java';
const String kRuntimePhp = 'php';

/// 实例索引项：仅包含选择列表所需的 [id] 与 [name]。
///
/// 实例选择列表只读取索引（`config/instances.json`），无需加载每个实例
/// 完整的启动配置（那些存在各自的 `config/instances/<id>.json` 中）。
class InstanceSummary {
  const InstanceSummary({required this.id, required this.name});

  final String id;
  final String name;

  InstanceSummary copyWith({String? name}) =>
      InstanceSummary(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory InstanceSummary.fromJson(Map<String, dynamic> json) =>
      InstanceSummary(id: json['id'] as String, name: json['name'] as String);
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
  });

  final String id;
  final String name;
  final String runtime;
  final int? maxMemory;
  final String? javaVersion;
  final String? selectedJar;
  final String? customJvmArgs;
  final bool compatMode;

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
    bool clearMaxMemory = false,
    bool clearJavaVersion = false,
    bool clearSelectedJar = false,
    bool clearCustomJvmArgs = false,
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (runtime != kRuntimeJava) 'runtime': runtime,
    if (maxMemory != null) 'maxMemory': maxMemory,
    if (javaVersion != null) 'javaVersion': javaVersion,
    if (selectedJar != null) 'selectedJar': selectedJar,
    if (customJvmArgs != null) 'customJvmArgs': customJvmArgs,
    if (compatMode) 'compatMode': true,
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
  );
}
