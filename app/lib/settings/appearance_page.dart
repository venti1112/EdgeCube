import 'package:file_picker/file_picker.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'appearance.dart';
import 'bg_store.dart';

/// 外观设置页:主题模式/主题色/字体/控制台/背景/毛玻璃。
///
/// 每个设置项都直接 watch / read 它自己的全局 Provider
/// (见 appearance.dart 的「单项设置全局 Provider」一节),
/// 所以「改背景色」不会牵连毛玻璃那几个滑块重建。
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  Future<Color?> _showColorPickerDialog(
    BuildContext context,
    String title,
    Color current,
  ) async {
    var picked = current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        // flex_color_picker 基于 flutter/material,包一层同种子色的
        // material 主题保持观感一致
        content: material.Theme(
          data: material.ThemeData(
            colorScheme: material.ColorScheme.fromSeed(seedColor: current),
          ),
          child: SingleChildScrollView(
            child: ColorPicker(
              color: current,
              onColorChanged: (color) => picked = color,
              // 只保留 HSV 颜色转盘
              pickersEnabled: const <ColorPickerType, bool>{
                ColorPickerType.primary: false,
                ColorPickerType.accent: false,
                ColorPickerType.wheel: true,
              },
              enableShadesSelection: false,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return confirmed == true ? picked : null;
  }

  Future<void> _pickBackgroundImage(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (files.isEmpty) return;
    try {
      final stored = await persistBackgroundImage(files.single);
      await ref.read(backgroundImageProvider.notifier).set(stored);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存背景图片失败:$e')),
        );
      }
    }
  }

  /// 主题色选择:选完直接写回 seedColorProvider
  Future<void> _pickSeedColor(BuildContext context, WidgetRef ref) async {
    final color = await _showColorPickerDialog(
      context,
      '自定义主题色',
      ref.read(seedColorProvider),
    );
    if (color != null) await ref.read(seedColorProvider.notifier).set(color);
  }

  /// 背景色选择:选完直接写回 backgroundColorProvider
  Future<void> _pickBackgroundColor(BuildContext context, WidgetRef ref) async {
    final color = await _showColorPickerDialog(
      context,
      '背景色',
      ref.read(backgroundColorProvider),
    );
    if (color != null) {
      await ref.read(backgroundColorProvider.notifier).set(color);
    }
  }

  /// 改字体族:确定写值、留空 = 恢复默认、取消什么也不做。
  ///
  /// 没有「列出已装字体」这一步 —— Flutter 不提供跨平台的枚举接口，
  /// 所以让用户填字体族名（桌面端可先用 `fc-list` 查）。
  Future<void> _editFont(
    BuildContext context,
    String title,
    String? current,
    Future<void> Function(String?) apply,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _FontFamilyDialog(title: title, initial: current),
    );
    if (result == null) return;
    await apply(result.isEmpty ? null : result);
  }

  String _colorHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  String _imageLabel(String src) {
    if (src.startsWith('data:')) return '已选择图片';
    final name = src.split(RegExp(r'[\\/]')).last;
    return name.isEmpty ? '已选择图片' : name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final followSystemColor = ref.watch(followSystemColorProvider);
    final seedColor = ref.watch(seedColorProvider);
    final globalFontFamily = ref.watch(globalFontFamilyProvider);
    final consoleFontFamily = ref.watch(consoleFontFamilyProvider);
    final showConsoleKeys = ref.watch(showConsoleKeysProvider);
    final backgroundType = ref.watch(backgroundTypeProvider);
    final backgroundColor = ref.watch(backgroundColorProvider);
    final backgroundImage = ref.watch(backgroundImageProvider);
    final navBlurEnabled = ref.watch(navBlurEnabledProvider);
    final navBlurSigma = ref.watch(navBlurSigmaProvider);
    final navOpacity = ref.watch(navOpacityProvider);
    final contentBlurEnabled = ref.watch(contentBlurEnabledProvider);
    final contentBlurSigma = ref.watch(contentBlurSigmaProvider);
    final contentOpacity = ref.watch(contentOpacityProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('外观'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          _sectionLabel(context, '主题模式'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (value) =>
                ref.read(themeModeProvider.notifier).set(value!),
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('自动'),
                  subtitle: Text('跟随系统深浅色'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('浅色'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('深色'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _sectionLabel(context, '主题色'),
          SwitchListTile(
            title: const Text('跟随系统主题色'),
            subtitle: const Text('使用系统壁纸动态取色(Android 12+)'),
            value: followSystemColor,
            onChanged: (v) =>
                ref.read(followSystemColorProvider.notifier).set(v),
          ),
          ListTile(
            leading: CircleAvatar(radius: 18, backgroundColor: seedColor),
            title: const Text('自定义主题色'),
            subtitle: Text(_colorHex(seedColor)),
            enabled: !followSystemColor,
            trailing: const Icon(Icons.chevron_right),
            onTap: followSystemColor
                ? null
                : () => _pickSeedColor(context, ref),
          ),
          const Divider(height: 1),
          _sectionLabel(context, '字体'),
          ListTile(
            key: const Key('appearance_global_font'),
            leading: const Icon(Icons.text_fields),
            // 标题用当前字体渲染:填错了（系统里没这个字体）一眼就能看出来
            title: Text('全局字体', style: TextStyle(fontFamily: globalFontFamily)),
            subtitle: Text(globalFontFamily ?? '跟随系统默认'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editFont(
              context,
              '全局字体',
              globalFontFamily,
              (v) => ref.read(globalFontFamilyProvider.notifier).set(v),
            ),
          ),
          ListTile(
            key: const Key('appearance_console_font'),
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('控制台字体'),
            subtitle: Text(consoleFontFamily ?? '默认等宽字体（monospace）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editFont(
              context,
              '控制台字体',
              consoleFontFamily,
              (v) => ref.read(consoleFontFamilyProvider.notifier).set(v),
            ),
          ),
          const Divider(height: 1),
          _sectionLabel(context, '控制台'),
          SwitchListTile(
            key: const Key('appearance_console_keys'),
            title: const Text('显示扩展按键栏'),
            subtitle: const Text('控制台底部的 ESC / TAB / 方向键等按键'),
            value: showConsoleKeys,
            onChanged: (v) =>
                ref.read(showConsoleKeysProvider.notifier).set(v),
          ),
          const Divider(height: 1),
          _sectionLabel(context, '背景'),
          RadioGroup<BackgroundType>(
            groupValue: backgroundType,
            onChanged: (value) =>
                ref.read(backgroundTypeProvider.notifier).set(value!),
            child: const Column(
              children: [
                RadioListTile<BackgroundType>(
                  value: BackgroundType.none,
                  title: Text('无'),
                  subtitle: Text('跟随主题背景'),
                ),
                RadioListTile<BackgroundType>(
                  value: BackgroundType.color,
                  title: Text('纯色'),
                ),
                RadioListTile<BackgroundType>(
                  value: BackgroundType.image,
                  title: Text('图片'),
                ),
              ],
            ),
          ),
          if (backgroundType == BackgroundType.color)
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: backgroundColor,
              ),
              title: const Text('背景色'),
              subtitle: Text(_colorHex(backgroundColor)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickBackgroundColor(context, ref),
            ),
          if (backgroundType == BackgroundType.image)
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('背景图片'),
              subtitle: Text(
                backgroundImage == null ? '点击选择图片' : _imageLabel(backgroundImage),
              ),
              trailing: backgroundImage == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '清除背景图片',
                      onPressed: () =>
                          ref.read(backgroundImageProvider.notifier).set(null),
                    ),
              onTap: () => _pickBackgroundImage(context, ref),
            ),
          const Divider(height: 1),
          _sectionLabel(context, '毛玻璃'),
          SwitchListTile(
            title: const Text('底栏/侧栏模糊'),
            subtitle: const Text('导航栏高斯模糊透出背景'),
            value: navBlurEnabled,
            onChanged: (v) =>
                ref.read(navBlurEnabledProvider.notifier).set(v),
          ),
          if (navBlurEnabled)
            _sliderTile(
              title: '底栏/侧栏模糊半径',
              value: navBlurSigma,
              min: AppearanceSettings.blurSigmaMin,
              max: AppearanceSettings.blurSigmaMax,
              step: 1,
              onChanged: (v) => ref.read(navBlurSigmaProvider.notifier).set(v),
            ),
          _sliderTile(
            title: '底栏/侧栏不透明度',
            value: navOpacity,
            min: AppearanceSettings.opacityMin,
            max: AppearanceSettings.opacityMax,
            step: 0.01,
            percent: true,
            onChanged: (v) => ref.read(navOpacityProvider.notifier).set(v),
          ),
          SwitchListTile(
            title: const Text('内容区模糊'),
            subtitle: const Text('内容容器层整体高斯模糊'),
            value: contentBlurEnabled,
            onChanged: (v) =>
                ref.read(contentBlurEnabledProvider.notifier).set(v),
          ),
          if (contentBlurEnabled)
            _sliderTile(
              title: '内容区模糊半径',
              value: contentBlurSigma,
              min: AppearanceSettings.blurSigmaMin,
              max: AppearanceSettings.blurSigmaMax,
              step: 1,
              onChanged: (v) =>
                  ref.read(contentBlurSigmaProvider.notifier).set(v),
            ),
          _sliderTile(
            title: '内容表面不透明度',
            value: contentOpacity,
            min: AppearanceSettings.opacityMin,
            max: AppearanceSettings.opacityMax,
            step: 0.01,
            percent: true,
            onChanged: (v) => ref.read(contentOpacityProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }

  /// 标题行 + 滑块
  Widget _sliderTile({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 1,
    double step = 0.01,
    bool percent = false,
  }) {
    String label(double v) =>
        percent ? '${(v * 100).round()}%' : v.round().toString();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title)),
              Text(label(value)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: label(value),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// 字体族名输入框。
///
/// 返回值:`null` = 取消,空串 = 恢复默认,非空 = 新字体族名。
/// 用「空串 vs null」区分「清空」和「取消」——这个区别只有调用方在意,
/// 所以不额外搞个结果类型。
class _FontFamilyDialog extends StatefulWidget {
  const _FontFamilyDialog({required this.title, required this.initial});

  final String title;
  final String? initial;

  @override
  State<_FontFamilyDialog> createState() => _FontFamilyDialogState();
}

class _FontFamilyDialogState extends State<_FontFamilyDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String raw) => Navigator.of(context).pop(raw.trim());

  @override
  Widget build(BuildContext context) {
    // 预览:输入框本身就用这个字体渲染，边打边看
    final preview = _controller.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(fontFamily: preview.isEmpty ? null : preview),
        decoration: const InputDecoration(
          labelText: '字体族名',
          hintText: '如 Noto Sans CJK SC、JetBrains Mono',
          helperText: '填系统里已装的字体；留空 = 默认字体',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => _submit(''),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => _submit(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
