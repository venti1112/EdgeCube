import 'package:flutter/widgets.dart';

/// 描述一个可选语言：locale 代码、显示名、是否为随包内置语言。
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.name,
    required this.isBuiltin,
  });

  /// locale 代码，形如 `zh_CN`、`en_US`、`ja_JP`。
  final String code;

  /// 语言列表中展示的名称（如「简体中文」「English」「日本語」）。
  final String name;

  /// 是否为随包内置语言（false 表示用户导入的自定义翻译）。
  final bool isBuiltin;

  Locale get locale => localeFromCode(code);
}

/// 合法的 locale 代码正则：2-3 位语言代码 + 可选的 `_[国家/地区]`。
///
/// 例：`zh_CN`、`en_US`、`ja`、`zh`。暂不支持 script 子标签（如 `zh_Hans`）。
final _localeCodeRegExp = RegExp(r'^[a-zA-Z]{2,3}([_-][a-zA-Z]{2})?$');

/// 判断 [code] 是否是允许使用的 locale 代码格式。
bool isValidLocaleCode(String code) => _localeCodeRegExp.hasMatch(code);

/// 把 `语言[_地区]` 形式的代码解析为 [Locale]。
///
/// 例：`en_US` → `Locale('en','US')`；`zh` → `Locale('zh')`。
/// 兼容连字符写法 `en-US`。格式非法时回退到 `zh_CN`，避免生成空 languageCode
/// 等无效 Locale 导致 `MaterialLocalizations` 加载失败。
Locale localeFromCode(String code) {
  assert(isValidLocaleCode(code), 'locale 代码格式非法: $code，应形如 zh_CN、en_US、ja');
  final parts = code.split(RegExp(r'[_-]'));
  if (parts.length >= 2 && parts[1].isNotEmpty) {
    return Locale(parts[0], parts[1]);
  }
  if (parts[0].isNotEmpty) return Locale(parts[0]);
  return const Locale('zh', 'CN');
}
