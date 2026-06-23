import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import 'file_service.dart';

/// 内置纯文本编辑器：读取文件 → 编辑 → 保存写回（UTF-8）。
///
/// 适合编辑 server.properties、eula.txt、各类 yml/json 配置等。二进制或超大文件
/// 不应进入此页（由调用方按扩展名与大小拦截）。
class TextEditorPage extends StatefulWidget {
  const TextEditorPage({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  static const _service = FileService();

  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  Object? _error;

  /// 上次加载或保存时的文本快照，用于与当前文本对比判断是否有实际修改。
  String _savedText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await _service.readText(widget.path);
      if (!mounted) return;
      _controller.text = text;
      _savedText = text;
      // 在写入初值之后再监听，避免初始化即标记为已修改。
      _controller.addListener(_onChanged);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onChanged() {
    final isDirty = _controller.text != _savedText;
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await _service.writeText(widget.path, _controller.text);
      if (!mounted) return;
      _savedText = _controller.text;
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('textEditor.cannotOpenFile', {
              'error': _error.toString(),
            }),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.4,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
      ),
    );
  }
}
