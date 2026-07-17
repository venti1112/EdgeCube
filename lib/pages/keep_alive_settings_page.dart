import 'dart:io';

import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
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
  bool _overlayEnabled = false;
  bool _canDrawOverlays = false;
  bool _loaded = false;
  OverlayOptions _overlayOptions = const OverlayOptions();

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
    final overlay = await PowerService.isOverlayEnabled();
    final canDraw = await PowerService.canDrawOverlays();
    final overlayOptions = await PowerService.getOverlayOptions();
    final snapshot =
        await BatteryOptimizationHelper.getBatteryRestrictionSnapshot();
    if (!mounted) return;
    setState(() {
      _wakeLockEnabled = wakeLock;
      _overlayEnabled = overlay;
      _canDrawOverlays = canDraw;
      _overlayOptions = overlayOptions;
      _canOpenAutoStart = snapshot.canOpenAutoStartSettings;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('settings.autoStart.openFailed')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // —— 锁屏保活 / 悬浮窗 ——

  Future<void> _setWakeLock(bool value) async {
    setState(() => _wakeLockEnabled = value);
    await PowerService.setWakeLockEnabled(value);
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.section.keepAlive'))),
      body: ListView(
        children: [
          _sectionHeader(theme, context.tr('settings.keepAlive.systemSection')),
          _buildBatteryTile(context, theme),
          if (_canOpenAutoStart)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(context.tr('settings.autoStart.title')),
              subtitle: Text(context.tr('settings.autoStart.subtitle')),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: _openAutoStartSettings,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_clock_outlined),
            title: Text(context.tr('settings.wakeLock.title')),
            subtitle: Text(context.tr('settings.wakeLock.subtitle')),
            value: _wakeLockEnabled,
            onChanged: _loaded ? _setWakeLock : null,
          ),
          const Divider(),
          _sectionHeader(
            theme,
            context.tr('settings.keepAlive.overlaySection'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: Text(context.tr('settings.overlay.title')),
            subtitle: Text(
              _overlayEnabled || _canDrawOverlays
                  ? context.tr('settings.overlay.subtitle')
                  : context.tr('settings.overlay.needPermission'),
            ),
            value: _overlayEnabled && _canDrawOverlays,
            onChanged: _loaded ? _setOverlay : null,
          ),
          if (_overlayEnabled && _canDrawOverlays)
            ..._buildOverlayOptionTiles(context, theme),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildBatteryTile(BuildContext context, ThemeData theme) {
    final String subtitle;
    final Widget? trailing;
    if (!_batteryLoaded) {
      subtitle = context.tr('settings.battery.checking');
      trailing = null;
    } else if (_ignoringBattery) {
      subtitle = context.tr('settings.battery.whitelisted');
      trailing = const Icon(Icons.check_circle, color: Colors.green);
    } else {
      subtitle = context.tr('settings.battery.notWhitelisted');
      trailing = FilledButton.tonal(
        onPressed: _requestIgnoreBattery,
        child: Text(context.tr('common.goToSettings')),
      );
    }

    return ListTile(
      leading: const Icon(Icons.battery_saver),
      title: Text(context.tr('settings.battery.title')),
      subtitle: Text(subtitle),
      trailing: trailing,
      // 已在白名单中时无需再申请；点击整行等同于点击「去设置」。
      onTap: (!_batteryLoaded || _ignoringBattery)
          ? null
          : _requestIgnoreBattery,
    );
  }

  /// 悬浮窗子设置：显示内容、仅状态点、点颜色绑定、穿透模式。
  ///
  /// 缩进在开关下方（左侧 padding 对齐 ListTile 文本区），仅悬浮窗开启时显示。
  List<Widget> _buildOverlayOptionTiles(BuildContext context, ThemeData theme) {
    const indent = EdgeInsets.only(left: 72, right: 16);
    final opts = _overlayOptions;

    Widget check(String titleKey, bool value, ValueChanged<bool?> onChanged) {
      return Padding(
        padding: indent,
        child: CheckboxListTile(
          title: Text(context.tr(titleKey)),
          value: value,
          onChanged: onChanged,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
      );
    }

    String dotSourceLabel(OverlayDotSource s) => switch (s) {
      OverlayDotSource.status => context.tr('settings.overlay.dotSource.status'),
      OverlayDotSource.cpu => context.tr('settings.overlay.dotSource.cpu'),
      OverlayDotSource.mem => context.tr('settings.overlay.dotSource.mem'),
      OverlayDotSource.serverMem =>
        context.tr('settings.overlay.dotSource.serverMem'),
    };

    return [
      // 显示内容（仅状态点模式下隐藏，避免歧义）。
      if (!opts.dotOnly) ...[
        check(
          'settings.overlay.showCpu',
          opts.showCpu,
          (v) => _setOverlayOptions(opts.copyWith(showCpu: v ?? false)),
        ),
        check(
          'settings.overlay.showMem',
          opts.showMem,
          (v) => _setOverlayOptions(opts.copyWith(showMem: v ?? false)),
        ),
        check(
          'settings.overlay.showServerMem',
          opts.showServerMem,
          (v) => _setOverlayOptions(opts.copyWith(showServerMem: v ?? false)),
        ),
      ],
      // 仅状态点模式。
      Padding(
        padding: indent,
        child: SwitchListTile(
          title: Text(context.tr('settings.overlay.dotOnly')),
          subtitle: Text(context.tr('settings.overlay.dotOnlySubtitle')),
          value: opts.dotOnly,
          onChanged: (v) => _setOverlayOptions(opts.copyWith(dotOnly: v)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      // 点颜色绑定。
      Padding(
        padding: indent,
        child: ListTile(
          title: Text(context.tr('settings.overlay.dotSource')),
          subtitle: Text(dotSourceLabel(opts.dotColorSource)),
          trailing: const Icon(Icons.chevron_right),
          dense: true,
          contentPadding: EdgeInsets.zero,
          onTap: () => _pickOverlayDotSource(dotSourceLabel),
        ),
      ),
      // 穿透模式。
      Padding(
        padding: indent,
        child: SwitchListTile(
          title: Text(context.tr('settings.overlay.clickThrough')),
          subtitle: Text(context.tr('settings.overlay.clickThroughSubtitle')),
          value: opts.clickThrough,
          onChanged: (v) => _setOverlayOptions(opts.copyWith(clickThrough: v)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];
  }

  /// 弹出点颜色绑定来源选择对话框。
  Future<void> _pickOverlayDotSource(
    String Function(OverlayDotSource) label,
  ) async {
    final selected = await showDialog<OverlayDotSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.tr('settings.overlay.dotSource')),
        children: [
          for (final s in OverlayDotSource.values)
            ListTile(
              leading: Icon(
                s == _overlayOptions.dotColorSource
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: s == _overlayOptions.dotColorSource
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text(label(s)),
              onTap: () => Navigator.of(ctx).pop(s),
            ),
        ],
      ),
    );
    if (selected != null) {
      await _setOverlayOptions(
        _overlayOptions.copyWith(dotColorSource: selected),
      );
    }
  }
}
