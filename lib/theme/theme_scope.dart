import 'package:flutter/material.dart';

/// 向子树暴露当前主题模式与修改入口。
///
/// 设置页通过 [ThemeScope.of] 读取 [themeMode] 并调用 [setThemeMode] 切换，
/// 应用顶层据此驱动 [MaterialApp.themeMode]。
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.themeMode,
    required this.setThemeMode,
    required super.child,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> setThemeMode;

  static ThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope 未在 widget 树中找到');
    return scope!;
  }

  @override
  bool updateShouldNotify(ThemeScope oldWidget) =>
      themeMode != oldWidget.themeMode;
}
