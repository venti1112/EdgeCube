import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/sleep_screen_store.dart';
import '../i18n/locale_scope.dart';
import '../server/power_service.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';

/// 熄屏页（睡眠时钟）。
///
/// 全屏纯黑 + 极暗数字时钟（可关闭变全黑）：OLED 上显示区域几乎不耗电也不
/// 易烧屏，且 App 始终处于前台（配合强制常亮），避免锁屏后被系统回收导致
/// 服务端掉后台。轻触任意位置或按返回键退出；服务端停止时自动退出，避免
/// 盖住崩溃弹窗。进入时隐藏系统栏，退出时恢复。
class SleepScreenPage extends StatefulWidget {
  const SleepScreenPage({super.key});

  @override
  State<SleepScreenPage> createState() => _SleepScreenPageState();
}

class _SleepScreenPageState extends State<SleepScreenPage> {
  late DateTime _now = DateTime.now();
  Timer? _ticker;
  bool _showClock = true;
  ServerController? _serverController;
  bool _serverListened = false;
  bool _uiHidden = false;
  bool _keepAwakeOn = false;

  @override
  void initState() {
    super.initState();
    _loadClockPref();
    _applyKeepAwake(true);
    _setSystemUiHidden(true);
    // 秒级刷新，保证分钟切换即时，无需等整分钟。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (now.minute != _now.minute || now.hour != _now.hour) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ServerScope 只能在 didChangeDependencies 里取（initState 时未就绪）。
    _serverController ??= ServerScope.of(context);
    if (!_serverListened) {
      _serverListened = true;
      _serverController!.addListener(_onServerChanged);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _serverController?.removeListener(_onServerChanged);
    _applyKeepAwake(false);
    _setSystemUiHidden(false);
    super.dispose();
  }

  Future<void> _loadClockPref() async {
    final showClock = await SleepScreenStore.loadShowClock();
    if (mounted) setState(() => _showClock = showClock);
  }

  /// 原生侧临时强制常亮（不写「防息屏」开关，仅页面生命周期内生效）。
  Future<void> _applyKeepAwake(bool enabled) async {
    if (_keepAwakeOn == enabled) return;
    _keepAwakeOn = enabled;
    await PowerService.setKeepScreenOnOverride(enabled);
  }

  /// 隐藏/恢复系统状态栏与导航栏。
  Future<void> _setSystemUiHidden(bool hidden) async {
    if (_uiHidden == hidden) return;
    _uiHidden = hidden;
    await SystemChrome.setEnabledSystemUIMode(
      hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// 服务端停止时自动退出熄屏页，回到主页（崩溃弹窗等提示不会被盖住）。
  void _onServerChanged() {
    if (!mounted) return;
    if (_serverController?.status == ServerStatus.stopped) {
      Navigator.of(context).maybePop();
    }
  }

  void _exit() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // 返回键 = 退出，无需二次确认。
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          // 任意按下即退出。
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _exit(),
          child: ColoredBox(
            color: Colors.black,
            child: SafeArea(
              child: _showClock
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildClockText(),
                        const SizedBox(height: 10),
                        _buildDateLine(),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  /// 大号极暗时分显示。粗体字重会放大笔画占用，改用细字重减小像素点亮面积。
  Widget _buildClockText() {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hh:$mm',
      style: const TextStyle(
        color: Color(0x33FFFFFF), // 白 20%，极暗防烧屏
        fontSize: 96,
        fontWeight: FontWeight.w200,
        letterSpacing: 4,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  /// 日期行（月日与星期），亮度再降一档。星期名走多语言表。
  Widget _buildDateLine() {
    final now = _now;
    final weekday = context.tr('sleep.weekday.${now.weekday}');
    return Text(
      context.tr('sleep.dateLine', {
        'month': '${now.month}',
        'day': '${now.day}',
        'weekday': weekday,
      }),
      style: const TextStyle(
        color: Color(0x26FFFFFF), // 白 15%
        fontSize: 18,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
      ),
    );
  }
}