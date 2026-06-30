import 'package:path/path.dart' as p;
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

/// 语言检测结果：包含 re_highlight 语言标识名和对应的 Mode 规则。
///
/// [name] 用于 [CodeHighlightTheme.languages] 的键，
/// [mode] 用于语法高亮规则匹配。
typedef LanguageResult = ({String name, Mode mode});

/// 依据文件名扩展名推断 re_highlight 语法高亮语言；返回 null 表示按纯文本处理、不高亮。
///
/// 只看文件名、不读取内容，因此与 file_browser 的「可编辑扩展名白名单」相互独立——
/// 端口映射页直接传入的 `frpc.toml` 等不经白名单也能正确着色。覆盖范围对齐
/// `file_browser.dart` 的 `_textExtensions`（可在内置编辑器中打开的扩展名）。
LanguageResult? languageForFileName(String name) {
  switch (p.extension(name).toLowerCase()) {
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
