import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import 'create_instance_page.dart';
import 'instance.dart';
import 'instance_controller.dart';

/// 「导入服务端」独立页：选择本地 jar/phar 导入到已创建的空实例。
///
/// 实例由上一页（向导根页）创建并通过 [instanceId] 传入；本页只负责选文件、导入、
/// 写配置。成功后 `pop(CreateInstanceResult.done)`，由根页收尾关闭向导；用户取消选择
/// 或导入失败则 `pop()` 返回根页。未完成即离开时，[dispose] 清理这个空实例。
class ImportServerPage extends StatefulWidget {
  const ImportServerPage({
    super.key,
    required this.controller,
    required this.instanceId,
  });

  final InstanceController controller;
  final String instanceId;

  @override
  State<ImportServerPage> createState() => _ImportServerPageState();
}

class _ImportServerPageState extends State<ImportServerPage> {
  static const _fileService = FileService();

  bool _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    // 未完成即离开：清理已创建的空实例。
    if (!_completed) {
      widget.controller.deleteInstance(widget.instanceId);
    }
    super.dispose();
  }

  Future<void> _run() async {
    // 确保有文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await _showImportPermissionDialog();
      if (go != true) {
        _cancel();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _run();
      return;
    }

    if (!mounted) return;
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.jar', '.phar'],
    );
    if (sourcePath == null) {
      // 用户取消选择，返回根页（dispose 会清理空实例）。
      _cancel();
      return;
    }
    try {
      final dir = await widget.controller.directoryForId(widget.instanceId);
      final savedPath = await _fileService.importFile(sourcePath, dir);
      final jarName = p.basename(savedPath);
      // 导入 .phar 时自动切到 PHP（PocketMine）运行环境，其余按 Java 处理。
      final isPhar = jarName.toLowerCase().endsWith('.phar');
      await widget.controller.updateConfig(
        widget.instanceId,
        selectedJar: jarName,
        runtime: isPhar ? kRuntimePhp : kRuntimeJava,
      );
      _finish();
    } catch (_) {
      _cancel();
    }
  }

  void _finish() {
    _completed = true;
    if (mounted) Navigator.of(context).pop(CreateInstanceResult.done);
  }

  void _cancel() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool?> _showImportPermissionDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('instance.importStoragePermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('instance.titleImportServer'))),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                context.tr('instance.selectJarPrompt'),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
