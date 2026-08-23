import 'package:file_picker/file_picker.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_storage/just_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'bg_store.dart';

/// 背景类型:无(跟随主题)/纯色/自定义图片
enum BackgroundType { none, color, image }

/// copyWith 未传参哨兵(区分“未传”与“显式传 null”)
const _unset = Object();

/// 外观设置(不可变状态)
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.followSystemColor = true,
    this.seedColor = defaultSeedColor,
    this.backgroundType = BackgroundType.none,
    this.backgroundColor = defaultBackgroundColor,
    this.backgroundImage,
    this.navBlurEnabled = true,
    this.navBlurSigma = defaultNavBlurSigma,
    this.navOpacity = defaultNavOpacity,
    this.contentBlurEnabled = true,
    this.contentBlurSigma = defaultContentBlurSigma,
    this.contentOpacity = defaultContentOpacity,
  });

  /// 默认种子色
  static const defaultSeedColor = Color(0xFF00696E);

  /// 默认背景色(深灰蓝)
  static const defaultBackgroundColor = Color(0xFF26283B);

  /// 毛玻璃模糊半径范围(0 = 关闭模糊)
  static const blurSigmaMin = 0.0;
  static const blurSigmaMax = 40.0;
  static const defaultNavBlurSigma = 15.0;
  static const defaultContentBlurSigma = 18.0;

  /// 表面不透明度范围(0–1)
  static const opacityMin = 0.0;
  static const opacityMax = 1.0;
  static const defaultNavOpacity = 0.75;
  static const defaultContentOpacity = 0.8;

  /// 存储键
  static const storageKey = 'appearance';

  /// 主题模式,默认自动(跟随系统)
  final ThemeMode themeMode;

  /// 跟随系统主题色(Android 12+ 壁纸动态取色,其他平台忽略)
  final bool followSystemColor;

  /// 自定义主题色(种子色),跟随系统关闭时生效
  final Color seedColor;

  /// 背景类型
  final BackgroundType backgroundType;

  /// 纯色背景颜色
  final Color backgroundColor;

  /// 背景图片:本地文件路径(native)/dataURL(web)
  final String? backgroundImage;

  /// 底栏/侧栏毛玻璃开关
  final bool navBlurEnabled;

  /// 底栏/侧栏毛玻璃半径
  final double navBlurSigma;

  /// 底栏/侧栏表面不透明度
  final double navOpacity;

  /// 内容区毛玻璃开关
  final bool contentBlurEnabled;

  /// 内容区毛玻璃半径
  final double contentBlurSigma;

  /// 内容表面不透明度
  final double contentOpacity;

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    bool? followSystemColor,
    Color? seedColor,
    BackgroundType? backgroundType,
    Color? backgroundColor,
    Object? backgroundImage = _unset,
    bool? navBlurEnabled,
    double? navBlurSigma,
    double? navOpacity,
    bool? contentBlurEnabled,
    double? contentBlurSigma,
    double? contentOpacity,
  }) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        followSystemColor: followSystemColor ?? this.followSystemColor,
        seedColor: seedColor ?? this.seedColor,
        backgroundType: backgroundType ?? this.backgroundType,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        backgroundImage: backgroundImage == _unset
            ? this.backgroundImage
            : backgroundImage as String?,
        navBlurEnabled: navBlurEnabled ?? this.navBlurEnabled,
        navBlurSigma: navBlurSigma ?? this.navBlurSigma,
        navOpacity: navOpacity ?? this.navOpacity,
        contentBlurEnabled: contentBlurEnabled ?? this.contentBlurEnabled,
        contentBlurSigma: contentBlurSigma ?? this.contentBlurSigma,
        contentOpacity: contentOpacity ?? this.contentOpacity,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'followSystemColor': followSystemColor,
        'seedColor': seedColor.toARGB32(),
        'backgroundType': backgroundType.name,
        'backgroundColor': backgroundColor.toARGB32(),
        'backgroundImage': backgroundImage,
        'navBlurEnabled': navBlurEnabled,
        'navBlurSigma': navBlurSigma,
        'navOpacity': navOpacity,
        'contentBlurEnabled': contentBlurEnabled,
        'contentBlurSigma': contentBlurSigma,
        'contentOpacity': contentOpacity,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) =>
      AppearanceSettings(
        themeMode:
            ThemeMode.values.asNameMap()[json['themeMode'] as String?] ??
                ThemeMode.system,
        followSystemColor: json['followSystemColor'] as bool? ?? true,
        seedColor: Color(
          json['seedColor'] as int? ?? defaultSeedColor.toARGB32(),
        ),
        backgroundType:
            BackgroundType.values.asNameMap()[json['backgroundType'] as String?] ??
                BackgroundType.none,
        backgroundColor: Color(
          json['backgroundColor'] as int? ??
              defaultBackgroundColor.toARGB32(),
        ),
        backgroundImage: json['backgroundImage'] as String?,
        navBlurEnabled: json['navBlurEnabled'] as bool? ?? true,
        navBlurSigma:
            (json['navBlurSigma'] as num?)?.toDouble() ??
                defaultNavBlurSigma,
        navOpacity:
            (json['navOpacity'] as num?)?.toDouble() ?? defaultNavOpacity,
        contentBlurEnabled: json['contentBlurEnabled'] as bool? ?? true,
        contentBlurSigma:
            (json['contentBlurSigma'] as num?)?.toDouble() ??
                defaultContentBlurSigma,
        contentOpacity:
            (json['contentOpacity'] as num?)?.toDouble() ??
                defaultContentOpacity,
      );
}

/// 全局标准存储实例,main() 启动时初始化并 override
final storageProvider = Provider<JustStandardStorage>(
  (ref) => throw UnimplementedError('storageProvider 须在 main() 中 override'),
);

/// 启动时从存储加载的外观初始值,main() 中 override,
/// 保证首帧即正确主题(避免默认值闪变)
final initialAppearanceProvider = Provider<AppearanceSettings>(
  (ref) => const AppearanceSettings(),
);

/// 外观设置状态,变更即持久化
final appearanceSettingsProvider =
    NotifierProvider<AppearanceSettingsNotifier, AppearanceSettings>(
  AppearanceSettingsNotifier.new,
);

class AppearanceSettingsNotifier extends Notifier<AppearanceSettings> {
  @override
  AppearanceSettings build() => ref.watch(initialAppearanceProvider);

  Future<void> setThemeMode(ThemeMode value) async {
    if (state.themeMode == value) return;
    state = state.copyWith(themeMode: value);
    await _persist();
  }

  Future<void> setFollowSystemColor(bool value) async {
    if (state.followSystemColor == value) return;
    state = state.copyWith(followSystemColor: value);
    await _persist();
  }

  Future<void> setSeedColor(Color value) async {
    if (state.seedColor == value) return;
    state = state.copyWith(seedColor: value);
    await _persist();
  }

  Future<void> setBackgroundType(BackgroundType value) async {
    if (state.backgroundType == value) return;
    state = state.copyWith(backgroundType: value);
    await _persist();
  }

  Future<void> setBackgroundColor(Color value) async {
    if (state.backgroundColor == value) return;
    state = state.copyWith(backgroundColor: value);
    await _persist();
  }

  Future<void> setBackgroundImage(String? value) async {
    if (state.backgroundImage == value) return;
    state = state.copyWith(backgroundImage: value);
    await _persist();
  }

  Future<void> setNavBlurEnabled(bool value) async {
    if (state.navBlurEnabled == value) return;
    state = state.copyWith(navBlurEnabled: value);
    await _persist();
  }

  Future<void> setNavBlurSigma(double value) async {
    final v = value.clamp(
      AppearanceSettings.blurSigmaMin,
      AppearanceSettings.blurSigmaMax,
    );
    if (state.navBlurSigma == v) return;
    state = state.copyWith(navBlurSigma: v);
    await _persist();
  }

  Future<void> setNavOpacity(double value) async {
    final v = value.clamp(
      AppearanceSettings.opacityMin,
      AppearanceSettings.opacityMax,
    );
    if (state.navOpacity == v) return;
    state = state.copyWith(navOpacity: v);
    await _persist();
  }

  Future<void> setContentBlurEnabled(bool value) async {
    if (state.contentBlurEnabled == value) return;
    state = state.copyWith(contentBlurEnabled: value);
    await _persist();
  }

  Future<void> setContentBlurSigma(double value) async {
    final v = value.clamp(
      AppearanceSettings.blurSigmaMin,
      AppearanceSettings.blurSigmaMax,
    );
    if (state.contentBlurSigma == v) return;
    state = state.copyWith(contentBlurSigma: v);
    await _persist();
  }

  Future<void> setContentOpacity(double value) async {
    final v = value.clamp(
      AppearanceSettings.opacityMin,
      AppearanceSettings.opacityMax,
    );
    if (state.contentOpacity == v) return;
    state = state.copyWith(contentOpacity: v);
    await _persist();
  }

  Future<void> _persist() => ref
      .read(storageProvider)
      .writeJson(AppearanceSettings.storageKey, state, (s) => s.toJson());
}

/// 从存储加载外观设置,无记录或解析失败时返回默认值
Future<AppearanceSettings> loadAppearanceSettings(
  JustStandardStorage storage,
) async {
  final saved = await storage.readJson<AppearanceSettings>(
    AppearanceSettings.storageKey,
    AppearanceSettings.fromJson,
  );
  return saved ?? const AppearanceSettings();
}

/// 外观设置页:主题模式/主题色/背景/毛玻璃。
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    try {
      final stored = await persistBackgroundImage(result.files.single);
      await ref
          .read(appearanceSettingsProvider.notifier)
          .setBackgroundImage(stored);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存背景图片失败:$e')),
        );
      }
    }
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
    final s = ref.watch(appearanceSettingsProvider);
    final notifier = ref.watch(appearanceSettingsProvider.notifier);
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
            groupValue: s.themeMode,
            onChanged: (value) => notifier.setThemeMode(value!),
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
            value: s.followSystemColor,
            onChanged: notifier.setFollowSystemColor,
          ),
          ListTile(
            leading: CircleAvatar(radius: 18, backgroundColor: s.seedColor),
            title: const Text('自定义主题色'),
            subtitle: Text(_colorHex(s.seedColor)),
            enabled: !s.followSystemColor,
            trailing: const Icon(Icons.chevron_right),
            onTap: s.followSystemColor
                ? null
                : () async {
                    final color = await _showColorPickerDialog(
                      context,
                      '自定义主题色',
                      s.seedColor,
                    );
                    if (color != null) await notifier.setSeedColor(color);
                  },
          ),
          const Divider(height: 1),
          _sectionLabel(context, '背景'),
          RadioGroup<BackgroundType>(
            groupValue: s.backgroundType,
            onChanged: (value) => notifier.setBackgroundType(value!),
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
          if (s.backgroundType == BackgroundType.color)
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: s.backgroundColor,
              ),
              title: const Text('背景色'),
              subtitle: Text(_colorHex(s.backgroundColor)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final color = await _showColorPickerDialog(
                  context,
                  '背景色',
                  s.backgroundColor,
                );
                if (color != null) await notifier.setBackgroundColor(color);
              },
            ),
          if (s.backgroundType == BackgroundType.image)
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('背景图片'),
              subtitle: Text(
                s.backgroundImage == null
                    ? '点击选择图片'
                    : _imageLabel(s.backgroundImage!),
              ),
              trailing: s.backgroundImage == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '清除背景图片',
                      onPressed: () => notifier.setBackgroundImage(null),
                    ),
              onTap: () => _pickBackgroundImage(context, ref),
            ),
          const Divider(height: 1),
          _sectionLabel(context, '毛玻璃'),
          SwitchListTile(
            title: const Text('底栏/侧栏模糊'),
            subtitle: const Text('导航栏高斯模糊透出背景'),
            value: s.navBlurEnabled,
            onChanged: notifier.setNavBlurEnabled,
          ),
          if (s.navBlurEnabled)
            _sliderTile(
              title: '底栏/侧栏模糊半径',
              value: s.navBlurSigma,
              min: AppearanceSettings.blurSigmaMin,
              max: AppearanceSettings.blurSigmaMax,
              step: 1,
              onChanged: notifier.setNavBlurSigma,
            ),
          _sliderTile(
            title: '底栏/侧栏不透明度',
            value: s.navOpacity,
            min: AppearanceSettings.opacityMin,
            max: AppearanceSettings.opacityMax,
            step: 0.01,
            percent: true,
            onChanged: notifier.setNavOpacity,
          ),
          SwitchListTile(
            title: const Text('内容区模糊'),
            subtitle: const Text('内容容器层整体高斯模糊'),
            value: s.contentBlurEnabled,
            onChanged: notifier.setContentBlurEnabled,
          ),
          if (s.contentBlurEnabled)
            _sliderTile(
              title: '内容区模糊半径',
              value: s.contentBlurSigma,
              min: AppearanceSettings.blurSigmaMin,
              max: AppearanceSettings.blurSigmaMax,
              step: 1,
              onChanged: notifier.setContentBlurSigma,
            ),
          _sliderTile(
            title: '内容表面不透明度',
            value: s.contentOpacity,
            min: AppearanceSettings.opacityMin,
            max: AppearanceSettings.opacityMax,
            step: 0.01,
            percent: true,
            onChanged: notifier.setContentOpacity,
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
