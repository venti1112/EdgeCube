import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../instance/instance.dart';
import '../instance/instance_store.dart';
import '../online/online_service.dart';
import '../theme/theme_store.dart';
import '../tunnel/tunnel_service.dart';
import 'network_store.dart';

/// 一次性数据迁移：把旧版散落在 SharedPreferences 中的配置搬到新的文件式布局
/// （`config/*.json` 与 `instances/index.json` + 各实例 `config.json`）。
///
/// 通过 SharedPreferences 的 [_doneKey] 标志保证只执行一次：所有写入完成后才
/// 落地标志，中途崩溃则下次启动重试（对新文件的覆盖写入是幂等的）。旧键不删除，
/// 作为回退备份。
class ConfigMigration {
  ConfigMigration._();

  /// 迁移完成标志键（带版本号，便于将来追加新一轮迁移）。
  static const _doneKey = 'migrated_to_files_v1';

  // —— 旧版 SharedPreferences 键名 ——
  static const _oldInstances = 'instances';
  static const _oldSelected = 'selected_instance';
  static const _oldThemeMode = 'theme_mode';
  static const _oldSeedColor = 'seed_color';
  static const _oldUseDynamicColor = 'use_dynamic_color';
  static const _oldOnlineEnabled = 'online_services_enabled';
  static const _oldOnlineAsked = 'online_services_asked';
  static const _oldUpnp = 'upnp_enabled';
  static const _oldTunnel = 'tunnel_enabled';
  static const _oldFrpc = 'frpc_config';

  /// 执行迁移；已迁移过则直接返回。应在应用启动、任何新配置读取之前调用。
  static Future<void> run() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneKey) ?? false) return;

    await _migrateInstances(prefs);
    await _migrateTheme(prefs);
    await _migrateOnline(prefs);
    await _migrateNetwork(prefs);

    await prefs.setBool(_doneKey, true);
  }

  /// 旧 `instances`（完整实例 JSON 数组）+ `selected_instance`
  /// → `instances/index.json`（摘要 + 选中项）与各实例目录下的 `config.json`。
  static Future<void> _migrateInstances(SharedPreferences prefs) async {
    final raw = prefs.getString(_oldInstances);
    if (raw == null || raw.isEmpty) return;
    final List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return; // 旧数据损坏，跳过。
    }
    final instances = <Instance>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        try {
          instances.add(Instance.fromJson(e));
        } catch (_) {
          // 跳过个别损坏条目。
        }
      }
    }
    if (instances.isEmpty) return;

    final store = InstanceStore();
    // 各实例的完整配置写入其文件夹下的 config.json（目录缺失会自动创建）。
    for (final inst in instances) {
      await store.saveConfig(inst);
    }
    final selected = prefs.getString(_oldSelected);
    final selectedId =
        (selected != null && instances.any((i) => i.id == selected))
        ? selected
        : instances.first.id;
    final summaries = instances
        .map((i) => InstanceSummary(id: i.id, name: i.name))
        .toList();
    await store.saveIndex(summaries, selectedId);
  }

  /// 旧主题键 → `config/theme.json`。
  static Future<void> _migrateTheme(SharedPreferences prefs) async {
    final mode = prefs.getString(_oldThemeMode);
    if (mode != null) {
      await ThemeStore.save(
        ThemeMode.values.firstWhere(
          (m) => m.name == mode,
          orElse: () => ThemeMode.system,
        ),
      );
    }
    final seed = prefs.getInt(_oldSeedColor);
    if (seed != null) await ThemeStore.saveSeedColor(Color(seed));
    final useDynamic = prefs.getBool(_oldUseDynamicColor);
    if (useDynamic != null) await ThemeStore.saveUseDynamicColor(useDynamic);
  }

  /// 旧在线服务键 → `config/online.json`。
  static Future<void> _migrateOnline(SharedPreferences prefs) async {
    final enabled = prefs.getBool(_oldOnlineEnabled);
    final asked = prefs.getBool(_oldOnlineAsked);
    if (enabled == null && asked == null) return;
    await OnlineService.importState(enabled: enabled, asked: asked);
  }

  /// 旧网络映射键 → `config/network.json`。
  static Future<void> _migrateNetwork(SharedPreferences prefs) async {
    final upnp = prefs.getBool(_oldUpnp);
    if (upnp != null) await NetworkStore.saveUpnpEnabled(upnp);
    final tunnel = prefs.getBool(_oldTunnel);
    if (tunnel != null) await NetworkStore.saveTunnelEnabled(tunnel);
    final frpc = prefs.getString(_oldFrpc);
    if (frpc != null && frpc.isNotEmpty) {
      try {
        final m = jsonDecode(frpc) as Map<String, dynamic>;
        await NetworkStore.saveFrpc(FrpcConfig.fromJsonMap(m));
      } catch (_) {
        // 损坏的 frpc 配置跳过。
      }
    }
  }
}
