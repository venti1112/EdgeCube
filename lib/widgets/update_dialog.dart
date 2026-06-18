import 'package:flutter/material.dart';

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
        _error = '下载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最新版本：${widget.info.lastVersion}'),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              _progress != null
                  ? '正在下载… ${(_progress! * 100).toStringAsFixed(0)}%'
                  : '正在下载…',
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
            child: const Text('稍后再说'),
          ),
        if (!_downloading)
          FilledButton(
            onPressed: _startDownload,
            child: const Text('下载并安装'),
          ),
      ],
    );
  }
}
