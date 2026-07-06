/// server-settings.yml (Allay) 配置文件的轻量级解析与编辑器。
///
/// Allay 的配置采用多层嵌套 `key: value` 的 YAML 子集，例如：
/// ```yaml
/// network-settings:
///   port: 19132
/// entity-settings:
///   physics-engine-settings:
///     motion-threshold: 0.003
/// ```
/// 本解析器基于缩进栈支持任意层级嵌套，按 `a.b.c` 路径读写，
/// 序列化时保留原始注释与格式。
///
/// 不支持多行字符串、列表展开、流式语法等完整 YAML 语法——
/// server-settings.yml 实际使用的子集不涉及这些。
library;

/// 缩进栈条目：记录某层 mapping 的缩进与累积路径。
class _StackEntry {
  const _StackEntry(this.indent, this.path);

  final int indent;
  final String path;
}

/// Allay server-settings.yml 解析结果：支持按 `a.b.c` 路径读写，
/// 序列化时保留原始格式。
class AllayProperties {
  AllayProperties._(this._lines, this._index);

  /// 文件所有行（含注释、空行）。
  final List<String> _lines;

  /// `a.b.c` 路径 → 行索引的映射（仅 `key: value` 行，不含 mapping 起始行）。
  final Map<String, int> _index;

  /// 从原始文本解析 server-settings.yml 内容。
  factory AllayProperties.parse(String content) {
    final lines = <String>[];
    final index = <String, int>{};
    final stack = <_StackEntry>[];

    for (var raw in content.split('\n')) {
      if (raw.endsWith('\r')) raw = raw.substring(0, raw.length - 1);
      final lineIdx = lines.length;
      lines.add(raw);

      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#')) continue;

      // 计算缩进（前导空格数；Tab 视为一个字符，Allay 配置统一用空格）。
      final indent = raw.length - raw.trimLeft().length;

      // 弹出缩进 >= 当前行 的栈顶（回到更外层）。
      // 注意：mapping 起始行用 > 比较（同级 key 归到同一父层），
      // 但 mapping 起始行本身缩进等于其父级兄弟，故这里用 >= 先弹出同级 mapping。
      while (stack.isNotEmpty && stack.last.indent >= indent) {
        stack.removeLast();
      }

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) continue;
      final key = trimmed.substring(0, colonIdx).trim();
      final rest = trimmed.substring(colonIdx + 1).trim();

      final path = stack.isEmpty ? key : '${stack.last.path}.$key';

      if (rest.isEmpty) {
        // mapping 起始行：压栈，本身不作为可写值。
        stack.add(_StackEntry(indent, path));
      } else {
        // `key: value` 叶子行。
        index[path] = lineIdx;
      }
    }

    return AllayProperties._(lines, index);
  }

  /// 以 `a.b.c` 路径获取值；不存在返回 null。
  String? operator [](String path) {
    final lineIdx = _index[path];
    if (lineIdx == null) return null;
    return _parseValue(_lines[lineIdx]);
  }

  /// 以 `a.b.c` 路径设置值。key 不存在时忽略。
  void operator []=(String path, String value) {
    final lineIdx = _index[path];
    if (lineIdx == null) return;
    final oldLine = _lines[lineIdx];
    final colonIdx = oldLine.indexOf(':');
    if (colonIdx < 0) return;
    // 保留 key 前缀（含前导缩进）与行尾注释。
    final prefix = oldLine.substring(0, colonIdx + 1);
    final afterColon = oldLine.substring(colonIdx + 1);
    final commentStart = afterColon.indexOf(' #');
    final comment = commentStart >= 0 ? afterColon.substring(commentStart) : '';
    _lines[lineIdx] = '$prefix $value$comment';
  }

  /// 读取整数值，不存在或格式错误返回 null。
  int? getInt(String path) {
    final v = this[path];
    if (v == null) return null;
    return int.tryParse(v);
  }

  /// 读取浮点值，不存在或格式错误返回 null。
  double? getDouble(String path) {
    final v = this[path];
    if (v == null) return null;
    return double.tryParse(v);
  }

  /// 读取布尔值（`true`/`false`），不存在或格式不符返回 null。
  bool? getBool(String path) {
    final v = this[path];
    if (v == null) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    return null;
  }

  /// 获取服务器端口（`network-settings.port`），默认 19132。
  int getPort() => getInt('network-settings.port') ?? 19132;

  /// 判断指定 `a.b.c` 路径是否存在。
  bool containsKey(String path) => _index.containsKey(path);

  /// 序列化为 server-settings.yml 格式字符串（保留原始注释与格式）。
  @override
  String toString() => _lines.join('\n');

  /// 从一行 YAML 中提取 value 部分。
  static String? _parseValue(String line) {
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) return null;
    var value = line.substring(colonIdx + 1).trim();
    // 去除行尾注释（仅对未加引号的值生效）。
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
