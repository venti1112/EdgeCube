import 'dart:io';

import 'package:path/path.dart' as p;

import 'config_store.dart';

/// 自定义 EdgeCube 数据文件夹路径的本地持久化。
///
/// 设置页的「自定义实例文件夹」实际更改的是整个 EdgeCube 数据文件夹
/// （内部存储下的 `EdgeCube` 目录），其下的 `instances/` 子目录才存放
/// 各实例的服务端工作文件夹。
///
/// 存于 `config/data_folder.json`，仅一个字段 `customDataPath`：
/// - 非 null 且非空字符串：用户指定的 EdgeCube 数据文件夹绝对路径；
/// - null：使用默认位置（`<storage>/EdgeCube`）。
///
/// 由 [defaultEdgeCubeRoot] 在解析 EdgeCube 数据根目录时读取，
/// [defaultInstancesRoot] 再在其下拼接 `instances` 子目录，确保所有读取实例
/// 目录的调用方（控制器、存储管理页、迁移逻辑）一致地感知自定义路径。
///
/// 历史版本存于 `config/instance_path.json` 的 `customPath` 字段；
/// 首次读取时自动迁移到新文件并删除旧文件。
class DataFolderStore {
  DataFolderStore._();

  static const String _fileName = 'data_folder.json';
  static const String _customPathKey = 'customDataPath';

  /// 历史遗留：旧版配置文件与字段名（名字未体现「整个数据文件夹」的语义）。
  static const String _legacyFileName = 'instance_path.json';
  static const String _legacyCustomPathKey = 'customPath';

  /// 读取自定义数据文件夹路径；未设置返回 null。
  static Future<String?> loadCustomPath() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    var path = configMap[_customPathKey] as String?;
    path ??= await _migrateLegacy();
    if (path == null || path.trim().isEmpty) return null;
    return path.trim();
  }

  /// 持久化自定义数据文件夹路径；传入 null 表示恢复默认。
  static Future<void> saveCustomPath(String? path) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    if (path == null || path.trim().isEmpty) {
      configMap.remove(_customPathKey);
    } else {
      configMap[_customPathKey] = path.trim();
    }
    await ConfigStore.writeConfig(_fileName, configMap);
    // 防止旧文件残留导致下次读取时又被当作迁移源。
    await _deleteLegacyFile();
  }

  /// 从旧版 `instance_path.json` 迁移：读出旧值写入新文件后删除旧文件。
  /// 返回迁移到的路径；旧文件不存在或无有效值返回 null。
  static Future<String?> _migrateLegacy() async {
    final legacy = await ConfigStore.readConfig(_legacyFileName);
    final path = legacy[_legacyCustomPathKey] as String?;
    if (path != null && path.trim().isNotEmpty) {
      final configMap = await ConfigStore.readConfig(_fileName);
      configMap[_customPathKey] = path.trim();
      await ConfigStore.writeConfig(_fileName, configMap);
    }
    await _deleteLegacyFile();
    return path;
  }

  static Future<void> _deleteLegacyFile() async {
    try {
      final dir = await ConfigStore.configDir();
      final file = File(p.join(dir.path, _legacyFileName));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
