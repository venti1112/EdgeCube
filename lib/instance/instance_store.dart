import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/config_store.dart';
import '../files/storage_permission.dart';
import 'instance.dart';

/// 解析所有实例文件夹所在的根目录。
///
/// 默认指向共享内部存储 `EdgeCube/instances/`；测试可注入临时目录。
/// 该目录存放各实例的服务端工作文件夹（jar、世界存档等），与配置文件分离。
typedef InstancesRootResolver = Future<Directory> Function();

/// 默认实例根目录 `<storage>/EdgeCube/instances`。
Future<Directory> defaultInstancesRoot() async {
  final externalRoot = await StoragePermission.externalStorageRoot();
  if (externalRoot != null && externalRoot.isNotEmpty) {
    return Directory(p.join(externalRoot, 'EdgeCube', 'instances'));
  }
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'EdgeCube', 'instances'));
}

/// 旧版实例根目录 `<documents>/instances`，用于一次性数据迁移。
Future<Directory> legacyPrivateInstancesRoot() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'instances'));
}

/// 实例索引与单实例配置的文件持久化。
///
/// 配置统一存放在应用文档目录的 `config/` 下：
/// - `config/instances.json`：轻量索引，存选中项 id 与全部实例的
///   `{id, name}` 摘要，供实例选择列表读取（不加载完整启动配置）；
/// - `config/instances/<id>.json`：单个实例的完整启动配置。
///
/// 实例的服务端工作文件夹（jar、世界存档等）仍由 [InstanceController]
/// 通过 [defaultInstancesRoot] 管理，与本类的配置存储分离。
class InstanceStore {
  static const String _indexFileName = 'instances.json';
  static const String _instancesSubDir = 'instances';
  static const String _selectedKey = 'selected';
  static const String _instancesKey = 'instances';

  Future<File> _indexFile() async {
    final dir = await ConfigStore.configDir();
    return File(p.join(dir.path, _indexFileName));
  }

  Future<File> _configFile(String id) async {
    final dir = await ConfigStore.configDir();
    return File(p.join(dir.path, _instancesSubDir, '$id.json'));
  }

  /// 读取实例索引（摘要列表）。文件缺失或损坏时返回空列表。
  Future<List<InstanceSummary>> loadSummaries() async {
    final map = await ConfigStore.readJsonFile(await _indexFile());
    final list = map[_instancesKey];
    if (list is! List) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(InstanceSummary.fromJson)
        .toList();
  }

  /// 读取选中实例 id。
  Future<String?> loadSelectedId() async {
    final map = await ConfigStore.readJsonFile(await _indexFile());
    return map[_selectedKey] as String?;
  }

  /// 写入索引：摘要列表 + 选中项。
  Future<void> saveIndex(
    List<InstanceSummary> summaries,
    String? selectedId,
  ) async {
    await ConfigStore.writeJsonFile(await _indexFile(), {
      _selectedKey: selectedId,
      _instancesKey: summaries.map((e) => e.toJson()).toList(),
    });
  }

  /// 读取单个实例的完整配置；文件缺失返回 null。
  Future<Instance?> loadConfig(String id) async {
    final file = await _configFile(id);
    if (!await file.exists()) return null;
    final map = await ConfigStore.readJsonFile(file);
    if (map.isEmpty) return null;
    return Instance.fromJson(map);
  }

  /// 写入单个实例的完整配置到 `config/instances/<id>.json`。
  Future<void> saveConfig(Instance instance) async {
    await ConfigStore.writeJsonFile(
      await _configFile(instance.id),
      instance.toJson(),
    );
  }

  /// 删除单个实例的配置文件 `config/instances/<id>.json`（若存在）。
  Future<void> deleteConfig(String id) async {
    final file = await _configFile(id);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
