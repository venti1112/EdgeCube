import 'config_store.dart';

/// 自定义实例文件夹路径的本地持久化。
///
/// 「实例文件夹」指 EdgeCube 数据文件夹（内部存储下的 `EdgeCube` 目录），
/// 其下的 `instances/` 子目录存放各实例的服务端工作文件夹。
///
/// 存于 `config/instance_path.json`，仅一个字段 `customPath`：
/// - 非 null 且非空字符串：用户指定的 EdgeCube 数据文件夹绝对路径；
/// - null：使用默认位置（`<storage>/EdgeCube`）。
///
/// 由 [defaultEdgeCubeRoot] 在解析 EdgeCube 数据根目录时读取，
/// [defaultInstancesRoot] 再在其下拼接 `instances` 子目录，确保所有读取实例
/// 目录的调用方（控制器、存储管理页、迁移逻辑）一致地感知自定义路径。
class InstancePathStore {
  InstancePathStore._();

  static const String _fileName = 'instance_path.json';
  static const String _customPathKey = 'customPath';

  /// 读取自定义实例根目录路径；未设置返回 null。
  static Future<String?> loadCustomPath() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    final path = configMap[_customPathKey] as String?;
    if (path == null || path.trim().isEmpty) return null;
    return path.trim();
  }

  /// 持久化自定义实例根目录路径；传入 null 表示恢复默认。
  static Future<void> saveCustomPath(String? path) async {
    final configMap = await ConfigStore.readConfig(_fileName);
    if (path == null || path.trim().isEmpty) {
      configMap.remove(_customPathKey);
    } else {
      configMap[_customPathKey] = path.trim();
    }
    await ConfigStore.writeConfig(_fileName, configMap);
  }
}
