import 'package:logging/logging.dart';

import 'config_store.dart';

/// 日志功能的用户可配置等级子集（对应 `logging` 包的 [Level]）。
///
/// 用户在设置中选择其中一档，低于该等级的日志不会被记录。
const List<Level> kSelectableLogLevels = [
  Level.SEVERE, // 错误
  Level.WARNING, // 警告
  Level.INFO, // 信息
  Level.FINE, // 调试
  Level.FINEST, // 全部
];

/// 日志开关与等级的本地持久化。
///
/// 存储于 `config/log.json`，遵循 [ConfigStore] 的 read-modify-write 原子写入模式。
/// - `enabled`：日志总开关，默认 **关闭**。
/// - `level`：记录等级，默认 [Level.INFO]。
class LogStore {
  LogStore._();

  static const String _fileName = 'log.json';
  static const String _enabledKey = 'enabled';
  static const String _levelKey = 'level';

  /// 读取日志开关；缺失时默认返回 false（关闭）。
  static Future<bool> loadEnabled() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_enabledKey];
    return raw is bool ? raw : false;
  }

  /// 持久化日志开关。
  static Future<void> saveEnabled(bool value) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_enabledKey] = value;
    await ConfigStore.writeConfig(_fileName, config);
  }

  /// 读取日志等级；缺失或无法识别时默认返回 [Level.INFO]。
  static Future<Level> loadLevel() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_levelKey] as String?;
    return _levelFromName(raw) ?? Level.INFO;
  }

  /// 持久化日志等级（存储为等级名称字符串）。
  static Future<void> saveLevel(Level level) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_levelKey] = level.name;
    await ConfigStore.writeConfig(_fileName, config);
  }

  static Level? _levelFromName(String? name) {
    if (name == null) return null;
    for (final l in kSelectableLogLevels) {
      if (l.name == name) return l;
    }
    return null;
  }
}
