import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_scope.dart';
import 'ec_preference.dart';

/// 打开「选择实例」页，返回用户选中的实例摘要；取消时返回 null。
///
/// 选中后会同步切换 [InstanceController] 的当前实例（与服务器主页的实例切换
/// 语义一致），使页面上依赖当前实例的其它功能保持一致。
Future<InstanceSummary?> pickInstance(
  BuildContext context, {
  String? title,
}) async {
  final controller = InstanceScope.of(context);
  final result = await Navigator.of(context).push<InstanceSummary>(
    MaterialPageRoute(
      builder: (_) => _InstancePickerPage(title: title),
    ),
  );
  if (result != null) {
    await controller.select(result.id);
  }
  return result;
}

/// 实例选择页：以卡片列表展示全部实例，当前实例以单选图标高亮。
class _InstancePickerPage extends StatelessWidget {
  const _InstancePickerPage({this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final theme = MiuixTheme.of(context);
    final selectedId = controller.selected?.id;

    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: title ?? context.tr('instancePicker.title'),
        showBack: true,
      ),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              for (final instance in controller.instances) ...[
                EcCardTile(
                  leading: Icon(
                    instance.id == selectedId
                        ? Icons.radio_button_checked
                        : Icons.dns_outlined,
                    size: 36,
                    color: instance.id == selectedId
                        ? theme.colors.primary
                        : null,
                  ),
                  title: instance.name,
                  summary: instance.id,
                  onTap: () => Navigator.of(context).pop(instance),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
