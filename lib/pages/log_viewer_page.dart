import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../i18n/locale_scope.dart';
import '../logging/log_service.dart';
import '../widgets/error_dialog.dart';
import '../widgets/ec_preference.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';

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
    try {
      final file = _files[_selectedIndex];
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: context.tr('logViewer.exportText'),
        ),
      );
      if (mounted) {
        showMiuixSnackbar(context.tr('logViewer.exportSuccess'));
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
    final confirmed = await showMiuixConfirm(
      context,
      title: context.tr('logViewer.clearConfirmTitle'),
      message: context.tr('logViewer.clearConfirmMessage'),
    );
    if (!confirmed || !mounted) return;
    await LogService.instance.clearAllLogs();
    if (!mounted) return;
    showMiuixSnackbar(context.tr('logViewer.clearSuccess'));
    _selectedIndex = 0;
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);

    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('logViewer.title'),
        actions: [
          MiuixIconButton(
            onPressed: _loading ? null : _loadFiles,
            enabled: !_loading,
            child: const MiuixIcon(icon: Icons.refresh),
          ),
          MiuixIconButton(
            onPressed: (_loading || _files.isEmpty || _exporting)
                ? null
                : _exportCurrent,
            enabled: !(_loading || _files.isEmpty || _exporting),
            child: _exporting
                ? const MiuixInfiniteProgressIndicator(size: 20)
                : const MiuixIcon(icon: Icons.share_outlined),
          ),
          MiuixIconButton(
            onPressed: (_loading || _files.isEmpty) ? null : _clearAll,
            enabled: !(_loading || _files.isEmpty),
            child: const MiuixIcon(icon: Icons.delete_sweep_outlined),
          ),
        ],
        showBack: true,
      ),
      content: (padding) => Padding(
        padding: padding,
        child: _files.isEmpty
            ? Center(child: MiuixText(context.tr('logViewer.empty')))
            : Column(
                children: [
                  // 日期选择器
                  MiuixOverlayDropdownPreference(
                    title: context.tr('logViewer.selectDate'),
                    items: [for (final f in _files) _dateLabel(f)],
                    selectedIndex: _selectedIndex,
                    onSelectedIndexChange: (value) {
                      if (value == _selectedIndex) return;
                      setState(() => _selectedIndex = value);
                      _loadContent();
                    },
                  ),
                  const MiuixHorizontalDivider(),
                  // 日志内容展示区
                  Expanded(
                    child: _loading
                        ? Center(
                            child: MiuixText(context.tr('logViewer.loading')),
                          )
                        : _content.isEmpty
                        ? Center(
                            child: MiuixText(context.tr('logViewer.empty')),
                          )
                        : Scrollbar(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                _content,
                                style: theme.textStyles.footnote1.copyWith(
                                  color: theme.colors.onBackground,
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
      ),
    );
  }
}
