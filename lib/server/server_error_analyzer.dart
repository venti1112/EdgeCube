import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../config/config_store.dart';

/// 基于规则文件的 Minecraft 服务端错误分析器。
///
/// 设计目标：把「识别一种崩溃 → 给出主信息 + 建议操作」的知识从散落的硬编码
/// if-else 抽出，改由**外部 JSON 规则文件**描述，从而无需改动 Dart 代码即可
/// 持续补全新的错误规则。
///
/// 规则来源（后者可覆盖前者，[analyzeLines] 中排在更前、优先匹配）：
/// - 用户自定义：`<documents>/config/error_rules/*.json`（可选，方便临时补规则）
/// - 内置随包：`assets/rules/server_errors.json`
///
/// 规则文件为一个 JSON 数组，每个元素形如（参见工作目录下 `example.json`）：
/// ```json
/// {
///   "match":   "Failed to bind to port (\\d+)",     // 必填，正则表达式
///   "map":     { "61": "Java 17" },                   // 可选，捕获值→展示值映射表
///   "message": { "zh_CN": "端口 $1 被占用", ... },     // 必填，各语言主信息
///   "suggest": { "zh_CN": "请更换端口", ... }          // 可选，各语言建议操作
/// }
/// ```
///
/// 占位符（在 `message` / `suggest` 文案中）：
/// - `$0`…`$9`：正则的第 N 个捕获组（`$0` 为整段匹配）。
/// - `$map_1`…`$map_9`：以第 N 个捕获组的值为 key 查 [ServerErrorRule.map]；
///   查不到时回退为捕获组原值。例如 class 版本号 `61` → `Java 17`。
class ServerErrorAnalyzer {
  ServerErrorAnalyzer._();

  /// 全局单例。规则一次加载后进程内缓存复用。
  static final ServerErrorAnalyzer instance = ServerErrorAnalyzer._();

  /// 内置规则资源路径（随包）。
  static const String _builtinAsset = 'assets/rules/server_errors.json';

  /// 用户自定义规则目录名（位于 `config/` 下）。
  static const String _customDirName = 'error_rules';

  /// 已加载的规则表；null 表示尚未加载。
  List<ServerErrorRule>? _rules;

  /// 加载过程的去重 Future：并发调用 [ensureLoaded] 只触发一次真正加载。
  Future<void>? _loading;

  /// 确保规则已加载（幂等）。首次调用触发加载，后续直接复用缓存。
  Future<void> ensureLoaded() => _loading ??= _load();

  /// 丢弃缓存并重新加载（导入 / 修改自定义规则后调用）。
  Future<void> reload() {
    _rules = null;
    _loading = null;
    return ensureLoaded();
  }

  Future<void> _load() async {
    final rules = <ServerErrorRule>[];
    // 自定义规则排在前面：同一行命中时优先于内置规则，便于用户覆盖。
    rules.addAll(await _loadCustomRules());
    rules.addAll(await _loadBuiltinRules());
    _rules = rules;
  }

  /// 逐行（从最新一行往回）扫描日志，返回首个命中的分析结果；无匹配返回 null。
  ///
  /// 从尾部往前扫，使最接近崩溃时刻的错误优先命中（与旧启发式一致）。
  /// 同一行内则按规则表顺序取第一个匹配的规则。
  ServerErrorAnalysis? analyzeLines(List<String> lines) {
    final rules = _rules;
    if (rules == null || rules.isEmpty) return null;
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      for (final rule in rules) {
        final hit = rule.match(line);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  Future<List<ServerErrorRule>> _loadBuiltinRules() async {
    try {
      final raw = await rootBundle.loadString(_builtinAsset);
      return _parseRules(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  Future<List<ServerErrorRule>> _loadCustomRules() async {
    try {
      final cfg = await ConfigStore.configDir();
      final dir = Directory(p.join(cfg.path, _customDirName));
      if (!await dir.exists()) return const [];
      final rules = <ServerErrorRule>[];
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
          continue;
        }
        try {
          rules.addAll(_parseRules(jsonDecode(await entity.readAsString())));
        } catch (_) {
          // 单个文件损坏不影响其余规则加载。
        }
      }
      return rules;
    } catch (_) {
      return const [];
    }
  }

  /// 把解码后的 JSON（应为数组）解析为规则列表，逐条容错：非法规则被跳过。
  List<ServerErrorRule> _parseRules(dynamic decoded) {
    if (decoded is! List) return const [];
    final rules = <ServerErrorRule>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        rules.add(ServerErrorRule.fromJson(item.cast<String, dynamic>()));
      } catch (_) {
        // 正则非法 / 缺少 message 等：跳过该规则，不影响整体。
      }
    }
    return rules;
  }
}

/// 单条错误分析规则（一个匹配正则 + 多语言主信息 / 建议 + 可选映射表）。
class ServerErrorRule {
  ServerErrorRule({
    required this.pattern,
    required this.message,
    this.suggest = const {},
    this.map = const {},
  });

  /// 匹配日志行的正则表达式。
  final RegExp pattern;

  /// 各语言主信息，`locale code → 文案`（含占位符）。
  final Map<String, String> message;

  /// 各语言建议操作，`locale code → 文案`（含占位符）；可为空。
  final Map<String, String> suggest;

  /// 捕获值 → 展示值映射表，供 `$map_N` 占位符查表；可为空。
  final Map<String, String> map;

  /// 从单条规则 JSON 构造。`match` 缺失 / 非法或 `message` 为空时抛异常，
  /// 由调用方捕获并跳过该规则。
  factory ServerErrorRule.fromJson(Map<String, dynamic> json) {
    final match = json['match'];
    if (match is! String || match.isEmpty) {
      throw const FormatException('规则缺少合法的 match 字段');
    }
    final message = _asStringMap(json['message']);
    if (message.isEmpty) {
      throw const FormatException('规则缺少 message 文案');
    }
    return ServerErrorRule(
      pattern: RegExp(match), // 正则非法时抛 FormatException
      message: message,
      suggest: _asStringMap(json['suggest']),
      map: _asStringMap(json['map']),
    );
  }

  /// 尝试用本规则匹配 [line]；命中则返回占位符已展开的分析结果，否则 null。
  ServerErrorAnalysis? match(String line) {
    final m = pattern.firstMatch(line);
    if (m == null) return null;
    return ServerErrorAnalysis(
      message: message.map((k, v) => MapEntry(k, _expand(v, m))),
      suggest: suggest.map((k, v) => MapEntry(k, _expand(v, m))),
      detail: line.trim(),
    );
  }

  /// 展开文案中的占位符：先处理 `$map_N`（较长，避免被 `$N` 抢先），再处理 `$N`。
  String _expand(String template, Match m) {
    var result = template.replaceAllMapped(_reMapRef, (ref) {
      final value = _group(m, int.parse(ref.group(1)!)) ?? '';
      return map[value] ?? value;
    });
    result = result.replaceAllMapped(_reGroupRef, (ref) {
      return _group(m, int.parse(ref.group(1)!)) ?? '';
    });
    return result;
  }

  /// 安全取第 [index] 个捕获组（越界返回 null）。`$0` 为整段匹配。
  static String? _group(Match m, int index) =>
      index <= m.groupCount ? m.group(index) : null;

  static final RegExp _reMapRef = RegExp(r'\$map_(\d)');
  static final RegExp _reGroupRef = RegExp(r'\$(\d)');

  static Map<String, String> _asStringMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    value.forEach((k, v) {
      if (v is String) result[k.toString()] = v;
    });
    return result;
  }
}

/// 一次错误分析的结果：多语言主信息 / 建议 + 命中的原始日志行。
///
/// 主信息与建议保留各语言版本（占位符已展开），由展示层经 [messageFor] /
/// [suggestFor] 按当前语言取值，缺失语言按 `code → zh_CN → 任意` 回退。
class ServerErrorAnalysis {
  const ServerErrorAnalysis({
    required this.message,
    required this.suggest,
    required this.detail,
  });

  /// 各语言主信息，`locale code → 已展开文案`。
  final Map<String, String> message;

  /// 各语言建议操作，`locale code → 已展开文案`；可能为空。
  final Map<String, String> suggest;

  /// 命中的原始日志行（去除首尾空白），供展示原始错误详情。
  final String detail;

  /// 源语言（中文）代码，作为各语言查表的统一回退，与 `I18nService.sourceCode` 一致。
  static const String _fallbackCode = 'zh_CN';

  /// 取 [code] 对应的主信息，缺失时回退中文源、再回退任意可用语言。
  String messageFor(String code) => _pick(message, code);

  /// 取 [code] 对应的建议操作；本规则无建议时返回 null。
  String? suggestFor(String code) {
    final value = _pick(suggest, code);
    return value.isEmpty ? null : value;
  }

  static String _pick(Map<String, String> table, String code) {
    if (table.isEmpty) return '';
    return table[code] ?? table[_fallbackCode] ?? table.values.first;
  }
}
