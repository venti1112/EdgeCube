/// 一份已加载的翻译表：当前语言 [active] + 中文源 [source]。
///
/// 查表回退链：`active[key] → source[key] → key 本身`。因此中文源必须完整（权威
/// key 集），英文与自定义翻译可不完整，缺失项自动回退中文。
class Translations {
  const Translations({required this.active, required this.source});

  /// 当前语言的 key→译文映射。
  final Map<String, String> active;

  /// 中文源 key→中文映射（权威 key 集，作为回退）。
  final Map<String, String> source;

  /// 空表，仅用于初始化占位；查表时直接回退 key 本身。
  static const Translations empty = Translations(active: {}, source: {});

  /// 取 [key] 对应译文，按回退链查找；[params] 用于替换 `{name}` 形式占位符。
  String get(String key, [Map<String, String>? params]) {
    final raw = active[key] ?? source[key] ?? key;
    if (params == null || params.isEmpty) return raw;
    var result = raw;
    params.forEach((name, value) {
      result = result.replaceAll('{$name}', value);
    });
    return result;
  }
}
