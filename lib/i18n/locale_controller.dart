import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config/locale_store.dart';
import 'app_language.dart';
import 'i18n_service.dart';
import 'translations.dart';

/// 管理当前语言选择、已加载翻译表与可用语言列表，并在变化时通知重建。
///
/// 参照 [InstanceController] 的 ChangeNotifier 范式：应用启动时 [init] 一次，
/// 其后由设置页驱动 [setLanguage] / [importCustom] / [removeCustom]。
///
/// 选择标识符格式：
/// - `'system'` — 跟随系统
/// - `'b:<code>'` — 内置语言（如 `b:zh_CN`）
/// - `'c:<code>'` — 自定义语言（如 `c:zh_CN`）
class LocaleController extends ChangeNotifier {
  static const String _customPrefix = 'c:';
  static const String _builtinPrefix = 'b:';

  String _selectedCode = LocaleStore.systemCode;
  Translations _translations = Translations.empty;
  List<AppLanguage> _available = const [];
  bool _initialized = false;

  String get selectedCode => _selectedCode;
  Translations get translations => _translations;
  List<AppLanguage> get available => List.unmodifiable(_available);
  bool get isInitialized => _initialized;

  /// 是否跟随系统语言。
  bool get isFollowingSystem => _selectedCode == LocaleStore.systemCode;

  /// 从选择标识符中提取实际 locale 代码。
  String _localeCodeOf(String sel) {
    if (sel == LocaleStore.systemCode) return sel;
    if (sel.startsWith(_builtinPrefix) || sel.startsWith(_customPrefix)) {
      return sel.substring(2);
    }
    return sel;
  }

  bool _isCustom(String sel) => sel.startsWith(_customPrefix);

  /// 当前生效的 locale（用于 MaterialApp.locale，使框架本地化与应用文案一致）。
  ///
  /// 若解析到的 locale 不被 `GlobalMaterialLocalizations` 支持（如自定义文件里写了
  /// 非法或保留的 locale 代码），则回退到内置的 `en_US` 或 `zh_CN`，避免
  /// `MaterialLocalizations` 加载失败导致导航栏、返回按钮等渲染异常。
  Locale get locale {
    final loc = localeFromCode(_resolvedCode);
    if (GlobalMaterialLocalizations.delegate.isSupported(loc)) return loc;
    final hasEn = _available.any((l) => l.code == 'en_US');
    final fallback = hasEn
        ? const Locale('en', 'US')
        : const Locale('zh', 'CN');
    return GlobalMaterialLocalizations.delegate.isSupported(fallback)
        ? fallback
        : const Locale('zh', 'CN');
  }

  /// 已加载的全部 locale（内置 + 自定义），用于 MaterialApp.supportedLocales。
  ///
  /// 始终将内置的 `zh_CN` 与 `en_US` 放在前面作为兜底，即使自定义语言列表异常也
  /// 能保证框架本地化正常加载。
  List<Locale> get supportedLocales {
    final seen = <String>{};
    final list = <Locale>[];
    const fallbacks = [Locale('zh', 'CN'), Locale('en', 'US')];
    for (final loc in fallbacks) {
      final key = '${loc.languageCode}_${loc.countryCode ?? ''}';
      if (seen.add(key)) list.add(loc);
    }
    for (final lang in _available) {
      final loc = lang.locale;
      final key = '${loc.languageCode}_${loc.countryCode ?? ''}';
      if (seen.add(key)) list.add(loc);
    }
    return list;
  }

  /// 当前选中语言的展示名；跟随系统时返回 null（由 UI 显示「跟随系统」）。
  String? get currentLanguageName {
    if (isFollowingSystem) return null;
    final localeCode = _localeCodeOf(_selectedCode);
    final isCustom = _isCustom(_selectedCode);
    final match = _available.where(
      (l) => l.code == localeCode && l.isBuiltin == !isCustom,
    );
    return match.isNotEmpty ? match.first.name : localeCode;
  }

  /// 实际解析到的语言代码：跟随系统时按设备语言匹配，匹配不到回退中文源。
  String get _resolvedCode {
    if (!isFollowingSystem) return _localeCodeOf(_selectedCode);
    final lang = ui.PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    if (lang == 'zh') return I18nService.sourceCode;
    final hasEn = _available.any((l) => l.code == 'en_US');
    return hasEn ? 'en_US' : I18nService.sourceCode;
  }

  Future<void> init() async {
    var saved = await LocaleStore.load();
    if (saved != LocaleStore.systemCode) {
      if (saved.startsWith(_builtinPrefix) || saved.startsWith(_customPrefix)) {
        // 新格式
      } else if (isValidLocaleCode(saved)) {
        // 旧格式（纯 locale 代码）→ 视为内置语言
        saved = '$_builtinPrefix$saved';
      } else {
        saved = LocaleStore.systemCode;
      }
    }
    _selectedCode = saved;
    _available = await I18nService.availableLanguages();
    await _reload();
    _initialized = true;
    notifyListeners();
  }

  /// 重新加载当前选择对应的翻译表，并刷新进程级当前表（供顶层 tr 使用）。
  Future<void> _reload() async {
    final localeCode = _localeCodeOf(_selectedCode);
    _translations = await I18nService.loadTranslations(
      localeCode,
      preferCustom: _isCustom(_selectedCode),
    );
    I18nService.current = _translations;
  }

  /// 切换语言（`'system'`、`'b:<code>'` 或 `'c:<code>'`）。
  Future<void> setLanguage(String code) async {
    if (code == _selectedCode) return;
    final localeCode = _localeCodeOf(code);
    if (code != LocaleStore.systemCode && !isValidLocaleCode(localeCode))
      return;
    _selectedCode = code;
    await LocaleStore.save(_selectedCode);
    await _reload();
    notifyListeners();
  }

  /// 导入自定义翻译文件，成功后刷新列表并切换到该语言。
  /// 格式不正确时抛 [FormatException]。
  Future<AppLanguage> importCustom(String sourcePath) async {
    final lang = await I18nService.importPack(sourcePath);
    _available = await I18nService.availableLanguages();
    _selectedCode = '$_customPrefix${lang.code}';
    await LocaleStore.save(_selectedCode);
    await _reload();
    notifyListeners();
    return lang;
  }

  /// 删除自定义语言；若正在使用它，则切到对应内置语言或回退「跟随系统」。
  Future<void> removeCustom(String code) async {
    await I18nService.removePack(code);
    _available = await I18nService.availableLanguages();
    if (_isCustom(_selectedCode) && _localeCodeOf(_selectedCode) == code) {
      final builtinExists = _available.any(
        (l) => l.code == code && l.isBuiltin,
      );
      if (builtinExists) {
        _selectedCode = '$_builtinPrefix$code';
      } else {
        _selectedCode = LocaleStore.systemCode;
      }
      await LocaleStore.save(_selectedCode);
      await _reload();
    }
    notifyListeners();
  }
}
