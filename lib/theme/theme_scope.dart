import 'package:flutter/material.dart';

import 'precipitation_effect_mode.dart';

/// 向子树暴露当前主题模式、种子色与修改入口。
///
/// 设置页通过 [ThemeScope.of] 读取 [themeMode] / [seedColor] / [useDynamicColor]
/// 并调用对应 setter 切换，应用顶层据此驱动 [MaterialApp.themeMode] 与色彩方案。
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.themeMode,
    required this.setThemeMode,
    required this.seedColor,
    required this.setSeedColor,
    required this.useDynamicColor,
    required this.setUseDynamicColor,
    required this.snowfallEnabled,
    required this.setSnowfallEnabled,
    required this.precipitationMode,
    required this.setPrecipitationMode,
    required super.child,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> setThemeMode;

  final Color seedColor;
  final ValueChanged<Color> setSeedColor;

  final bool useDynamicColor;
  final ValueChanged<bool> setUseDynamicColor;

  final bool snowfallEnabled;
  final ValueChanged<bool> setSnowfallEnabled;

  final PrecipitationEffectMode precipitationMode;
  final ValueChanged<PrecipitationEffectMode> setPrecipitationMode;

  static ThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope 未在 widget 树中找到');
    return scope!;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) =>
      themeMode != oldWidget.themeMode ||
      seedColor != oldWidget.seedColor ||
      useDynamicColor != oldWidget.useDynamicColor ||
      snowfallEnabled != oldWidget.snowfallEnabled ||
      precipitationMode != oldWidget.precipitationMode;
}
