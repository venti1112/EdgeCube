/// pnx.yml (PowerNukkitX) 配置文件的轻量级解析与编辑器。
///
/// 支持两级嵌套 `key: value` 结构的读写，保留原始注释与格式。
/// 不支持多行字符串、列表展开等完整 YAML 语法——pnx.yml 实际使用的子集不涉及这些。
library;

/// pnx.yml 解析结果：支持按 `section.key` 路径读写，序列化时保留原始格式。
class PnxProperties {
  PnxProperties._(this._lines, this._index);

  /// 文件所有行（含注释、空行）。
  final List<String> _lines;

  /// `section.key` → 行索引的映射（用于快速定位要修改的行）。
  final Map<String, int> _index;

  /// 从原始文本解析 pnx.yml 内容。
  factory PnxProperties.parse(String content) {
    final lines = <String>[];
    final index = <String, int>{};
    String? currentSection;

    for (var raw in content.split('\n')) {
      if (raw.endsWith('\r')) raw = raw.substring(0, raw.length - 1);
      final lineIdx = lines.length;
      lines.add(raw);

      final trimmed = raw.trimRight();
      if (trimmed.isEmpty) continue;
      final trimmedLeft = trimmed.trimLeft();
      if (trimmedLeft.startsWith('#')) continue;

      // 顶层 section：行首无缩进且 `name:` 后无值。
      if (!raw.startsWith(' ') && !raw.startsWith('\t')) {
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx > 0) {
          final rest = trimmed.substring(colonIdx + 1).trim();
          if (rest.isEmpty) {
            currentSection = trimmed.substring(0, colonIdx).trim();
            continue;
          }
        }
      }

      // 嵌套 key: value（有缩进）。
      if (currentSection != null && (raw.startsWith(' ') || raw.startsWith('\t'))) {
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx > 0) {
          final key = trimmed.substring(0, colonIdx).trim();
          index['$currentSection.$key'] = lineIdx;
        }
      }
    }

    return PnxProperties._(lines, index);
  }

  /// 以 `section.key` 路径获取值；不存在返回 null。
  String? operator [](String path) {
    final lineIdx = _index[path];
    if (lineIdx == null) return null;
    return _parseValue(_lines[lineIdx]);
  }

  /// 以 `section.key` 路径设置值。key 不存在时忽略。
  void operator []=(String path, String value) {
    final lineIdx = _index[path];
    if (lineIdx == null) return;
    final oldLine = _lines[lineIdx];
    final colonIdx = oldLine.indexOf(':');
    if (colonIdx < 0) return;
    final prefix = oldLine.substring(0, colonIdx + 1);
    // 保留行尾注释。
    final commentStart = oldLine.indexOf(' #', colonIdx + 1);
    final comment = commentStart >= 0 ? oldLine.substring(commentStart) : '';
    _lines[lineIdx] = '$prefix $value$comment';
  }

  /// 读取整数值，不存在或格式错误返回 null。
  int? getInt(String path) {
    final v = this[path];
    if (v == null) return null;
    return int.tryParse(v);
  }

  /// 读取布尔值（`true`/`false`），不存在或格式不符返回 null。
  bool? getBool(String path) {
    final v = this[path];
    if (v == null) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    return null;
  }

  /// 获取服务器端口（`settings.port`），默认 19132。
  int getPort() => getInt('settings.port') ?? 19132;

  /// 判断指定 `section.key` 路径是否存在。
  bool containsKey(String path) => _index.containsKey(path);

  /// 获取所有已注册的 section 名称。
  List<String> get sections {
    final seen = <String>{};
    for (final key in _index.keys) {
      final dot = key.indexOf('.');
      if (dot > 0) seen.add(key.substring(0, dot));
    }
    return seen.toList();
  }

  /// 获取指定 section 下的所有 key 名称。
  List<String> keysInSection(String section) {
    final prefix = '$section.';
    return _index.keys
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList();
  }

  /// 序列化为 pnx.yml 格式字符串（保留原始注释与格式）。
  @override
  String toString() => _lines.join('\n');

  /// 从一行 YAML 中提取 value 部分。
  static String? _parseValue(String line) {
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) return null;
    var value = line.substring(colonIdx + 1).trim();
    // 去除行尾注释。
    if (!value.startsWith('"') && !value.startsWith("'")) {
      final hashIdx = value.indexOf(' #');
      if (hashIdx >= 0) value = value.substring(0, hashIdx).trim();
    }
    // 去除引号。
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }
}
