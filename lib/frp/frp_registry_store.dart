import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../config/config_store.dart';
import 'frp_models.dart';

/// 已保存隧道的本地注册表。
///
/// 与服务器实例同策略：每条隧道分配一个随机 16 位十六进制 localId，
/// 元数据存于 `config/frp/config/<localId>.json`，实际运行的 TOML 存于
/// `config/frp/toml/<localId>.toml`，启动时直接把 TOML 路径传给 frpc。
///
/// 仅存非机密元数据（供应商、远端隧道 ID、节点、端口等）；登录 token 在
/// [FrpTokenStore]（加密存储）。
class FrpRegistryStore {
  FrpRegistryStore._();

  static final Random _random = Random.secure();

  /// 隧道元数据目录 `config/frp/config/`，不存在时自动创建。
  static Future<Directory> _metaDir() => _ensureDir('config');

  /// 隧道 TOML 目录 `config/frp/toml/`，不存在时自动创建。
  static Future<Directory> _tomlDir() => _ensureDir('toml');

  static Future<Directory> _ensureDir(String sub) async {
    final base = await ConfigStore.configDir();
    final dir = Directory(p.join(base.path, 'frp', sub));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _metaFile(String localId) async {
    final dir = await _metaDir();
    return File(p.join(dir.path, '$localId.json'));
  }

  static Future<File> tomlFile(String localId) async {
    final dir = await _tomlDir();
    return File(p.join(dir.path, '$localId.toml'));
  }

  /// 读取全部已保存隧道，按创建时间排序。
  static Future<List<SavedFrpTunnel>> load() async {
    final dir = await _metaDir();
    final tunnels = <SavedFrpTunnel>[];
    final createdAt = <String, int>{};
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final map = await ConfigStore.readJsonFile(entity);
      final tunnel = SavedFrpTunnel.fromJson(map);
      if (tunnel.localId.isEmpty) continue;
      tunnels.add(tunnel);
      createdAt[tunnel.localId] = (map['createdAt'] as int?) ?? 0;
    }
    tunnels.sort(
      (a, b) => createdAt[a.localId]!.compareTo(createdAt[b.localId]!),
    );
    return tunnels;
  }

  /// 新增或更新（按 localId 定位文件）一条隧道。
  static Future<void> upsert(SavedFrpTunnel tunnel) async {
    final file = await _metaFile(tunnel.localId);
    // 保留首次写入的创建时间，保证列表顺序稳定。
    final existing = await ConfigStore.readJsonFile(file);
    await ConfigStore.writeJsonFile(file, {
      ...tunnel.toJson(),
      'createdAt':
          (existing['createdAt'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 删除指定隧道的元数据与 TOML 文件。
  static Future<void> remove(String localId) async {
    final meta = await _metaFile(localId);
    if (await meta.exists()) await meta.delete();
    final toml = await tomlFile(localId);
    if (await toml.exists()) await toml.delete();
  }

  /// 生成不与现有条目冲突的随机 16 位十六进制本地 ID（与实例 ID 同策略）。
  static Future<String> newLocalId() async {
    const chars = '0123456789abcdef';
    while (true) {
      final id = List.generate(
        16,
        (_) => chars[_random.nextInt(chars.length)],
      ).join();
      final file = await _metaFile(id);
      if (!await file.exists()) return id;
    }
  }

  /// 写入隧道实际运行的 TOML，返回文件（路径直接传给 frpc 启动）。
  static Future<File> writeToml(String localId, String content) async {
    final file = await tomlFile(localId);
    await file.writeAsString(content, flush: true);
    return file;
  }

  /// 读取隧道 TOML；文件不存在时返回 null。
  static Future<String?> readToml(String localId) async {
    final file = await tomlFile(localId);
    if (!await file.exists()) return null;
    return file.readAsString();
  }
}
