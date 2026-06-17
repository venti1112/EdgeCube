import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式的本地持久化读写。
class ThemeStore {
  static const String _key = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _useDynamicColorKey = 'use_dynamic_color';

  /// 默认种子色。
  static const Color defaultSeedColor = Colors.green;

  /// 读取已保存的主题模式，未保存过时回退到 [ThemeMode.system]。
  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key));
  }

  /// 持久化指定的主题模式。
  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  static ThemeMode _decode(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  /// 读取已保存的种子色，未保存过时回退到 [defaultSeedColor]。
  static Future<Color> loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_seedColorKey);
    return stored != null ? Color(stored) : defaultSeedColor;
  }

  /// 持久化指定的种子色。
  static Future<void> saveSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
  }

  /// 读取是否跟随系统主题色（Android 12+ Material You），未保存过时回退到 false。
  static Future<bool> loadUseDynamicColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useDynamicColorKey) ?? false;
  }

  /// 持久化是否跟随系统主题色。
  static Future<void> saveUseDynamicColor(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useDynamicColorKey, value);
  }
}
