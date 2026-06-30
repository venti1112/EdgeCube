import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/config_store.dart';
import '../files/storage_permission.dart';
import '../i18n/locale_scope.dart';
import '../i18n/translations.dart';
import '../instance/instance_store.dart';
import '../mods/icon_cache.dart';

/// 存储空间管理页：展示设备总空间与本程序各部分的占用。
///
/// 顶部是一个大占用条，按比例显示各部分的色块；
/// 下方是各部分的明细列表，支持清理缓存。
class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  // 设备空间
  int _totalBytes = 0;
  int _availableBytes = 0;

  // 各部分大小
  int _cacheSize = 0;
  int _instancesSize = 0;
  int _runtimeSize = 0;
  int _appDataSize = 0;
  int _appSize = 0;

  bool _loading = true;
  bool _calculating = true;
  bool _clearing = false;

  // 各部分目录路径（用于显示）
  String _cachePath = '';
  String _instancesPath = '';
  String _runtimePath = '';
  String _appDataPath = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _calculating = true;
    });

    // 获取各目录路径
    final cacheDir = await getTemporaryDirectory();
    final supportDir = await getApplicationSupportDirectory();
    final docsDir = await getApplicationDocumentsDirectory();
    final instancesDir = await defaultInstancesRoot();
    final runtimeDir = Directory(p.join(supportDir.path, 'runtimes'));
    final configDir = await ConfigStore.configDir();

    _cachePath = cacheDir.path;
    _instancesPath = instancesDir.path;
    _runtimePath = runtimeDir.path;
    _appDataPath = docsDir.path;

    // 获取设备总空间（使用外部存储根目录或应用目录）
    String? statPath;
    if (Platform.isAndroid) {
      statPath = await StoragePermission.externalStorageRoot();
    }
    statPath ??= docsDir.path;

    final stats = await StoragePermission.getStorageStats(statPath);
    if (stats != null) {
      _totalBytes = stats.totalBytes;
      _availableBytes = stats.availableBytes;
    }

    // 获取程序本体大小（APK + native 库）
    final appSize = await StoragePermission.getAppSize();
    if (appSize != null) {
      _appSize = appSize.totalSize;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // 并行计算各部分大小（在 isolate 中执行避免卡 UI）
    final futures = await Future.wait([
      compute(_calcDirSize, cacheDir.path),
      compute(_calcDirSize, instancesDir.path),
      compute(_calcDirSize, runtimeDir.path),
      // 程序数据 = config 目录（排除 instances 和 runtime，它们已单独计算）
      compute(_calcDirSize, configDir.path),
    ]);

    if (!mounted) return;
    setState(() {
      _cacheSize = futures[0];
      _instancesSize = futures[1];
      _runtimeSize = futures[2];
      _appDataSize = futures[3];
      _calculating = false;
    });
  }

  /// 清理缓存目录。
  Future<void> _clearCache() async {
    final tr = LocaleScope.of(context).translations;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('storage.clearCacheTitle')),
        content: Text(tr.get('storage.clearCacheConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('storage.clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearing = true);
    try {
      final cacheDir = await getTemporaryDirectory();
      await _deleteDirContents(cacheDir);
      // 清除图标内存缓存
      ModIconCache.instance.clearMemory();
      if (!mounted) return;
      setState(() {
        _cacheSize = 0;
        _clearing = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(tr.get('storage.clearCacheSuccess')),
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _clearing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(tr.get('storage.clearFailed', {'error': '$e'})),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = LocaleScope.of(context).translations;
    return Scaffold(
      appBar: AppBar(title: Text(tr.get('storage.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildUsageBar(theme, tr),
                  const SizedBox(height: 24),
                  _buildSectionHeader(theme, tr.get('storage.breakdown')),
                  _buildSectionItem(
                    theme,
                    tr,
                    icon: Icons.cloud_outlined,
                    color: const Color(0xFF42A5F5),
                    label: tr.get('storage.cache'),
                    size: _cacheSize,
                    path: _cachePath,
                    actionText: tr.get('storage.clear'),
                    onAction: _clearing ? null : _clearCache,
                    actionInProgress: _clearing,
                  ),
                  _buildSectionItem(
                    theme,
                    tr,
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF66BB6A),
                    label: tr.get('storage.instances'),
                    size: _instancesSize,
                    path: _instancesPath,
                  ),
                  _buildSectionItem(
                    theme,
                    tr,
                    icon: Icons.memory,
                    color: const Color(0xFFFF7043),
                    label: tr.get('storage.runtime'),
                    size: _runtimeSize,
                    path: _runtimePath,
                  ),
                  _buildSectionItem(
                    theme,
                    tr,
                    icon: Icons.folder_outlined,
                    color: const Color(0xFFAB47BC),
                    label: tr.get('storage.appData'),
                    size: _appDataSize,
                    path: _appDataPath,
                  ),
                  _buildSectionItem(
                    theme,
                    tr,
                    icon: Icons.apps,
                    color: const Color(0xFF26A69A),
                    label: tr.get('storage.app'),
                    size: _appSize,
                    path: '',
                  ),
                  const SizedBox(height: 16),
                  _buildDeviceInfo(theme, tr),
                ],
              ),
            ),
    );
  }

  /// 顶部大占用条：显示设备总空间和本程序各部分的占比。
  Widget _buildUsageBar(ThemeData theme, Translations tr) {
    final appTotal =
        _cacheSize + _instancesSize + _runtimeSize + _appDataSize + _appSize;
    final usedBytes = _totalBytes - _availableBytes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.get('storage.deviceStorage'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            // 占用条
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 24,
                child: Row(children: _buildBarSegments(appTotal, usedBytes)),
              ),
            ),
            const SizedBox(height: 12),
            // 总计文字
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _calculating
                      ? tr.get('storage.appUsed', {
                          'used': tr.get('storage.calculating'),
                        })
                      : tr.get('storage.appUsed', {
                          'used': _formatSize(appTotal),
                        }),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  tr.get('storage.totalSpace', {
                    'total': _formatSize(_totalBytes),
                  }),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr.get('storage.availableSpace', {
                'available': _formatSize(_availableBytes),
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建占用条的分段色块。
  List<Widget> _buildBarSegments(int appTotal, int usedBytes) {
    if (_totalBytes == 0 || _calculating) {
      return [Expanded(child: Container(color: Colors.grey.shade300))];
    }

    final segments = <Widget>[];
    final colors = [
      const Color(0xFF42A5F5), // 缓存-蓝
      const Color(0xFF66BB6A), // 实例-绿
      const Color(0xFFFF7043), // 运行环境-橙
      const Color(0xFFAB47BC), // 程序数据-紫
      const Color(0xFF26A69A), // 程序本体-青
    ];
    final sizes = [
      _cacheSize,
      _instancesSize,
      _runtimeSize,
      _appDataSize,
      _appSize,
    ];

    for (var i = 0; i < 5; i++) {
      if (sizes[i] <= 0) continue;
      final flex = (sizes[i] / _totalBytes * 10000).round().clamp(1, 10000);
      segments.add(
        Expanded(
          flex: flex,
          child: Container(color: colors[i]),
        ),
      );
    }

    // 其余已用空间（非本程序）- 灰色
    final otherUsed = usedBytes - appTotal;
    if (otherUsed > 0) {
      final flex = (otherUsed / _totalBytes * 10000).round().clamp(1, 10000);
      segments.add(
        Expanded(
          flex: flex,
          child: Container(color: Colors.grey.shade400),
        ),
      );
    }

    // 可用空间 - 浅灰
    if (_availableBytes > 0) {
      final flex = (_availableBytes / _totalBytes * 10000).round().clamp(
        1,
        10000,
      );
      segments.add(
        Expanded(
          flex: flex,
          child: Container(color: Colors.grey.shade200),
        ),
      );
    }

    if (segments.isEmpty) {
      return [Expanded(child: Container(color: Colors.grey.shade200))];
    }
    return segments;
  }

  Widget _buildSectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSectionItem(
    ThemeData theme,
    Translations tr, {
    required IconData icon,
    required Color color,
    required String label,
    required int size,
    required String path,
    String? actionText,
    VoidCallback? onAction,
    bool actionInProgress = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    (_calculating && size == 0)
                        ? tr.get('storage.calculating')
                        : _formatSize(size),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (actionText != null)
              actionInProgress
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(onPressed: onAction, child: Text(actionText)),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo(ThemeData theme, Translations tr) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图例
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _legend(
                  theme,
                  const Color(0xFF42A5F5),
                  tr.get('storage.cache'),
                ),
                _legend(
                  theme,
                  const Color(0xFF66BB6A),
                  tr.get('storage.instances'),
                ),
                _legend(
                  theme,
                  const Color(0xFFFF7043),
                  tr.get('storage.runtime'),
                ),
                _legend(
                  theme,
                  const Color(0xFFAB47BC),
                  tr.get('storage.appData'),
                ),
                _legend(theme, const Color(0xFF26A69A), tr.get('storage.app')),
                _legend(
                  theme,
                  Colors.grey.shade400,
                  tr.get('storage.otherUsed'),
                ),
                _legend(
                  theme,
                  Colors.grey.shade200,
                  tr.get('storage.available'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(ThemeData theme, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ── 辅助函数 ──────────────────────────────────────────────────

/// 在 isolate 中递归计算目录大小（字节）。
@pragma('vm:entry-point')
int _calcDirSize(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  int size = 0;
  try {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          size += entity.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return size;
}

/// 删除目录下所有内容（保留目录本身）。
Future<void> _deleteDirContents(Directory dir) async {
  if (!dir.existsSync()) return;
  await for (final entity in dir.list(followLinks: false)) {
    try {
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }
}

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unitIndex]}';
}
