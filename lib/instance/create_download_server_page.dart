import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import 'create_download_progress_page.dart';
import 'create_download_version_page.dart';
import 'download_session.dart';
import 'server_select_step.dart';

/// 流程第 3 页：选择具体服务端。
///
/// [types] 为上一页（Java 分类 / 基岩类型）确定的可选服务端类型列表。
/// 选定后按类型跳转：
/// - 模组端（fabric/forge/neoforge）→ 版本页（选 MC 版本）
/// - BungeeCord → 直接进入下载页（下载最新构建，无版本选择）
/// - 其余（原版/插件/代理/基岩端）→ 版本页（选版本）
class SelectServerPage extends StatelessWidget {
  const SelectServerPage({
    super.key,
    required this.session,
    required this.types,
  });

  final DownloadSession session;
  final List<String> types;

  void _select(BuildContext context, String type) {
    session.serverType = type;
    if (type == 'bungeecord') {
      // BungeeCord 无版本选择，直接进入下载页下载最新构建。
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DownloadProgressPage(session: session),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectVersionPage(
          session: session,
          stage: VersionStage.forServerType(type),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bedrock =
        types.contains('pocketmine') || types.contains('powernukkitx');
    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: bedrock
            ? context.tr('instance.titleBedrockServerType')
            : context.tr('instance.titleJavaServerType'),
      ),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ServerTypeTileList(
            types: types,
            onSelect: (t) => _select(context, t),
          ),
        ),
      ),
    );
  }
}
