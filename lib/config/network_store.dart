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
    final m = await ConfigStore.readConfig(_fileName);
    return m[_useCustomFrpcKey] as bool? ?? false;
  }

  static Future<void> saveUseCustomFrpc(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_useCustomFrpcKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 是否使用镜像源（MSL 开服器）下载服务端，默认关闭。
  static Future<bool> loadUseMirror() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_useMirrorKey] as bool? ?? false;
  }

  static Future<void> saveUseMirror(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_useMirrorKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 是否已询问过用户「是否启用镜像源」（首次启动弹窗只展示一次）。
  static Future<bool> loadMirrorAsked() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_mirrorAskedKey] as bool? ?? false;
  }

  static Future<void> saveMirrorAsked(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_mirrorAskedKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 是否已询问过用户「加入 QQ 群」（首次启动弹窗只展示一次）。
  static Future<bool> loadQqGroupAsked() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_qqGroupAskedKey] as bool? ?? false;
  }

  static Future<void> saveQqGroupAsked(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_qqGroupAskedKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<bool> loadUpnpEnabled() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_upnpKey] as bool? ?? false;
  }

  static Future<void> saveUpnpEnabled(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_upnpKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<bool> loadTunnelEnabled() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_tunnelKey] as bool? ?? false;
  }

  static Future<void> saveTunnelEnabled(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_tunnelKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 读取已保存的 frpc 配置；未保存过返回 null。
  static Future<FrpcConfig?> loadFrpc() async {
    final m = await ConfigStore.readConfig(_fileName);
    final frpc = m[_frpcKey];
    if (frpc is! Map<String, dynamic>) return null;
    return FrpcConfig.fromJsonMap(frpc);
  }

  static Future<void> saveFrpc(FrpcConfig config) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_frpcKey] = config.toJsonMap();
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<String?> loadFrpcRuntimeId() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_frpcRuntimeIdKey] as String?;
  }

  static Future<void> saveFrpcRuntimeId(String? value) async {
    final m = await ConfigStore.readConfig(_fileName);
    if (value == null) {
      m.remove(_frpcRuntimeIdKey);
    } else {
      m[_frpcRuntimeIdKey] = value;
    }
    await ConfigStore.writeConfig(_fileName, m);
  }
}
