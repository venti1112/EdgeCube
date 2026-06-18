import 'package:package_info_plus/package_info_plus.dart';

import 'config_store.dart';

/// 应用版本信息的本地持久化，存于 `config/version.json`。
///
/// 记录两项内容：
/// - `lastVersion`：最后一次打开应用时的完整版本号（`version+buildNumber`）；
/// - `history`：该设备上运行过的全部历史版本列表，按首次出现顺序去重追加。
///
/// 应在应用启动时调用 [recordOpen]，每次打开都更新 `lastVersion` 并按需
/// 扩充 `history`。
class VersionStore {
  VersionStore._();

  static const String _fileName = 'version.json';
  static const String _lastVersionKey = 'lastVersion';
  static const String _historyKey = 'history';

  /// 组合 [PackageInfo] 的 version 与 buildNumber 为完整版本号，形如 `1.0.0-beta2+2`。
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  /// 记录本次启动的版本：更新 `lastVersion`，并把该版本加入 `history`
  /// （已存在则不重复，保持首次出现顺序）。
  static Future<void> recordOpen() async {
    final version = await currentVersion();
    final m = await ConfigStore.readConfig(_fileName);
    m[_lastVersionKey] = version;
    final history =
        (m[_historyKey] as List?)?.whereType<String>().toList() ?? <String>[];
    if (!history.contains(version)) {
      history.add(version);
    }
    m[_historyKey] = history;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 读取最后一次打开的版本号；未记录过返回 null。
  static Future<String?> loadLastVersion() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_lastVersionKey] as String?;
  }

  /// 读取设备上运行过的全部历史版本列表（按首次出现顺序）；未记录过返回空列表。
  static Future<List<String>> loadHistory() async {
    final m = await ConfigStore.readConfig(_fileName);
    final list = m[_historyKey];
    if (list is! List) return [];
    return list.whereType<String>().toList();
  }
}
