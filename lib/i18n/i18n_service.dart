import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../config/config_store.dart';
import '../config/locale_store.dart';
import 'app_language.dart';
import 'translations.dart';

/// 多语言资源的加载与查询中枢。
///
/// - 内置语言放在 `assets/i18n/`：`index.json`（清单）+ 各 locale 的 `<code>.json`。
/// - 自定义语言为用户导入的 JSON，存于 `<documents>/config/translations/<code>.json`，
///   自描述格式：`{"locale":"ja_JP","name":"日本語","translations":{...}}`。
/// - 维护一个进程级「当前翻译表」[current]，供非 widget 代码经顶层 [tr] 取译文。
class I18nService {
  I18nService._();

  static const String _assetDir = 'assets/i18n';
  static const String _indexAsset = '$_assetDir/index.json';
  static const String _customDirName = 'translations';

  /// 源语言代码（中文）。其 key 集为权威，作为所有语言的回退。
  static const String sourceCode = 'zh_CN';

  /// 进程级当前翻译表，供非 widget 代码经 [tr] 读取；
  /// 由 [LocaleController] 在每次加载后写入。
  static Translations current = Translations.empty;

  static Map<String, String>? _sourceCache;

  /// 读取并缓存中文源映射（权威 key 集）。
  static Future<Map<String, String>> loadSource() async {
    return _sourceCache ??= await _loadAssetMap(sourceCode);
  }

  /// 列出全部可用语言：内置（来自 index.json）+ 自定义（来自 config/translations）。
  static Future<List<AppLanguage>> availableLanguages() async {
    final result = await _builtinLanguages();
    result.addAll(await _customLanguages());
    return result;
  }

  /// 加载指定语言（附带中文源作为回退）的合并翻译表。
  /// [preferCustom] 为 true 且存在自定义文件时，优先加载自定义翻译。
  static Future<Translations> loadTranslations(String code, {bool preferCustom = false}) async {
    final source = await loadSource();
    final Map<String, String> active;
    if (preferCustom && await hasCustom(code)) {
      active = await _loadCustomMap(code);
    } else if (code == sourceCode) {
      active = source;
    } else {
      active = await _loadAssetMap(code);
    }
    return Translations(active: active, source: source);
  }

  // ── 内置 ──

  static Future<List<AppLanguage>> _builtinLanguages() async {
    try {
      final raw = await rootBundle.loadString(_indexAsset);
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list.whereType<Map<String, dynamic>>())
          AppLanguage(
            code: e['locale'] as String,
            name: (e['name'] as String?) ?? e['locale'] as String,
            isBuiltin: true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> hasCustom(String code) async {
    final dir = await customDir();
    return File(p.join(dir.path, '$code.json')).exists();
  }

  static Future<Map<String, String>> _loadAssetMap(String code) async {
    try {
      final raw = await rootBundle.loadString('$_assetDir/$code.json');
      return _asStringMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  // ── 自定义 ──

  /// 自定义翻译目录 `<documents>/config/translations/`，不存在时创建。
  static Future<Directory> customDir() async {
    final cfg = await ConfigStore.configDir();
    final dir = Directory(p.join(cfg.path, _customDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<AppLanguage>> _customLanguages() async {
    final dir = await customDir();
    final result = <AppLanguage>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final pack = await _readPack(entity);
      if (pack == null) continue;
      result.add(
        AppLanguage(code: pack.code, name: pack.name, isBuiltin: false),
      );
    }
    return result;
  }

  static Future<Map<String, String>> _loadCustomMap(String code) async {
    final dir = await customDir();
    final pack = await _readPack(File(p.join(dir.path, '$code.json')));
    return pack?.translations ?? {};
  }

  /// 校验并解析一个自定义翻译包文件；不合法返回 null。
  static Future<TranslationPack?> _readPack(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final code = decoded['locale'];
      final translations = decoded['translations'];
      // locale 必须为非空、格式合法，且不能是保留的「跟随系统」标记。
      if (code is! String || code.isEmpty || !isValidLocaleCode(code)) {
        return null;
      }
      if (code == LocaleStore.systemCode) return null;
      if (translations is! Map) return null;
      final name = decoded['name'];
      return TranslationPack(
        code: code,
        name: (name is String && name.isNotEmpty) ? name : code,
        translations: _asStringMap(translations),
      );
    } catch (_) {
      return null;
    }
  }

  /// 导入一个自定义翻译文件：校验后规范化写入 config/translations/<code>.json。
  /// 返回导入成功的语言；格式不正确时抛 [FormatException]。
  static Future<AppLanguage> importPack(String sourcePath) async {
    final pack = await _readPack(File(sourcePath));
    if (pack == null) {
      throw const FormatException('翻译文件格式不正确');
    }
    final dir = await customDir();
    final dest = File(p.join(dir.path, '${pack.code}.json'));
    await dest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'locale': pack.code,
        'name': pack.name,
        'translations': pack.translations,
      }),
    );
    return AppLanguage(code: pack.code, name: pack.name, isBuiltin: false);
  }

  /// 删除一个自定义语言文件。
  static Future<void> removePack(String code) async {
    final dir = await customDir();
    final file = File(p.join(dir.path, '$code.json'));
    if (await file.exists()) await file.delete();
  }

  /// 导出中文源映射为翻译模板（供翻译者参考全部 key），返回 JSON 字符串。
  static Future<String> exportTemplate() async {
    final source = await loadSource();
    return const JsonEncoder.withIndent('  ').convert({
      'locale': 'xx_XX',
      'name': '语言名称 / Language name',
      'translations': source,
    });
  }

  static Map<String, String> _asStringMap(dynamic decoded) {
    if (decoded is! Map) return {};
    final result = <String, String>{};
    decoded.forEach((k, v) {
      if (v is String) result[k.toString()] = v;
    });
    return result;
  }
}

/// 解析后的翻译包。
class TranslationPack {
  const TranslationPack({
    required this.code,
    required this.name,
    required this.translations,
  });

  final String code;
  final String name;
  final Map<String, String> translations;
}

/// 供**非 widget 代码**取译文（异常 toString、控制器内 SnackBar/通知等）。
///
/// widget 代码请改用 `context.tr(...)`，以便语言切换时所在子树自动重建。
String tr(String key, [Map<String, String>? params]) =>
    I18nService.current.get(key, params);
