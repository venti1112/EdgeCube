import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'models.dart';

/// 扫描结果里挑出「客户端专属模组」并弹窗供用户一键移除。
///
/// 整合包导入后 `overrides` 解压会把客户端模组一并放进 `mods/`（整合包作者
/// 打包时通常面向客户端）。这些模组在服务端运行时会崩溃或报错，需要清理。
///
/// **只列出元数据明确声明 `environment="client"` 的模组**；元数据缺失
/// （`environment` 为 `unknown`）的模组**不**列入，避免误删服务端模组 ——
/// 这条判据是 daemon 解析 jar 得到的（`ModMeta.isClientOnly`）。
///
/// 返回值：
/// - `true`：已执行清理（有文件被删除）；
/// - `false`：找到客户端模组但用户取消；
/// - `null`：没有客户端模组（**不弹窗**，调用方据此提示「未找到可识别的客户端模组」）。
Future<bool?> showClientModsCleanupDialog(
  BuildContext context, {
  required ModsApi api,
  required String instanceId,
  required List<InstalledMod> mods,
}) async {
  if (mods.isEmpty) return null;

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ClientModsCleanupDialog(
      api: api,
      instanceId: instanceId,
      mods: mods,
    ),
  );
}

/// 清理对话框主体：标题 + 说明 + 模组列表 + 全选/取消 + 移除。
class _ClientModsCleanupDialog extends ConsumerStatefulWidget {
  const _ClientModsCleanupDialog({
    required this.api,
    required this.instanceId,
    required this.mods,
  });

  final ModsApi api;
  final String instanceId;
  final List<InstalledMod> mods;

  @override
  ConsumerState<_ClientModsCleanupDialog> createState() =>
      _ClientModsCleanupDialogState();
}

class _ClientModsCleanupDialogState
    extends ConsumerState<_ClientModsCleanupDialog> {
  /// 各模组的选中状态，**默认全选**（一键移除是常见诉求）。
  late final List<bool> _selected = List.filled(widget.mods.length, true);
  bool _removing = false;

  bool get _anySelected => _selected.any((selected) => selected);

  Future<void> _confirm() async {
    final targets = <InstalledMod>[
      for (var i = 0; i < widget.mods.length; i++)
        if (_selected[i]) widget.mods[i],
    ];
    if (targets.isEmpty || _removing) return;
    setState(() => _removing = true);

    var removed = 0;
    for (final mod in targets) {
      try {
        // 客户端专属模组只可能出现在 mods/ 里（插件不带 side 信息）
        await widget.api.remove(
          instanceId: widget.instanceId,
          projectType: 'mod',
          fileName: mod.fileName,
        );
        removed++;
      } catch (_) {
        // 单个删不掉不该中断整批
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已移除 $removed 个客户端模组')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('清理客户端模组'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '检测到 ${widget.mods.length} 个客户端专属模组，它们在服务端运行会导致崩溃，建议移除。',
            ),
            const SizedBox(height: 12),
            // 模组列表（限高在屏幕高度的一半）
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: widget.mods.length,
                itemBuilder: (context, index) {
                  final mod = widget.mods[index];
                  return _ClientModRow(
                    mod: mod,
                    selected: _selected[index],
                    onChanged: (value) =>
                        setState(() => _selected[index] = value),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // 全选/取消全选 + 取消 + 移除
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      final target = !_anySelected;
                      for (var i = 0; i < _selected.length; i++) {
                        _selected[i] = target;
                      }
                    });
                  },
                  child: Text(_anySelected ? '取消全选' : '全选'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _removing
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _anySelected && !_removing ? _confirm : null,
                  child: _removing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('移除'),
                ),
              ],
            ),
            if (widget.mods.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '这些模组已从列表中勾选；移除后可以从上游重新下载。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个模组行：复选框 + 名称 + 「加载器 · 版本」。
class _ClientModRow extends StatelessWidget {
  const _ClientModRow({
    required this.mod,
    required this.selected,
    required this.onChanged,
  });

  final InstalledMod mod;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = mod.meta;
    final label = [
      if (meta != null && meta.loaderLabel.isNotEmpty) meta.loaderLabel,
      if (meta?.version != null) meta!.version!,
    ].join(' · ');

    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mod.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (label.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
