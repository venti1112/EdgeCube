import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import 'create_download_category_page.dart';
import 'create_download_proot_page.dart';
import 'create_download_server_page.dart';
import 'create_instance_page.dart';
import 'download_session.dart';
import 'server_select_step.dart';

/// 流程第 1 页：选择类型（Java 版 / 基岩版 / Survivalcraft 联机版）。
///
/// 这是「下载服务端」流程的根页面，以 [kDownloadFlowRootRouteName] 注册路由名，
/// 完成时各下级页面通过 [finishDownloadFlow] 一次性弹回到此并返回
/// [CreateInstanceResult.done]。
class SelectEditionPage extends StatelessWidget {
  const SelectEditionPage({super.key, required this.session});

  final DownloadSession session;

  void _pushJava(BuildContext context) {
    session.serverType = null;
    session.javaServerCategory = null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectCategoryPage(session: session),
      ),
    );
  }

  void _pushBedrock(BuildContext context) {
    session.serverType = null;
    session.javaServerCategory = null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectServerPage(
          session: session,
          types: const ['pocketmine', 'powernukkitx', 'allay'],
        ),
      ),
    );
  }

  void _pushSurvivalcraft(BuildContext context) {
    session.serverType = 'survivalcraft';
    session.javaServerCategory = null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectProotContainerPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('instance.titleSelectEdition'))),
      body: SafeArea(
        child: EditionSelectStep(
          onSelectJavaEdition: () => _pushJava(context),
          onSelectBedrockEdition: () => _pushBedrock(context),
          onSelectSurvivalcraftEdition: () => _pushSurvivalcraft(context),
        ),
      ),
    );
  }
}
