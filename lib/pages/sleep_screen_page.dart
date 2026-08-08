import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/sleep_screen_store.dart';
import '../i18n/locale_scope.dart';
import '../server/power_service.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';
import '../server/system_monitor_scope.dart';

/// 熄屏页（睡眠时钟）。
///
/// 全屏纯黑 + 信息显示（可关闭变全黑）：OLED 上显示区域几乎不耗电也不易
/// 烧屏，且 App 始终处于前台（配合强制常亮），避免锁屏后被系统回收导致
/// 服务端掉后台。轻触任意位置或按返回键退出；服务端停止时自动退出，避免
/// 盖住崩溃弹窗。进入时隐藏系统栏与状态悬浮窗，退出时恢复。
///
/// 防烧屏：信息整体每分钟随机漂移到预置锚点（约 3s 平滑移动），避免同一
/// 像素长期点亮。文字颜色与透明度可自定义（见 [SleepScreenStore]）。
class SleepScreenPage extends StatefulWidget {
  const SleepScreenPage({super.key});

  @override
  State<SleepScreenPage> createState() => _SleepScreenPageState();
}

class _SleepScreenPageState extends State<SleepScreenPage> {
  late DateTime _now = DateTime.now();
  Timer? _ticker;
  bool _showInfo = true;
  bool _showTime = SleepScreenStore.defaultShowTime;
  int _textColor = SleepScreenStore.defaultTextColor;
  int _textOpacity = SleepScreenStore.defaultTextOpacity;
  bool _showServerStatus = SleepScreenStore.defaultShowServerStatus;
  bool _showCpu = SleepScreenStore.defaultShowCpu;
  bool _showMem = SleepScreenStore.defaultShowMem;
  bool _showServerMem = SleepScreenStore.defaultShowServerMem;
  ServerController? _serverController;
  bool _serverListened = false;
  bool _uiHidden = false;
  bool _keepAwakeOn = false;
  bool _overlayHiddenOn = false;

  /// 防烧屏漂移锚点（全部避开屏幕边缘与刘海/手势区，9 宫格散布）。
  static const List<Alignment> _anchors = [
    Alignment(0, 0),
    Alignment(-0.62, -0.62),
    Alignment(0, -0.7),
    Alignment(0.62, -0.62),
    Alignment(-0.72, 0),
    Alignment(0.72, 0),
    Alignment(-0.62, 0.62),
    Alignment(0, 0.7),
    Alignment(0.62, 0.62),
  ];
  final math.Random _rng = math.Random();
  int _anchorIndex = 0;
  Alignment _alignment = Alignment(0, 0);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _applyKeepAwake(true);
    _setOverlayHidden(true);
    _setSystemUiHidden(true);
    // 秒级刷新，保证分钟切换即时，无需等整分钟。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (now.minute != _now.minute || now.hour != _now.hour) {
        setState(() {
          _now = now;
          _driftToNextAnchor();
        });
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
    _setOverlayHidden(false);
    _setSystemUiHidden(false);
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final showInfo = await SleepScreenStore.loadShowInfo();
    final showTime = await SleepScreenStore.loadShowTime();
    final textColor = await SleepScreenStore.loadTextColor();
    final textOpacity = await SleepScreenStore.loadTextOpacity();
    final showServerStatus = await SleepScreenStore.loadShowServerStatus();
    final showCpu = await SleepScreenStore.loadShowCpu();
    final showMem = await SleepScreenStore.loadShowMem();
    final showServerMem = await SleepScreenStore.loadShowServerMem();
    if (!mounted) return;
    setState(() {
      _showInfo = showInfo;
      _showTime = showTime;
      _textColor = textColor;
      _textOpacity = textOpacity;
      _showServerStatus = showServerStatus;
      _showCpu = showCpu;
      _showMem = showMem;
      _showServerMem = showServerMem;
    });
  }

  /// 原生侧临时强制常亮（不写「防息屏」开关，仅页面生命周期内生效）。
  Future<void> _applyKeepAwake(bool enabled) async {
    if (_keepAwakeOn == enabled) return;
    _keepAwakeOn = enabled;
    await PowerService.setKeepScreenOnOverride(enabled);
  }

  /// 原生侧临时隐藏状态悬浮窗（不写「悬浮窗」开关，仅页面生命周期内生效）。
  Future<void> _setOverlayHidden(bool hidden) async {
    if (_overlayHiddenOn == hidden) return;
    _overlayHiddenOn = hidden;
    await PowerService.setOverlayHidden(hidden);
  }

  /// 隐藏/恢复系统状态栏与导航栏。
  Future<void> _setSystemUiHidden(bool hidden) async {
    if (_uiHidden == hidden) return;
    _uiHidden = hidden;
    await SystemChrome.setEnabledSystemUIMode(
      hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// 服务端停止时自动退出熄屏页，回到主页（崩溃弹窗等提示不会被盖住）；
  /// 状态变化时刷新状态行文案。
  void _onServerChanged() {
    if (!mounted) return;
    if (_serverController?.status == ServerStatus.stopped) {
      Navigator.of(context).maybePop();
    } else if (_showServerStatus) {
      setState(() {});
    }
  }

  /// 随机选一个与当前不同的锚点，供 [AnimatedAlign] 平滑漂移。
  void _driftToNextAnchor() {
    var next = _rng.nextInt(_anchors.length - 1);
    if (next >= _anchorIndex) next++;
    _anchorIndex = next;
    _alignment = _anchors[_anchorIndex];
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 信息关闭＝纯黑屏，内容与漂移全部跳过。
                if (!_showInfo) return const SizedBox.expand();
                return AnimatedAlign(
                  alignment: _alignment,
                  duration: const Duration(milliseconds: 3000),
                  curve: Curves.easeInOutCubic,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_showTime) ...[
                        _buildClockText(),
                        const SizedBox(height: 10),
                        _buildDateLine(),
                      ],
                      if (_showServerStatus ||
                          _showCpu ||
                          _showMem ||
                          _showServerMem) ...[
                        const SizedBox(height: 20),
                        _buildStatusBlock(),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 按层级系数计算信息文字颜色：实际 alpha = 透明度 × 系数
  /// （时间 1.0 / 日期 0.75 / 状态 0.6），保证层级主次清晰。
  Color _infoColor(double factor) {
    final base = Color(_textColor);
    final alpha = (_textOpacity / 100 * factor).clamp(0.0, 1.0);
    return base.withValues(alpha: alpha);
  }

  /// 大号时分显示。粗体字重会放大笔画占用，改用细字重减小像素点亮面积。
  Widget _buildClockText() {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hh:$mm',
      style: TextStyle(
        color: _infoColor(1.0),
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
      style: TextStyle(
        color: _infoColor(0.75),
        fontSize: 18,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
      ),
    );
  }

  /// 状态信息块：服务端状态（实例名 · 状态）与系统占用行
  /// （CPU / 设备内存 / 服务端内存，按各自的开关逐段拼装）。
  Widget _buildStatusBlock() {
    final server = _serverController;
    final wantsSystem = _showCpu || _showMem || _showServerMem;

    final lines = <Widget>[];

    if (_showServerStatus) {
      final status = server?.status ?? ServerStatus.stopped;
      final statusText = context.tr(_statusKey(status));
      final name = server?.runningInstanceName?.trim() ?? '';
      final text = name.isNotEmpty
          ? context.tr('sleep.serverLine', {
              'name': name,
              'status': statusText,
            })
          : statusText;
      lines.add(_dimText(text));
    }

    // 任一系统类开关开启才订阅 SystemMonitorScope 实现按 2s 轮询联动刷新。
    final info = wantsSystem ? SystemMonitorScope.of(context).info : null;
    final segments = <String>[];
    if (_showCpu) {
      final cpu = info?.cpuUsage ?? -1;
      segments.add(
        context.tr('sleep.sysCpu', {
          'cpu': cpu >= 0 ? '${cpu.toStringAsFixed(1)}%' : '--',
        }),
      );
    }
    if (_showMem && info != null) {
      segments.add(
        context.tr('sleep.sysMem', {
          'used': _gb(info.usedMemMb),
          'total': _gb(info.totalMemMb),
        }),
      );
    }
    // 服务端进程不存在时原生不提供统计，自动隐藏该段。
    if (_showServerMem && info?.serverMemMb != null) {
      segments.add(
        context.tr('sleep.sysServerMem', {
          'mem': _gb(info!.serverMemMb!),
        }),
      );
    }
    if (segments.isNotEmpty) lines.add(_dimText(segments.join(' · ')));

    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: lines);
  }

  Widget _dimText(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: _infoColor(0.6),
        fontSize: 14,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
      ),
    );
  }

  String _statusKey(ServerStatus s) => switch (s) {
    ServerStatus.stopped => 'server.statusStopped',
    ServerStatus.preparing => 'server.statusPreparing',
    ServerStatus.starting => 'server.statusStarting',
    ServerStatus.running => 'server.statusRunning',
    ServerStatus.stopping => 'server.statusStopping',
  };

  /// 亮起像素面积最小的 GB 格式（一位小数）。
  String _gb(int mb) => (mb / 1024).toStringAsFixed(1);
}