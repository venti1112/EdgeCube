import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/locale_scope.dart';

class PhotoAsset {
  const PhotoAsset({
    required this.uri,
    required this.name,
    required this.size,
    required this.modified,
    required this.width,
    required this.height,
  });

  final String uri;
  final String name;
  final int size;
  final int modified;
  final int width;
  final int height;

  factory PhotoAsset.fromMap(Map<dynamic, dynamic> map) {
    return PhotoAsset(
      uri: map['uri'] as String,
      name: (map['name'] as String?) ?? 'photo',
      size: (map['size'] as num?)?.toInt() ?? 0,
      modified: (map['modified'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}

class PhotoLibrary {
  static const MethodChannel _channel = MethodChannel(
    'com.venti1112.edgecube/photos',
  );

  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('isGranted') ?? false;
  }

  static Future<bool> request() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('request') ?? false;
  }

  static Future<List<PhotoAsset>> list() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('list') ?? [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(PhotoAsset.fromMap)
        .toList(growable: false);
  }

  static Future<Uint8List> bytes(String uri, {required int maxSize}) async {
    final bytes = await _channel.invokeMethod<Uint8List>('bytes', {
      'uri': uri,
      'maxSize': maxSize,
    });
    if (bytes == null) throw StateError('无法读取图片');
    return bytes;
  }

  /// 读取图片原始字节，不经过任何压缩或缩放。
  static Future<Uint8List> originalBytes(String uri) async {
    final bytes = await _channel.invokeMethod<Uint8List>('originalBytes', {
      'uri': uri,
    });
    if (bytes == null) throw StateError('无法读取图片');
    return bytes;
  }

  static Future<String> copyToCache(PhotoAsset photo) async {
    final path = await _channel.invokeMethod<String>('copyToCache', {
      'uri': photo.uri,
      'name': photo.name,
    });
    if (path == null) throw StateError('无法复制图片');
    return path;
  }
}

/// 打开相册式照片选择器，从系统照片媒体库读取并提供大图预览。
Future<String?> pickPhoto(BuildContext context) async {
  if (!await PhotoLibrary.isGranted()) {
    if (!context.mounted) return null;
    final allowed = await _requestPhotoPermission(context);
    if (!allowed) return null;
  }
  if (!context.mounted) return null;
  final photo = await Navigator.of(context).push<PhotoAsset>(
    MaterialPageRoute(builder: (_) => const _PhotoPickerPage()),
  );
  if (photo == null) return null;
  return PhotoLibrary.copyToCache(photo);
}

Future<bool> _requestPhotoPermission(BuildContext context) async {
  final shouldRequest = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.tr('photoPicker.permissionTitle')),
      content: Text(context.tr('photoPicker.permissionContent')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.tr('photoPicker.allow')),
        ),
      ],
    ),
  );
  if (shouldRequest != true) return false;
  return PhotoLibrary.request();
}

class _PhotoPickerPage extends StatefulWidget {
  const _PhotoPickerPage();

  @override
  State<_PhotoPickerPage> createState() => _PhotoPickerPageState();
}

class _PhotoPickerPageState extends State<_PhotoPickerPage> {
  late final Future<List<PhotoAsset>> _photosFuture = PhotoLibrary.list();

  Future<void> _openPreview(List<PhotoAsset> photos, int index) async {
    final selected = await Navigator.of(context).push<PhotoAsset>(
      MaterialPageRoute(
        builder: (_) => _PhotoPreviewPage(photos: photos, initialIndex: index),
      ),
    );
    if (selected != null && mounted) {
      Navigator.of(context).pop(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(context.tr('photoPicker.selectPhoto')),
      ),
      body: FutureBuilder<List<PhotoAsset>>(
        future: _photosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('photoPicker.loadFailed', {
                    'error': snapshot.error.toString(),
                  }),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          final photos = snapshot.data ?? const <PhotoAsset>[];
          if (photos.isEmpty) {
            return Center(
              child: Text(
                context.tr('photoPicker.noPhotos'),
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }
          return _PhotoGrid(
            photos: photos,
            onSelected: (index) => _openPreview(photos, index),
          );
        },
      ),
    );
  }
}

class _PhotoPreviewPage extends StatefulWidget {
  const _PhotoPreviewPage({required this.photos, required this.initialIndex});

  final List<PhotoAsset> photos;
  final int initialIndex;

  @override
  State<_PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<_PhotoPreviewPage> {
  late final PageController _controller;
  late int _index = widget.initialIndex;

  PhotoAsset get _current => widget.photos[_index];

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.photos.length}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_current),
            child: Text(
              context.tr('photoPicker.use'),
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (_, index) {
              final photo = widget.photos[index];
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: _OriginalBytesImage(
                    key: ValueKey('large-${photo.uri}'),
                    photo: photo,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(top: false, child: _PhotoInfo(photo: _current)),
          ),
        ],
      ),
    );
  }
}

class _PhotoInfo extends StatelessWidget {
  const _PhotoInfo({required this.photo});

  final PhotoAsset photo;

  @override
  Widget build(BuildContext context) {
    final dimensions = photo.width > 0 && photo.height > 0
        ? '${photo.width} x ${photo.height}'
        : context.tr('photoPicker.unknownDimensions');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            photo.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$dimensions  ·  ${_formatBytes(context, photo.size)}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos, required this.onSelected});

  final List<PhotoAsset> photos;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: photos.length,
      itemBuilder: (_, index) {
        final photo = photos[index];
        return GestureDetector(
          onTap: () => onSelected(index),
          child: _PhotoBytesImage(
            key: ValueKey('thumb-${photo.uri}'),
            photo: photo,
            maxSize: 400,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _OriginalBytesImage extends StatelessWidget {
  const _OriginalBytesImage({
    super.key,
    required this.photo,
    required this.fit,
  });

  final PhotoAsset photo;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: PhotoLibrary.originalBytes(photo.uri),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFF151515),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0xFF151515),
            child: Icon(Icons.broken_image_outlined, color: Colors.white54),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: fit,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFF151515),
            child: Icon(Icons.broken_image_outlined, color: Colors.white54),
          ),
        );
      },
    );
  }
}

class _PhotoBytesImage extends StatelessWidget {
  const _PhotoBytesImage({
    super.key,
    required this.photo,
    required this.maxSize,
    required this.fit,
  });

  final PhotoAsset photo;
  final int maxSize;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: PhotoLibrary.bytes(photo.uri, maxSize: maxSize),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFF151515),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0xFF151515),
            child: Icon(Icons.broken_image_outlined, color: Colors.white54),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: fit,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFF151515),
            child: Icon(Icons.broken_image_outlined, color: Colors.white54),
          ),
        );
      },
    );
  }
}

String _formatBytes(BuildContext context, int bytes) {
  if (bytes <= 0) return context.tr('photoPicker.unknownSize');
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(1)} MB';
}
