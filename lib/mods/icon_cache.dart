import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
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

  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'mod_icons'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// 以 URL 的 SHA1 作为缓存文件名。
  String _fileName(String url) =>
      sha1.convert(utf8.encode(url)).toString();

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

      // 磁盘命中
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        _memory[url] = bytes;
        return bytes;
      }

      // 下载
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;

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
  const CachedModIcon({
    super.key,
    this.url,
    this.size = 40,
    this.fallback,
  });

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        _bytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            widget.fallback ?? _defaultFallback(context),
      ),
    );
  }

  Widget _defaultFallback(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.extension, size: widget.size * 0.6),
    );
  }
}
