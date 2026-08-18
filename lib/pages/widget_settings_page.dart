import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../server/widget_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/miuix_dialog.dart';

/// 桌面小组件设置页（仅 Android）。
///
/// 包含：
/// - 总开关 + 添加小组件到桌面；
/// - 展示字段勾选（实例名 / 玩家数 / 地址 / CPU·MEM）；
/// - 启停按钮是否显示；
/// - 外观自定义（背景/文字颜色与透明度）。
///
/// 与 KeepAliveSettingsPage 风格保持一致，使用同一套 Miuix Preference 组件。
class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({super.key});

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage>
    with WidgetsBindingObserver {
  bool _supported = false;
  bool _enabled = false;
  bool _loaded = false;

  WidgetDisplayOptions _options = const WidgetDisplayOptions();

  /// 外观：背景/文字颜色与不透明度。
  WidgetAppearance _appearance = const WidgetAppearance();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!Platform.isAndroid) return;
    final supported = await WidgetService.isSupported();
    final enabled = await WidgetService.isEnabled();
    final options = await WidgetService.getDisplayOptions();
    final appearance = await WidgetService.getAppearance();
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = enabled;
      _options = options;
      _appearance = appearance;
      _loaded = true;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await WidgetService.setEnabled(value);
  }

  Future<void> _updateOptions(WidgetDisplayOptions opts) async {
    setState(() => _options = opts);
    await WidgetService.setDisplayOptions(opts);
  }

  Future<void> _updateAppearance(WidgetAppearance appearance) async {
    setState(() => _appearance = appearance);
    await WidgetService.setAppearance(appearance);
  }

  /// 弹出外观颜色选择对话框（预设色板 + 自由取色）。
  Future<void> _pickAppearanceColor({
    required String titleKey,
    required int current,
    required ValueChanged<int> onPicked,
  }) async {
    final picked = await showMiuixDialog<Color>(
      context: context,
      title: context.tr(titleKey),
      builder: (ctx) => _WidgetColorPickerContent(initialColor: Color(current)),
    );
    if (picked == null || !mounted) return;
    onPicked(picked.toARGB32());
  }

  /// 当前颜色显示名：命中预设则显示名称，否则显示「自定义」。
  String _appearanceColorLabel(int argb) {
    for (final option in _WidgetColorPickerContent.presets) {
      if (option.color.toARGB32() == Color(argb).toARGB32()) {
        return context.tr(option.labelKey);
      }
    }
    return context.tr('sleep.color.custom');
  }

  Future<void> _requestPin() async {
    final pinned = await WidgetService.requestPinWidget();
    if (!mounted) return;
    if (!pinned) {
      // 平台或启动器不支持，回退：在原生层确保 receiver 启用（已默认 enabled），
      // 引导用户从系统的「长按桌面 → 添加小组件」入口添加。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('widget.pinUnsupportedHint')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return EcSettingsPage(
      title: context.tr('settings.widget.title'),
      children: [
        if (!_supported)
          MiuixBasicComponent(
            startAction: prefIcon(Icons.warning_amber_outlined),
            title: context.tr('settings.widget.unsupportedTitle'),
            summary: context.tr('settings.widget.unsupportedSummary'),
          )
        else ...[
          MiuixSwitchPreference(
            startAction: prefIcon(Icons.widgets_outlined),
            title: context.tr('settings.widget.enable'),
            summary: context.tr('settings.widget.enableSummary'),
            value: _enabled,
            enabled: _loaded,
            onChanged: _setEnabled,
          ),
          if (_enabled) ...[
            MiuixSmallTitle(context.tr('settings.widget.sectionDisplay')),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSwitchPreference(
                title: context.tr('settings.widget.showInstance'),
                value: _options.showInstance,
                enabled: _loaded,
                onChanged: (v) =>
                    _updateOptions(_options.copyWith(showInstance: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSwitchPreference(
                title: context.tr('settings.widget.showPlayers'),
                summary: context.tr('settings.widget.showPlayersSummary'),
                value: _options.showPlayers,
                enabled: _loaded,
                onChanged: (v) =>
                    _updateOptions(_options.copyWith(showPlayers: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSwitchPreference(
                title: context.tr('settings.widget.showAddress'),
                summary: context.tr('settings.widget.showAddressSummary'),
                value: _options.showAddress,
                enabled: _loaded,
                onChanged: (v) =>
                    _updateOptions(_options.copyWith(showAddress: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSwitchPreference(
                title: context.tr('settings.widget.showStats'),
                summary: context.tr('settings.widget.showStatsSummary'),
                value: _options.showStats,
                enabled: _loaded,
                onChanged: (v) =>
                    _updateOptions(_options.copyWith(showStats: v)),
              ),
            ),

            MiuixSmallTitle(context.tr('settings.widget.sectionButtons')),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSwitchPreference(
                title: context.tr('settings.widget.showButtons'),
                summary: context.tr('settings.widget.showButtonsSummary'),
                value: _options.showButtons,
                enabled: _loaded,
                onChanged: (v) =>
                    _updateOptions(_options.copyWith(showButtons: v)),
              ),
            ),

            MiuixSmallTitle(context.tr('settings.widget.sectionAppearance')),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixArrowPreference(
                title: context.tr('settings.widget.bgColor'),
                summary: _appearanceColorLabel(_appearance.bgColor),
                enabled: _loaded,
                endActions: [_WidgetColorDot(color: Color(_appearance.bgColor))],
                onClick: () => _pickAppearanceColor(
                  titleKey: 'settings.widget.bgColor',
                  current: _appearance.bgColor,
                  onPicked: (c) => _updateAppearance(_appearance.copyWith(bgColor: c)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSliderPreference(
                startAction: prefIcon(Icons.opacity),
                title: context.tr('settings.widget.bgOpacity'),
                value: _appearance.bgOpacity.toDouble(),
                valueText: '${_appearance.bgOpacity}%',
                min: 5,
                max: 100,
                steps: 19,
                enabled: _loaded,
                onValueChange: (v) =>
                    setState(() => _appearance = _appearance.copyWith(bgOpacity: v.round())),
                onValueChangeFinished: () =>
                    WidgetService.setAppearance(_appearance),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixArrowPreference(
                title: context.tr('settings.widget.textColor'),
                summary: _appearanceColorLabel(_appearance.textColor),
                enabled: _loaded,
                endActions: [_WidgetColorDot(color: Color(_appearance.textColor))],
                onClick: () => _pickAppearanceColor(
                  titleKey: 'settings.widget.textColor',
                  current: _appearance.textColor,
                  onPicked: (c) => _updateAppearance(_appearance.copyWith(textColor: c)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: MiuixSliderPreference(
                startAction: prefIcon(Icons.opacity),
                title: context.tr('settings.widget.textOpacity'),
                value: _appearance.textOpacity.toDouble(),
                valueText: '${_appearance.textOpacity}%',
                min: 5,
                max: 100,
                steps: 19,
                enabled: _loaded,
                onValueChange: (v) =>
                    setState(() => _appearance = _appearance.copyWith(textOpacity: v.round())),
                onValueChangeFinished: () =>
                    WidgetService.setAppearance(_appearance),
              ),
            ),

            MiuixSmallTitle(context.tr('settings.widget.sectionAdd')),
            MiuixArrowPreference(
              startAction: prefIcon(Icons.add_to_home_screen_outlined),
              title: context.tr('settings.widget.addToHome'),
              summary: context.tr('settings.widget.addToHomeSummary'),
              onClick: _requestPin,
            ),
          ],
        ],
      ],
    );
  }
}

/// 外观颜色选择弹窗内容：预设色板 + 自由取色两个分段页。
/// 与熄屏页的取色器保持一致（MiuixTabRow + Wrap + MiuixColorPicker）。
class _WidgetColorPickerContent extends StatefulWidget {
  const _WidgetColorPickerContent({required this.initialColor});

  final Color initialColor;

  /// 预设色板（标签存翻译 key，颜色名 key 与熄屏页共用）。
  static const List<({String labelKey, Color color})> presets = [
    (labelKey: 'sleep.color.white', color: Colors.white),
    (labelKey: 'sleep.color.green', color: Color(0xFF7CFC96)),
    (labelKey: 'sleep.color.blue', color: Color(0xFF8AC8FF)),
    (labelKey: 'sleep.color.purple', color: Color(0xFFD4A5FF)),
    (labelKey: 'sleep.color.red', color: Color(0xFFFF8A80)),
    (labelKey: 'sleep.color.orange', color: Color(0xFFFFCC80)),
    (labelKey: 'sleep.color.teal', color: Color(0xFF80DEEA)),
    (labelKey: 'sleep.color.pink', color: Color(0xFFFFB3C1)),
    (labelKey: 'sleep.color.indigo', color: Color(0xFFB3C6FF)),
  ];

  @override
  State<_WidgetColorPickerContent> createState() =>
      _WidgetColorPickerContentState();
}

class _WidgetColorPickerContentState extends State<_WidgetColorPickerContent> {
  late Color _pickedColor = widget.initialColor;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Miuix 没有 TabBarView 的对应物，分段控制器 + IndexedStack，
        // 两页等高避免切换时对话框高度跳变。
        MiuixTabRow(
          tabs: [
            context.tr('sleep.color.tabPreset'),
            context.tr('sleep.color.tabWheel'),
          ],
          selectedTabIndex: _tab,
          onTabSelected: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: IndexedStack(
            index: _tab,
            children: [
              SingleChildScrollView(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final option in _WidgetColorPickerContent.presets)
                      _WidgetColorSwatch(
                        color: option.color,
                        selected: _pickedColor.toARGB32() ==
                            option.color.toARGB32(),
                        onTap: () =>
                            setState(() => _pickedColor = option.color),
                      ),
                  ],
                ),
              ),
              SingleChildScrollView(
                child: MiuixColorPicker(
                  color: _pickedColor,
                  onColorChanged: (c) => setState(() => _pickedColor = c),
                  colorSpace: MiuixColorSpace.hsv,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(
          children: [
            MiuixTextButton(
              context.tr('common.cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            MiuixButton(
              onPressed: () => Navigator.of(context).pop(_pickedColor),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(context.tr('common.confirm')),
            ),
          ],
        ),
      ],
    );
  }
}

/// 预设色板中的单个色块。
class _WidgetColorSwatch extends StatelessWidget {
  const _WidgetColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: MiuixTheme.of(context).colors.surface,
                  width: 3,
                )
              : null,
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
              : null,
        ),
        child: selected
            ? const MiuixIcon(icon: Icons.check, size: 22, tint: Colors.black54)
            : null,
      ),
    );
  }
}

/// 设置行尾部展示当前颜色的小圆点。
class _WidgetColorDot extends StatelessWidget {
  const _WidgetColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: MiuixTheme.of(context).colors.dividerLine),
      ),
    );
  }
}
