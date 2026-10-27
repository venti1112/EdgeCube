import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dos.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;

import 'models.dart';

/// 语言检测结果：包含 re_highlight 语言标识名和对应的 Mode 规则。
///
/// `name` 用作 `CodeHighlightTheme.languages` 的键（见 editor_page.dart），
/// `mode` 用于语法高亮规则匹配。
typedef LanguageResult = ({String name, Mode mode});

/// 依据文件名扩展名推断 re_highlight 语法高亮语言；返回 null 表示按纯文本处理、不高亮。
///
/// 只看文件名、不读取内容，因此与 `models.dart` 那张「点行就直接打开」的扩展名表
/// （`textExtensions`）相互独立。覆盖范围对齐那张表。
LanguageResult? languageForFileName(String name) {
  switch (extensionOf(name)) {
    case '.json':
    case '.json5':
    case '.mcmeta':
    case '.snbt': // SNBT 近似 JSON，借用其括号/字符串着色
      return (name: 'json', mode: langJson);
    case '.yml':
    case '.yaml':
      return (name: 'yaml', mode: langYaml);
    case '.properties':
    case '.lang':
      return (name: 'properties', mode: langProperties);
    case '.toml': // re_highlight 无 toml，用 ini 兜底（键值/分段语法相近）
    case '.ini':
    case '.cfg':
    case '.conf':
    case '.env':
      return (name: 'ini', mode: langIni);
    case '.xml':
    case '.html':
    case '.htm':
      return (name: 'xml', mode: langXml);
    case '.css':
      return (name: 'css', mode: langCss);
    case '.js':
      return (name: 'javascript', mode: langJavascript);
    case '.ts':
      return (name: 'typescript', mode: langTypescript);
    case '.sh':
      return (name: 'bash', mode: langBash);
    case '.bat':
    case '.cmd':
      return (name: 'dos', mode: langDos);
    case '.py':
      return (name: 'python', mode: langPython);
    case '.lua':
      return (name: 'lua', mode: langLua);
    case '.md':
    case '.markdown':
      return (name: 'markdown', mode: langMarkdown);
    default:
      return null; // .txt/.text/.log/.list/.csv/.tsv 等按纯文本处理
  }
}
