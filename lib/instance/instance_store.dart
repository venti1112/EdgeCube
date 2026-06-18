import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/config_store.dart';
import 'instance.dart';

/// 解析所有实例文件夹所在的根目录。
///
/// 默认指向应用私有文档目录下的 `instances/`；测试可注入临时目录。
typedef InstancesRootResolver = Future<Directory> Function();

/// 默认实例根目录 `<documents>/instances`。
Future<Directory> defaultInstancesRoot() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'instances'));
}

/// 实例索引与单实例配置的文件持久化。
///
/// 拆分为两层：
/// - `<instancesRoot>/index.json`：轻量索引，存选中项 id 与全部实例的
///   `{id, name}` 摘要，供实例选择列表读取（不加载完整启动配置）；
/// - `<instancesRoot>/<id>/config.json`：单个实例的完整启动配置。
///
/// 本类只做读写，目录创建/删除由 [InstanceController] 负责。
class InstanceStore {
  static const String _indexFileName = 'index.json';
  static const String _configFileName = 'config.json';
  static const String _selectedKey = 'selected';
  static const String _instancesKey = 'instances';

  /// 解析实例根目录；缺省使用 [defaultInstancesRoot]。
  final InstancesRootResolver _rootResolver;

  InstanceStore([InstancesRootResolver? root])
    : _rootResolver = root ?? defaultInstancesRoot;

  File _indexFile(Directory root) => File(p.join(root.path, _indexFileName));

  File _configFile(Directory root, String id) =>
      File(p.join(root.path, id, _configFileName));

  /// 读取实例索引（摘要列表）。文件缺失或损坏时返回空列表。
  Future<List<InstanceSummary>> loadSummaries() async {
    final root = await _rootResolver();
    final map = await ConfigStore.readJsonFile(_indexFile(root));
    final list = map[_instancesKey];
    if (list is! List) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(InstanceSummary.fromJson)
        .toList();
  }

  /// 读取选中实例 id。
  Future<String?> loadSelectedId() async {
    final root = await _rootResolver();
    final map = await ConfigStore.readJsonFile(_indexFile(root));
    return map[_selectedKey] as String?;
  }

  /// 写入索引：摘要列表 + 选中项。
  Future<void> saveIndex(
    List<InstanceSummary> summaries,
    String? selectedId,
  ) async {
    final root = await _rootResolver();
    await ConfigStore.writeJsonFile(_indexFile(root), {
      _selectedKey: selectedId,
      _instancesKey: summaries.map((e) => e.toJson()).toList(),
    });
  }

  /// 读取单个实例的完整配置；文件缺失返回 null。
  Future<Instance?> loadConfig(String id) async {
    final root = await _rootResolver();
    final file = _configFile(root, id);
    if (!await file.exists()) return null;
    final map = await ConfigStore.readJsonFile(file);
    if (map.isEmpty) return null;
    return Instance.fromJson(map);
  }

  /// 写入单个实例的完整配置到其文件夹内的 `config.json`。
  Future<void> saveConfig(Instance instance) async {
    final root = await _rootResolver();
    await ConfigStore.writeJsonFile(
      _configFile(root, instance.id),
      instance.toJson(),
    );
  }
}
