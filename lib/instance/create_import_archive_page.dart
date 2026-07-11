import 'package:flutter/material.dart';

import '../files/archive_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import 'create_instance_page.dart';
import 'instance_controller.dart';
import 'progress_steps.dart';

/// 「导入压缩包」独立页：选择本地压缩包并解压到已创建的空实例目录。
///
/// 实例由上一页（向导根页）创建并通过 [instanceId] 传入。本页两个阶段同处一页：
/// 先选文件（转圈），再解压（进度）。成功后 `pop(CreateInstanceResult.done)`；用户
/// 取消选择或解压失败则 `pop()` 返回根页。未完成即离开时，[dispose] 清理这个空实例。
class ImportArchivePage extends StatefulWidget {
  const ImportArchivePage({
    super.key,
    required this.controller,
    required this.instanceId,
  });

  final InstanceController controller;
  final String instanceId;

  @override
  State<ImportArchivePage> createState() => _ImportArchivePageState();
}

class _ImportArchivePageState extends State<ImportArchivePage> {
  bool _completed = false;
  bool _extracting = false;
  double? _extractProgress;
  String? _extractError;

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
      // 与原生 ArchiveExtractor 支持的格式保持一致。
      allowedExtensions: const [
        '.zip',
        '.tar',
        '.tar.gz',
        '.tgz',
        '.tar.xz',
        '.txz',
        '.tar.bz2',
        '.tbz2',
        '.tar.zst',
        '.tzst',
        '.tar.lz4',
        '.7z',
      ],
    );
    if (sourcePath == null) {
      _cancel();
      return;
    }

    setState(() {
      _extracting = true;
      _extractError = null;
      _extractProgress = null;
    });

    try {
      final dir = await widget.controller.directoryForId(widget.instanceId);
      await ArchiveService.extractWithProgress(
        sourcePath,
        dir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _extractProgress = total > 0 ? current / total : null;
          });
        },
      );
      _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _extractProgress = null;
        _extractError = context.tr('instance.extractArchiveFailed', {
          'error': '$e',
        });
      });
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
    // 解压中或出错：展示解压进度/错误；否则（仍在选文件）展示转圈。
    final showExtract = _extracting || _extractError != null;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('instance.titleImportArchive'))),
      body: SafeArea(
        child: showExtract
            ? ExtractingArchiveStep(
                extracting: _extracting,
                progress: _extractProgress,
                error: _extractError,
                onCancel: _cancel,
                onReselect: _cancel,
              )
            : Center(
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
