import 'config_store.dart';

/// 熄屏设置持久化：`config/sleep_screen.json`。
///
/// 保存用户对熄屏（睡眠时钟）页的偏好：
/// - [showInfo]：熄屏时是否显示信息（关闭后为纯黑屏）；
/// - 信息逐项开关：[showTime] / [showServerStatus] / [showCpu] /
///   [showMem] / [showServerMem]，时间（时分 + 日期）也是其中一项，
///   与状态悬浮窗各调各的，互不影响；
/// - [textColor] / [textOpacity]：信息文字颜色（ARGB）与透明度（0-100%），
///   实际显示亮度 = 透明度 × 层级系数（时间 1.0 / 日期 0.75 / 状态 0.6）；
/// - [idleTimeoutMinutes]：服务端运行中无操作多少分钟后自动进入熄屏，
///   `null` 表示关闭自动进入。
class SleepScreenStore {
  SleepScreenStore._();

  static const String _fileName = 'sleep_screen.json';

  /// 默认：显示信息；无操作 2 分钟后自动进入。
  static const bool defaultShowInfo = true;
  static const bool defaultShowTime = true;
  static const int defaultTextColor = 0xFFFFFFFF;
  static const int defaultTextOpacity = 25;
  static const int defaultIdleTimeoutMinutes = 2;

  /// 默认：仅「服务端状态」开，CPU/设备内存/服务端内存默认关。
  static const bool defaultShowServerStatus = true;
  static const bool defaultShowCpu = false;
  static const bool defaultShowMem = false;
  static const bool defaultShowServerMem = false;

  /// 自动进入可选时长（分钟），0 表示关闭。
  static const List<int> idleTimeoutOptions = [0, 1, 2, 5, 10, 15];

  /// 内存缓存：HomeShell 的定时检查直接读这里，避免每次轮询都读盘；
  /// 设置页保存时同步更新。
  static int? cachedIdleMinutes = defaultIdleTimeoutMinutes;

  /// 是否显示信息（默认 true）。兼容旧版本 `showClock` 键。
  static Future<bool> loadShowInfo() async {
    final config = await ConfigStore.readConfig(_fileName);
    if (config['showInfo'] is bool) return config['showInfo'] as bool;
    final legacy = config['showClock'];
    return legacy is bool ? legacy : defaultShowInfo;
  }

  static Future<bool> loadShowTime() =>
      _loadBool('showTime', defaultShowTime);

  /// 信息文字颜色（ARGB int，默认白色）。
  static Future<int> loadTextColor() async {
    final config = await ConfigStore.readConfig(_fileName);
    final v = config['textColor'];
    return v is int && (v & 0xFF000000) != 0 ? v : defaultTextColor;
  }

  /// 信息文字透明度（0-100，默认 25）。
  static Future<int> loadTextOpacity() async {
    final config = await ConfigStore.readConfig(_fileName);
    final v = config['textOpacity'];
    return v is int && v >= 0 && v <= 100 ? v : defaultTextOpacity;
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

  /// 读取熄屏页信息项开关（缺省回退默认值）。
  static Future<bool> loadShowServerStatus() =>
      _loadBool('showServerStatus', defaultShowServerStatus);

  static Future<bool> loadShowCpu() => _loadBool('showCpu', defaultShowCpu);

  static Future<bool> loadShowMem() => _loadBool('showMem', defaultShowMem);

  static Future<bool> loadShowServerMem() =>
      _loadBool('showServerMem', defaultShowServerMem);

  static Future<bool> _loadBool(String key, bool fallback) async {
    final config = await ConfigStore.readConfig(_fileName);
    final v = config[key];
    return v is bool ? v : fallback;
  }

  /// 保存熄屏设置；[idleTimeoutMinutes] 传 `null` 表示关闭自动进入。
  static Future<void> save({
    bool? showInfo,
    bool? showTime,
    int? textColor,
    int? textOpacity,
    int? idleTimeoutMinutes,
    bool? showServerStatus,
    bool? showCpu,
    bool? showMem,
    bool? showServerMem,
  }) async {
    final config = await ConfigStore.readConfig(_fileName);
    if (showInfo != null) config['showInfo'] = showInfo;
    if (showTime != null) config['showTime'] = showTime;
    if (textColor != null) config['textColor'] = textColor;
    if (textOpacity != null) config['textOpacity'] = textOpacity;
    if (idleTimeoutMinutes == null) {
      config.remove('idleTimeoutMinutes');
    } else {
      config['idleTimeoutMinutes'] = idleTimeoutMinutes;
    }
    if (showServerStatus != null) config['showServerStatus'] = showServerStatus;
    if (showCpu != null) config['showCpu'] = showCpu;
    if (showMem != null) config['showMem'] = showMem;
    if (showServerMem != null) config['showServerMem'] = showServerMem;
    cachedIdleMinutes = idleTimeoutMinutes;
    await ConfigStore.writeConfig(_fileName, config);
  }
}