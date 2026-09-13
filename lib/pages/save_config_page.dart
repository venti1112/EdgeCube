import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../files/archive_service.dart';
import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../server/server_service.dart';
import '../server/world_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/placeholder_page.dart';

/// 「存档配置」页：管理当前实例的世界（存档）。
///
/// - 导入：选择本地压缩包（zip / tar / 7z 等），把其中的世界目录导入实例；
/// - 导出：把某个世界压缩为 zip 后分享或保存到外部文件夹；
/// - 地图重置：删除当前世界（含 nether / the_end 伴生目录）并清空 level-seed，
///   使服务端下次启动生成一张全新地图；
/// - 删除：只删除选中的世界目录。
///
/// 所有写操作都要求服务端处于停止状态；服务端运行中写入世界目录会造成存档损坏。
class SaveConfigPage extends StatefulWidget {
  const SaveConfigPage({super.key});

  @override
  State<SaveConfigPage> createState() => _SaveConfigPageState();
}

class _SaveConfigPageState extends State<SaveConfigPage> {
  /// 与原生解压器支持的格式保持一致。
  static const List<String> _archiveExtensions = [
    '.zip',
    '.tar',
    '.tar.gz',
    '.tgz',
    '.tar.xz',
    '.txz',
    '.tar.bz2',
    '.tbz2',
    '.tar.zst',
    '.tzst',
    '.tar.lz4',
    '.7z',
  ];

  bool _loading = true;
  Instance? _instance;
  Directory? _instanceDir;
  String _levelName = WorldService.defaultLevelName;
  List<WorldInfo> _worlds = const [];

  /// 进行中的长任务；非 null 时页面只展示进度。
  String? _busyMessage;
  double? _busyProgress;

  InstanceController? _controller;
  String? _loadedInstanceId = '\u0000';

  bool get _busy => _busyMessage != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = InstanceScope.of(context);
    if (controller != _controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller?.addListener(_onControllerChanged);
    }
    _onControllerChanged();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// 当前实例变化（本页切换或别处切换）时重新加载世界列表。
  void _onControllerChanged() {
    final id = _controller?.selected?.id;
    if (id == _loadedInstanceId) return;
    _loadedInstanceId = id;
    // didChangeDependencies 阶段不能同步 setState，挪到当前帧结束后再加载。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final controller = _controller;
    if (controller == null) return;
    final instance = controller.selected;
    if (instance == null) {
      if (!mounted) return;
      setState(() {
        _instance = null;
        _instanceDir = null;
        _worlds = const [];
        _loading = false;
      });
      return;
    }
    final dir = await controller.directoryFor(instance);
    final levelName = await WorldService.readLevelName(dir);
    final worlds = await WorldService.listWorlds(dir);
    if (!mounted) return;
    setState(() {
      _instance = instance;
      _instanceDir = dir;
      _levelName = levelName;
      _worlds = worlds;
      _loading = false;
    });
  }

  // ── 导入 ──

  Future<void> _importWorld() async {
    final dir = _instanceDir;
    if (dir == null) return;
    if (!await _requireServerStopped()) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;

    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: _archiveExtensions,
    );
    if (sourcePath == null || !mounted) return;

    final tmpDir = Directory(
      p.join(dir.path, '.world_import_${DateTime.now().millisecondsSinceEpoch}'),
    );
    setState(() {
      _busyMessage = context.tr('saveConfig.importingWorld');
      _busyProgress = null;
    });
    try {
      await tmpDir.create(recursive: true);
      await ArchiveService.extractWithProgress(
        sourcePath,
        tmpDir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() => _busyProgress = total > 0 ? current / total : null);
        },
      );

      final found = await WorldService.scanForWorlds(
        tmpDir,
        fallbackName: _archiveBaseName(sourcePath),
      );
      if (found.isEmpty) {
        throw const _NoWorldInArchiveException();
      }

      // 同名目录已存在时先征询用户，避免静默覆盖别人的存档。
      final conflicts = found
          .where(
            (w) => FileSystemEntity.typeSync(
                  p.join(dir.path, w.name),
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound,
          )
          .map((w) => w.name)
          .toList();
      var overwrite = false;
      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        final ok = await showMiuixConfirm(
          context,
          title: context.tr('saveConfig.importOverwriteTitle'),
          message: context.tr('saveConfig.importOverwriteMessage', {
            'names': conflicts.join('、'),
          }),
          confirmLabel: context.tr('saveConfig.importOverwriteAction'),
        );
        if (ok != true) return;
        overwrite = true;
      }

      final imported = await WorldService.moveIntoInstance(
        dir,
        found,
        overwrite: overwrite,
      );
      if (!mounted) return;
      await _maybeSwitchLevel(dir, imported);
      if (!mounted) return;
      showMiuixSnackbar(
        context.tr('saveConfig.importSuccess', {'names': imported.join('、')}),
      );
      await _load();
    } on _NoWorldInArchiveException {
      if (mounted) {
        showErrorDialog(context, context.tr('saveConfig.importNoWorld'));
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('saveConfig.importFailed', {'error': '$e'}),
        );
      }
    } finally {
      // 临时目录只用于解压探测，无论成败都要清掉（否则会残留成"世界"）。
      try {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _busyMessage = null;
          _busyProgress = null;
        });
      }
    }
  }

  /// 导入的世界不是当前 level-name 时，询问是否切换过去。
  Future<void> _maybeSwitchLevel(
    Directory instanceDir,
    List<String> imported,
  ) async {
    if (imported.isEmpty) return;
    if (imported.any((n) => n.toLowerCase() == _levelName.toLowerCase())) {
      return;
    }
    final ok = await showMiuixConfirm(
      context,
      title: context.tr('saveConfig.switchLevelTitle'),
      message: context.tr('saveConfig.switchLevelMessage', {
        'name': imported.first,
        'current': _levelName,
      }),
      confirmLabel: context.tr('common.yes'),
      cancelLabel: context.tr('common.no'),
    );
    if (ok == true) {
      await WorldService.writeLevelName(instanceDir, imported.first);
    }
  }

  // ── 导出 ──

  /// 压缩世界目录到临时文件并调起系统分享面板。
  Future<void> _shareWorld(WorldInfo world) async {
    if (!await _worldExists(world)) return;
    if (!mounted) return;
    try {
      final zipPath = await runWithLoadingDialog(
        context,
        context.tr('saveConfig.compressing'),
        () async {
          final tempDir = await getTemporaryDirectory();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final path = p.join(
            tempDir.path,
            '${_sanitizeName(world.name)}_$ts.zip',
          );
          await ArchiveService.compress([world.path], path);
          return path;
        },
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipPath)],
          text: context.tr('saveConfig.shareText', {'name': world.name}),
        ),
      );
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('saveConfig.exportFailed', {'error': '$e'}),
        );
      }
    }
  }

  /// 压缩世界目录到用户选择的外部文件夹。
  Future<void> _saveWorldToFolder(WorldInfo world) async {
    if (!await _worldExists(world)) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null || !mounted) return;
    try {
      final zipPath = await runWithLoadingDialog(
        context,
        context.tr('saveConfig.compressing'),
        () => const FileService().compressMany(
          [world.path],
          Directory(destDir),
          '${_sanitizeName(world.name)}.zip',
        ),
      );
      if (mounted) {
        showMiuixSnackbar(context.tr('saveConfig.savedTo', {'path': zipPath}));
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('saveConfig.exportFailed', {'error': '$e'}),
        );
      }
    }
  }

  /// 删除单个世界目录。
  Future<void> _deleteWorld(WorldInfo world) async {
    if (!await _requireServerStopped()) return;
    if (!mounted) return;
    final ok = await showMiuixConfirm(
      context,
      title: context.tr('saveConfig.deleteConfirmTitle'),
      message: context.tr('saveConfig.deleteConfirmMessage', {
        'name': world.name,
      }),
      confirmLabel: context.tr('common.delete'),
    );
    if (ok != true || !mounted) return;
    try {
      await WorldService.deleteWorld(world);
      if (!mounted) return;
      showMiuixSnackbar(context.tr('saveConfig.deleted', {'name': world.name}));
      await _load();
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('saveConfig.deleteFailed', {'error': '$e'}),
        );
      }
    }
  }

  // ── 地图重置 ──

  Future<void> _resetMap() async {
    final dir = _instanceDir;
    if (dir == null) return;
    if (!await _requireServerStopped()) return;
    if (!mounted) return;

    final related = await WorldService.worldsForLevel(dir, _levelName);
    if (!mounted) return;
    final names = related.isEmpty
        ? _levelName
        : related.map((w) => w.name).join('、');
    final ok = await showMiuixConfirm(
      context,
      title: context.tr('saveConfig.resetConfirmTitle'),
      message: context.tr('saveConfig.resetConfirmMessage', {'worlds': names}),
      confirmLabel: context.tr('saveConfig.resetConfirmAction'),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busyMessage = context.tr('saveConfig.resetting');
      _busyProgress = null;
    });
    try {
      for (final world in related) {
        await WorldService.deleteWorld(world);
      }
      // 只删目录的话，同一种子会生成一模一样的地图；清空种子才是真正的重置。
      await WorldService.clearLevelSeed(dir);
      if (!mounted) return;
      showMiuixSnackbar(context.tr('saveConfig.resetSuccess'));
      await _load();
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          context.tr('saveConfig.deleteFailed', {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyMessage = null;
          _busyProgress = null;
        });
      }
    }
  }

  // ── 通用 ──

  /// 世界目录已被外部删除时提示并刷新列表。
  Future<bool> _worldExists(WorldInfo world) async {
    if (await world.directory.exists()) return true;
    if (!mounted) return false;
    showErrorDialog(
      context,
      context.tr('saveConfig.worldMissing', {'name': world.name}),
    );
    await _load();
    return false;
  }

  /// 写操作前置检查：服务端运行中时提示先停止。
  Future<bool> _requireServerStopped() async {
    if (!await ServerService().isRunning()) return true;
    if (mounted) {
      showErrorDialog(context, context.tr('saveConfig.serverRunning'));
    }
    return false;
  }

  /// 确保已获得「管理全部文件」权限；未授予时引导用户去系统设置开启。
  Future<bool> _ensurePermission() async {
    if (!mounted) return false;
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showMiuixConfirm(
      context,
      title: context.tr('saveConfig.permissionTitle'),
      message: context.tr('saveConfig.permissionContent'),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('saveConfig.grantPermission'),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    if (!mounted) return false;
    return StoragePermission.isGranted();
  }

  /// 文件名中非法字符替换为下划线，并确保非空。
  String _sanitizeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? WorldService.defaultLevelName : cleaned;
  }

  /// 由压缩包路径推导出包名（去扩展名），作为「压缩包内世界没有外层文件夹」
  /// 时的世界名兜底。
  String _archiveBaseName(String path) {
    var name = p.basename(path);
    final lower = name.toLowerCase();
    for (final ext in const [
      '.tar.gz',
      '.tar.xz',
      '.tar.bz2',
      '.tar.zst',
      '.tar.lz4',
    ]) {
      if (lower.endsWith(ext)) {
        return _sanitizeName(name.substring(0, name.length - ext.length));
      }
    }
    return _sanitizeName(p.basenameWithoutExtension(name));
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return context.tr('saveConfig.sizeUnknown');
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 100 ? 0 : 1);
    return '$text ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      // 导入/重置过程中不允许返回：中途离开会留下半完成的存档目录。
      return PopScope(
        canPop: false,
        child: MiuixScaffold(
          topBar: EcTopAppBar(title: context.tr('saveConfig.title')),
          content: (padding) => Padding(
            padding: padding,
            // padding.top 已含顶栏（连同状态栏）高度，故 SafeArea 只保留左右与底部。
            child: SafeArea(
              top: false,
              child: _BusyView(message: _busyMessage!, progress: _busyProgress),
            ),
          ),
        ),
      );
    }

    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('saveConfig.title'),
        actions: [
          MiuixIconButton(
            onPressed: _loading ? null : _load,
            child: MiuixIcon(icon: Icons.refresh),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故 SafeArea 只保留左右与底部。
        child: SafeArea(
          top: false,
          child: _instance == null ? _buildEmpty() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    if (_loading) {
      return const Center(child: MiuixInfiniteProgressIndicator());
    }
    return PlaceholderPage(
      icon: Icons.map_outlined,
      title: context.tr('saveConfig.emptyTitle'),
      description: context.tr('saveConfig.emptyDescription'),
    );
  }

  Widget _buildContent() {
    final instance = _instance!;
    final theme = MiuixTheme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            context.tr('saveConfig.intro'),
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
        EcCardTile(
          leading: const Icon(Icons.dns_outlined, size: 36),
          title: instance.name,
          summary: context.tr('saveConfig.currentLevel', {'name': _levelName}),
        ),
        EcCardTile(
          leading: const Icon(Icons.file_download_outlined, size: 36),
          title: context.tr('saveConfig.import'),
          summary: context.tr('saveConfig.importSubtitle'),
          onTap: _importWorld,
        ),
        EcCardTile(
          leading: Icon(Icons.restart_alt, size: 36, color: theme.colors.error),
          title: context.tr('saveConfig.resetMap'),
          summary: context.tr('saveConfig.resetMapSubtitle'),
          onTap: _resetMap,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MiuixText(
            context.tr('saveConfig.worldsTitle'),
            style: theme.textStyles.subtitle,
            color: theme.colors.primary,
          ),
        ),
        if (_loading && _worlds.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: MiuixInfiniteProgressIndicator()),
          )
        else if (_worlds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              context.tr('saveConfig.worldsEmpty'),
              textAlign: TextAlign.center,
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
          )
        else
          for (final world in _worlds) ...[
            _WorldTile(
              world: world,
              isCurrent: world.name.toLowerCase() == _levelName.toLowerCase(),
              sizeText: _formatSize(world.sizeBytes),
              onShare: () => _shareWorld(world),
              onSaveToFolder: () => _saveWorldToFolder(world),
              onDelete: () => _deleteWorld(world),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// 单个世界（存档）卡片：展示名称、大小与是否为当前世界，并提供导出/删除操作。
class _WorldTile extends StatelessWidget {
  const _WorldTile({
    required this.world,
    required this.isCurrent,
    required this.sizeText,
    required this.onShare,
    required this.onSaveToFolder,
    required this.onDelete,
  });

  final WorldInfo world;
  final bool isCurrent;
  final String sizeText;
  final VoidCallback onShare;
  final VoidCallback onSaveToFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.public : Icons.map_outlined,
            color: isCurrent ? theme.colors.primary : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        world.name,
                        style: theme.textStyles.title4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      EcStatusChip(context.tr('saveConfig.currentBadge')),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sizeText,
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          MiuixIconButton(
            onPressed: onShare,
            child: MiuixIcon(icon: Icons.share_outlined),
          ),
          MiuixIconButton(
            onPressed: onSaveToFolder,
            child: MiuixIcon(icon: Icons.folder_copy_outlined),
          ),
          MiuixIconButton(
            onPressed: onDelete,
            child: MiuixIcon(
              icon: Icons.delete_outline,
              tint: theme.colors.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// 长任务进度视图：文案 +（可选的）确定进度条，不提供取消按钮
/// （解压/删除中途取消反而会留下半成品存档）。
class _BusyView extends StatelessWidget {
  const _BusyView({required this.message, this.progress});

  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final value = progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              MiuixCircularProgressIndicator(progress: value)
            else
              const MiuixInfiniteProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (value != null) ...[
              const SizedBox(height: 8),
              Text(
                '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: theme.textStyles.footnote1.copyWith(
                  color: theme.colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 压缩包中没有任何可识别的世界目录。
class _NoWorldInArchiveException implements Exception {
  const _NoWorldInArchiveException();
}
