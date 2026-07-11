import 'config_store.dart';

/// Java 运行环境优先级：决定「原生运行时」与「proot 容器」都可用时优先选谁。
///
/// proot 里是原版 JDK（比为安卓适配而改动过的原生运行时更稳定），故默认优先
/// proot；优先项不可用时自动回退到另一种。见 [resolveJavaEnv]。
enum RuntimePriority {
  proot,
  native;

  /// 持久化用的字符串标识。
  String get key => name;

  static RuntimePriority fromKey(String? key) {
    return RuntimePriority.values.firstWhere(
      (e) => e.key == key,
      orElse: () => RuntimePriority.proot,
    );
  }
}

/// 运行环境优先级设置的本地持久化（`config/runtime.json`）。
class RuntimePrefStore {
  RuntimePrefStore._();

  static const String _fileName = 'runtime.json';
  static const String _priorityKey = 'priority';

  /// 读取优先级；未设置时默认 [RuntimePriority.proot]。
  static Future<RuntimePriority> loadPriority() async {
    final config = await ConfigStore.readConfig(_fileName);
    return RuntimePriority.fromKey(config[_priorityKey] as String?);
  }

  static Future<void> savePriority(RuntimePriority priority) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_priorityKey] = priority.key;
    await ConfigStore.writeConfig(_fileName, config);
  }
}
