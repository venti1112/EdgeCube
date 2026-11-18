import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 模组图标缓存（内存 + 磁盘）。
///
/// 避免每次显示图标都重新下载，触发 Modrinth CDN 限流。
/// - 内存缓存：同一会话内不重复读磁盘
/// - 磁盘缓存：跨会话持久化，以 URL 的 SHA1 作为文件名
/// - 去重：同一 URL 的并发请求只发一次
class ModIconCache {
  ModIconCache._();
  static final ModIconCache instance = ModIconCache._();

  /// 内存缓存：URL → 图片字节
  final Map<String, Uint8List> _memory = {};

  /// 进行中的下载：URL → Future，避免并发重复下载
  final Map<String, Future<Uint8List?>> _pending = {};

  /// 同时进行的网络下载上限。
  ///
  /// 列表快速滑动时「新出现的图标」会集中发起请求，若不限流，一次滑动就能
  /// 同时开几十上百个 HTTP 连接：连接建立、TLS 握手、回调切回主 isolate 都要
  /// 抢 CPU，正是列表滑动掉帧的常见来源（也更容易触发 Modrinth CDN 限流）。
  /// 排队执行后总耗时接近，但每帧的主线程压力小得多。
  static const _maxConcurrentDownloads = 4;
  int _activeDownloads = 0;
  final List<Completer<void>> _downloadQueue = [];

  Future<void> _acquireDownloadSlot() async {
    if (_activeDownloads < _maxConcurrentDownloads) {
      _activeDownloads++;
      return;
    }
    final waiter = Completer<void>();
    _downloadQueue.add(waiter);
    await waiter.future;
  }

  void _releaseDownloadSlot() {
    if (_downloadQueue.isEmpty) {
      _activeDownloads--;
      return;
    }
    // 直接把名额移交给队首等待者，不必先减后加。
    _downloadQueue.removeAt(0).complete();
  }

  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'mod_icons'));
    // 用异步版本：磁盘探测/建目录同样会阻塞主线程，页面初始化时成批出现
    // 模组卡片会因此掉帧。
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// 以 URL 的 SHA1 作为缓存文件名。
  String _fileName(String url) => sha1.convert(utf8.encode(url)).toString();

  /// 获取图标字节。优先从内存/磁盘读取，不存在则下载并缓存。
  Future<Uint8List?> get(String url) async {
    // 1. 内存命中
    final mem = _memory[url];
    if (mem != null) return mem;

    // 2. 已有相同 URL 的下载在进行中 → 复用
    final pending = _pending[url];
    if (pending != null) return pending;

    // 3. 发起新的获取
    final future = _fetch(url);
    _pending[url] = future;
    try {
      return await future;
    } finally {
      _pending.remove(url);
    }
  }

  Future<Uint8List?> _fetch(String url) async {
    try {
      final dir = await _getCacheDir();
      final file = File(p.join(dir.path, _fileName(url)));

      // 磁盘命中。注意这里必须用异步 IO：列表滚动时每个新出现的图标都会走到
      // 这里，同步读盘会直接卡住 UI 线程。
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _memory[url] = bytes;
        return bytes;
      }

      // 下载（限流，避免一次滑动派出上百个并发请求）
      await _acquireDownloadSlot();
      final Uint8List bytes;
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) return null;
        bytes = response.bodyBytes;
      } finally {
        _releaseDownloadSlot();
      }

      // 写入磁盘
      await file.writeAsBytes(bytes);
      _memory[url] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 清除内存缓存（磁盘缓存保留）。
  void clearMemory() => _memory.clear();
}

/// 带缓存的模组图标组件。
///
/// 优先使用 [ModIconCache] 读取已缓存的图标字节，
/// 加载中/失败时显示 [fallback]。
class CachedModIcon extends StatefulWidget {
  const CachedModIcon({super.key, this.url, this.size = 40, this.fallback});

  final String? url;
  final double size;
  final Widget? fallback;

  @override
  State<CachedModIcon> createState() => _CachedModIconState();
}

class _CachedModIconState extends State<CachedModIcon> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedModIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _loaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final bytes = await ModIconCache.instance.get(url);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = widget.url != null && widget.url!.isNotEmpty;

    // 无 URL 或加载失败 → 回退
    if (!hasUrl || (_loaded && _bytes == null)) {
      return widget.fallback ?? _defaultFallback(context);
    }

    // 加载中 → 占位
    if (!_loaded || _bytes == null) {
      return _defaultFallback(context);
    }

    // 按显示尺寸解码：Modrinth 的图标常见 256/512px，而这里只画 40px。
    // 全尺寸解码 + 上传大纹理是列表滑动掉帧的常见来源，故按物理像素
    // （逻辑尺寸 × devicePixelRatio）限制解码大小。
    //
    // 用 ResizeImagePolicy.fit 而不是 Image.memory 的 cacheWidth/cacheHeight：
    // 后者同时给宽高会按 BoxFit.fill 拉伸（非正方形图标会变形），fit 策略则
    // 在保留原图宽高比的前提下缩到目标框内，再交给 BoxFit.cover 裁剪。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeSize = (widget.size * dpr).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image(
        image: ResizeImage(
          MemoryImage(_bytes!),
          width: decodeSize,
          height: decodeSize,
          policy: ResizeImagePolicy.fit,
        ),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => widget.fallback ?? _defaultFallback(context),
      ),
    );
  }

  Widget _defaultFallback(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: MiuixTheme.of(context).colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.extension, size: widget.size * 0.6),
    );
  }
}
