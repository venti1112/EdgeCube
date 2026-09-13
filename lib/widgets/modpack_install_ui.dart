import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../mods/modpack/modpack_provider.dart';
import '../mods/modpack_service.dart';
import 'ec_preference.dart';
import 'miuix_dialog.dart';
import '../instance/progress_steps.dart';

/// 整合包加载器的人类可读名称。
///
/// 抽自 `modpack_install_page.dart` 与 `create_modpack_page.dart` 中两份完全
/// 相同的 `_loaderLabel` / `_modpackLoaderLabel`。键名遵循 Modrinth 风格
/// （见 [ParsedModpack.dependencies]）。
String modpackLoaderLabel(BuildContext context, ParsedModpack modpack) {
  final deps = modpack.dependencies;
  if (deps['fabric-loader'] != null) return 'Fabric';
  if (deps['quilt-loader'] != null) return 'Quilt';
  if (deps['forge'] != null) return 'Forge';
  if (deps['neo-forge'] != null || deps['neoforge'] != null) return 'NeoForge';
  if (deps['minecraft'] != null) return context.tr('instance.modpackVanilla');
  return '-';
}

/// 整合包导入前的确认弹窗：展示名称 / MC 版本 / 加载器 / 模组数。
///
/// [extraNotice] 会拼接在摘要文案之后（如「不替换服务端 jar」提示），
/// 不传则只显示摘要——对应新建实例向导里的整合包导入场景。
Future<bool> showModpackConfirmDialog(
  BuildContext context,
  ParsedModpack modpack, {
  String? extraNotice,
}) {
  final mc = modpack.dependencies['minecraft'] ?? '-';
  final loader = modpackLoaderLabel(context, modpack);
  final modCount = modpack.serverFiles.length;
  final summary = context.tr('instance.modpackSummary', {
    'name': modpack.name ?? '-',
    'mc': mc,
    'loader': loader,
    'count': '$modCount',
  });
  return showMiuixConfirm(
    context,
    title: context.tr('instance.modpackConfirmTitle'),
    message: extraNotice == null ? summary : '$summary\n\n$extraNotice',
    cancelLabel: context.tr('common.cancel'),
    confirmLabel: context.tr('common.ok'),
  );
}

/// 整合包导入页的标准脚手架。
///
/// 抽自 `modpack_install_page.dart` 的 `build` 方法：`PopScope`（忙碌时禁止
/// 返回）+ `MiuixScaffold` + `EcTopAppBar` + `SafeArea(top: false)`，并根据
/// [busy] 在 [busyView] 与 [content] 之间切换。两个整合包导入入口
/// （新建实例向导 / 已有实例导入）共用此结构。
class ModpackInstallScaffold extends StatelessWidget {
  const ModpackInstallScaffold({
    super.key,
    required this.title,
    required this.busy,
    required this.content,
    required this.busyView,
  });

  final String title;

  /// 导入进行中（解析 / 下载 / 解压）。为 true 时禁止返回并展示 [busyView]。
  final bool busy;

  /// 非忙碌态展示的页面内容。
  final Widget content;

  /// 忙碌态展示的进度内容（通常是 [ModpackImportStep]）。
  final Widget busyView;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: MiuixScaffold(
        topBar: EcTopAppBar(title: title),
        content: (padding) => Padding(
          padding: padding,
          // padding.top 已含顶栏（连同状态栏）高度，故 SafeArea 只保留左右与底部。
          child: SafeArea(
            top: false,
            child: busy ? busyView : content,
          ),
        ),
      ),
    );
  }
}

/// 整合包导入页的操作列表布局：介绍文案 + 卡片列表 + 脚注。
///
/// 对应 `modpack_install_page.dart` 的 `_buildContent` 中那段 `ListView`：
/// 顶部一段说明文字，中间若干 [EcCardTile] 操作项，底部一段脚注提示。
/// 卡片由调用方通过 [actions] 提供，保持各操作项的回调与上下文绑定灵活。
class ModpackActionList extends StatelessWidget {
  const ModpackActionList({
    super.key,
    required this.intro,
    required this.actions,
    this.footnote,
  });

  /// 顶部介绍文案。
  final String intro;

  /// 操作卡片列表（通常是 [EcCardTile]）。
  final List<Widget> actions;

  /// 底部脚注提示，可选。
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            intro,
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
        ...actions,
        if (footnote != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              footnote!,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
