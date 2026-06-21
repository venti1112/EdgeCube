import 'package:flutter/material.dart';

import '../config/config_store.dart';

/// 主题配置的本地持久化读写，存于 `config/theme.json`。
class ThemeStore {
  static const String _fileName = 'theme.json';
  static const String _modeKey = 'mode';
  static const String _seedColorKey = 'seedColor';
  static const String _useDynamicColorKey = 'useDynamicColor';
  static const String _snowfallEnabledKey = 'snowfallEnabled';

  /// 默认种子色。
  static const Color defaultSeedColor = Colors.green;

  /// 读取已保存的主题模式，未保存过时回退到 [ThemeMode.system]。
  static Future<ThemeMode> load() async {
    final m = await ConfigStore.readConfig(_fileName);
    return _decode(m[_modeKey] as String?);
  }

  /// 持久化指定的主题模式。
  static Future<void> save(ThemeMode mode) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_modeKey] = mode.name;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static ThemeMode _decode(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  /// 读取已保存的种子色，未保存过时回退到 [defaultSeedColor]。
  static Future<Color> loadSeedColor() async {
    final m = await ConfigStore.readConfig(_fileName);
    final stored = m[_seedColorKey] as int?;
    return stored != null ? Color(stored) : defaultSeedColor;
  }

  /// 持久化指定的种子色。
  static Future<void> saveSeedColor(Color color) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_seedColorKey] = color.toARGB32();
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 读取是否跟随系统主题色（Android 12+ Material You），未保存过时回退到 false。
  static Future<bool> loadUseDynamicColor() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_useDynamicColorKey] as bool? ?? false;
  }

  /// 持久化是否跟随系统主题色。
  static Future<void> saveUseDynamicColor(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_useDynamicColorKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<bool> loadSnowfallEnabled() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_snowfallEnabledKey] as bool? ?? false;
  }

  static Future<void> saveSnowfallEnabled(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_snowfallEnabledKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }
}
