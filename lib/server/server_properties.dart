/// server.properties 文件的解析、读写与序列化。
///
/// 该模块独立于 UI 层，供任何需要读取或修改 server.properties 的功能使用。
///
/// 文件格式：
/// - 以 `#` 开头的行为注释，原样保留。
/// - `key=value` 形式的行为属性条目；value 中的 `\:` `\=` `\ ` `\t` `\\`
///   均为 Java Properties 转义序列，本解析器在读取时不解码，写入时也不编码，
///   保持与服务端原生格式一致。
/// - 空行保留，序列化时原样输出。
library;

/// 单条 server.properties 条目：键值对或注释/空行。
sealed class PropertiesEntry {
  const PropertiesEntry();
}

/// 注释行或空行（保留原始文本以便原样回写）。
class CommentEntry extends PropertiesEntry {
  const CommentEntry(this.raw);

  /// 原始行文本（含前导 `#` 及空格，不含换行符）。
  final String raw;
}

/// `key=value` 属性条目。
class KeyValueEntry extends PropertiesEntry {
  const KeyValueEntry(this.key, this.value);

  final String key;
  final String value;

  KeyValueEntry copyWith({String? value}) =>
      KeyValueEntry(key, value ?? this.value);
}

/// 解析结果：有序的条目列表，并提供按 key 随机访问的快捷方法。
class ServerProperties {
  ServerProperties._(this._entries);

  final List<PropertiesEntry> _entries;

  /// 从原始文本解析 server.properties 内容。
  ///
  /// 解析规则：
  /// - 以 `#` 开头的行视为注释。
  /// - 含 `=` 的行按首个 `=` 分割为 key/value（value 可能为空）。
  /// - 其它非空行视为注释（保留原文）。
  factory ServerProperties.parse(String content) {
    final lines = content.split('\n');
    final entries = <PropertiesEntry>[];
    for (var raw in lines) {
      // 去掉行尾的 \r（兼容 Windows 换行）。
      if (raw.endsWith('\r')) raw = raw.substring(0, raw.length - 1);

      if (raw.isEmpty || raw.startsWith('#')) {
        entries.add(CommentEntry(raw));
      } else {
        final eqIndex = raw.indexOf('=');
        if (eqIndex > 0) {
          final key = raw.substring(0, eqIndex).trim();
          final value = raw.substring(eqIndex + 1);
          entries.add(KeyValueEntry(key, value));
        } else {
          // 无法解析的行视为注释保留。
          entries.add(CommentEntry(raw));
        }
      }
    }
    return ServerProperties._(entries);
  }

  /// 所有有序条目（只读视图）。
  List<PropertiesEntry> get entries => List.unmodifiable(_entries);

  /// 以 key 为索引获取值；不存在返回 null。
  String? operator [](String key) {
    for (final e in _entries) {
      if (e is KeyValueEntry && e.key == key) return e.value;
    }
    return null;
  }

  /// 设置 key 的值；key 已存在则更新，否则追加到末尾。
  void operator []=(String key, String value) {
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (e is KeyValueEntry && e.key == key) {
        _entries[i] = e.copyWith(value: value);
        return;
      }
    }
    _entries.add(KeyValueEntry(key, value));
  }

  /// 是否存在指定 key。
  bool containsKey(String key) => this[key] != null;

  /// 移除指定 key（若存在）。
  void remove(String key) {
    _entries.removeWhere((e) => e is KeyValueEntry && e.key == key);
  }

  // —— 类型化快捷读取 ——

  /// 读取布尔值（`true`/`false`），不存在或格式不符返回 null。
  bool? getBool(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    return null;
  }

  /// 读取整数值，不存在或格式错误返回 null。
  int? getInt(String key) {
    final v = this[key];
    if (v == null) return null;
    return int.tryParse(v);
  }

  // —— 类型化快捷写入 ——

  void setBool(String key, bool value) => this[key] = value.toString();
  void setInt(String key, int value) => this[key] = value.toString();

  /// 将所有条目序列化为 server.properties 格式的字符串。
  ///
  /// 输出与原文件保持一致：注释/空行原样输出，`key=value` 条目直接拼接。
  /// 末尾添加一个换行符。
  @override
  String toString() {
    final buf = StringBuffer();
    for (final e in _entries) {
      switch (e) {
        case CommentEntry(:final raw):
          buf.writeln(raw);
        case KeyValueEntry(:final key, :final value):
          buf.writeln('$key=$value');
      }
    }
    return buf.toString();
  }
}
