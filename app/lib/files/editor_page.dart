import 'dart:async';

import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import '../connection/client.dart';
import '../settings/appearance.dart';
import 'code_find_panel.dart';
import 'dialogs.dart';
import 'editor_language.dart';
import 'models.dart';
import 'providers.dart';

/// 编辑器字号与行高。
const double _kFontSize = 13;
const double _kLineHeight = 1.4;

/// 文本超过这个长度才把「分行」丢到后台 isolate（见 `_applyText`）。
///
/// 几 KB 的配置文件同步解析就是一瞬间，为它付一次 isolate 往返反而更慢；
/// daemon 那边文本上限 4MB（`text_max_bytes`），那种量级才值得异步。
const int _kAsyncParseThreshold = 64 * 1024;

/// 内置文本编辑器：读文件 → 编辑 → 保存写回（UTF-8）。
///
/// 交互：标题带未保存标记 `名字 •`，右上角撤销 / 重做 /
/// 查找 / 保存；非 UTF-8 文件报错并提供「强制打开」（按 latin1 强读）；
/// 有改动时返回要过「不保存 / 取消 / 保存」三选一。编辑器本体是
/// `re_editor` + `re_highlight`（按扩展名挑语言，github / github-dark 配色），
/// 查找替换面板见 `code_find_panel.dart`。
///
/// 几处刻意的选择：
///
/// * **字体取「控制台字体」设置**，没设时用 `monospace`
///   （V2 只有这一个等宽字体设置项，编辑器跟着它走）。
/// * **小文件同步分行**（见 `_kAsyncParseThreshold`），大文件才丢到后台解析。
/// * 文案写死中文（V2 这套前端还没有 i18n）。
class TextEditorPage extends ConsumerStatefulWidget {
  const TextEditorPage({
    super.key,
    required this.instanceId,
    required this.path,
    required this.name,
  });

  final String instanceId;

  /// 相对实例目录的路径（`server.properties`、`config/paper.yml`）。
  final String path;

  /// 文件名（标题用，也用来推断高亮语言）。
  final String name;

  @override
  ConsumerState<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends ConsumerState<TextEditorPage> {
  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;

  /// 按文件名推断的高亮语言；null 表示纯文本，不高亮。
  LanguageResult? _language;

  /// 上次保存（或打开）时的文本快照，用来判断「有未保存的改动」。
  String _savedText = '';
  bool _dirty = false;

  bool _loading = true;
  bool _saving = false;

  /// 打开失败的原因（已翻成中文）；非空时整页显示错误态。
  String? _error;

  /// 上面这个错误是不是「不是 UTF-8」——只有这种才给「强制打开」。
  bool _notUtf8 = false;

  /// 撤销/重做可用状态，由 controller 变更驱动。
  bool _canUndo = false;
  bool _canRedo = false;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _findController = CodeFindController(_controller);
    _language = languageForFileName(widget.name);
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _findController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── 读 / 写 ──────────────────────────────────────────────────────────────

  Future<void> _load({bool raw = false}) async {
    final api = ref.read(fileApiProvider);
    if (api == null) {
      setState(() {
        _error = '连接已断开';
        _notUtf8 = false;
        _loading = false;
      });
      return;
    }
    try {
      final file = await api.readText(
        widget.instanceId,
        path: widget.path,
        raw: raw,
      );
      if (!mounted) return;
      await _applyText(file.content);
    } on DaemonException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeFileError(error);
        _notUtf8 = error.code == 'file_not_utf8';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _notUtf8 = false;
        _loading = false;
      });
    }
  }

  /// 把文本铺进编辑器，并以它为「已保存」基线（打开后不该是脏的）。
  Future<void> _applyText(String text) async {
    if (text.length < _kAsyncParseThreshold) {
      _controller.text = text;
    } else {
      // textAsync 是 fire-and-forget，靠一次性监听器等它铺完。
      final ready = Completer<void>();
      void onReady() {
        if (!ready.isCompleted) ready.complete();
      }

      _controller.addListener(onReady);
      _controller.textAsync = text;
      await ready.future;
      _controller.removeListener(onReady);
    }
    if (!mounted) return;
    // 基线从 controller 读：分行会把 CRLF 归一成 LF，与磁盘原文未必逐字相同。
    _savedText = _controller.text;
    // 铺完初值再监听，免得开局就标记成已修改。
    _controller.addListener(_onChanged);
    setState(() {
      _error = null;
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final api = ref.read(fileApiProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      final text = _controller.text;
      await api.writeText(
        widget.instanceId,
        path: widget.path,
        content: text,
      );
      if (!mounted) return;
      _savedText = text;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      showSnack(context, '已保存');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showErrorDialog(context, '保存失败：${describeFileError(error)}');
    }
  }

  void _onChanged() {
    var rebuild = false;
    final dirty = _controller.text != _savedText;
    if (dirty != _dirty) {
      _dirty = dirty;
      rebuild = true;
    }
    if (_controller.canUndo != _canUndo) {
      _canUndo = _controller.canUndo;
      rebuild = true;
    }
    if (_controller.canRedo != _canRedo) {
      _canRedo = _controller.canRedo;
      rebuild = true;
    }
    if (rebuild) _requestRebuild();
  }

  /// 请求重建，躲开「正在 build / 已经 unmount」这两种不能 setState 的时机。
  ///
  /// re_editor 挂载和销毁 `CodeEditor` 时会换掉 controller 的 delegate 并顺带
  /// 通知一次（见其 `_CodeEditorState.initState` / `dispose`），那时我们这边正在
  /// build（或元素已经 deactivate），直接 setState 会撞断言。推到帧尾重建即可。
  void _requestRebuild() {
    if (!mounted) return;
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// 三选一：不保存 / 取消 / 保存。返回 true 表示可以退出。
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('文件有未保存的更改。'),
        actions: [
          TextButton(
            key: const Key('editor_discard'),
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('不保存'),
          ),
          TextButton(
            key: const Key('editor_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(1),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('editor_save_then_exit'),
            onPressed: () => Navigator.of(dialogContext).pop(2),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (choice == 2) {
      await _save();
      return !_dirty; // 保存失败就别退
    }
    return choice == 0;
  }

  // ── 界面 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canEdit = !_loading && _error == null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmDiscard();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: Text(_dirty ? '${widget.name} •' : widget.name),
          actions: [
            IconButton(
              key: const Key('editor_undo'),
              tooltip: '撤销',
              icon: const Icon(Icons.undo),
              onPressed: _canUndo ? _controller.undo : null,
            ),
            IconButton(
              key: const Key('editor_redo'),
              tooltip: '重做',
              icon: const Icon(Icons.redo),
              onPressed: _canRedo ? _controller.redo : null,
            ),
            IconButton(
              key: const Key('editor_find'),
              tooltip: '查找',
              icon: const Icon(Icons.search),
              onPressed: canEdit ? _findController.findMode : null,
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            else
              IconButton(
                key: const Key('editor_save'),
                tooltip: '保存',
                icon: const Icon(Icons.save_outlined),
                onPressed: canEdit && _dirty ? _save : null,
              ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) return _errorBody(error);
    // 高亮配色随应用明暗主题切换；root 样式同时提供编辑器底色。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightTheme = isDark ? githubDarkTheme : githubTheme;
    final bgColor =
        highlightTheme['root']?.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    // 编辑器等宽字体取「控制台字体」设置（应用里唯一那个等宽字体选项）
    final editorFont = ref.watch(consoleFontFamilyProvider) ?? 'monospace';

    // 认不出扩展名就整个不给 codeTheme：空的语言表会让 re_editor 的高亮引擎
    // 在 isolate 里 reduce 空列表而抛异常（.txt / .log 这类文件一直在踩）。
    final lang = _language;
    final codeTheme = lang == null
        ? null
        : CodeHighlightTheme(
            languages: {lang.name: CodeHighlightThemeMode(mode: lang.mode)},
            theme: highlightTheme,
          );

    return ColoredBox(
      color: bgColor,
      // re_editor 内部 import 的是 `package:flutter/material.dart`，属于
      // AGENTS.md 说的「仍依赖内建 Material 的第三方子树」——用桥接把
      // Theme / Localizations 递进去，否则正文颜色、光标与选区都取不到应用主题。
      // ignore: deprecated_member_use
      child: MaterialUiCompatibilityBridge(
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
            fontFamily: editorFont,
            fontSize: _kFontSize,
            fontHeight: _kLineHeight,
            codeTheme: codeTheme,
          ),
          wordWrap: false,
        ),
      ),
    );
  }

  Widget _errorBody(String error) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // 编码错误才提「不是 UTF-8」；其它错误（不存在、过大…）用中性说法
              _notUtf8 ? '无法打开该文件（可能不是 UTF-8 文本）：\n$error' : '无法打开该文件：\n$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('editor_close_error'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            if (_notUtf8) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('editor_force_open'),
                onPressed: () => unawaited(_load(raw: true)),
                icon: const Icon(Icons.warning_amber),
                label: const Text('强制打开'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
