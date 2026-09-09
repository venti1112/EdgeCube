import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'code_find_panel.dart';
import 'editor_language.dart';

/// 内置代码编辑器:经 daemon API 读取远程文件 → 编辑 → 保存写回(UTF-8)。
///
/// 基于 [CodeEditor](re_editor),按文件名扩展名启用 re_highlight 语法高亮。
/// 适合编辑 server.properties、eula.txt、各类 yml/json 配置等。二进制或
/// 超大文件不应进入此页(由调用方按扩展名与大小拦截)。
class TextEditorPage extends ConsumerStatefulWidget {
  const TextEditorPage({
    super.key,
    required this.instanceId,
    required this.path,
    required this.name,
  });

  /// 实例 ID(沙箱 cwd 根)。
  final String instanceId;

  /// 目标文件路径(相对实例 cwd)。
  final String path;

  /// 文件名(按扩展名推断高亮语言)。
  final String name;

  @override
  ConsumerState<TextEditorPage> createState() => _TextEditorPageState();
}

/// 标记读取失败原因为「文件不是合法 UTF-8 文本」的哨兵错误。
class _EncodingError implements Exception {
  const _EncodingError();
}

class _TextEditorPageState extends ConsumerState<TextEditorPage> {
  /// 可安全进入内置编辑器的最大文件大小(与后端 write 上限同量级)。
  static const _openLimitBytes = 16 * 1024 * 1024;

  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;

  /// 按文件名推断的高亮语言;null 表示纯文本不高亮。
  LanguageResult? _language;

  bool _loading = true;
  bool _saving = false;
  Object? _error;

  /// 是否有未保存修改,通过比较 [_controller.text] 与 [_savedText] 驱动。
  bool _dirty = false;

  /// 上次保存时的文本快照,用于脏检测。
  String _savedText = '';

  /// 撤销/重做可用状态,由 controller 变更驱动。
  bool _canUndo = false;
  bool _canRedo = false;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _findController = CodeFindController(_controller);
    _language = languageForFileName(widget.name);
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _findController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      if (!mounted) return;
      setState(() {
        _error = '未连接服务器';
        _loading = false;
      });
      return;
    }
    try {
      final resp = await client
          .getFilesApi()
          .downloadFile(instanceId: widget.instanceId, path: widget.path);
      if (!mounted) return;
      final bytes = resp.data ?? Uint8List(0);
      if (bytes.length > _openLimitBytes) {
        setState(() {
          _error = '文件过大(${bytes.length} 字节),无法在编辑器中打开';
          _loading = false;
        });
        return;
      }
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw const _EncodingError();
      }
      await _applyText(text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// 将文本写入编辑器 controller 并结束 loading 状态。
  ///
  /// 空文本走快速路径;非空文本使用 textAsync 将行解析放到后台 isolate,
  /// 避免大文件在主线程卡死 UI。
  Future<void> _applyText(String text) async {
    if (text.isEmpty) {
      // 空文件无需后台解析,直接就绪。
      _savedText = '';
      _controller.addListener(_onChanged);
      setState(() => _loading = false);
      return;
    }
    // textAsync 是 fire-and-forget,通过一次性监听器检测解析完成。
    final completer = Completer<void>();
    void readyListener() {
      if (!completer.isCompleted) completer.complete();
    }

    _controller.addListener(readyListener);
    _controller.textAsync = text;
    await completer.future;
    _controller.removeListener(readyListener);
    if (!mounted) return;
    // 把刚载入的内容设为「已保存」基线,使脏检测从干净状态开始。
    _savedText = _controller.text;
    // 在写入初值之后再监听,避免初始化即标记为已修改。
    _controller.addListener(_onChanged);
    setState(() => _loading = false);
  }

  /// 以 latin1 强制读取文件内容,用于用户在编码错误提示后选择继续打开。
  Future<void> _forceOpen() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final resp = await client
          .getFilesApi()
          .downloadFile(instanceId: widget.instanceId, path: widget.path);
      if (!mounted) return;
      final bytes = resp.data ?? Uint8List(0);
      await _applyText(String.fromCharCodes(bytes));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onChanged() {
    bool needsRebuild = false;
    final isDirty = _controller.text != _savedText;
    if (isDirty != _dirty) {
      _dirty = isDirty;
      needsRebuild = true;
    }
    if (_controller.canUndo != _canUndo) {
      _canUndo = _controller.canUndo;
      needsRebuild = true;
    }
    if (_controller.canRedo != _canRedo) {
      _canRedo = _controller.canRedo;
      needsRebuild = true;
    }
    if (needsRebuild) setState(() {});
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null) return;
    setState(() => _saving = true);
    try {
      final text = _controller.text;
      await client.getFilesApi().writeFile(
            fsWriteRequest: FsWriteRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = widget.path
              ..content = text),
          );
      if (!mounted) return;
      // 更新「已保存」基线并刷新脏标记。
      _savedText = text;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSaveError(e);
    }
  }

  void _showSaveError(Object e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('保存失败:${apiErrorMessage(e)}')));
  }

  /// 弹出三选一对话框:保存、不保存、取消。
  /// 返回 true 表示允许退出,false 表示取消退出。
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存更改?'),
        content: const Text('此文件有未保存的修改,是否保存?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('不保存'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    switch (choice) {
      case 2:
        await _save();
        return !_dirty; // 保存成功则允许退出
      case 0:
        return true; // 不保存,直接退出
      default:
        return false; // 取消退出
    }
  }

  @override
  Widget build(BuildContext context) {
    // 应用主题由 material_ui 的 MaterialApp 通过其自身继承链注入;
    // 本页组件来自 flutter/material,flutter 的 Theme.of 取不到该主题,
    // 会回落浅色默认主题导致深色模式失效。故按外层 material_ui 主题的
    // 亮度派生一个 flutter Theme 包裹整页,保证 flutter 组件主题一致。
    final muiTheme = mui.Theme.of(context);
    final isDark = muiTheme.brightness == Brightness.dark;
    final flutterData = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: muiTheme.colorScheme.primary,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return Theme(
      data: flutterData,
      child: PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_dirty ? '${widget.name} •' : widget.name),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              tooltip: '撤销',
              onPressed: _canUndo ? _controller.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: _canRedo ? _controller.redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: '查找/替换',
              onPressed: _loading ? null : _findController.findMode,
              icon: const Icon(Icons.search),
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: '保存',
                onPressed: (_loading || _error != null || !_dirty)
                    ? null
                    : _save,
                icon: const Icon(Icons.save_outlined),
              ),
          ],
        ),
        body: _buildBody(context),
      ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final isEncoding = _error is _EncodingError;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEncoding
                    ? '此文件不是合法的 UTF-8 文本,可能包含二进制内容'
                    : '无法打开文件:$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              if (isEncoding) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _forceOpen,
                  icon: const Icon(Icons.warning_amber),
                  label: const Text('强制打开(以 latin1 读取)'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    // 高亮配色随应用明暗主题切换;root 样式同时提供编辑器底色。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightTheme = isDark ? githubDarkTheme : githubTheme;
    final bgColor =
        highlightTheme['root']?.backgroundColor ??
        Theme.of(context).colorScheme.surface;

    // 构建语法高亮配置:语言名 → CodeHighlightThemeMode。
    final lang = _language;
    final codeTheme = lang != null
        ? CodeHighlightTheme(
            languages: {lang.name: CodeHighlightThemeMode(mode: lang.mode)},
            theme: highlightTheme,
          )
        : CodeHighlightTheme(languages: const {}, theme: highlightTheme);

    return ColoredBox(
      color: bgColor,
      child: CodeEditor(
        controller: _controller,
        findController: _findController,
        findBuilder: (context, controller, readOnly) =>
            CodeFindPanelView(controller: controller, readOnly: readOnly),
        toolbarController: MobileSelectionToolbarController(
          builder:
              ({
                required context,
                required anchors,
                required controller,
                required onDismiss,
                required onRefresh,
              }) {
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: anchors,
                  buttonItems: [
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.cut,
                      onPressed: () {
                        controller.cut();
                        onDismiss();
                      },
                    ),
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.copy,
                      onPressed: () {
                        controller.copy();
                        onDismiss();
                      },
                    ),
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.paste,
                      onPressed: () {
                        controller.paste();
                        onDismiss();
                      },
                    ),
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.selectAll,
                      onPressed: () {
                        controller.selectAll();
                        onRefresh();
                      },
                    ),
                  ],
                );
              },
        ),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            },
        leadingDivider: Container(
          width: 1,
          color: Theme.of(context).dividerColor,
        ),
        style: CodeEditorStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontHeight: 1.4,
          codeTheme: codeTheme,
        ),
        wordWrap: false,
      ),
    );
  }
}