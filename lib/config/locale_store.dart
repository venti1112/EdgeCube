import 'config_store.dart';

/// 语言选择的本地持久化，存于 `config/locale.json`。
class LocaleStore {
  static const String _fileName = 'locale.json';
  static const String _localeKey = 'locale';

  /// 「跟随系统」的标记值。
  static const String systemCode = 'system';

  /// 读取已保存的语言代码，未保存过时回退到 [systemCode]。
  static Future<String> load() async {
    final m = await ConfigStore.readConfig(_fileName);
    final v = m[_localeKey];
    return (v is String && v.isNotEmpty) ? v : systemCode;
  }

  /// 持久化语言代码（`system` 或具体 locale，如 `en_US`）。
  static Future<void> save(String code) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_localeKey] = code;
    await ConfigStore.writeConfig(_fileName, m);
  }
}
