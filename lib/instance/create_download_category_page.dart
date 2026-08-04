import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import 'create_download_server_page.dart';
import 'download_session.dart';
import 'server_select_step.dart';

/// 流程第 2 页：选择服务端分类（Java 类型独有）。
///
/// 分类：原版 / 插件 / 模组 / 代理。选定后进入该分类下的具体服务端列表。
class SelectCategoryPage extends StatelessWidget {
  const SelectCategoryPage({super.key, required this.session});

  final DownloadSession session;

  /// 各分类下可选的具体服务端类型。
  static const Map<String, List<String>> _categories = {
    'vanilla': ['vanilla'],
    'plugin': ['paper', 'spigot', 'craftbukkit', 'purpur', 'leaf', 'leaves'],
    'mod': ['fabric', 'forge', 'neoforge'],
    'proxy': ['velocity', 'bungeecord'],
  };

  void _selectCategory(BuildContext context, String category) {
    session.javaServerCategory = category;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectServerPage(
          session: session,
          types: _categories[category] ?? const <String>[],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: context.tr('instance.titleJavaServerCategory'),
        navigationIcon: const EcBackButton(),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: SafeArea(
          child: JavaServerCategoryStep(
            onSelectCategory: (c) => _selectCategory(context, c),
          ),
        ),
      ),
    );
  }
}
