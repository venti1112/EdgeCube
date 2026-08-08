import 'dart:io';

import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../config/sleep_screen_store.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/error_dialog.dart';
import '../server/power_service.dart';

/// 后台保活设置子页面（仅 Android）。
///
/// 包含：忽略电池优化、锁屏保活（WakeLock + WifiLock）、状态悬浮窗
/// （显示内容 / 仅状态点 / 点颜色绑定 / 穿透模式）、厂商自启动入口。
class KeepAliveSettingsPage extends StatefulWidget {
  const KeepAliveSettingsPage({super.key});

  @override
  State<KeepAliveSettingsPage> createState() => _KeepAliveSettingsPageState();
}

class _KeepAliveSettingsPageState extends State<KeepAliveSettingsPage>
    with WidgetsBindingObserver {
  bool _ignoringBattery = true;
  bool _batteryLoaded = false;

  bool _wakeLockEnabled = true;
  bool _keepScreenOnEnabled = false;
  bool _overlayEnabled = false;
  bool _canDrawOverlays = false;
  bool _loaded = false;
  OverlayOptions _overlayOptions = const OverlayOptions();

  /// 熄屏偏好（跟随防息屏显示）：时钟开关 / 无操作自动进入时长。
  bool _sleepShowClock = SleepScreenStore.defaultShowClock;
  int? _sleepIdleMinutes = SleepScreenStore.defaultIdleTimeoutMinutes;

  /// 厂商自启动设置页是否可打开（仅部分 OEM ROM 支持）。
  bool _canOpenAutoStart = false;

  /// 用户为开启悬浮窗而去系统设置授权，返回后待自动开启。
  bool _pendingOverlayEnable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBattery();
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统电池/悬浮窗设置页返回前台时刷新状态。
    if (state == AppLifecycleState.resumed) {
      _refreshBattery();
      _refreshOverlayPermission();
    }
  }

  Future<void> _loadAll() async {
    if (!Platform.isAndroid) return;
    final wakeLock = await PowerService.isWakeLockEnabled();
    final keepScreenOn = await PowerService.isKeepScreenOnEnabled();
    final overlay = await PowerService.isOverlayEnabled();
    final canDraw = await PowerService.canDrawOverlays();
    final overlayOptions = await PowerService.getOverlayOptions();
    final snapshot =
        await BatteryOptimizationHelper.getBatteryRestrictionSnapshot();
    final sleepShowClock = await SleepScreenStore.loadShowClock();
    final sleepIdleMinutes = await SleepScreenStore.loadIdleTimeoutMinutes();
    if (!mounted) return;
    setState(() {
      _wakeLockEnabled = wakeLock;
      _keepScreenOnEnabled = keepScreenOn;
      _overlayEnabled = overlay;
      _canDrawOverlays = canDraw;
      _overlayOptions = overlayOptions;
      _canOpenAutoStart = snapshot.canOpenAutoStartSettings;
      _sleepShowClock = sleepShowClock;
      _sleepIdleMinutes = sleepIdleMinutes;
      _loaded = true;
    });
  }

  // —— 电池优化 ——

  Future<void> _refreshBattery() async {
    final ignoring = await PowerService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _ignoringBattery = ignoring;
      _batteryLoaded = true;
    });
  }

  Future<void> _requestIgnoreBattery() async {
    // battery_optimization_helper：优先直接弹系统白名单对话框，个别 ROM
    // 不支持时自动退回打开电池优化设置页。
    await BatteryOptimizationHelper.ensureOptimizationDisabledDetailed();
    // 请求后立即刷新一次；返回前台时还会再刷新。
    await _refreshBattery();
  }

  /// 打开厂商自启动管理页（小米/华为/OPPO 等 OEM ROM 的额外后台限制入口）。
  Future<void> _openAutoStartSettings() async {
    final opened = await BatteryOptimizationHelper.openAutoStartSettings();
    if (!opened && mounted) {
      showErrorDialog(context, context.tr('settings.autoStart.openFailed'));
    }
  }

  // —— 锁屏保活 / 悬浮窗 ——

  Future<void> _setWakeLock(bool value) async {
    setState(() => _wakeLockEnabled = value);
    await PowerService.setWakeLockEnabled(value);
  }

  Future<void> _setKeepScreenOn(bool value) async {
    setState(() => _keepScreenOnEnabled = value);
    await PowerService.setKeepScreenOnEnabled(value);
  }

  Future<void> _setOverlay(bool value) async {
    if (value && !_canDrawOverlays) {
      // 未授权：先跳系统设置授予悬浮窗权限，返回前台时经
      // didChangeAppLifecycleState 刷新状态后自动打开开关。
      _pendingOverlayEnable = true;
      await PowerService.requestOverlayPermission();
      return;
    }
    setState(() => _overlayEnabled = value);
    await PowerService.setOverlayEnabled(value);
  }

  /// 更新悬浮窗设置并同步到原生（正在显示时立即重建生效）。
  Future<void> _setOverlayOptions(OverlayOptions options) async {
    setState(() => _overlayOptions = options);
    await PowerService.setOverlayOptions(options);
  }

  /// 从系统设置返回时刷新悬浮窗权限；若为开启悬浮窗而去授权且已授予，自动打开。
  Future<void> _refreshOverlayPermission() async {
    if (!Platform.isAndroid) return;
    final canDraw = await PowerService.canDrawOverlays();
    if (!mounted) return;
    setState(() => _canDrawOverlays = canDraw);
    if (_pendingOverlayEnable) {
      _pendingOverlayEnable = false;
      if (canDraw) await _setOverlay(true);
    }
  }

  // —— UI ——

  @override
  Widget build(BuildContext context) {
    return EcSettingsPage(
      title: context.tr('settings.section.keepAlive'),
      children: [
        MiuixSmallTitle(context.tr('settings.keepAlive.systemSection')),
        _buildBatteryTile(context),
        if (_canOpenAutoStart)
          MiuixArrowPreference(
            startAction: prefIcon(Icons.restart_alt),
            title: context.tr('settings.autoStart.title'),
            summary: context.tr('settings.autoStart.subtitle'),
            endActions: [const MiuixIcon(icon: Icons.open_in_new, size: 18)],
            onClick: _openAutoStartSettings,
          ),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.lock_clock_outlined),
          title: context.tr('settings.wakeLock.title'),
          summary: context.tr('settings.wakeLock.subtitle'),
          value: _wakeLockEnabled,
          enabled: _loaded,
          onChanged: _setWakeLock,
        ),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.visibility_outlined),
          title: context.tr('settings.keepScreenOn.title'),
          summary: context.tr('settings.keepScreenOn.subtitle'),
          value: _keepScreenOnEnabled,
          enabled: _loaded,
          onChanged: _setKeepScreenOn,
        ),
        // 熄屏设置跟随防息屏：仅在防息屏开启时显示（熄屏依赖常亮，
        // 不开防息屏时系统会自然息屏，无需熄屏页）。
        if (_keepScreenOnEnabled)
          ..._buildSleepTiles(context),

        MiuixSmallTitle(context.tr('settings.keepAlive.overlaySection')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.picture_in_picture_alt_outlined),
          title: context.tr('settings.overlay.title'),
          summary: _overlayEnabled || _canDrawOverlays
              ? context.tr('settings.overlay.subtitle')
              : context.tr('settings.overlay.needPermission'),
          value: _overlayEnabled && _canDrawOverlays,
          enabled: _loaded,
          onChanged: _setOverlay,
        ),
        if (_overlayEnabled && _canDrawOverlays)
          ..._buildOverlayOptionTiles(context),
      ],
    );
  }

  Widget _buildBatteryTile(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final String summary;
    final Widget? endAction;
    if (!_batteryLoaded) {
      summary = context.tr('settings.battery.checking');
      endAction = null;
    } else if (_ignoringBattery) {
      summary = context.tr('settings.battery.whitelisted');
      endAction = MiuixIcon(
        icon: Icons.check_circle,
        tint: theme.colors.primary,
      );
    } else {
      summary = context.tr('settings.battery.notWhitelisted');
      endAction = MiuixButton(
        onPressed: _requestIgnoreBattery,
        insideMargin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minWidth: 0,
        minHeight: 0,
        child: MiuixText(
          context.tr('common.goToSettings'),
          style: theme.textStyles.button,
        ),
      );
    }

    return MiuixBasicComponent(
      startAction: prefIcon(Icons.battery_saver),
      title: context.tr('settings.battery.title'),
      summary: summary,
      endActions: endAction == null ? null : [endAction],
      // 已在白名单中时无需再申请；点击整行等同于点击「去设置」。
      onClick: (!_batteryLoaded || _ignoringBattery)
          ? null
          : _requestIgnoreBattery,
    );
  }

  /// 熄屏偏好子设置（相对「防息屏」缩进，仅防息屏开启时显示）。
  ///
  /// - 显示时钟：熄屏时黑底上显示极暗时分与日期，关闭后为纯黑屏；
  /// - 无操作自动进入：服务端运行中无操作达到时长后自动进入熄屏，
  ///   防止界面长时间常亮烧屏。
  /// 相对上一级开关缩进，与悬浮窗子设置一致。
  List<Widget> _buildSleepTiles(BuildContext context) {
    const indent = EdgeInsets.only(left: 38);

    String timeoutLabel(int? minutes) {
      return minutes == null
          ? context.tr('sleep.timeout.off')
          : context.tr('sleep.timeout.minutes', {'minutes': '$minutes'});
    }

    return [
      Padding(
        padding: indent,
        child: MiuixSwitchPreference(
          title: context.tr('sleep.showClock'),
          summary: context.tr('sleep.showClockSummary'),
          value: _sleepShowClock,
          enabled: _loaded,
          onChanged: (v) async {
            setState(() => _sleepShowClock = v);
            await SleepScreenStore.save(showClock: v);
          },
        ),
      ),
      Padding(
        padding: indent,
        child: MiuixArrowPreference(
          title: context.tr('sleep.autoEnter'),
          summary: timeoutLabel(_sleepIdleMinutes),
          enabled: _loaded,
          onClick: () => _pickSleepTimeout(timeoutLabel),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 54, right: 16, bottom: 8),
        child: MiuixText(
          context.tr('sleep.autoEnterHint'),
          style: MiuixTheme.of(context).textStyles.footnote1,
          color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
        ),
      ),
    ];
  }

  /// 弹出无操作自动进入时长选择。
  Future<void> _pickSleepTimeout(
    String Function(int?) label,
  ) async {
    final selected = await showMiuixSingleChoice<int>(
      context: context,
      title: context.tr('sleep.autoEnter'),
      options: SleepScreenStore.idleTimeoutOptions,
      // 关闭（0）与未配置（null）等价展示。
      selected: _sleepIdleMinutes ?? 0,
      labelOf: (c, m) => label(m == 0 ? null : m),
    );
    if (selected == null || !mounted) return;
    final minutes = selected == 0 ? null : selected;
    setState(() => _sleepIdleMinutes = minutes);
    await SleepScreenStore.save(idleTimeoutMinutes: minutes);
  }

  /// 悬浮窗子设置：显示内容、仅状态点、点颜色绑定、穿透模式。
  ///
  /// 相对上一级开关缩进，仅悬浮窗开启时显示。
  List<Widget> _buildOverlayOptionTiles(BuildContext context) {
    // 缩进量对齐上级开关的文本区（图标宽 22 + 右侧留白 16 + 行内边距 16）。
    const indent = EdgeInsets.only(left: 38);
    final opts = _overlayOptions;

    Widget check(String titleKey, bool value, ValueChanged<bool> onChanged) {
      return Padding(
        padding: indent,
        child: MiuixCheckboxPreference(
          title: context.tr(titleKey),
          value: value,
          onChanged: onChanged,
          insideMargin: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
        ),
      );
    }

    String dotSourceLabel(BuildContext ctx, OverlayDotSource s) => switch (s) {
      OverlayDotSource.status => ctx.tr('settings.overlay.dotSource.status'),
      OverlayDotSource.cpu => ctx.tr('settings.overlay.dotSource.cpu'),
      OverlayDotSource.mem => ctx.tr('settings.overlay.dotSource.mem'),
      OverlayDotSource.serverMem => ctx.tr(
        'settings.overlay.dotSource.serverMem',
      ),
    };

    return [
      // 显示内容（仅状态点模式下隐藏，避免歧义）。
      if (!opts.dotOnly) ...[
        check(
          'settings.overlay.showCpu',
          opts.showCpu,
          (v) => _setOverlayOptions(opts.copyWith(showCpu: v)),
        ),
        check(
          'settings.overlay.showMem',
          opts.showMem,
          (v) => _setOverlayOptions(opts.copyWith(showMem: v)),
        ),
        check(
          'settings.overlay.showServerMem',
          opts.showServerMem,
          (v) => _setOverlayOptions(opts.copyWith(showServerMem: v)),
        ),
      ],
      // 仅状态点模式。
      Padding(
        padding: indent,
        child: MiuixSwitchPreference(
          title: context.tr('settings.overlay.dotOnly'),
          summary: context.tr('settings.overlay.dotOnlySubtitle'),
          value: opts.dotOnly,
          onChanged: (v) => _setOverlayOptions(opts.copyWith(dotOnly: v)),
        ),
      ),
      // 点颜色绑定。
      Padding(
        padding: indent,
        child: MiuixArrowPreference(
          title: context.tr('settings.overlay.dotSource'),
          summary: dotSourceLabel(context, opts.dotColorSource),
          onClick: () => _pickOverlayDotSource(dotSourceLabel),
        ),
      ),
      // 穿透模式。
      Padding(
        padding: indent,
        child: MiuixSwitchPreference(
          title: context.tr('settings.overlay.clickThrough'),
          summary: context.tr('settings.overlay.clickThroughSubtitle'),
          value: opts.clickThrough,
          onChanged: (v) => _setOverlayOptions(opts.copyWith(clickThrough: v)),
        ),
      ),
    ];
  }

  /// 弹出点颜色绑定来源选择对话框。
  Future<void> _pickOverlayDotSource(
    String Function(BuildContext, OverlayDotSource) label,
  ) async {
    final selected = await showMiuixSingleChoice<OverlayDotSource>(
      context: context,
      title: context.tr('settings.overlay.dotSource'),
      options: OverlayDotSource.values,
      selected: _overlayOptions.dotColorSource,
      labelOf: label,
    );
    if (selected != null) {
      await _setOverlayOptions(
        _overlayOptions.copyWith(dotColorSource: selected),
      );
    }
  }
}
