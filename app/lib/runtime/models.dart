/// 运行环境的线上模型。
///
/// 字段名与 daemon 的线上格式一一对应（snake_case）。有哪些厂商、哪些包类型、
/// 本机平台是什么 —— 全部由 daemon 的 `runtime.catalog` 给，前端**不硬编码**。
library;

/// `runtime.catalog` 的返回：厂商 / 包类型表 + 本机平台。
class RuntimeCatalog {
  const RuntimeCatalog({
    required this.providers,
    required this.packageTypes,
    required this.defaultProvider,
    required this.defaultPackageType,
    required this.supported,
    this.host,
  });

  final List<RuntimeProvider> providers;
  final List<RuntimePackageType> packageTypes;
  final String defaultProvider;
  final String defaultPackageType;

  /// 本机平台；`null` = daemon 没说（老版本 daemon）。
  final RuntimeHost? host;

  /// 这台机器有没有对应的构建。false 时入口置灰并说明原因。
  final bool supported;

  factory RuntimeCatalog.fromJson(Map<String, dynamic> json) {
    final host = json['host'];
    return RuntimeCatalog(
      providers: [
        for (final item in _list(json['providers']))
          RuntimeProvider.fromJson(_cast(item)),
      ],
      packageTypes: [
        for (final item in _list(json['package_types']))
          RuntimePackageType.fromJson(_cast(item)),
      ],
      defaultProvider: json['default_provider']?.toString() ?? '',
      defaultPackageType: json['default_package_type']?.toString() ?? '',
      host: host is Map ? RuntimeHost.fromJson(host.cast<String, dynamic>()) : null,
      supported: json['supported'] == true,
    );
  }
}

class RuntimeProvider {
  const RuntimeProvider({
    required this.id,
    required this.name,
    required this.homepage,
    required this.packageTypes,
  });

  final String id;
  final String name;
  final String homepage;
  final List<String> packageTypes;

  factory RuntimeProvider.fromJson(Map<String, dynamic> json) => RuntimeProvider(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    homepage: json['homepage']?.toString() ?? '',
    packageTypes: [
      for (final item in _list(json['package_types'])) item.toString(),
    ],
  );
}

class RuntimePackageType {
  const RuntimePackageType({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  factory RuntimePackageType.fromJson(Map<String, dynamic> json) =>
      RuntimePackageType(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
      );
}

class RuntimeHost {
  const RuntimeHost({
    required this.os,
    required this.arch,
    required this.archiveType,
    this.libc,
  });

  final String os;
  final String arch;
  final String archiveType;

  /// 只有 Linux 有（glibc / musl）。
  final String? libc;

  factory RuntimeHost.fromJson(Map<String, dynamic> json) => RuntimeHost(
    os: json['os']?.toString() ?? '',
    arch: json['arch']?.toString() ?? '',
    archiveType: json['archive_type']?.toString() ?? '',
    libc: json['libc']?.toString(),
  );

  /// 展示用的短句（`linux · x64`）。
  String get label => '$os · $arch';
}

/// `runtime.versions` 的返回。
class RuntimeVersions {
  const RuntimeVersions({
    required this.provider,
    required this.packageType,
    required this.os,
    required this.arch,
    required this.versions,
    this.all = false,
  });

  final String provider;
  final String packageType;

  /// 这一份是不是「全部历史版本」。
  ///
  /// `false` = 只有最新那个（daemon 的默认行为），页面据此决定要不要显示
  /// 「历史版本」按钮；已经拉到全部了就没必要再显示。
  final bool all;

  /// 这次要装的本机平台（daemon 按它筛的）。
  final String os;
  final String arch;

  /// 大版本降序（新的在前）。
  final List<RuntimeVersion> versions;

  factory RuntimeVersions.fromJson(Map<String, dynamic> json) => RuntimeVersions(
    provider: json['provider']?.toString() ?? '',
    packageType: json['package_type']?.toString() ?? '',
    os: json['os']?.toString() ?? '',
    arch: json['arch']?.toString() ?? '',
    all: json['all'] == true,
    versions: [
      for (final item in _list(json['versions']))
        RuntimeVersion.fromJson(_cast(item)),
    ],
  );
}

/// 一条可装的版本。
///
/// 形状对两家厂商是同一套（daemon 那边压平过了）：
///
/// * [version] —— 装的时候原样传回去。JDK 是 `21`，frp 是 `0.71.0`；
/// * [label] —— 列表主行。JDK 是 `Java 21`，frp 是 `0.71.0`；
/// * [subtitle] —— 副行。JDK 是完整版本号 `21.0.12.1`，frp 是发布日期。
///
/// **前端不拼这些字符串**：厂商不同、版本号的读法就不同，那是 daemon 的知识
/// （厂商表里的 `version_prefix`），前端只显示。
class RuntimeVersion {
  const RuntimeVersion({
    required this.version,
    required this.label,
    this.subtitle = '',
  });

  final String version;
  final String label;
  final String subtitle;

  factory RuntimeVersion.fromJson(Map<String, dynamic> json) => RuntimeVersion(
    version: json['version']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    subtitle: json['subtitle']?.toString() ?? '',
  );
}

/// `runtime.list` 的返回。
class RuntimeEnvList {
  const RuntimeEnvList({required this.environments, required this.dir});

  final List<RuntimeEnv> environments;

  /// 环境装在哪（`<数据根>/runtimes`），展示用。
  final String dir;

  static const RuntimeEnvList empty = RuntimeEnvList(environments: [], dir: '');

  factory RuntimeEnvList.fromJson(Map<String, dynamic> json) => RuntimeEnvList(
    environments: [
      for (final item in _list(json['environments']))
        RuntimeEnv.fromJson(_cast(item)),
    ],
    dir: json['dir']?.toString() ?? '',
  );
}

/// 一个运行环境。
///
/// 状态机：`downloading → extracting → installed`，任何一步失败落成
/// `failed`（带 [stage] 与 [error]）。进行中的两态会有后台任务在跑，
/// 进度看 [taskId] 对应的 `download.progress` 事件。
class RuntimeEnv {
  const RuntimeEnv({
    required this.id,
    required this.vendor,
    required this.packageType,
    required this.version,
    required this.versionName,
    required this.vendorVersion,
    required this.os,
    required this.arch,
    required this.archiveType,
    required this.fileName,
    required this.state,
    required this.createdAtMs,
    this.size,
    this.supportTerm,
    this.stage,
    this.error,
    this.taskId,
    this.home,
    this.binary,
    this.installedAtMs,
  });

  /// `zulu-jdk-21-linux-x64`：可读且稳定，一个组合只有一个环境。
  final String id;
  final String vendor;
  final String packageType;

  /// 装的是哪个版本：JDK 是 `21`，frp 是 `0.71.0`。
  final String version;

  /// 更完整的版本串（展示副标题）：JDK 是 `21.0.12.1`；frp 与 [version] 相同。
  final String versionName;

  /// 厂商自己的版本号（Zulu 的 `21.52.203`）。frp 没有这一层，空串。
  final String vendorVersion;
  final String os;
  final String arch;
  final String archiveType;
  final String fileName;

  final RuntimeEnvState state;

  /// 失败发生在哪一步；重试据此决定要不要重新下载（daemon 侧已经处理了）。
  final RuntimeStage? stage;
  final String? error;

  /// 下载任务 id；非空 = 前端可以拿它订阅 `download.progress` 看进度。
  final String? taskId;

  final int? size;
  final String? supportTerm;

  /// 解压出来的「家目录」与可执行文件（相对环境目录）。
  /// JDK 是 `…/bin/java`，frp 是包里的 `frpc`。
  final String? home;
  final String? binary;

  final int createdAtMs;
  final int? installedAtMs;

  factory RuntimeEnv.fromJson(Map<String, dynamic> json) => RuntimeEnv(
    id: json['id']?.toString() ?? '',
    vendor: json['vendor']?.toString() ?? '',
    packageType: json['package_type']?.toString() ?? '',
    version: json['version']?.toString() ?? '',
    versionName: json['version_name']?.toString() ?? '',
    vendorVersion: json['vendor_version']?.toString() ?? '',
    os: json['os']?.toString() ?? '',
    arch: json['arch']?.toString() ?? '',
    archiveType: json['archive_type']?.toString() ?? '',
    fileName: json['file_name']?.toString() ?? '',
    state: RuntimeEnvState.parse(json['state']),
    stage: RuntimeStage.parse(json['stage']),
    error: json['error']?.toString(),
    taskId: json['task_id']?.toString(),
    size: _int(json['size']),
    supportTerm: json['support_term']?.toString(),
    home: json['home']?.toString(),
    binary: json['binary']?.toString(),
    installedAtMs: _int(json['installed_at_ms']),
    createdAtMs: _int(json['created_at_ms']) ?? 0,
  );

  bool get isBusy => state == RuntimeEnvState.downloading ||
      state == RuntimeEnvState.extracting;

  /// `linux · x64`。
  String get platformLabel => '$os · $arch';
}

/// 环境的显示名：`Zulu JDK · 21.0.12.1` / `frp frp 客户端 · 0.71.0`。
///
/// 厂商与包类型的**显示名**来自 catalog（daemon 给的），catalog 没带上时退回
/// id 本身 —— 零硬编码的口径，别在前端拼一张名字表。
String runtimeEnvTitle(RuntimeCatalog? catalog, RuntimeEnv env) {
  String? providerName;
  for (final provider in catalog?.providers ?? const <RuntimeProvider>[]) {
    if (provider.id == env.vendor) providerName = provider.name;
  }
  String? typeName;
  for (final type in catalog?.packageTypes ?? const <RuntimePackageType>[]) {
    if (type.id == env.packageType) typeName = type.name;
  }
  // 版本那一截也不拼厂商相关的前缀（JDK 才该有 `Java `），直接给版本串
  final version = env.versionName.isNotEmpty ? env.versionName : env.version;
  return '${providerName ?? env.vendor} ${typeName ?? env.packageType} · $version';
}

enum RuntimeEnvState {
  downloading,
  extracting,
  installed,
  failed;

  static RuntimeEnvState parse(Object? raw) => switch (raw) {
    'downloading' => RuntimeEnvState.downloading,
    'extracting' => RuntimeEnvState.extracting,
    'installed' => RuntimeEnvState.installed,
    'failed' => RuntimeEnvState.failed,
    _ => RuntimeEnvState.failed,
  };

  /// 给人看的状态词。
  String get label => switch (this) {
    RuntimeEnvState.downloading => '下载中',
    RuntimeEnvState.extracting => '解压中',
    RuntimeEnvState.installed => '已安装',
    RuntimeEnvState.failed => '失败',
  };
}

/// 失败发生在哪一步。重试时 daemon 据此决定要不要重新下载。
enum RuntimeStage {
  download,
  extract;

  static RuntimeStage? parse(Object? raw) => switch (raw) {
    'download' => RuntimeStage.download,
    'extract' => RuntimeStage.extract,
    _ => null,
  };

  String get label => switch (this) {
    RuntimeStage.download => '下载',
    RuntimeStage.extract => '解压',
  };
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

List<dynamic> _list(Object? raw) => raw is List ? raw : const [];

Map<String, dynamic> _cast(Object? raw) =>
    raw is Map ? raw.cast<String, dynamic>() : const {};

int? _int(Object? raw) => switch (raw) {
  int value => value,
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};
