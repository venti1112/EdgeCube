import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base.dart';
import '../storage.dart';

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

// ══════════════════════════════════════════════════════════════════════════
// 存储与聚合状态
// ══════════════════════════════════════════════════════════════════════════

/// 启动时从存储加载的外观初始值,main() 中 override,
/// 保证首帧即正确主题(避免默认值闪变)
final initialAppearanceProvider = Provider<AppearanceSettings>(
  (ref) => const AppearanceSettings(),
);

/// 聚合状态:所有外观设置的唯一真源,也是持久化的落点。
///
/// **UI 不要直接 watch 它** —— 那样任一设置变动都会让整棵子树重建。
/// 读单项请用下面各自的单项 Provider(见「单项设置全局 Provider」一节),
/// 写单项用 `ref.read(xxxProvider.notifier).set(...)`。
final appearanceSettingsProvider =
    NotifierProvider<AppearanceSettingsNotifier, AppearanceSettings>(
  AppearanceSettingsNotifier.new,
);

/// 聚合状态读写:负责校验(越界 clamp)与落盘,单项 Provider 都委托到这里。
/// 单项 Notifier 只是"门面",真正的规则集中在本类,避免各写一份。
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
      .setString(AppearanceSettings.storageKey, jsonEncode(state.toJson()));
}

/// 从存储加载外观设置,无记录或解析失败时返回默认值
Future<AppearanceSettings> loadAppearanceSettings(
  SharedPreferences storage,
) async {
  final raw = storage.getString(AppearanceSettings.storageKey);
  if (raw == null) return const AppearanceSettings();
  try {
    return AppearanceSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  } catch (_) {
    return const AppearanceSettings();
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 单项设置全局 Provider
// ══════════════════════════════════════════════════════════════════════════
//
// 每一项设置都是一个独立、可从任意位置访问的全局 Provider:
//
//   读: ref.watch(navBlurSigmaProvider)              // 只在本项变化时重建
//   写: ref.read(navBlurSigmaProvider.notifier).set(20)
//
// 为什么不是一个聚合 Provider 走到底:
//   watch(appearanceSettingsProvider) 会让"改背景色"也重建所有毛玻璃控件。
//   拆成单项后,每个控件只订阅自己那一项,依赖关系一目了然。
//
// 数据仍然只存一份:各单项 build() 从聚合状态 select 出自己那一项,
// set() 又委托回聚合 Notifier 统一 clamp + 落盘,不存在双份真源。
//
// 可用清单:
//   themeModeProvider          followSystemColorProvider   seedColorProvider
//   backgroundTypeProvider     backgroundColorProvider     backgroundImageProvider
//   navBlurEnabledProvider     navBlurSigmaProvider        navOpacityProvider
//   contentBlurEnabledProvider contentBlurSigmaProvider    contentOpacityProvider
//   glassModeEnabledProvider   (派生:是否进入磨砂模式)

/// 单项设置 Notifier 的公共骨架(实现见 `settings/base.dart`)。
///
/// 这里只把「聚合 Provider 是谁」钉死成外观设置,其余(selectValue /
/// applyValue / set)由子类实现:把"读哪一项 / 写哪一项"缩成两个方法。
abstract class SettingNotifier<T>
    extends
        SettingNotifierBase<
          AppearanceSettings,
          T,
          AppearanceSettingsNotifier
        > {
  @override
  NotifierProvider<AppearanceSettingsNotifier, AppearanceSettings>
  get aggregate => appearanceSettingsProvider;
}

// ── 主题 ──────────────────────────────────────────────────────────────────

/// 主题模式(自动 / 浅色 / 深色)
class _ThemeModeSetting extends SettingNotifier<ThemeMode> {
  @override
  ThemeMode selectValue(AppearanceSettings s) => s.themeMode;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, ThemeMode value) =>
      n.setThemeMode(value);
}

final themeModeProvider =
    NotifierProvider<_ThemeModeSetting, ThemeMode>(_ThemeModeSetting.new);

/// 是否跟随系统主题色(Android 12+ 壁纸取色)
class _FollowSystemColorSetting extends SettingNotifier<bool> {
  @override
  bool selectValue(AppearanceSettings s) => s.followSystemColor;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, bool value) =>
      n.setFollowSystemColor(value);
}

final followSystemColorProvider =
    NotifierProvider<_FollowSystemColorSetting, bool>(
  _FollowSystemColorSetting.new,
);

/// 自定义主题色(种子色)
class _SeedColorSetting extends SettingNotifier<Color> {
  @override
  Color selectValue(AppearanceSettings s) => s.seedColor;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, Color value) =>
      n.setSeedColor(value);
}

final seedColorProvider =
    NotifierProvider<_SeedColorSetting, Color>(_SeedColorSetting.new);

// ── 背景 ──────────────────────────────────────────────────────────────────

/// 背景类型(无 / 纯色 / 图片)
class _BackgroundTypeSetting extends SettingNotifier<BackgroundType> {
  @override
  BackgroundType selectValue(AppearanceSettings s) => s.backgroundType;

  @override
  Future<void> applyValue(
    AppearanceSettingsNotifier n,
    BackgroundType value,
  ) =>
      n.setBackgroundType(value);
}

final backgroundTypeProvider =
    NotifierProvider<_BackgroundTypeSetting, BackgroundType>(
  _BackgroundTypeSetting.new,
);

/// 纯色背景颜色
class _BackgroundColorSetting extends SettingNotifier<Color> {
  @override
  Color selectValue(AppearanceSettings s) => s.backgroundColor;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, Color value) =>
      n.setBackgroundColor(value);
}

final backgroundColorProvider =
    NotifierProvider<_BackgroundColorSetting, Color>(
  _BackgroundColorSetting.new,
);

/// 背景图片:本地文件路径(native)/ dataURL(web),null = 未设置
class _BackgroundImageSetting extends SettingNotifier<String?> {
  @override
  String? selectValue(AppearanceSettings s) => s.backgroundImage;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, String? value) =>
      n.setBackgroundImage(value);
}

final backgroundImageProvider =
    NotifierProvider<_BackgroundImageSetting, String?>(
  _BackgroundImageSetting.new,
);

/// 磨砂模式总开关(派生):必须有自定义背景才有东西可模糊,
/// 所以「背景类型 != 无」即进入毛玻璃模式。
final glassModeEnabledProvider = Provider<bool>(
  (ref) => ref.watch(backgroundTypeProvider) != BackgroundType.none,
);

// ── 底栏/侧栏毛玻璃 ───────────────────────────────────────────────────────

/// 底栏/侧栏模糊开关
class _NavBlurEnabledSetting extends SettingNotifier<bool> {
  @override
  bool selectValue(AppearanceSettings s) => s.navBlurEnabled;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, bool value) =>
      n.setNavBlurEnabled(value);
}

final navBlurEnabledProvider =
    NotifierProvider<_NavBlurEnabledSetting, bool>(_NavBlurEnabledSetting.new);

/// 底栏/侧栏模糊半径(0 = 关闭模糊)
class _NavBlurSigmaSetting extends SettingNotifier<double> {
  @override
  double selectValue(AppearanceSettings s) => s.navBlurSigma;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, double value) =>
      n.setNavBlurSigma(value);
}

final navBlurSigmaProvider =
    NotifierProvider<_NavBlurSigmaSetting, double>(_NavBlurSigmaSetting.new);

/// 底栏/侧栏表面不透明度
class _NavOpacitySetting extends SettingNotifier<double> {
  @override
  double selectValue(AppearanceSettings s) => s.navOpacity;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, double value) =>
      n.setNavOpacity(value);
}

final navOpacityProvider =
    NotifierProvider<_NavOpacitySetting, double>(_NavOpacitySetting.new);

// ── 内容区毛玻璃 ──────────────────────────────────────────────────────────

/// 内容区模糊开关
class _ContentBlurEnabledSetting extends SettingNotifier<bool> {
  @override
  bool selectValue(AppearanceSettings s) => s.contentBlurEnabled;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, bool value) =>
      n.setContentBlurEnabled(value);
}

final contentBlurEnabledProvider =
    NotifierProvider<_ContentBlurEnabledSetting, bool>(
  _ContentBlurEnabledSetting.new,
);

/// 内容区模糊半径(0 = 关闭模糊)
class _ContentBlurSigmaSetting extends SettingNotifier<double> {
  @override
  double selectValue(AppearanceSettings s) => s.contentBlurSigma;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, double value) =>
      n.setContentBlurSigma(value);
}

final contentBlurSigmaProvider =
    NotifierProvider<_ContentBlurSigmaSetting, double>(
  _ContentBlurSigmaSetting.new,
);

/// 内容表面不透明度
class _ContentOpacitySetting extends SettingNotifier<double> {
  @override
  double selectValue(AppearanceSettings s) => s.contentOpacity;

  @override
  Future<void> applyValue(AppearanceSettingsNotifier n, double value) =>
      n.setContentOpacity(value);
}

final contentOpacityProvider =
    NotifierProvider<_ContentOpacitySetting, double>(_ContentOpacitySetting.new);
