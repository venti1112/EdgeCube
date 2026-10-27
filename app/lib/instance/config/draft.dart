import 'models.dart';
import 'parsers.dart';
import 'sections.dart';

/// 一次「进页面 → 改 → 存」的编辑会话。
///
/// 拿着 daemon 回来的那份文本与解析结果，记住「哪些字段被改了」。脏的判定按
/// **字段**而不是整份文本：改回原样就自动不脏，顶部的保存按钮随之
/// 变灰 —— 用户能一眼看出「还有没有没存的改动」。
///
/// 保存时**只写脏字段**（见 [serialize]），没动过的行连碰都不碰。
class ConfigDraft {
  ConfigDraft({
    required this.kind,
    required this.file,
    required this.document,
  }) : _original = {
         for (final field in fieldsOfKind(kind)) field.key: document[field.key],
       },
       _values = {
         for (final field in fieldsOfKind(kind))
           field.key: ?document[field.key],
       };

  /// daemon 认出来的类型（`java` / `pmmp` / `pnx` / `allay`）。
  final String kind;

  /// 文件名（daemon 给的，只用于显示）。
  final String file;

  final ConfigDocument document;

  /// 这次编辑用哪张字段表。
  List<ConfigSection> get sections => sectionsForKind(kind);

  /// 进入页面时各字段的原始值（`null` = 文件里原本没有这个键）。
  final Map<String, String?> _original;

  /// 编辑中的值。
  final Map<String, String> _values;

  ConfigFieldDef? _fieldOf(String key) {
    for (final field in fieldsOfKind(kind)) {
      if (field.key == key) return field;
    }
    return null;
  }

  /// 文件里原本有没有这个键。
  ///
  /// 用来决定**画不画**：「文件里没有的字段不显示」（开关除外 ——
  /// 缺省即关，得让用户能打开）。凭空显示一堆服务端根本不认的键只会让人困惑。
  bool present(String key) => _original[key] != null;

  /// 读文本框 / 下拉的值。文件里没有这个键时给空串（输入框要能输入）。
  String value(String key) => _values[key] ?? '';

  /// 读开关的值。**缺省即关**，且两种写法（`true`/`on`）都认。
  bool boolValue(String key) => BoolFormat.decode(_values[key]) ?? false;

  /// 这个字段相对进来时改过没有。
  ///
  /// 开关按**生效的布尔值**比较：文件里本来没有 `pvp`，用户打开又关上，不该算脏
  /// （否则会把一个原本不存在的键写进文件）。
  bool dirty(String key) {
    final field = _fieldOf(key);
    if (field?.kind == ConfigFieldKind.toggle) {
      final before = BoolFormat.decode(_original[key]) ?? false;
      final now = BoolFormat.decode(_values[key]) ?? false;
      return before != now;
    }
    return _values[key] != _original[key];
  }

  /// 有没有任何改动（顶部保存按钮的可用性看它）。
  bool get hasChanges => fieldsOfKind(kind).any((field) => dirty(field.key));

  /// 改一个文本 / 数字 / 下拉的值。
  void setValue(String key, String value) => _values[key] = value;

  /// 改一个开关的值（按字段自己的写法序列化：`true`/`false` 或 `on`/`off`）。
  void setBool(String key, bool value) {
    final format = _fieldOf(key)?.boolFormat ?? BoolFormat.trueFalse;
    _values[key] = format.encode(value);
  }

  /// 把改动落进 [document] 并序列化成要写回文件的文本。
  String serialize() {
    for (final field in fieldsOfKind(kind)) {
      if (!dirty(field.key)) continue;
      document.setValue(field.key, _values[field.key] ?? '');
    }
    return document.serialize();
  }
}
