import 'config_store.dart';

/// 终端字号的默认值与允许范围（控制台与 Shell 终端共用同一套范围常量）。
const double kDefaultTerminalFontSize = 13.0;
const double kMinTerminalFontSize = 6.0;
const double kMaxTerminalFontSize = 40.0;

/// 终端外观偏好（目前仅字号）的本地持久化。
///
/// 控制台（MC 服务器控制台）与 Shell 终端各自记忆字号，分别存于 `config/terminal.json`
/// 的 `consoleFontSize` / `shellFontSize` 两个键。读取缺失或越界时回退到合法范围内。
class TerminalStore {
  TerminalStore._();

  static const String _fileName = 'terminal.json';
  static const String _consoleKey = 'consoleFontSize';
  static const String _shellKey = 'shellFontSize';

  static Future<double> loadConsoleFontSize() => _load(_consoleKey);
  static Future<void> saveConsoleFontSize(double value) =>
      _save(_consoleKey, value);

  static Future<double> loadShellFontSize() => _load(_shellKey);
  static Future<void> saveShellFontSize(double value) =>
      _save(_shellKey, value);

  static Future<double> _load(String key) async {
    final m = await ConfigStore.readConfig(_fileName);
    final raw = m[key];
    final value = raw is num ? raw.toDouble() : kDefaultTerminalFontSize;
    return value.clamp(kMinTerminalFontSize, kMaxTerminalFontSize);
  }

  static Future<void> _save(String key, double value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[key] = value.clamp(kMinTerminalFontSize, kMaxTerminalFontSize);
    await ConfigStore.writeConfig(_fileName, m);
  }
}
