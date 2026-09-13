import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 校验内置多语言资源：清单可解析、各语言 JSON 合法、键集合完全一致。
///
/// 缺键会在运行时静默回退到中文源，多键则是无用的死文案，两者都视为错误，
/// 避免新增文案时只改了其中一种语言。
void main() {
  const dir = 'assets/i18n';

  test('index.json 中的语言都能解析且键集合一致', () {
    final indexRaw = File('$dir/index.json').readAsStringSync();
    final index = jsonDecode(indexRaw) as List<dynamic>;
    final locales = [
      for (final entry in index)
        if (entry is Map<String, dynamic>) entry['locale'] as String,
    ];
    expect(locales, isNotEmpty);
    // 中文源是权威键集，必须排在最前。
    expect(locales.first, 'zh_CN');

    final keySets = <String, Set<String>>{};
    for (final locale in locales) {
      final raw = File('$dir/$locale.json').readAsStringSync();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      keySets[locale] = map.keys.toSet();
      expect(map, isNotEmpty, reason: '$locale 没有翻译条目');
    }

    final source = keySets['zh_CN']!;
    for (final locale in locales.skip(1)) {
      final keys = keySets[locale]!;
      expect(
        keys.difference(source),
        isEmpty,
        reason: '$locale 存在中文源没有的多余键',
      );
      expect(
        source.difference(keys),
        isEmpty,
        reason: '$locale 缺少中文源中的键',
      );
    }
  });
}
