import 'dart:io';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import '../theme/precipitation_effect_mode.dart';
import '../theme/theme_scope.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeScope = ThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('appearance.title'))),
      body: ListView(
        children: [
          // ── 主题模式 ──
          _sectionHeader(theme, context.tr('appearance.themeModeSection')),
          RadioGroup<ThemeMode>(
            groupValue: themeScope.themeMode,
            onChanged: (mode) {
              if (mode != null) themeScope.setThemeMode(mode);
            },
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text(context.tr('themeMode.system')),
                  secondary: const Icon(Icons.brightness_auto),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text(context.tr('themeMode.dark')),
                  secondary: const Icon(Icons.dark_mode),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: Text(context.tr('themeMode.light')),
                  secondary: const Icon(Icons.light_mode),
                  value: ThemeMode.light,
                ),
              ],
            ),
          ),

          const Divider(),

          // ── 主题色 ──
          _sectionHeader(theme, context.tr('appearance.themeColorSection')),

          // 跟随系统主题色（仅 Android 12+ 支持）。
          if (Platform.isAndroid)
            SwitchListTile(
              title: Text(context.tr('appearance.dynamicColor')),
              subtitle: Text(context.tr('appearance.dynamicColorSubtitle')),
              secondary: const Icon(Icons.auto_awesome),
              value: themeScope.useDynamicColor,
              onChanged: (v) => themeScope.setUseDynamicColor(v),
            ),

          // 自定义种子色（当跟随系统主题色关闭时可用）。
          ListTile(
            leading: const Icon(Icons.palette),
            title: Text(context.tr('appearance.customSeed')),
            subtitle: Text(
              themeScope.useDynamicColor
                  ? context.tr('appearance.dynamicColorOnHint')
                  : context.tr(_currentSeedLabel(themeScope.seedColor)),
            ),
            trailing: CircleAvatar(
              radius: 14,
              backgroundColor: themeScope.seedColor,
            ),
            enabled: !themeScope.useDynamicColor,
            onTap: themeScope.useDynamicColor
                ? null
                : () => _showSeedColorPicker(context, themeScope),
          ),

          const Divider(),

          _sectionHeader(theme, context.tr('appearance.effectSection')),
          SwitchListTile(
            title: Text(context.tr('appearance.precipitation')),
            subtitle: Text(context.tr('appearance.precipitationSubtitle')),
            secondary: const Icon(Icons.ac_unit),
            value: themeScope.snowfallEnabled,
            onChanged: (v) => themeScope.setSnowfallEnabled(v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SegmentedButton<PrecipitationEffectMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PrecipitationEffectMode.snow,
                  icon: const Icon(Icons.ac_unit),
                  label: Text(context.tr('appearance.effect.snow')),
                ),
                ButtonSegment(
                  value: PrecipitationEffectMode.rain,
                  icon: const Icon(Icons.water_drop_outlined),
                  label: Text(context.tr('appearance.effect.rain')),
                ),
                ButtonSegment(
                  value: PrecipitationEffectMode.hail,
                  icon: const Icon(Icons.circle_outlined),
                  label: Text(context.tr('appearance.effect.hail')),
                ),
              ],
              selected: {themeScope.precipitationMode},
              onSelectionChanged: (selected) {
                themeScope.setPrecipitationMode(selected.first);
              },
            ),
          ),
        ],
      ),
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

  void _showSeedColorPicker(BuildContext context, ThemeScope themeScope) {
    // 用 StatefulWidget 的临时包装来管理弹窗内的临时选中色。
    showDialog<Color>(
      context: context,
      builder: (ctx) => _SeedColorPickerDialog(
        initialColor: themeScope.seedColor,
        presetColors: _presetColors,
      ),
    ).then((result) {
      if (result != null) themeScope.setSeedColor(result);
    });
  }
}

/// 种子色选择弹窗：预设色板 + HSV 色轮双选项卡。
class _SeedColorPickerDialog extends StatefulWidget {
  const _SeedColorPickerDialog({
    required this.initialColor,
    required this.presetColors,
  });

  final Color initialColor;
  final List<_SeedColorOption> presetColors;

  @override
  State<_SeedColorPickerDialog> createState() => _SeedColorPickerDialogState();
}

class _SeedColorPickerDialogState extends State<_SeedColorPickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late Color _pickedColor;

  @override
  void initState() {
    super.initState();
    _pickedColor = widget.initialColor;
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(context.tr('appearance.seedPickerTitle')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabCtrl,
              tabs: [
                Tab(text: context.tr('appearance.seedTab.preset')),
                Tab(text: context.tr('appearance.seedTab.wheel')),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              // 给 TabBarView 固定高度以撑开内容。
              height: 260,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── 预设色板 ──
                  GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    shrinkWrap: true,
                    children: widget.presetColors.map((option) {
                      final isSelected =
                          _pickedColor.toARGB32() == option.color.toARGB32();
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _pickedColor = option.color),
                        child: Tooltip(
                          message: context.tr(option.labelKey),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: option.color,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: option.color.withValues(
                                          alpha: 0.6,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 22,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // ── HSV 色轮 ──
                  SingleChildScrollView(
                    child: ColorPicker(
                      color: _pickedColor,
                      onColorChanged: (c) => setState(() => _pickedColor = c),
                      heading: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          context.tr('appearance.freeColor'),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      subheading: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          context.tr('appearance.hueBrightness'),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      wheelSubheading: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          context.tr('appearance.hueRing'),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      showMaterialName: false,
                      showColorName: true,
                      showColorCode: true,
                      colorCodeHasColor: true,
                      showRecentColors: false,
                      enableTonalPalette: false,
                      pickerTypeLabels: {
                        ColorPickerType.wheel: context.tr(
                          'appearance.colorWheel',
                        ),
                      },
                      pickersEnabled: const <ColorPickerType, bool>{
                        ColorPickerType.both: false,
                        ColorPickerType.primary: false,
                        ColorPickerType.accent: false,
                        ColorPickerType.bw: false,
                        ColorPickerType.custom: false,
                        ColorPickerType.wheel: true,
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pickedColor),
          child: Text(context.tr('common.confirm')),
        ),
      ],
    );
  }
}

class _SeedColorOption {
  const _SeedColorOption(this.labelKey, this.color);
  final String labelKey;
  final Color color;
}
