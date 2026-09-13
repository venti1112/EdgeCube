import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../mods/mod_metadata.dart';
import 'miuix_dialog.dart';
import 'miuix_snackbar.dart';

/// 扫描实例 `mods/` 目录，识别客户端专属模组并弹窗供用户一键移除。
///
/// 整合包导入后，`overrides` 解压会把客户端模组一并放进 `mods/`（整合包作者
/// 打包时通常面向客户端）。这些模组在服务端运行时会崩溃或报错，需要清理。
///
/// 仅移除元数据明确声明 `environment="client"` / `side="CLIENT"` 的模组；
/// 元数据缺失（`unknown`）的模组**不**列入清理范围，避免误删服务端模组。
///
/// 返回值：
/// - `true`：已执行清理（有文件被删除）。
/// - `false`：找到客户端模组但用户取消弹窗。
/// - `null`：没有找到可识别的客户端模组（不弹窗）。
Future<bool?> showClientModsCleanupDialog(
  BuildContext context,
  Directory instanceDir,
) async {
  final modsDir = Directory(p.join(instanceDir.path, 'mods'));
  if (!modsDir.existsSync()) return null;

  // 收集 mods/ 下的 .jar（含 .disabled，用户可能手动禁用过）。
  final jarPaths = <String>[];
  for (final entry in modsDir.listSync(followLinks: false)) {
    if (entry is! File) continue;
    final name = p.basename(entry.path);
    final lower = name.toLowerCase();
    if (!lower.endsWith('.jar') && !lower.endsWith('.jar.disabled')) continue;
    jarPaths.add(entry.path);
  }
  if (jarPaths.isEmpty) return null;

  // 批量解析元数据（在 isolate 中执行，避免阻塞 UI）。
  final metas = await ModMetadataParser.parseAll(jarPaths);

  // 筛出客户端专属模组。
  final clientMods = <_ClientMod>[];
  for (final path in jarPaths) {
    final meta = metas[path];
    if (meta != null && meta.isClientOnly) {
      clientMods.add(_ClientMod(path: path, meta: meta));
    }
  }
  if (clientMods.isEmpty) return null;
  if (!context.mounted) return null;

  return showMiuixDialog<bool>(
    context: context,
    title: context.tr('clientModsCleanup.title'),
    summary: context.tr('clientModsCleanup.summary', {
      'count': '${clientMods.length}',
    }),
    builder: (ctx) => _ClientModsCleanupBody(mods: clientMods),
  ).then((r) => r ?? false);
}

/// 单个客户端模组条目。
class _ClientMod {
  const _ClientMod({required this.path, required this.meta});

  final String path;
  final ModMetadata meta;
}

/// 清理对话框主体：模组列表 + 全选/取消 + 确认移除。
class _ClientModsCleanupBody extends StatefulWidget {
  const _ClientModsCleanupBody({required this.mods});

  final List<_ClientMod> mods;

  @override
  State<_ClientModsCleanupBody> createState() => _ClientModsCleanupBodyState();
}

class _ClientModsCleanupBodyState extends State<_ClientModsCleanupBody> {
  /// 各模组的选中状态，默认全选（一键移除的常见诉求）。
  late final List<bool> _selected = List.filled(widget.mods.length, true);

  bool get _anySelected => _selected.any((s) => s);

  Future<void> _confirm() async {
    final toDelete = <String>[];
    for (var i = 0; i < widget.mods.length; i++) {
      if (_selected[i]) toDelete.add(widget.mods[i].path);
    }
    if (toDelete.isEmpty) return;

    var deleted = 0;
    for (final path in toDelete) {
      try {
        await File(path).delete();
        deleted++;
      } catch (_) {}
    }
    if (!mounted) return;
    showMiuixSnackbar(
      context.tr('clientModsCleanup.removed', {'count': '$deleted'}),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 模组列表。
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: widget.mods.length,
            itemBuilder: (ctx, i) {
              final mod = widget.mods[i];
              return _ModRow(
                name: mod.meta.name,
                version: mod.meta.version,
                loaderLabel: mod.meta.loaderLabel,
                selected: _selected[i],
                onChanged: (v) => setState(() => _selected[i] = v),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // 全选/全不选 + 操作按钮。
        Row(
          children: [
            MiuixTextButton(
              context.tr(_anySelected
                  ? 'clientModsCleanup.deselectAll'
                  : 'clientModsCleanup.selectAll'),
              onPressed: () {
                setState(() {
                  final target = !_anySelected;
                  for (var i = 0; i < _selected.length; i++) {
                    _selected[i] = target;
                  }
                });
              },
            ),
            const Spacer(),
            MiuixTextButton(
              context.tr('common.cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(width: 8),
            MiuixButton(
              onPressed: _anySelected ? _confirm : null,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(context.tr('clientModsCleanup.remove')),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单个模组行：复选框 + 名称 + 版本/加载器标签。
class _ModRow extends StatelessWidget {
  const _ModRow({
    required this.name,
    required this.version,
    required this.loaderLabel,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final String? version;
  final String loaderLabel;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
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
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: theme.textStyles.main),
                  if (version != null || loaderLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (loaderLabel.isNotEmpty) loaderLabel,
                        if (version != null) version,
                      ].join(' · '),
                      style: theme.textStyles.footnote1.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
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
