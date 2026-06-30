import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import '../i18n/locale_scope.dart';
import 'code_find_panel.dart';
import 'editor_language.dart';
import 'file_service.dart';

/// 内置代码编辑器：读取文件 → 编辑 → 保存写回（UTF-8）。
///
/// 基于 [CodeEditor]（re_editor），按文件名扩展名启用 re_highlight
/// 语法高亮。适合编辑 server.properties、eula.txt、各类 yml/json 配置等。二进制或
/// 超大文件不应进入此页（由调用方按扩展名与大小拦截）。
class TextEditorPage extends StatefulWidget {
  const TextEditorPage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  static const _service = FileService();

  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;

  /// 按文件名推断的高亮语言；null 表示纯文本不高亮。
  LanguageResult? _language;

  bool _loading = true;
  bool _saving = false;
  Object? _error;

  /// 是否有未保存修改，通过比较 [_controller.text] 与 [_savedText] 驱动。
  bool _dirty = false;

  /// 上次保存时的文本快照，用于脏检测。
  String _savedText = '';

  /// 撤销/重做可用状态，由 controller 变更驱动。
  bool _canUndo = false;
  bool _canRedo = false;

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
    try {
      final text = await _service.readText(widget.path);
      if (!mounted) return;
      _applyText(text);
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
  /// 空文本走快速路径；非空文本使用 textAsync 将行解析放到后台 isolate，
  /// 避免大文件在主线程卡死 UI。
  Future<void> _applyText(String text) async {
    if (text.isEmpty) {
      // 空文件无需后台解析，直接就绪。
      _savedText = '';
      _controller.addListener(_onChanged);
      setState(() => _loading = false);
      return;
    }
    // textAsync 是 fire-and-forget，通过一次性监听器检测解析完成。
    final completer = Completer<void>();
    void readyListener() {
      if (!completer.isCompleted) completer.complete();
    }
    _controller.addListener(readyListener);
    _controller.textAsync = text;
    await completer.future;
    _controller.removeListener(readyListener);
    if (!mounted) return;
    // 把刚载入的内容设为「已保存」基线，使脏检测从干净状态开始。
    _savedText = _controller.text;
    // 在写入初值之后再监听，避免初始化即标记为已修改。
    _controller.addListener(_onChanged);
    setState(() => _loading = false);
  }

  /// 检测异常是否为 UTF-8 编码错误（文件不是合法 UTF-8 文本）。
  static bool _isEncodingError(Object e) {
    if (e is FileSystemException) return e.osError == null;
    return false;
  }

  /// 以 latin1 强制读取文件内容，用于用户在编码错误提示后选择继续打开。
  Future<void> _forceOpen() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final text = await _service.readTextRaw(widget.path);
      if (!mounted) return;
      _applyText(text);
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
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final text = _controller.text;
      await _service.writeText(widget.path, text);
      if (!mounted) return;
      // 更新「已保存」基线并刷新脏标记。
      _savedText = text;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('textEditor.saved'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('textEditor.saveFailed', {'error': e.toString()}),
          ),
        ),
      );
    }
  }

  /// 弹出三选一对话框：保存、不保存、取消。
  /// 返回 true 表示允许退出，false 表示取消退出。
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('textEditor.saveChangesTitle')),
        content: Text(context.tr('textEditor.saveChangesContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: Text(context.tr('textEditor.discard')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: Text(context.tr('common.save')),
          ),
        ],
      ),
    );
    switch (choice) {
      case 2:
        await _save();
        return !_dirty; // 保存成功则允许退出
      case 0:
        return true; // 不保存，直接退出
      default:
        return false; // 取消退出
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _dirty ? '${widget.name} •' : widget.name,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: context.tr('common.undo'),
              onPressed: _canUndo ? _controller.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: context.tr('common.redo'),
              onPressed: _canRedo ? _controller.redo : null,
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: context.tr('textEditor.find'),
              onPressed: _loading ? null : _findController.findMode,
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
                icon: const Icon(Icons.save_outlined),
                tooltip: context.tr('common.save'),
                onPressed: (_loading || _error != null || !_dirty)
                    ? null
                    : _save,
              ),
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final isEncoding = _isEncodingError(_error!);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('textEditor.cannotOpenFile', {
                  'error': _error.toString(),
                }),
                textAlign: TextAlign.center,
              ),
              if (isEncoding) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _forceOpen,
                  icon: const Icon(Icons.warning_amber),
                  label: Text(context.tr('textEditor.forceOpen')),
                ),
              ],
            ],
          ),
        ),
      );
    }
    // 高亮配色随应用明暗主题切换；root 样式同时提供编辑器底色。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightTheme = isDark ? githubDarkTheme : githubTheme;
    final bgColor =
        highlightTheme['root']?.backgroundColor ??
        Theme.of(context).colorScheme.surface;

    // 构建语法高亮配置：语言名 → CodeHighlightThemeMode。
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
          builder: ({
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
        indicatorBuilder: (context, editingController, chunkController, notifier) {
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
        sperator: Container(
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
