import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'instance.dart';
import 'instance_store.dart';

/// 当新建或重命名导致出现同名实例时抛出。
class DuplicateInstanceNameException implements Exception {
  const DuplicateInstanceNameException(this.name);

  final String name;

  @override
  String toString() => '已存在同名实例：$name';
}

/// 管理服务器实例的索引、当前选中项的完整配置与磁盘文件夹。
///
/// 索引（[instances]）只含 `{id, name}` 摘要，供选择列表读取；当前选中实例的
/// 完整启动配置（[selected]）按需从其 `config.json` 加载并缓存。
class InstanceController extends ChangeNotifier {
  InstanceController({
    InstanceStore? store,
    InstancesRootResolver? rootResolver,
  }) : _rootResolver = rootResolver ?? defaultInstancesRoot,
       _store = store ?? InstanceStore(rootResolver);

  final InstanceStore _store;
  final InstancesRootResolver _rootResolver;
  final Random _random = Random.secure();

  List<InstanceSummary> _summaries = [];
  String? _selectedId;
  Instance? _selected;
  bool _initialized = false;

  /// 实例索引（摘要列表），用于选择列表渲染。
  List<InstanceSummary> get instances => List.unmodifiable(_summaries);
  bool get isInitialized => _initialized;

  /// 当前选中实例的完整配置；无选中项时为 null。
  Instance? get selected => _selected;

  /// 从持久化存储加载索引与选中项配置，应在应用启动时调用一次。
  Future<void> init() async {
    _summaries = await _store.loadSummaries();
    final savedId = await _store.loadSelectedId();
    // 选中项可能已被删除，回退到第一个实例。
    if (savedId != null && _summaries.any((i) => i.id == savedId)) {
      _selectedId = savedId;
    } else {
      _selectedId = _summaries.isNotEmpty ? _summaries.first.id : null;
    }
    await _loadSelected();
    _initialized = true;
    notifyListeners();
  }

  /// 加载当前 [_selectedId] 对应的完整配置到 [_selected]。
  Future<void> _loadSelected() async {
    final id = _selectedId;
    _selected = id == null ? null : await _store.loadConfig(id);
  }

  /// 解析指定实例在磁盘上的文件夹。
  Future<Directory> directoryFor(Instance instance) =>
      directoryForId(instance.id);

  /// 按 id 解析实例在磁盘上的文件夹。
  Future<Directory> directoryForId(String id) async {
    final root = await _rootResolver();
    return Directory(p.join(root.path, id));
  }

  /// 新建实例：生成随机文件夹名、创建目录、写入配置与索引并自动选中。
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
    await _store.saveConfig(instance);
    _summaries = [..._summaries, InstanceSummary(id: id, name: trimmed)];
    _selectedId = id;
    _selected = instance;
    await _store.saveIndex(_summaries, _selectedId);
    notifyListeners();
    return instance;
  }

  /// 切换当前选中的实例，并加载其完整配置。
  Future<void> select(String id) async {
    if (_selectedId == id) return;
    _selectedId = id;
    await _loadSelected();
    await _store.saveIndex(_summaries, _selectedId);
    notifyListeners();
  }

  /// 修改指定实例的名称（同步更新索引摘要与该实例的 config.json）。
  ///
  /// 若与其它实例重名（忽略首尾空白），抛 [DuplicateInstanceNameException]。
  Future<void> rename(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (_isNameTaken(trimmed, exceptId: id)) {
      throw DuplicateInstanceNameException(trimmed);
    }
    _summaries = [
      for (final s in _summaries)
        if (s.id == id) s.copyWith(name: trimmed) else s,
    ];
    final config = await _configFor(id);
    if (config != null) {
      final updated = config.copyWith(name: trimmed);
      await _store.saveConfig(updated);
      if (id == _selectedId) _selected = updated;
    }
    await _store.saveIndex(_summaries, _selectedId);
    notifyListeners();
  }

  /// 更新指定实例的启动配置（运行环境、内存、Java 版本、服务端 jar/phar、自定义 JVM 参数、兼容模式）。
  Future<void> updateConfig(
    String id, {
    String? runtime,
    int? maxMemory,
    String? javaVersion,
    String? selectedJar,
    String? customJvmArgs,
    bool? compatMode,
    bool clearCustomJvmArgs = false,
  }) async {
    final config = await _configFor(id);
    if (config == null) return;
    final updated = config.copyWith(
      runtime: runtime,
      maxMemory: maxMemory,
      javaVersion: javaVersion,
      selectedJar: selectedJar,
      customJvmArgs: customJvmArgs,
      compatMode: compatMode,
      clearCustomJvmArgs: clearCustomJvmArgs,
    );
    await _store.saveConfig(updated);
    if (id == _selectedId) _selected = updated;
    notifyListeners();
  }

  /// 实例目录内文件发生变化的修订号。用户在「文件」页导入文件后自增，
  /// 供依赖文件列表的页面（如服务器页扫描 jar）感知并刷新。
  int _filesRevision = 0;
  int get filesRevision => _filesRevision;

  /// 通知当前实例目录内的文件发生变化（如导入 jar），触发依赖方重新扫描。
  void notifyInstanceFilesChanged() {
    _filesRevision++;
    notifyListeners();
  }

  /// 删除指定实例：删除磁盘文件夹、从索引移除并持久化；若删的是当前选中项则自动选第一个。
  Future<void> deleteInstance(String id) async {
    final dir = await directoryForId(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _summaries = _summaries.where((i) => i.id != id).toList();
    if (_selectedId == id) {
      _selectedId = _summaries.isNotEmpty ? _summaries.first.id : null;
      await _loadSelected();
    }
    await _store.saveIndex(_summaries, _selectedId);
    notifyListeners();
  }

  /// 解析指定实例是否启用兼容模式（供服务端状态机在原生回放时按 id 查询）。
  Future<bool> compatModeFor(String id) async {
    final config = await _configFor(id);
    return config?.compatMode ?? false;
  }

  /// 获取指定实例的完整配置：选中项直接复用缓存，否则从磁盘读取。
  Future<Instance?> _configFor(String id) async {
    if (id == _selectedId && _selected != null) return _selected;
    return _store.loadConfig(id);
  }

  /// 是否已存在指定名称的实例；[exceptId] 用于改名时排除自身。
  bool _isNameTaken(String name, {String? exceptId}) {
    return _summaries.any((s) => s.id != exceptId && s.name == name);
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
