import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'about_platform_io.dart'
    if (dart.library.js_interop) 'about_platform_web.dart';

/// 「关于」页两端设备信息的采集与解析。
///
/// 前端这一侧靠 `device_info_plus` / `package_info_plus`；插件在个别平台
/// 拿不到的字段由 `about_platform_*` 补（Linux 的主机名、内存），仍然拿不到
/// 就显示「未知」—— 这里不抛异常，页面不该因为某个字段缺失就整块报错。
///
/// 后端这一侧调 daemon 的 `core.host` 与 `core.info`。旧版 daemon 没有
/// `core.host` 时只标记 [DaemonDeviceInfo.hostUnsupported]，服务信息照常显示。

/// 前端运行设备的信息。
class ClientDeviceInfo {
  const ClientDeviceInfo({
    this.appVersion = '未知',
    this.platform = '未知',
    this.system = '未知',
    this.device = '未知',
    this.cpuCores,
    this.memoryMb,
  });

  /// 应用版本，形如 `2.0.0+200`。
  final String appVersion;

  /// Android / iOS / Linux / Windows / macOS / Web。
  final String platform;

  /// 操作系统版本（Android 14、Ubuntu 24.04 LTS、浏览器所在平台……）。
  final String system;

  /// 设备型号；桌面端是主机名，Web 端是浏览器名。
  final String device;

  /// CPU 逻辑核心数。
  final int? cpuCores;

  /// 设备总内存（MB）。
  final int? memoryMb;

  String get cpuLabel {
    final cores = cpuCores;
    return cores == null || cores <= 0 ? '未知' : '$cores 核';
  }

  String get memoryLabel => _formatMegabytes(memoryMb);

  /// 采集一次。任何一步失败都退化成「未知」，不把异常抛给页面。
  static Future<ClientDeviceInfo> load() async {
    var system = '未知';
    var device = '未知';
    int? cpuCores = localCpuCores();
    int? memoryMb = localMemoryMb();

    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await plugin.webBrowserInfo;
        system = _asText(web.platform) ?? '未知';
        final browser = _browserLabel(web.browserName);
        device = browser == '浏览器' ? browser : '$browser 浏览器';
        cpuCores = web.hardwareConcurrency ?? cpuCores;
        final memoryGb = web.deviceMemory;
        if (memoryGb != null && memoryGb > 0) {
          memoryMb = (memoryGb * 1024).round();
        }
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final android = await plugin.androidInfo;
            final release = _asText(android.version.release);
            system = _joinNonEmpty([
              release == null ? null : 'Android $release',
              'SDK ${android.version.sdkInt}',
            ], separator: ' · ');
            device = _joinNonEmpty([android.manufacturer, android.model]);
            if (android.physicalRamSize > 0) {
              memoryMb = android.physicalRamSize;
            }
          case TargetPlatform.iOS:
            final ios = await plugin.iosInfo;
            system = _joinNonEmpty([ios.systemName, ios.systemVersion]);
            device = _joinNonEmpty([
              _asText(ios.modelName) ?? ios.model,
              ios.utsname.machine,
            ]);
            if (ios.physicalRamSize > 0) {
              memoryMb = ios.physicalRamSize;
            }
          case TargetPlatform.linux:
            final linux = await plugin.linuxInfo;
            system =
                _asText(linux.prettyName) ??
                _joinNonEmpty([linux.name, linux.versionId]);
            device = localHostname() ?? '未知';
          case TargetPlatform.windows:
            final windows = await plugin.windowsInfo;
            system = _joinNonEmpty([
              windows.productName,
              windows.displayVersion,
            ]);
            device = _asText(windows.computerName) ?? '未知';
            if (windows.numberOfCores > 0) {
              cpuCores = windows.numberOfCores;
            }
            if (windows.systemMemoryInMegabytes > 0) {
              memoryMb = windows.systemMemoryInMegabytes;
            }
          case TargetPlatform.macOS:
            final macos = await plugin.macOsInfo;
            system =
                'macOS ${macos.majorVersion}.${macos.minorVersion}.${macos.patchVersion}';
            device =
                _asText(macos.computerName) ?? _asText(macos.modelName) ?? '未知';
            if (macos.activeCPUs > 0) cpuCores = macos.activeCPUs;
            // `memorySize` 是字节（sysctl hw.memsize）。
            final macMemoryMb = macos.memorySize ~/ (1024 * 1024);
            if (macMemoryMb > 0) memoryMb = macMemoryMb;
          case TargetPlatform.fuchsia:
            break;
        }
      }
    } catch (_) {
      // 插件不可用（测试环境、平台不支持）时保留基础字段，不把整页拖进错误态。
    }

    return ClientDeviceInfo(
      appVersion: await _loadAppVersion(),
      platform: _platformLabel(),
      system: system,
      device: device,
      cpuCores: cpuCores,
      memoryMb: memoryMb,
    );
  }
}

/// 后端运行设备的静态信息（`core.host`）。
class DaemonHostInfo {
  const DaemonHostInfo({
    this.hostname,
    this.osName,
    this.osVersion,
    this.kernelVersion,
    this.arch,
    this.cpuBrand,
    this.cpuCores = 0,
    this.cpuPhysicalCores,
    this.memoryTotalMb = 0,
    this.uptimeSecs = 0,
  });

  final String? hostname;
  final String? osName;
  final String? osVersion;
  final String? kernelVersion;
  final String? arch;
  final String? cpuBrand;
  final int cpuCores;
  final int? cpuPhysicalCores;
  final int memoryTotalMb;
  final int uptimeSecs;

  factory DaemonHostInfo.fromJson(Map<String, dynamic> json) => DaemonHostInfo(
    hostname: _asText(json['hostname']),
    osName: _asText(json['os_name']),
    osVersion: _asText(json['os_version']),
    kernelVersion: _asText(json['kernel_version']),
    arch: _asText(json['arch']),
    cpuBrand: _asText(json['cpu_brand']),
    cpuCores: _asInt(json['cpu_cores']),
    cpuPhysicalCores: _asIntOrNull(json['cpu_physical_cores']),
    memoryTotalMb: _asInt(json['memory_total_mb']),
    uptimeSecs: _asInt(json['uptime_secs']),
  );

  String get systemLabel => _joinNonEmpty([osName, osVersion]);

  String get cpuCoresLabel {
    if (cpuCores <= 0) return '未知';
    final physical = cpuPhysicalCores;
    if (physical == null || physical <= 0 || physical == cpuCores) {
      return '$cpuCores 核';
    }
    return '$cpuCores 核（$physical 物理）';
  }

  String get memoryLabel => _formatMegabytes(memoryTotalMb);

  String get uptimeLabel => _humanizeSeconds(uptimeSecs);
}

/// 后端设备 + 守护进程服务信息的合并结果。
class DaemonDeviceInfo {
  const DaemonDeviceInfo({
    this.host,
    this.info = const <String, dynamic>{},
    this.hostUnsupported = false,
  });

  /// `core.host` 的解析结果；旧版 daemon 没有这个方法时为 null。
  final DaemonHostInfo? host;

  /// `core.info` 的原始结果，用来显示守护进程版本与运行时长。
  final Map<String, dynamic> info;

  /// daemon 不认识 `core.host`（App 比 daemon 新）。
  final bool hostUnsupported;

  String? get version => _asText(info['version']);

  String get daemonLabel {
    final uptimeMs = _asIntOrNull(info['uptime_ms']);
    final uptime = uptimeMs != null && uptimeMs > 0
        ? _humanizeSeconds(uptimeMs ~/ 1000)
        : _asText(info['uptime_human']);
    return _joinNonEmpty([
      version,
      uptime == null ? null : '已运行 $uptime',
    ], separator: ' · ');
  }
}

/// 前端运行设备（当前打开 App 的机器）。
final clientDeviceInfoProvider = FutureProvider<ClientDeviceInfo>(
  (ref) => ClientDeviceInfo.load(),
);

/// 后端运行设备（daemon 所在机器）；未连接时为 null。
///
/// 连接变化会让本 Provider 重跑，所以重连后信息会自动更新。
final daemonDeviceInfoProvider = FutureProvider<DaemonDeviceInfo?>((ref) async {
  final client = ref.watch(daemonClientProvider);
  if (client == null) return null;

  DaemonHostInfo? host;
  var hostUnsupported = false;
  try {
    host = DaemonHostInfo.fromJson(await client.callObject('core.host'));
  } on DaemonException catch (error) {
    // 旧版 daemon 没有 core.host：保留服务信息，别整张卡报错。
    if (!error.isMethodNotFound) rethrow;
    hostUnsupported = true;
  }

  final info = await client.callObject('core.info');
  return DaemonDeviceInfo(
    host: host,
    info: info,
    hostUnsupported: hostUnsupported,
  );
});

Future<String> _loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isEmpty) return '未知';
    final build = info.buildNumber.trim();
    return build.isEmpty ? version : '$version+$build';
  } catch (_) {
    return '未知';
  }
}

String _platformLabel() {
  if (kIsWeb) return 'Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

String _browserLabel(BrowserName name) => switch (name) {
  BrowserName.firefox => 'Firefox',
  BrowserName.samsungInternet => 'Samsung Internet',
  BrowserName.opera => 'Opera',
  BrowserName.msie => 'Internet Explorer',
  BrowserName.edge => 'Edge',
  BrowserName.chrome => 'Chrome',
  BrowserName.safari => 'Safari',
  BrowserName.unknown => '浏览器',
};

String? _asText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;

int? _asIntOrNull(Object? value) => value is num ? value.toInt() : null;

String _joinNonEmpty(Iterable<String?> parts, {String separator = ' '}) {
  final values = <String>[];
  final seen = <String>{};
  for (final part in parts) {
    final value = _asText(part);
    if (value == null) continue;
    if (!seen.add(value.toLowerCase())) continue;
    values.add(value);
  }
  return values.isEmpty ? '未知' : values.join(separator);
}

String _formatMegabytes(int? mb) {
  if (mb == null || mb <= 0) return '未知';
  if (mb < 1024) return '$mb MB';
  final gb = mb / 1024;
  final text = gb
      .toStringAsFixed(gb >= 100 ? 0 : 1)
      .replaceFirst(RegExp(r'\.0$'), '');
  return '$text GB';
}

String _humanizeSeconds(int seconds) {
  if (seconds <= 0) return '未知';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (days > 0) return '$days 天 $hours 小时';
  if (hours > 0) return '$hours 小时 $minutes 分';
  if (minutes > 0) return '$minutes 分 $secs 秒';
  return '$secs 秒';
}
