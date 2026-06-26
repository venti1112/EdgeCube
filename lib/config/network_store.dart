import 'dart:io';

import 'package:path/path.dart' as p;

import '../tunnel/tunnel_service.dart';
import 'config_store.dart';

/// 网络映射配置（UPnP 开关、FRP 隧道开关与 frpc 配置）的本地持久化。
///
/// 全部存于 `config/network.json`，取代旧版散落在 SharedPreferences 中的
/// `upnp_enabled` / `tunnel_enabled` / `frpc_config` 三个键。
///
/// 另支持「直接编辑配置文件」：用户可编辑原始 TOML 存于 `config/frpc.toml`，
/// 启用 [loadUseCustomFrpc] 后隧道将使用该文件覆盖表单生成的配置。
class NetworkStore {
  NetworkStore._();

  static const String _fileName = 'network.json';
  static const String _upnpKey = 'upnpEnabled';
  static const String _tunnelKey = 'tunnelEnabled';
  static const String _frpcKey = 'frpc';
  static const String _frpcRuntimeIdKey = 'frpcRuntimeId';
  static const String _useCustomFrpcKey = 'useCustomFrpc';
  static const String _useMirrorKey = 'useMirror';
  static const String _mirrorAskedKey = 'mirrorAsked';
  static const String _qqGroupAskedKey = 'qqGroupAsked';

  /// 用户可直接编辑的自定义 frpc.toml 文件路径（`config/frpc.toml`）。
  static Future<File> customFrpcFile() async {
    final dir = await ConfigStore.configDir();
    return File(p.join(dir.path, 'frpc.toml'));
  }

  /// 确保自定义配置文件存在；不存在时以 [base] 生成的 TOML 作为初始内容写入。
  /// 返回该文件。
  static Future<File> ensureCustomFrpcFile(FrpcConfig base) async {
    final file = await customFrpcFile();
    if (!await file.exists()) {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(base.toToml(), flush: true);
    }
    return file;
  }

  /// 是否启用「使用自定义配置文件」模式。
  static Future<bool> loadUseCustomFrpc() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_useCustomFrpcKey] as bool? ?? false;
  }

  static Future<void> saveUseCustomFrpc(bool enabled) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_useCustomFrpcKey] = enabled;
    await ConfigStore.writeConfig(_fileName, configMap);
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

  static Future<bool> loadTunnelEnabled() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    return configMap[_tunnelKey] as bool? ?? false;
  }

  static Future<void> saveTunnelEnabled(bool enabled) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_tunnelKey] = enabled;
    await ConfigStore.writeConfig(_fileName, configMap);
  }

  /// 读取已保存的 frpc 配置；未保存过返回 null。
  static Future<FrpcConfig?> loadFrpc() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    final frpc = configMap[_frpcKey];
    if (frpc is! Map<String, dynamic>) return null;
    return FrpcConfig.fromJsonMap(frpc);
  }

  static Future<void> saveFrpc(FrpcConfig config) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_frpcKey] = config.toJsonMap();
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
}
