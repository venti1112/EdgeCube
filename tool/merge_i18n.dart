// 把 .i18n_fragments/ 下各迁移代理产出的翻译片段合并进 assets/i18n 的
// zh_CN.json 与 en_US.json。片段格式：{"zh": {key: 中文}, "en": {key: English}}。
//
// 用法：dart tool/merge_i18n.dart [fragmentsDir]
// 默认 fragmentsDir 为 .i18n_fragments。合并后保留原有键顺序，新键按字母序追加；
// 已存在的键不会被覆盖（冲突会打印出来）。
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final fragDir = Directory(args.isNotEmpty ? args[0] : '.i18n_fragments');
  if (!fragDir.existsSync()) {
    stderr.writeln('片段目录不存在：${fragDir.path}');
    exit(1);
  }

  final zhFile = File('assets/i18n/zh_CN.json');
  final enFile = File('assets/i18n/en_US.json');
  final zh = _readMap(zhFile);
  final en = _readMap(enFile);

  final newZh = <String, String>{};
  final newEn = <String, String>{};
  final conflicts = <String>[];

  final fragments = fragDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final frag in fragments) {
    final data = jsonDecode(frag.readAsStringSync());
    if (data is! Map) continue;
    final fz = (data['zh'] as Map?) ?? const {};
    final fe = (data['en'] as Map?) ?? const {};
    fz.forEach((k, v) {
      final key = k.toString();
      if (zh.containsKey(key)) {
        if (zh[key] != v) conflicts.add('zh $key (已存在「${zh[key]}」≠「$v」)');
      } else {
        newZh[key] = v.toString();
      }
    });
    fe.forEach((k, v) {
      final key = k.toString();
      if (!en.containsKey(key)) newEn[key] = v.toString();
    });
  }

  // 追加新键（按 key 排序，分组更整齐）。
  final sortedZh = newZh.keys.toList()..sort();
  for (final k in sortedZh) {
    zh[k] = newZh[k]!;
  }
  final sortedEn = newEn.keys.toList()..sort();
  for (final k in sortedEn) {
    en[k] = newEn[k]!;
  }

  zhFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(zh)}\n');
  enFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(en)}\n');

  stdout.writeln(
    '合并完成：zh +${newZh.length}（共 ${zh.length}），en +${newEn.length}（共 ${en.length}）',
  );
  if (conflicts.isNotEmpty) {
    stdout.writeln('冲突（保留原值，未覆盖）：');
    for (final c in conflicts) {
      stdout.writeln('  - $c');
    }
  }
}

Map<String, String> _readMap(File f) {
  if (!f.existsSync()) return {};
  final decoded = jsonDecode(f.readAsStringSync());
  final result = <String, String>{};
  if (decoded is Map) {
    decoded.forEach((k, v) {
      if (v is String) result[k.toString()] = v;
    });
  }
  return result;
}
