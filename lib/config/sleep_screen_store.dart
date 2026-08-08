import 'config_store.dart';

/// 熄屏设置持久化：`config/sleep_screen.json`。
///
/// 保存用户对熄屏（睡眠时钟）页的偏好：
/// - [showClock]：熄屏时是否显示极暗数字时钟（关闭后为纯黑屏）；
/// - [idleTimeoutMinutes]：服务端运行中无操作多少分钟后自动进入熄屏，
///   `null` 表示关闭自动进入。
class SleepScreenStore {
  SleepScreenStore._();

  static const String _fileName = 'sleep_screen.json';

  /// 默认：显示时钟；无操作 2 分钟后自动进入。
  static const bool defaultShowClock = true;
  static const int defaultIdleTimeoutMinutes = 2;

  /// 自动进入可选时长（分钟），0 表示关闭。
  static const List<int> idleTimeoutOptions = [0, 1, 2, 5, 10, 15];

  /// 内存缓存：HomeShell 的定时检查直接读这里，避免每次轮询都读盘；
  /// 设置页保存时同步更新。
  static int? cachedIdleMinutes = defaultIdleTimeoutMinutes;

  /// 是否显示时钟（默认 true）。
  static Future<bool> loadShowClock() async {
    final config = await ConfigStore.readConfig(_fileName);
    final v = config['showClock'];
    return v is bool ? v : defaultShowClock;
  }

  /// 无操作自动进入熄屏的分钟数；`null` 表示关闭。默认 2 分钟。
  static Future<int?> loadIdleTimeoutMinutes() async {
    final config = await ConfigStore.readConfig(_fileName);
    final v = config['idleTimeoutMinutes'];
    final result = v is int
        ? (v > 0 ? v : null)
        : defaultIdleTimeoutMinutes;
    cachedIdleMinutes = result;
    return result;
  }

  /// 保存熄屏设置；[idleTimeoutMinutes] 传 `null` 表示关闭自动进入。
  static Future<void> save({
    bool? showClock,
    int? idleTimeoutMinutes,
  }) async {
    final config = await ConfigStore.readConfig(_fileName);
    if (showClock != null) config['showClock'] = showClock;
    if (idleTimeoutMinutes == null) {
      config.remove('idleTimeoutMinutes');
    } else {
      config['idleTimeoutMinutes'] = idleTimeoutMinutes;
    }
    cachedIdleMinutes = idleTimeoutMinutes;
    await ConfigStore.writeConfig(_fileName, config);
  }
}