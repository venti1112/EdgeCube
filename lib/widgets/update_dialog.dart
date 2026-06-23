import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import '../online/update_service.dart';

/// 更新提示对话框：展示新版本号，确认后下载 APK 并触发安装。
///
/// 供「关于」页手动检查更新与启动时后台检查更新共用。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double? _progress; // 0.0–1.0，null 表示未知总大小
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
    });
    try {
      final apkPath = await UpdateService.downloadApk(
        widget.info.downloadLink,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;
      // 下载完成，触发系统安装界面。
      await UpdateService.installApk(apkPath);
      // 安装界面弹出后关闭对话框。
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = context.tr('update.downloadFailed', {'error': '$e'});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(context.tr('update.newVersionFound')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('update.latestVersion', {
              'version': widget.info.lastVersion,
            }),
          ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              _progress != null
                  ? context.tr('update.downloadingProgress', {
                      'progress': (_progress! * 100).toStringAsFixed(0),
                    })
                  : context.tr('update.downloading'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('update.later')),
          ),
        if (!_downloading)
          FilledButton(
            onPressed: _startDownload,
            child: Text(context.tr('update.downloadAndInstall')),
          ),
      ],
    );
  }
}
