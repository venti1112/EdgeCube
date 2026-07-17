import 'dart:io';

import 'package:path/path.dart' as p;

import 'config_store.dart';

/// Java 运行环境优先级：决定「原生运行时」与「proot 容器」都可用时优先选谁。
///
/// 仅影响 Java 实例的启动与模组加载器安装（PHP 与非 Java 的 proot 实例不受
/// 影响）。proot 里是原版 JDK（比为安卓适配而改动过的原生运行时更稳定），故
/// 默认优先 proot；优先项不可用时自动回退到另一种。见 [resolveJavaEnv]。
enum JavaEnvPriority {
  proot,
  native;

  /// 持久化用的字符串标识。
  String get key => name;

  static JavaEnvPriority fromKey(String? key) {
    return JavaEnvPriority.values.firstWhere(
      (e) => e.key == key,
      orElse: () => JavaEnvPriority.proot,
    );
  }
}

/// Java 环境优先级设置的本地持久化（`config/java_env.json`）。
///
/// 历史版本存于 `config/runtime.json`（名字未体现「仅 Java 环境」的语义）；
/// 首次读取时自动迁移到新文件并删除旧文件。
class JavaEnvPrefStore {
  JavaEnvPrefStore._();

  static const String _fileName = 'java_env.json';
  static const String _priorityKey = 'priority';

  /// 历史遗留：旧版配置文件名。
  static const String _legacyFileName = 'runtime.json';

  /// 读取优先级；未设置时默认 [JavaEnvPriority.proot]。
  static Future<JavaEnvPriority> loadPriority() async {
    final config = await ConfigStore.readConfig(_fileName);
    var raw = config[_priorityKey] as String?;
    raw ??= await _migrateLegacy();
    return JavaEnvPriority.fromKey(raw);
  }

  static Future<void> savePriority(JavaEnvPriority priority) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_priorityKey] = priority.key;
    await ConfigStore.writeConfig(_fileName, config);
    await _deleteLegacyFile();
  }

  /// 从旧版 `runtime.json` 迁移：读出旧值写入新文件后删除旧文件。
  /// 返回迁移到的原始值；旧文件不存在或无有效值返回 null。
  static Future<String?> _migrateLegacy() async {
    final legacy = await ConfigStore.readConfig(_legacyFileName);
    final raw = legacy[_priorityKey] as String?;
    if (raw != null) {
      final config = await ConfigStore.readConfig(_fileName);
      config[_priorityKey] = raw;
      await ConfigStore.writeConfig(_fileName, config);
    }
    await _deleteLegacyFile();
    return raw;
  }

  static Future<void> _deleteLegacyFile() async {
    try {
      final dir = await ConfigStore.configDir();
      final file = File(p.join(dir.path, _legacyFileName));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
