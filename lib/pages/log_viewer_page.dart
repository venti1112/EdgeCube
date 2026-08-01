import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../i18n/locale_scope.dart';
import '../logging/log_service.dart';
import '../widgets/error_dialog.dart';

/// 日志查看与导出页面。
///
/// 列出所有按日期命名的日志文件（最新在前），用户可选择某天的日志查看内容，
/// 并通过系统分享面板导出，或一键清除全部日志。
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<File> _files = [];
  int _selectedIndex = 0;
  String _content = '';
  bool _loading = true;
  bool _exporting = false;
  int _loadSeq = 0; // 递增序号，用于丢弃过期的读取响应

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  /// 重新加载日志文件列表并读取当前选中文件内容。
  Future<void> _loadFiles() async {
    if (!mounted) return;
    // 使任何在途的旧读取请求失效
    _loadSeq++;
    setState(() => _loading = true);
    final files = await LogService.instance.getLogFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      if (_files.isNotEmpty) {
        _selectedIndex = _selectedIndex.clamp(0, _files.length - 1);
      } else {
        _selectedIndex = 0;
      }
    });
    await _loadContent();
  }

  /// 读取当前选中日志文件的内容。
  ///
  /// 通过 [_loadSeq] 校验响应是否过期：期间用户切换了日期或刷新了列表，
  /// 则丢弃本次结果，避免旧内容覆盖新选择。
  Future<void> _loadContent() async {
    if (!mounted) return;
    if (_files.isEmpty) {
      setState(() {
        _content = '';
        _loading = false;
      });
      return;
    }
    final seq = _loadSeq;
    setState(() => _loading = true);
    try {
      final content = await LogService.instance.readLogFile(
        _files[_selectedIndex],
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _content = '';
        _loading = false;
      });
    }
  }

  /// 从文件名中提取日期显示文本，如 `log_2026-08-01.txt` → `2026-08-01`。
  String _dateLabel(File file) {
    final name = p.basename(file.path);
    // log_YYYY-MM-DD.txt → YYYY-MM-DD
    if (name.startsWith('log_') && name.endsWith('.txt')) {
      return name.substring(4, name.length - 4);
    }
    return name;
  }

  /// 导出当前选中的日志文件（通过系统分享面板）。
  Future<void> _exportCurrent() async {
    if (_files.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = _files[_selectedIndex];
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: context.tr('logViewer.exportText'),
        ),
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.tr('logViewer.exportSuccess'))),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('logViewer.exportFailed', {'error': e.toString()}),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 清除全部日志文件（带确认对话框）。
  Future<void> _clearAll() async {
    if (_files.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('logViewer.clearConfirmTitle')),
        content: Text(ctx.tr('logViewer.clearConfirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await LogService.instance.clearAllLogs();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(context.tr('logViewer.clearSuccess'))),
    );
    _selectedIndex = 0;
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('logViewer.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('logViewer.refresh'),
            onPressed: _loading ? null : _loadFiles,
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
            tooltip: context.tr('logViewer.export'),
            onPressed: (_loading || _files.isEmpty || _exporting)
                ? null
                : _exportCurrent,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: context.tr('logViewer.clearAll'),
            onPressed: (_loading || _files.isEmpty) ? null : _clearAll,
          ),
        ],
      ),
      body: _files.isEmpty
          ? Center(child: Text(context.tr('logViewer.empty')))
          : Column(
              children: [
                // 日期选择器
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        context.tr('logViewer.selectDate'),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedIndex,
                          items: [
                            for (var i = 0; i < _files.length; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text(_dateLabel(_files[i])),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null || value == _selectedIndex) {
                              return;
                            }
                            setState(() => _selectedIndex = value);
                            _loadContent();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 日志内容展示区
                Expanded(
                  child: _loading
                      ? Center(
                          child: Text(context.tr('logViewer.loading')),
                        )
                      : _content.isEmpty
                          ? Center(child: Text(context.tr('logViewer.empty')))
                          : Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  _content,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontFamilyFallback: const [
                                      'Courier',
                                      'Menlo',
                                    ],
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                ),
              ],
            ),
    );
  }
}
