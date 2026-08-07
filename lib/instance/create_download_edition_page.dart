import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import 'create_download_category_page.dart';
import 'create_download_proot_page.dart';
import 'create_download_server_page.dart';
import 'create_download_version_page.dart';
import 'create_instance_page.dart';
import 'download_session.dart';
import 'server_select_step.dart';

/// 流程第 1 页：选择类型（Java 版 / 基岩版 / Survivalcraft 联机版）。
///
/// 这是「下载服务端」流程的根页面，以 [kDownloadFlowRootRouteName] 注册路由名，
/// 完成时各下级页面通过 [finishDownloadFlow] 一次性弹回到此并返回
/// [CreateInstanceResult.done]。
///
/// 更新模式下 Survivalcraft 跳过 proot 容器选择（实例已在容器内），直接进入版本页。
class SelectEditionPage extends StatelessWidget {
  const SelectEditionPage({super.key, required this.session});

  final DownloadSession session;

  void _pushJava(BuildContext context) {
    session.serverType = null;
    session.javaServerCategory = null;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SelectCategoryPage(session: session)),
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
    // 更新模式：实例已在 proot 容器内，跳过容器选择，直接进版本页。
    if (session.updateMode) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SelectVersionPage(
            session: session,
            stage: VersionStage.forServerType('survivalcraft'),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectProotContainerPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('instance.titleSelectEdition')),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: EditionSelectStep(
            onSelectJavaEdition: () => _pushJava(context),
            onSelectBedrockEdition: () => _pushBedrock(context),
            onSelectSurvivalcraftEdition: () => _pushSurvivalcraft(context),
          ),
        ),
      ),
    );
  }
}
