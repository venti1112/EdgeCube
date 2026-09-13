import 'dart:io';

import 'package:path/path.dart' as p;

import 'server_properties.dart';

/// 实例内的一个世界（存档）目录。
class WorldInfo {
  const WorldInfo({required this.name, required this.path, this.sizeBytes});

  /// 目录名，即服务端眼中的世界名（server.properties 的 level-name 取值）。
  final String name;

  /// 目录的绝对路径。
  final String path;

  /// 占用字节数；null 表示未统计或统计失败。
  final int? sizeBytes;

  Directory get directory => Directory(path);
}

/// 从解压结果中识别出的一个待导入世界。
class ImportedWorld {
  const ImportedWorld({required this.sourcePath, required this.name});

  /// 归档解压出的世界目录路径。
  final String sourcePath;

  /// 世界目录名（导入后写入实例目录时使用的名字）。
  final String name;
}

/// 把实例目录当作服务端工作目录，处理「世界（存档）」的识别、导入、导出与重置。
///
/// 全部基于路径、不依赖任何原生插件，可直接单元测试。
///
/// 世界目录的判定（覆盖本项目支持的各服务端）：
/// - Java 版（Vanilla / Spigot / Paper / Forge / NeoForge / Fabric）：含 `level.dat`；
/// - 部分第三方实现只有区域文件：含 `region` 目录；
/// - 基岩版（Nukkit / PowerNukkitX）：含 `db` 目录。
class WorldService {
  WorldService._();

  /// Java 版世界标识文件。
  static const String levelDatName = 'level.dat';

  /// Java 版世界备份标识文件（旧版服务端可能只留下它）。
  static const String levelDatOldName = 'level.dat_old';

  /// 在世界目录中标记 world 的根目录名：Bukkit/Spigot 系多维世界共用该目录结构。
  static const String regionDirName = 'region';

  /// 基岩版世界的数据目录名。
  static const String dbDirName = 'db';

  static const String serverPropertiesName = 'server.properties';

  /// server.properties 未指定 level-name 时的缺省世界名。
  static const String defaultLevelName = 'world';

  /// 统计目录大小时最多遍历的文件数，避免超大世界长时间占用 UI。
  static const int _sizeScanFileLimit = 20000;

  /// 读取实例 `server.properties` 中的世界名（level-name），
  /// 文件缺失、无法解析或值为空时返回 [defaultLevelName]。
  static Future<String> readLevelName(Directory instanceDir) async {
    final file = File(p.join(instanceDir.path, serverPropertiesName));
    try {
      if (!await file.exists()) return defaultLevelName;
      final props = ServerProperties.parse(await file.readAsString());
      final value = props['level-name']?.trim();
      return (value == null || value.isEmpty) ? defaultLevelName : value;
    } catch (_) {
      return defaultLevelName;
    }
  }

  /// 写入世界名（level-name）到实例 `server.properties`；文件不存在时不做任何事
  /// （避免为一个尚未运行过的服务端凭空创建配置）。
  static Future<bool> writeLevelName(
    Directory instanceDir,
    String levelName,
  ) async {
    final trimmed = levelName.trim();
    if (trimmed.isEmpty) return false;
    final file = File(p.join(instanceDir.path, serverPropertiesName));
    try {
      if (!await file.exists()) return false;
      final props = ServerProperties.parse(await file.readAsString());
      props['level-name'] = trimmed;
      await file.writeAsString(props.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清空 `server.properties` 中的 level-seed，使服务端下次生成地图时使用随机种子。
  ///
  /// 没有 level-seed 条目、或它已经是空值时返回 false 且不改动文件
  /// （两种情况本来就是随机种子）。
  static Future<bool> clearLevelSeed(Directory instanceDir) async {
    final file = File(p.join(instanceDir.path, serverPropertiesName));
    try {
      if (!await file.exists()) return false;
      final props = ServerProperties.parse(await file.readAsString());
      final current = props['level-seed'];
      if (current == null || current.isEmpty) return false;
      props['level-seed'] = '';
      await file.writeAsString(props.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 同步判定 [dir] 是否是一个世界目录。
  static bool isWorldDirSync(Directory dir) {
    bool exists(String name) => FileSystemEntity.typeSync(
      p.join(dir.path, name),
      followLinks: false,
    ) !=
        FileSystemEntityType.notFound;

    if (exists(levelDatName) || exists(levelDatOldName)) return true;
    if (exists(regionDirName)) return true;
    if (exists(dbDirName)) return true;
    return false;
  }

  /// 列出实例目录下的全部世界目录（隐藏目录跳过），按名称排序。
  static Future<List<WorldInfo>> listWorlds(Directory instanceDir) async {
    if (!await _exists(instanceDir)) return const [];
    final worlds = <WorldInfo>[];
    try {
      await for (final entity in instanceDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (!isWorldDirSync(entity)) continue;
        worlds.add(
          WorldInfo(
            name: name,
            path: entity.path,
            sizeBytes: await directorySize(entity),
          ),
        );
      }
    } catch (_) {
      return worlds;
    }
    _sortByName(worlds);
    return worlds;
  }

  /// 当前世界（level-name）及其伴生维度目录：`<level>`、`<level>_nether`、
  /// `<level>_the_end`（Bukkit/Spigot 系的多维世界布局）。
  static List<String> relatedWorldNames(String levelName) {
    final base = levelName.trim().isEmpty ? defaultLevelName : levelName.trim();
    return [base, '${base}_nether', '${base}_the_end'];
  }

  /// 按 [levelName] 找出实例中属于同一个地图的全部世界目录（含伴生维度）。
  static Future<List<WorldInfo>> worldsForLevel(
    Directory instanceDir,
    String levelName,
  ) async {
    final names = relatedWorldNames(
      levelName,
    ).map((n) => n.toLowerCase()).toSet();
    final all = await listWorlds(instanceDir);
    return all.where((w) => names.contains(w.name.toLowerCase())).toList();
  }

  /// 递归统计目录占用字节数。
  ///
  /// 最多遍历 [_sizeScanFileLimit] 个文件后停止累计（超大世界只给出下界近似值），
  /// 遍历过程中的权限错误静默跳过，绝不抛出。
  static Future<int?> directorySize(Directory dir) async {
    var total = 0;
    var files = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } catch (_) {
          continue;
        }
        files++;
        if (files >= _sizeScanFileLimit) break;
      }
    } catch (_) {
      return null;
    }
    return total;
  }

  /// 删除一个世界目录（递归）；目录本就不存在时静默通过。
  static Future<void> deleteWorld(WorldInfo world) async {
    final dir = Directory(world.path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 扫描解压结果 [root]，找出其中的世界目录（用于导入存档）。
  ///
  /// - [root] 自身就是世界（`level.dat` 等直接躺在解压根下）时，返回一个
  ///   名为 [fallbackName] 的世界（压缩包没有外层文件夹，用压缩包文件名兜底）；
  /// - 否则收集 [root] 的直接子目录中的世界；再不行往下一层找（支持
  ///   `备份/world/` 这类多包一层的归档）。
  ///
  /// 什么都不匹配时返回空列表，由调用方提示「压缩包中没有存档」。
  static Future<List<ImportedWorld>> scanForWorlds(
    Directory root, {
    String fallbackName = 'world',
  }) async {
    if (isWorldDirSync(root)) {
      return [ImportedWorld(sourcePath: root.path, name: _safeName(fallbackName))];
    }
    final found = <ImportedWorld>[];
    final children = await _subDirectories(root);
    for (final child in children) {
      if (isWorldDirSync(child)) {
        found.add(
          ImportedWorld(
            sourcePath: child.path,
            name: _safeName(p.basename(child.path)),
          ),
        );
      }
    }
    if (found.isNotEmpty) return found;

    // 归档里多包了一层（如 `存档备份/world/`、`backup/world_nether/`）。
    for (final child in children) {
      for (final grand in await _subDirectories(child)) {
        if (isWorldDirSync(grand)) {
          found.add(
            ImportedWorld(
              sourcePath: grand.path,
              name: _safeName(p.basename(grand.path)),
            ),
          );
        }
      }
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  /// 把 [worlds] 的世界目录移动到实例目录中，返回导入后的世界名列表。
  ///
  /// [overwrite] 为 false 时，遇到同名目录会抛 [WorldImportConflictException]，
  /// 由调用方先征询用户后再以 true 重试。
  static Future<List<String>> moveIntoInstance(
    Directory instanceDir,
    List<ImportedWorld> worlds, {
    bool overwrite = false,
  }) async {
    final imported = <String>[];
    for (final world in worlds) {
      final target = p.join(instanceDir.path, world.name);
      if (FileSystemEntity.typeSync(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        if (!overwrite) throw WorldImportConflictException(world.name);
        await Directory(target).delete(recursive: true);
      }
      await Directory(world.sourcePath).rename(target);
      imported.add(world.name);
    }
    return imported;
  }

  /// 目录下需要跳过的隐藏条目（如导入用的临时目录）。
  static bool isHiddenName(String name) => name.startsWith('.');

  static void _sortByName(List<WorldInfo> worlds) {
    worlds.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  static Future<bool> _exists(Directory dir) async {
    try {
      return await dir.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<List<Directory>> _subDirectories(Directory dir) async {
    final out = <Directory>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (isHiddenName(p.basename(entity.path))) continue;
        out.add(entity);
      }
    } catch (_) {
      return out;
    }
    out.sort(
      (a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()),
    );
    return out;
  }

  /// 目录名清洗：去掉路径分隔符等文件系统敏感字符，空名回退为 [defaultLevelName]。
  static String _safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    return cleaned.isEmpty ? defaultLevelName : cleaned;
  }
}

/// 导入的世界与实例中已有目录重名，且调用方未允许覆盖。
class WorldImportConflictException implements Exception {
  const WorldImportConflictException(this.name);

  final String name;

  @override
  String toString() => name;
}
