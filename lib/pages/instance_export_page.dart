import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../files/archive_service.dart';
import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/i18n_service.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../widgets/placeholder_page.dart';

/// 实例导出页：把指定实例目录下的全部文件压缩为 zip 压缩包并导出。
///
/// 提供两种导出方式：
/// - 分享：压缩到临时目录后调起系统分享面板；
/// - 保存到文件夹：压缩到用户选择的外部目录。
class InstanceExportPage extends StatelessWidget {
  const InstanceExportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final instances = controller.instances;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('instanceExport.title'))),
      body: SafeArea(
        child: instances.isEmpty
            ? PlaceholderPage(
                icon: Icons.archive_outlined,
                title: context.tr('instanceExport.emptyTitle'),
                description: context.tr('instanceExport.emptyDescription'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      context.tr('instanceExport.intro'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final instance in instances) ...[
                    _InstanceExportTile(
                      controller: controller,
                      instance: instance,
                      selected: instance.id == controller.selected?.id,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }
}

/// 单个实例导出卡片：展示实例名称与 id，提供「分享」与「保存到文件夹」操作。
class _InstanceExportTile extends StatelessWidget {
  const _InstanceExportTile({
    required this.controller,
    required this.instance,
    required this.selected,
  });

  final InstanceController controller;
  final InstanceSummary instance;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.dns_outlined,
              color: selected ? theme.colorScheme.primary : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(instance.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    instance.id,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('instanceExport.shareTooltip'),
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _share(context),
            ),
            IconButton(
              tooltip: context.tr('instanceExport.saveTooltip'),
              icon: const Icon(Icons.folder_copy_outlined),
              onPressed: () => _saveToFolder(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 文件名中非法字符替换为下划线，并确保非空。
  String _sanitizeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? instance.id : cleaned;
  }

  /// 压缩实例目录到临时文件并调起系统分享面板。
  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final dirNotExistMsg = context.tr('instanceExport.dirNotExist', {
      'name': instance.name,
    });
    final shareText = context.tr('instanceExport.shareText', {
      'name': instance.name,
    });
    final dir = await controller.directoryForId(instance.id);
    if (!await dir.exists()) {
      messenger.showSnackBar(SnackBar(content: Text(dirNotExistMsg)));
      return;
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(context.tr('instanceExport.compressing')),
            ],
          ),
        ),
      ),
    );
    try {
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final zipPath = p.join(
        tempDir.path,
        '${_sanitizeName(instance.name)}_$ts.zip',
      );
      await ArchiveService.compress([dir.path], zipPath);
      if (context.mounted) Navigator.of(context).pop();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(zipPath)], text: shareText),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('instanceExport.exportFailed', {'error': '$e'})),
        ),
      );
    }
  }

  /// 压缩实例目录到用户选择的外部文件夹。
  Future<void> _saveToFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final dirNotExistMsg = context.tr('instanceExport.dirNotExist', {
      'name': instance.name,
    });
    if (!await _ensurePermission(context)) return;
    if (!context.mounted) return;
    final dir = await controller.directoryForId(instance.id);
    if (!await dir.exists()) {
      messenger.showSnackBar(SnackBar(content: Text(dirNotExistMsg)));
      return;
    }
    if (!context.mounted) return;
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null) return;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Text(context.tr('instanceExport.compressing')),
            ],
          ),
        ),
      ),
    );
    try {
      const service = FileService();
      final zipPath = await service.compressMany(
        [dir.path],
        Directory(destDir),
        '${_sanitizeName(instance.name)}.zip',
      );
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('instanceExport.savedTo', {'path': zipPath})),
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('instanceExport.exportFailed', {'error': '$e'})),
        ),
      );
    }
  }

  /// 确保已获得「管理全部文件」权限；未授予则弹窗引导用户去系统设置开启。
  Future<bool> _ensurePermission(BuildContext context) async {
    if (await StoragePermission.isGranted()) return true;
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('instanceExport.permissionTitle')),
        content: Text(context.tr('instanceExport.permissionContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('instanceExport.grantPermission')),
          ),
        ],
      ),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    return false;
  }
}
