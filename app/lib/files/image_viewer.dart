import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'providers.dart';

/// 图片查看器：把实例目录里的图片下载下来，全屏预览（可捏合缩放 / 拖动）。
///
/// 图片在**服务端机器上**，所以要经 HTTP 下载（`FileTransfer.download`），
/// 拿到字节后用 `Image.memory` 显示。
///
/// 文件页给图片开的「点开就看」这条路：分派优先级是
/// 目录 → 图片 → 可编辑文本 → 什么都不做（见 `file_browser.dart` 的 `onTap`）。
class ImageViewerPage extends ConsumerStatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.instanceId,
    required this.path,
    required this.name,
  });

  final String instanceId;

  /// 相对实例目录的路径（`mods/xxx.png`）。
  final String path;

  final String name;

  @override
  ConsumerState<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<ImageViewerPage> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final transfer = ref.read(fileTransferProvider);
    if (transfer == null) {
      setState(() {
        _loading = false;
        _error = '还没有配置服务器';
      });
      return;
    }
    try {
      final bytes = await transfer.download(widget.instanceId, widget.path);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeFileError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 看图用纯黑底：图片（尤其透明 png）在黑底上看得最清楚
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : Center(
              child: InteractiveViewer(
                maxScale: 8,
                child: Image.memory(
                  _bytes!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  // 字节不是合法图片（下错了 / 文件损坏）不该把页面炸了
                  errorBuilder: (context, error, stack) => const _ErrorView(
                    message: '无法预览这张图片（可能不是图片，或文件已损坏）',
                  ),
                ),
              ),
            ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: Colors.white70,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
