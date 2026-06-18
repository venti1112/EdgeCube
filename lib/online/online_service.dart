import 'package:android_cn_oaid/android_cn_oaid.dart';
import 'package:flutter/foundation.dart';

import '../config/config_store.dart';

/// 在线服务管理器：管理在线服务总开关状态与设备唯一标识。
///
/// 设备 ID 规则：
/// - 若设备支持 OAID / AAID，则获取后加上前缀 `AA`；
/// - 若不支持，则回退到 GUID 并加上前缀 `GG`。
///
/// 开关状态与设备 ID 一并保存在 `config/online.json`，只要开关打开且尚无
/// 设备 ID 就自动获取并保存；已有则直接复用（对应"开→关→开"场景）。
class OnlineService extends ChangeNotifier {
  static const _fileName = 'online.json';
  static const _enabledKey = 'enabled';
  static const _askedKey = 'asked';
  static const _deviceIdKey = 'deviceId';

  bool _enabled = false;
  bool _asked = false;
  String? _deviceId;

  /// 当前在线服务是否启用。
  bool get enabled => _enabled;

  /// 是否已询问过用户（首次启动弹窗已展示）。
  bool get asked => _asked;

  /// 设备唯一 ID（仅在启用后才有值）。
  String? get deviceId => _deviceId;

  /// 供数据迁移使用：直接写入持久化的 enabled/asked，不触发设备 ID 生成等副作用。
  static Future<void> importState({bool? enabled, bool? asked}) async {
    final m = await ConfigStore.readConfig(_fileName);
    if (enabled != null) m[_enabledKey] = enabled;
    if (asked != null) m[_askedKey] = asked;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 从 `config/online.json` 读取持久化状态，若已启用则同时加载 / 生成设备 ID。
  Future<void> init() async {
    final m = await ConfigStore.readConfig(_fileName);
    _enabled = m[_enabledKey] as bool? ?? false;
    _asked = m[_askedKey] as bool? ?? false;
    _deviceId = m[_deviceIdKey] as String?;
    if (_enabled) {
      await _ensureDeviceId();
    }
  }

  /// 标记"已询问"状态，控制首次启动弹窗只展示一次。
  Future<void> markAsked() async {
    _asked = true;
    final m = await ConfigStore.readConfig(_fileName);
    m[_askedKey] = true;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 设置在线服务总开关。开启时自动确保设备 ID 存在。
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final m = await ConfigStore.readConfig(_fileName);
    m[_enabledKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
    if (value) {
      await _ensureDeviceId();
    }
    notifyListeners();
  }

  /// 若已有设备 ID 则直接复用，否则获取新 ID 并写入 `config/online.json`。
  Future<void> _ensureDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return;
    await _generateAndSaveDeviceId();
  }

  /// 调用 android_cn_oaid 获取设备标识并持久化到 `config/online.json`。
  Future<void> _generateAndSaveDeviceId() async {
    final plugin = AndroidCnOaid();
    // 隐私合规：在用户同意后才调用 register()。
    await plugin.register();

    String id;
    try {
      final supported = await plugin.isSupported();
      if (supported) {
        final oaid = await plugin.getOAID();
        if (oaid != null && oaid.isNotEmpty) {
          id = 'AA$oaid';
        } else {
          // 声称支持但实际获取为空，回退 GUID。
          final guid = await plugin.getGUID();
          id = 'GG$guid';
        }
      } else {
        final guid = await plugin.getGUID();
        id = 'GG$guid';
      }
    } catch (_) {
      // 任何异常均回退到 GUID，保证 ID 一定能生成。
      final guid = await plugin.getGUID();
      id = 'GG$guid';
    }

    _deviceId = id;
    final m = await ConfigStore.readConfig(_fileName);
    m[_deviceIdKey] = id;
    await ConfigStore.writeConfig(_fileName, m);
  }
}
