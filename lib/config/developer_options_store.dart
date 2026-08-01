import 'config_store.dart';

/// 开发者选项的本地持久化。
///
/// 存储于 `config/developer_options.json`，遵循 [ConfigStore] 的 read-modify-write
/// 原子写入模式。
///
/// - `enabled`：开发者模式开关，默认 **关闭**。
///   需在「关于」页面连续点击版本号 5 次后开启。
class DeveloperOptionsStore {
  DeveloperOptionsStore._();

  static const String _fileName = 'developer_options.json';
  static const String _enabledKey = 'enabled';

  /// 读取开发者模式开关；缺失时默认返回 false（关闭）。
  static Future<bool> loadEnabled() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_enabledKey];
    return raw is bool ? raw : false;
  }

  /// 持久化开发者模式开关。
  static Future<void> saveEnabled(bool value) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_enabledKey] = value;
    await ConfigStore.writeConfig(_fileName, config);
  }
}
