import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'instance.dart';

/// 实例元数据与选中项的本地持久化。
///
/// 仅负责键值读写；文件夹的创建由 [InstanceController] 处理。
class InstanceStore {
  static const String _instancesKey = 'instances';
  static const String _selectedKey = 'selected_instance';

  Future<List<Instance>> loadInstances() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_instancesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Instance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveInstances(List<Instance> instances) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(instances.map((e) => e.toJson()).toList());
    await prefs.setString(_instancesKey, raw);
  }

  Future<String?> loadSelectedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedKey);
  }

  Future<void> saveSelectedId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_selectedKey);
    } else {
      await prefs.setString(_selectedKey, id);
    }
  }
}
