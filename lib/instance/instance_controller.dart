import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'instance.dart';
import 'instance_store.dart';

/// 解析所有实例文件夹所在的根目录。
///
/// 默认指向应用私有文档目录下的 `instances/`；测试可注入临时目录。
typedef InstancesRootResolver = Future<Directory> Function();

/// 当新建或重命名导致出现同名实例时抛出。
class DuplicateInstanceNameException implements Exception {
  const DuplicateInstanceNameException(this.name);

  final String name;

  @override
  String toString() => '已存在同名实例：$name';
}

Future<Directory> _defaultInstancesRoot() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'instances'));
}

/// 管理服务器实例的列表、当前选中项与磁盘文件夹。
class InstanceController extends ChangeNotifier {
  InstanceController({
    InstanceStore? store,
    InstancesRootResolver? rootResolver,
  })  : _store = store ?? InstanceStore(),
        _rootResolver = rootResolver ?? _defaultInstancesRoot;

  final InstanceStore _store;
  final InstancesRootResolver _rootResolver;
  final Random _random = Random.secure();

  List<Instance> _instances = [];
  String? _selectedId;
  bool _initialized = false;

  List<Instance> get instances => List.unmodifiable(_instances);
  bool get isInitialized => _initialized;

  Instance? get selected {
    if (_selectedId == null) return null;
    for (final instance in _instances) {
      if (instance.id == _selectedId) return instance;
    }
    return null;
  }

  /// 从持久化存储加载实例列表与选中项，应在应用启动时调用一次。
  Future<void> init() async {
    _instances = await _store.loadInstances();
    final savedId = await _store.loadSelectedId();
    // 选中项可能已被删除，回退到第一个实例。
    if (savedId != null && _instances.any((i) => i.id == savedId)) {
      _selectedId = savedId;
    } else {
      _selectedId = _instances.isNotEmpty ? _instances.first.id : null;
    }
    _initialized = true;
    notifyListeners();
  }

  /// 解析指定实例在磁盘上的文件夹。
  Future<Directory> directoryFor(Instance instance) async {
    final root = await _rootResolver();
    return Directory(p.join(root.path, instance.id));
  }

  /// 新建实例：生成随机文件夹名、创建目录、持久化并自动选中。
  ///
  /// 若已存在同名实例（忽略首尾空白），抛 [DuplicateInstanceNameException]。
  Future<Instance> createInstance(String name) async {
    final trimmed = name.trim();
    if (_isNameTaken(trimmed)) {
      throw DuplicateInstanceNameException(trimmed);
    }
    final id = _generateId();
    final root = await _rootResolver();
    await Directory(p.join(root.path, id)).create(recursive: true);

    final instance = Instance(id: id, name: trimmed);
    _instances = [..._instances, instance];
    _selectedId = id;
    await _store.saveInstances(_instances);
    await _store.saveSelectedId(_selectedId);
    notifyListeners();
    return instance;
  }

  /// 切换当前选中的实例。
  Future<void> select(String id) async {
    if (_selectedId == id) return;
    _selectedId = id;
    await _store.saveSelectedId(id);
    notifyListeners();
  }

  /// 修改指定实例的显示名称。
  ///
  /// 若与其它实例重名（忽略首尾空白），抛 [DuplicateInstanceNameException]。
  Future<void> rename(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (_isNameTaken(trimmed, exceptId: id)) {
      throw DuplicateInstanceNameException(trimmed);
    }
    _instances = [
      for (final instance in _instances)
        if (instance.id == id) instance.copyWith(name: trimmed) else instance,
    ];
    await _store.saveInstances(_instances);
    notifyListeners();
  }

  /// 更新指定实例的启动配置（内存、Java 版本、服务端 jar）。
  Future<void> updateConfig(
    String id, {
    int? maxMemory,
    String? javaVersion,
    String? selectedJar,
  }) async {
    _instances = [
      for (final instance in _instances)
        if (instance.id == id)
          instance.copyWith(
            maxMemory: maxMemory,
            javaVersion: javaVersion,
            selectedJar: selectedJar,
          )
        else
          instance,
    ];
    await _store.saveInstances(_instances);
    notifyListeners();
  }

  /// 删除指定实例：从列表移除、删除磁盘文件夹、持久化；若删的是当前选中项则自动选第一个。
  Future<void> deleteInstance(String id) async {
    final dir = await _rootResolver();
    final instanceDir = Directory(p.join(dir.path, id));
    if (await instanceDir.exists()) {
      await instanceDir.delete(recursive: true);
    }
    _instances = _instances.where((i) => i.id != id).toList();
    if (_selectedId == id) {
      _selectedId = _instances.isNotEmpty ? _instances.first.id : null;
    }
    await _store.saveInstances(_instances);
    await _store.saveSelectedId(_selectedId);
    notifyListeners();
  }

  /// 是否已存在指定名称的实例；[exceptId] 用于改名时排除自身。
  bool _isNameTaken(String name, {String? exceptId}) {
    return _instances.any(
      (instance) => instance.id != exceptId && instance.name == name,
    );
  }

  /// 生成 16 字符的随机十六进制文件夹名。
  String _generateId() {
    const chars = '0123456789abcdef';
    return List.generate(
      16,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }
}
