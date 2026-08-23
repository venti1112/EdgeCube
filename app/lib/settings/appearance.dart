import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_storage/just_storage.dart';
import 'package:material_ui/material_ui.dart';

/// 外观设置(不可变状态)
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.followSystemColor = true,
    this.seedColor = defaultSeedColor,
  });

  /// 默认种子色
  static const defaultSeedColor = Color(0xFF00696E);

  /// 存储键
  static const storageKey = 'appearance';

  /// 主题模式,默认自动(跟随系统)
  final ThemeMode themeMode;

  /// 跟随系统主题色(Android 12+ 壁纸动态取色,其他平台忽略)
  final bool followSystemColor;

  /// 自定义主题色(种子色),跟随系统关闭时生效
  final Color seedColor;

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    bool? followSystemColor,
    Color? seedColor,
  }) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        followSystemColor: followSystemColor ?? this.followSystemColor,
        seedColor: seedColor ?? this.seedColor,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'followSystemColor': followSystemColor,
        'seedColor': seedColor.toARGB32(),
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

/// 外观设置页:主题模式单选 + 主题色(跟随系统开关 + 自定义种子色)。
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  Future<void> _pickSeedColor(
    BuildContext context,
    AppearanceSettingsNotifier notifier,
    Color current,
  ) async {
    var picked = current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义主题色'),
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
    if (confirmed == true) await notifier.setSeedColor(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appearanceSettingsProvider);
    final notifier = ref.watch(appearanceSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
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
            subtitle: Text(
              '#${s.seedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
            ),
            enabled: !s.followSystemColor,
            trailing: const Icon(Icons.chevron_right),
            onTap: s.followSystemColor
                ? null
                : () => _pickSeedColor(context, notifier, s.seedColor),
          ),
        ],
      ),
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
