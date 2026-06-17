import 'dart:io';

import 'package:android_cn_oaid/android_cn_oaid.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线服务管理器：管理在线服务总开关状态与设备唯一标识。
///
/// 设备 ID 规则：
/// - 若设备支持 OAID / AAID，则获取后加上前缀 `AA`；
/// - 若不支持，则回退到 GUID 并加上前缀 `GG`。
///
/// ID 保存在应用文档目录下的 `device_id.txt`，只要开关打开且文件
/// 不存在就自动获取并保存；已有则直接复用（对应“开→关→开”场景）。
class OnlineService extends ChangeNotifier {
  static const _enabledKey = 'online_services_enabled';
  static const _askedKey = 'online_services_asked';
  static const _idFileName = 'device_id.txt';

  bool _enabled = false;
  bool _asked = false;
  String? _deviceId;

  /// 当前在线服务是否启用。
  bool get enabled => _enabled;

  /// 是否已询问过用户（首次启动弹窗已展示）。
  bool get asked => _asked;

  /// 设备唯一 ID（仅在启用后才有值）。
  String? get deviceId => _deviceId;

  /// 从 SharedPreferences 读取持久化状态，若已启用则同时加载 / 生成设备 ID。
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _asked = prefs.getBool(_askedKey) ?? false;
    if (_enabled) {
      await _ensureDeviceId();
    }
  }

  /// 标记"已询问"状态，控制首次启动弹窗只展示一次。
  Future<void> markAsked() async {
    _asked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
  }

  /// 设置在线服务总开关。开启时自动确保设备 ID 存在。
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) {
      await _ensureDeviceId();
    }
    notifyListeners();
  }

  /// 若设备 ID 文件已存在则读取，否则获取新 ID 并写入文件。
  Future<void> _ensureDeviceId() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_idFileName');
    if (await file.exists()) {
      final content = (await file.readAsString()).trim();
      if (content.isNotEmpty) {
        _deviceId = content;
        return;
      }
    }
    await _generateAndSaveDeviceId(file);
  }

  /// 调用 android_cn_oaid 获取设备标识并持久化。
  Future<void> _generateAndSaveDeviceId(File file) async {
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
    await file.writeAsString(id);
  }
}
