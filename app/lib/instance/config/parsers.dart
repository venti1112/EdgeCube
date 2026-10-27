/// 服务端配置文件的「行级编辑器」。
///
/// # 为什么要自己写而不是用 YAML 库
///
/// 编辑配置的**第一诉求是别弄坏用户的文件**：注释、空行、字段顺序、行尾那个
/// `# 说明`、缩进用几个空格……这些都不该因为「存一次」而变样。用库解析成
/// 对象再序列化回去，必然丢掉一部分（注释最先丢）。
///
/// 所以是**面向行的**：解析只建一张「键 → 行号」的索引，改值就是改那一行冒号
/// 后面那一段，其余行原文不动 —— 这里把两份（properties 一份、YAML 两份）合成
/// 一套：
///
/// * [`KeyValueDocument`] —— `server.properties`，`key=value` / `#` 注释；
/// * [`YamlDocument`] —— `pnx.yml` / `server-settings.yml`，按缩进栈支持任意
///   层级，键是点分路径 `a.b.c`。
///
/// 两份都**只改已存在的键**（不认识的键不新增不删除）：字段表里没有的键原样
/// 留着，用户手写的自定义配置不会因为「进来点了保存」而消失。
library;

/// 一份可编辑的配置文本。
abstract class ConfigDocument {
  /// 从原文解析。
  factory ConfigDocument.parse(String kind, String content) =>
      kind.startsWith('pnx') || kind.startsWith('allay')
      ? YamlDocument.parse(content)
      : KeyValueDocument.parse(content);

  /// 按 key（YAML 是点分路径）取值；不存在返回 `null`。
  String? operator [](String key);

  /// 改一个值。**键不存在时什么也不做** —— 见库文档的说明。
  void setValue(String key, String value);

  /// 这个键在不在文件里。
  bool containsKey(String key);

  /// 序列化回文本（除改过的行，其余逐字保留）。
  String serialize();
}

/// `key=value` 形式的配置文件（`server.properties`）。
class KeyValueDocument implements ConfigDocument {
  KeyValueDocument._(this._lines, this._index, this._endsWithNewline);

  /// 全部行（含注释与空行）。
  final List<String> _lines;

  /// `key` → 行号。
  final Map<String, int> _index;

  /// 原文件末尾有没有换行符 —— 有就保持有、没有就别硬加，存一次不会凭空多
  /// 一个空行。
  final bool _endsWithNewline;

  factory KeyValueDocument.parse(String content) {
    final endsWithNewline = content.endsWith('\n');
    final raw = content.split('\n');
    // `split` 在「以换行结尾」时会多给一个空元素，那是分隔符不是内容，去掉
    final lines = endsWithNewline && raw.isNotEmpty
        ? raw.sublist(0, raw.length - 1)
        : raw;

    final index = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].endsWith('\r')
          ? lines[i].substring(0, lines[i].length - 1)
          : lines[i];
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      // 首个 `=` 之前为空的行（`=x`）不算属性
      if (eq <= 0) continue;
      index[line.substring(0, eq).trim()] = i;
    }
    return KeyValueDocument._(lines, index, endsWithNewline);
  }

  @override
  String? operator [](String key) {
    final i = _index[key];
    if (i == null) return null;
    final line = _lines[i];
    // 与解析时同一套：去掉行尾 `\r`，值取首个 `=` 之后的**全部**
    // （properties 的值里可以有 `=`，不能按最后一个切）
    final clean = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    return clean.substring(clean.indexOf('=') + 1);
  }

  @override
  void setValue(String key, String value) {
    final i = _index[key];
    if (i == null) return;
    final line = _lines[i];
    final eq = line.indexOf('=');
    if (eq < 0) return;
    final cr = line.endsWith('\r') ? '\r' : '';
    _lines[i] = '${line.substring(0, eq + 1)}$value$cr';
  }

  @override
  bool containsKey(String key) => _index.containsKey(key);

  @override
  String serialize() => _lines.join('\n') + (_endsWithNewline ? '\n' : '');
}

/// 缩进式 YAML 的配置文件（`pnx.yml` / `server-settings.yml`）。
///
/// 光标是「缩进栈」：每读到一个 `key:`（冒号后为空）就压栈，读到 `key: value`
/// 就把它记为 `<父路径>.<key>`。这样任意层级都能定位，而写回只改那一行的值。
class YamlDocument implements ConfigDocument {
  YamlDocument._(this._lines, this._index);

  final List<String> _lines;

  /// `a.b.c` → 行号（只含 `key: value` 叶子行，mapping 起始行不在内）。
  final Map<String, int> _index;

  factory YamlDocument.parse(String content) {
    final lines = content.split('\n');
    final index = <String, int>{};

    // 栈里是「这一层 mapping 的缩进 + 到目前为止的路径」
    final indents = <int>[];
    final paths = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].endsWith('\r')
          ? lines[i].substring(0, lines[i].length - 1)
          : lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final indent = line.length - line.trimLeft().length;

      // 回到更外层：弹掉所有「缩进 >= 本行」的层。
      // `>=` 而不是 `>`：同级的新 mapping 起始行也要先把上一个兄弟弹掉。
      while (indents.isNotEmpty && indents.last >= indent) {
        indents.removeLast();
        paths.removeLast();
      }

      final colon = trimmed.indexOf(':');
      if (colon < 0) continue;
      final key = trimmed.substring(0, colon).trim();
      final rest = trimmed.substring(colon + 1).trim();
      final path = paths.isEmpty ? key : '${paths.last}.$key';

      if (rest.isEmpty) {
        // mapping 起始行：压栈，它自己不是可写的值
        indents.add(indent);
        paths.add(path);
      } else {
        index[path] = i;
      }
    }
    return YamlDocument._(lines, index);
  }

  @override
  String? operator [](String key) {
    final i = _index[key];
    if (i == null) return null;
    return _valueOf(_lines[i]);
  }

  @override
  void setValue(String key, String value) {
    final i = _index[key];
    if (i == null) return;
    final line = _lines[i];
    final colon = line.indexOf(':');
    if (colon < 0) return;
    // 保留「缩进 + key + 冒号」与行尾注释，只换中间那段值
    final head = line.substring(0, colon + 1);
    final tail = line.substring(colon + 1);
    final commentAt = tail.indexOf(' #');
    final comment = commentAt >= 0 ? tail.substring(commentAt) : '';
    _lines[i] = '$head $value$comment';
  }

  @override
  bool containsKey(String key) => _index.containsKey(key);

  @override
  String serialize() => _lines.join('\n');

  /// 取一行的值：去掉行尾注释与首尾引号。空值算「没有」。
  static String? _valueOf(String line) {
    final colon = line.indexOf(':');
    if (colon < 0) return null;
    var value = line.substring(colon + 1).trim();
    // 加引号的值里 ` #` 是内容的一部分，不能当注释切
    if (!value.startsWith('"') && !value.startsWith("'")) {
      final at = value.indexOf(' #');
      if (at >= 0) value = value.substring(0, at).trim();
    }
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }
}
