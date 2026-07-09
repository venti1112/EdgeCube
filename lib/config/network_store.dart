import 'dart:io';

import 'package:path/path.dart' as p;

import 'config_store.dart';

/// 网络映射配置（UPnP 开关、FRP 隧道开关）的本地持久化。
///
/// 全部存于 `config/network.json`。FRP 配置通过直接编辑 `config/frpc.toml`
/// 文件完成，不再提供表单界面。
///
class NetworkStore {
  NetworkStore._();

  static const String _fileName = 'network.json';
  static const String _upnpKey = 'upnpEnabled';
  static const String _upnpExternalPortKey = 'upnpExternalPort';
  static const String _upnpProtocolKey = 'upnpProtocol';
  static const String _tunnelKey = 'tunnelEnabled';
  static const String _frpcRuntimeIdKey = 'frpcRuntimeId';
  static const String _useMirrorKey = 'useMirror';
  static const String _mirrorAskedKey = 'mirrorAsked';
  static const String _qqGroupAskedKey = 'qqGroupAsked';

  /// 用户可直接编辑的自定义 frpc.toml 文件路径（`config/frpc.toml`）。
  static Future<File> customFrpcFile() async {
    final dir = await ConfigStore.configDir();
    return File(p.join(dir.path, 'frpc.toml'));
  }

  /// 确保自定义配置文件存在；不存在时写入默认模板。
  /// 返回该文件。
  static Future<File> ensureCustomFrpcFile() async {
    final file = await customFrpcFile();
    if (!await file.exists()) {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(_defaultTemplate(), flush: true);
    }
    return file;
  }

  static String _defaultTemplate() {
    return '''# frpc 配置文件
# 请根据你的 frps 服务器信息修改以下内容
serverAddr = "frp.example.com"
serverPort = 7000
# auth.token = "your_token"

transport.protocol = "tcp"
transport.tls.enable = true

log.to = "console"
log.level = "info"

[[proxies]]
name = "minecraft"
type = "tcp"
localIP = "127.0.0.1"
localPort = 25565
remotePort = 25566
# transport.useEncryption = true
# transport.useCompression = true
''';
  }

  /// 是否使用镜像源（MSL 开服器）下载服务端，默认关闭。
  static Future<bool> loadUseMirror() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_useMirrorKey] as bool? ?? false;
  }

  static Future<void> saveUseMirror(bool enabled) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_useMirrorKey] = enabled;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  /// 是否已询问过用户「是否启用镜像源」（首次启动弹窗只展示一次）。
  static Future<bool> loadMirrorAsked() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_mirrorAskedKey] as bool? ?? false;
  }

  static Future<void> saveMirrorAsked(bool asked) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_mirrorAskedKey] = asked;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  /// 是否已询问过用户「加入 QQ 群」（首次启动弹窗只展示一次）。
  static Future<bool> loadQqGroupAsked() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_qqGroupAskedKey] as bool? ?? false;
  }

  static Future<void> saveQqGroupAsked(bool asked) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_qqGroupAskedKey] = asked;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  static Future<bool> loadUpnpEnabled() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_upnpKey] as bool? ?? false;
  }

  static Future<void> saveUpnpEnabled(bool enabled) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_upnpKey] = enabled;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  /// 读取 UPnP 自定义外网端口；未设置返回 null（表示使用服务端端口）。
  static Future<int?> loadUpnpExternalPort() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    final value = configMap[_upnpExternalPortKey];
    if (value is int) return value;
    return null;
  }

  static Future<void> saveUpnpExternalPort(int? port) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    if (port == null) {
      configMap.remove(_upnpExternalPortKey);
    } else {
      configMap[_upnpExternalPortKey] = port;
    }
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  /// 读取 UPnP 映射协议；默认 'tcp'（Java 版），基岩版应设为 'udp'。
  static Future<String> loadUpnpProtocol() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_upnpProtocolKey] as String? ?? 'tcp';
  }

  static Future<void> saveUpnpProtocol(String protocol) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_upnpProtocolKey] = protocol;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  static Future<bool> loadTunnelEnabled() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_tunnelKey] as bool? ?? false;
  }

  static Future<void> saveTunnelEnabled(bool enabled) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_tunnelKey] = enabled;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  static Future<String?> loadFrpcRuntimeId() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_frpcRuntimeIdKey] as String?;
  }

  static Future<void> saveFrpcRuntimeId(String? runtimeId) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    if (runtimeId == null) {
      configMap.remove(_frpcRuntimeIdKey);
    } else {
      configMap[_frpcRuntimeIdKey] = runtimeId;
    }
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  static const String _betaUpdatesKey = 'enableBetaUpdates';

  static Future<bool> loadBetaUpdates() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_betaUpdatesKey] as bool? ?? true;
  }

  static Future<void> saveBetaUpdates(bool enabled) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_betaUpdatesKey] = enabled;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  /// 自定义 DNS 服务器列表键。存储为逗号分隔的字符串（如 "8.8.8.8,1.1.1.1"）。
  /// 原生侧（Kotlin）直接从 `<filesDir>/config/network.json` 读取该字段，
  /// 用于 proot rootfs 的 /etc/resolv.conf、PHP 的 /sdcard/resolv.conf
  /// 以及 JVM 的 -Dsun.net.spi.nameserver.nameservers 参数。
  static const String _customDnsKey = 'customDns';
  static const String _defaultCustomDns = '8.8.8.8,1.1.1.1';

  /// 读取自定义 DNS 字符串（逗号分隔）；未设置时返回默认值。
  static Future<String> loadCustomDns() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    final value = configMap[_customDnsKey] as String?;
    if (value == null || value.trim().isEmpty) return _defaultCustomDns;
    return value;
  }

  static Future<void> saveCustomDns(String dns) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_customDnsKey] = dns;
    await ConfigStore.writeConfig(_fileName, configMap);
  }
}
