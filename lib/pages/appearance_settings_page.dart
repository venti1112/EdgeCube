import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../theme/precipitation_effect_mode.dart';
import '../theme/theme_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/miuix_dialog.dart';

/// 外观设置子页面：主题模式、种子色、跟随系统主题色。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  /// 预设种子色列表（标签存翻译 key，展示时经 context.tr 解析）。
  static const List<_SeedColorOption> _presetColors = [
    _SeedColorOption('appearance.color.green', Colors.green),
    _SeedColorOption('appearance.color.blue', Colors.blue),
    _SeedColorOption('appearance.color.purple', Colors.purple),
    _SeedColorOption('appearance.color.red', Colors.red),
    _SeedColorOption('appearance.color.orange', Colors.orange),
    _SeedColorOption('appearance.color.teal', Colors.teal),
    _SeedColorOption('appearance.color.pink', Colors.pink),
    _SeedColorOption('appearance.color.indigo', Colors.indigo),
  ];

  static const List<({PrecipitationEffectMode mode, String labelKey})>
  _effectModes = [
    (mode: PrecipitationEffectMode.snow, labelKey: 'appearance.effect.snow'),
    (mode: PrecipitationEffectMode.rain, labelKey: 'appearance.effect.rain'),
    (mode: PrecipitationEffectMode.hail, labelKey: 'appearance.effect.hail'),
  ];

  @override
  Widget build(BuildContext context) {
    final themeScope = ThemeScope.of(context);

    return EcSettingsPage(
      title: context.tr('appearance.title'),
      children: [
        // ── 主题模式 ──
        MiuixSmallTitle(context.tr('appearance.themeModeSection')),
        for (final entry in const [
          (mode: ThemeMode.system, labelKey: 'themeMode.system'),
          (mode: ThemeMode.dark, labelKey: 'themeMode.dark'),
          (mode: ThemeMode.light, labelKey: 'themeMode.light'),
        ])
          MiuixRadioButtonPreference(
            title: context.tr(entry.labelKey),
            selected: themeScope.themeMode == entry.mode,
            onClick: () => themeScope.setThemeMode(entry.mode),
          ),

        // ── 主题色 ──
        MiuixSmallTitle(context.tr('appearance.themeColorSection')),

        // 跟随系统主题色（仅 Android 12+ 支持）。
        if (Platform.isAndroid)
          MiuixSwitchPreference(
            startAction: prefIcon(Icons.auto_awesome),
            title: context.tr('appearance.dynamicColor'),
            summary: context.tr('appearance.dynamicColorSubtitle'),
            value: themeScope.useDynamicColor,
            onChanged: themeScope.setUseDynamicColor,
          ),

        // 自定义种子色（当跟随系统主题色关闭时可用）。
        MiuixArrowPreference(
          startAction: prefIcon(Icons.palette),
          title: context.tr('appearance.customSeed'),
          summary: themeScope.useDynamicColor
              ? context.tr('appearance.dynamicColorOnHint')
              : context.tr(_currentSeedLabel(themeScope.seedColor)),
          enabled: !themeScope.useDynamicColor,
          endActions: [_ColorDot(color: themeScope.seedColor)],
          onClick: themeScope.useDynamicColor
              ? null
              : () => _showSeedColorPicker(context, themeScope),
        ),

        // ── 雨雪特效 ──
        MiuixSmallTitle(context.tr('appearance.effectSection')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.ac_unit),
          title: context.tr('appearance.precipitation'),
          summary: context.tr('appearance.precipitationSubtitle'),
          value: themeScope.snowfallEnabled,
          onChanged: themeScope.setSnowfallEnabled,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: MiuixTabRow(
            tabs: [for (final e in _effectModes) context.tr(e.labelKey)],
            selectedTabIndex: _effectModes.indexWhere(
              (e) => e.mode == themeScope.precipitationMode,
            ),
            onTabSelected: (i) =>
                themeScope.setPrecipitationMode(_effectModes[i].mode),
          ),
        ),
      ],
    );
  }

  String _currentSeedLabel(Color c) {
    final match = _presetColors.firstWhere(
      (o) => o.color.toARGB32() == c.toARGB32(),
      orElse: () =>
          const _SeedColorOption('appearance.color.custom', Colors.transparent),
    );
    return match.labelKey;
  }

  Future<void> _showSeedColorPicker(
    BuildContext context,
    ThemeScope themeScope,
  ) async {
    final picked = await showMiuixDialog<Color>(
      context: context,
      title: context.tr('appearance.seedPickerTitle'),
      builder: (ctx) => _SeedColorPickerContent(
        initialColor: themeScope.seedColor,
        presetColors: _presetColors,
      ),
    );
    if (picked != null) themeScope.setSeedColor(picked);
  }
}

/// 种子色选择弹窗内容：预设色板 + 自由取色两个分段页。
class _SeedColorPickerContent extends StatefulWidget {
  const _SeedColorPickerContent({
    required this.initialColor,
    required this.presetColors,
  });

  final Color initialColor;
  final List<_SeedColorOption> presetColors;

  @override
  State<_SeedColorPickerContent> createState() =>
      _SeedColorPickerContentState();
}

class _SeedColorPickerContentState extends State<_SeedColorPickerContent> {
  late Color _pickedColor = widget.initialColor;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Miuix 没有 TabBarView 的对应物，这里用分段控制器 + IndexedStack
        // 自行同步，两页等高避免切换时对话框高度跳变。
        MiuixTabRow(
          tabs: [
            context.tr('appearance.seedTab.preset'),
            context.tr('appearance.seedTab.wheel'),
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
              // ── 预设色板 ──
              SingleChildScrollView(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final option in widget.presetColors)
                      _PresetSwatch(
                        color: option.color,
                        selected:
                            _pickedColor.toARGB32() == option.color.toARGB32(),
                        onTap: () =>
                            setState(() => _pickedColor = option.color),
                      ),
                  ],
                ),
              ),

              // ── 自由取色 ──
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
class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
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
        curve: MiuixMotion.standardDecelerate,
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
            ? const MiuixIcon(icon: Icons.check, size: 22, tint: Colors.white)
            : null,
      ),
    );
  }
}

/// 设置行尾部展示当前种子色的小圆点。
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

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

class _SeedColorOption {
  const _SeedColorOption(this.labelKey, this.color);
  final String labelKey;
  final Color color;
}
