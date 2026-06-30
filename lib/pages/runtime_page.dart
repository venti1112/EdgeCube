import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../server/ecpkg_handler.dart';
import '../server/runtime_service.dart';
import '../server/runtime_update_service.dart';

/// 「运行环境」管理页：列出已安装运行时，导入/删除/更新 .ecpkg。
class RuntimePage extends StatefulWidget {
  const RuntimePage({super.key, this.initialEcpkgPath});

  /// 从文件关联打开时传入的 .ecpkg 文件路径。
  final String? initialEcpkgPath;

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

class _RuntimePageState extends State<RuntimePage> {
  final _service = const RuntimeService();
  List<RuntimeInfo> _runtimes = [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
    EcpkgHandler.onOpenEcpkg = _handleOpenEcpkg;
    // 处理从文件关联传入的路径
    if (widget.initialEcpkgPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleOpenEcpkg(widget.initialEcpkgPath!);
      });
    }
  }

  @override
  void dispose() {
    EcpkgHandler.onOpenEcpkg = null;
    super.dispose();
  }

  void _handleOpenEcpkg(String path) {
    if (!mounted) return;
    if (!path.toLowerCase().endsWith('.ecpkg')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('runtime.notEcpkg'))));
      return;
    }
    _doImport(path);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.installedRuntimes();
      if (!mounted) return;
      setState(() => _runtimes = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('fileBrowser.permissionTitle')),
          content: Text(ctx.tr('fileBrowser.permissionContent')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('fileBrowser.grantPermission')),
            ),
          ],
        ),
      );
      if (go != true) return;
      await StoragePermission.request();
      if (!mounted) return;
      return _import();
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final path = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.ecpkg'],
    );
    if (path == null || !path.toLowerCase().endsWith('.ecpkg')) {
      if (mounted && path != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.notEcpkg'))),
        );
      }
      return;
    }

    await _doImport(path);
  }

  Future<void> _doImport(String path, {bool force = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    setState(() => _importing = true);
    try {
      await _service.importPackage(path, force: force);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.importSuccess'))),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'IMPORT_FAILED' &&
          e.message?.contains('RUNTIME_EXISTS') == true &&
          !force) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr.get('runtime.importConfirmTitle')),
            content: Text(tr.get('runtime.importConfirmContent')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr.get('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr.get('common.replace')),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _doImport(path, force: true);
        }
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get('runtime.importFailed', {'error': '${e.message}'}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('runtime.importFailed', {'error': '$e'})),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(RuntimeInfo info) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final runtimeRunning = await _service.isRuntimeRunning(info.id);
    if (runtimeRunning) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.cannotDeleteRunning'))),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('runtime.deleteConfirmTitle')),
        content: Text(
          tr.get('runtime.deleteConfirmContent', {'name': info.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteRuntime(info.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('runtime.deleteFailed', {'error': '$e'})),
        ),
      );
    }
  }

  /// 检查单个运行时更新。
  Future<void> _checkUpdate(RuntimeInfo info) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);

    if (!info.canCheckUpdate) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.update.noUpdateUrl'))),
      );
      return;
    }

    // 检查更新期间，先确认运行时未在运行（避免更新覆盖正在使用的二进制）。
    final running = await _service.isRuntimeRunning(info.id);
    if (running) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.cannotUpdateRunning'))),
      );
      return;
    }

    if (!mounted) return;
    // 显示加载对话框
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(tr.get('runtime.update.checking')),
          ],
        ),
      ),
    );

    RuntimeUpdateInfo? updateInfo;
    String? error;
    try {
      updateInfo = await RuntimeUpdateService.checkForUpdates(info);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭加载对话框

    if (updateInfo == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get('runtime.update.checkFailed', {'error': error ?? ''}),
          ),
        ),
      );
      return;
    }

    if (!RuntimeUpdateService.hasUpdate(info, updateInfo)) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.update.alreadyLatest'))),
      );
      return;
    }

    if (!mounted) return;
    await _showUpdateDialog(info, updateInfo);
  }

  /// 展示更新详情对话框，确认后下载并安装。
  Future<void> _showUpdateDialog(
    RuntimeInfo runtime,
    RuntimeUpdateInfo info,
  ) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('runtime.update.availableTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.get('runtime.update.versionRow', {
                  'current': runtime.version,
                  'latest': info.latestVersion,
                }),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (info.publishedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  tr.get('runtime.update.publishedAt', {
                    'date': info.publishedAt!,
                  }),
                ),
              ],
              if (info.releaseNotes != null &&
                  info.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(info.releaseNotes!),
              ],
              const SizedBox(height: 12),
              Text(
                tr.get('runtime.update.noteOverwrite'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('runtime.update.download')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // 选取下载包
    final deviceArch = await _service.getDeviceArch();
    final pkg = RuntimeUpdateService.pickPackage(info, deviceArch);
    if (pkg == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.update.noMatchingPackage'))),
      );
      return;
    }

    if (!mounted) return;
    await _downloadAndInstall(runtime, pkg);
  }

  /// 下载并安装更新包，展示进度对话框。
  Future<void> _downloadAndInstall(
    RuntimeInfo runtime,
    RuntimeUpdatePackage pkg,
  ) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);

    final progressNotifier = ValueNotifier<_DownloadProgress>(
      _DownloadProgress(
        stage: _DownloadStage.downloading,
        received: 0,
        total: pkg.size,
      ),
    );
    var cancelled = false;

    // 进度对话框（用户可取消下载）
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateProgressDialog(
        progressNotifier: progressNotifier,
        sizeBytes: pkg.size,
        onCancel: () => cancelled = true,
        tr: tr,
      ),
    );

    String? downloadedPath;
    String? error;
    try {
      downloadedPath = await RuntimeUpdateService.downloadPackage(
        pkg,
        onProgress: (received, total) {
          progressNotifier.value = _DownloadProgress(
            stage: _DownloadStage.downloading,
            received: received,
            total: total ?? pkg.size,
          );
        },
        isCancelled: () => cancelled,
      );
    } on CancellationException {
      // 用户取消
    } catch (e) {
      error = '$e';
    }

    if (!mounted) {
      // 页面已销毁，关闭对话框并退出
      progressNotifier.dispose();
      return;
    }

    if (error != null) {
      // 下载/校验失败：关闭对话框并提示
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.failed,
        received: 0,
        total: pkg.size,
        error: error,
      );
      // 等待对话框关闭（用户点击关闭）
      await dialogFuture;
      progressNotifier.dispose();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr.get('runtime.update.downloadFailed', {'error': error}),
            ),
          ),
        );
      }
      return;
    }

    if (downloadedPath == null) {
      // 用户取消
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.cancelled,
        received: 0,
        total: pkg.size,
      );
      await dialogFuture;
      progressNotifier.dispose();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.update.cancelled'))),
        );
      }
      return;
    }

    // 下载成功，切换到安装阶段
    progressNotifier.value = _DownloadProgress(
      stage: _DownloadStage.installing,
      received: pkg.size ?? 0,
      total: pkg.size,
    );

    try {
      await _service.importPackage(downloadedPath, force: true);
      if (!mounted) {
        progressNotifier.dispose();
        return;
      }
      // 安装成功：关闭对话框，刷新列表，提示
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.done,
        received: pkg.size ?? 0,
        total: pkg.size,
      );
      await dialogFuture;
      progressNotifier.dispose();
      await _load();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.update.success'))),
        );
      }
    } catch (e) {
      if (!mounted) {
        progressNotifier.dispose();
        return;
      }
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.failed,
        received: pkg.size ?? 0,
        total: pkg.size,
        error: '$e',
      );
      await dialogFuture;
      progressNotifier.dispose();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get('runtime.update.installFailed', {'error': '$e'}),
          ),
        ),
      );
    }
  }

  String _typeLabel(String type) {
    return switch (type) {
      'jre' => 'Java',
      'php' => 'PHP',
      'frpc' => 'FRP',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('runtime.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runtimes.isEmpty
          ? _EmptyBody(onImport: _import)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _runtimes.length,
              itemBuilder: (_, i) {
                final rt = _runtimes[i];
                return Card(
                  child: ListTile(
                    leading: Icon(switch (rt.type) {
                      'jre' => Icons.coffee,
                      'php' => Icons.code,
                      'frpc' => Icons.network_check,
                      _ => Icons.memory,
                    }, size: 32),
                    title: Text(rt.name),
                    subtitle: Text(
                      '${_typeLabel(rt.type)} · ${rt.version}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.system_update_alt),
                          tooltip: context.tr('runtime.update.tooltip'),
                          onPressed: rt.canCheckUpdate
                              ? () => _checkUpdate(rt)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(rt),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: _importing
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: _import,
              icon: const Icon(Icons.add),
              label: Text(context.tr('runtime.import')),
            ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.memory,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('runtime.emptyTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('runtime.emptyDescription'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: Text(context.tr('runtime.import')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下载阶段。
enum _DownloadStage { downloading, installing, done, failed, cancelled }

/// 下载进度快照。
class _DownloadProgress {
  const _DownloadProgress({
    required this.stage,
    required this.received,
    required this.total,
    this.error,
  });

  final _DownloadStage stage;
  final int received;
  final int? total;
  final String? error;

  /// 0–100，未知时为 null。
  int? get percent {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received * 100 ~/ t).clamp(0, 100);
  }
}

/// 更新下载/安装进度对话框。
///
/// 通过 [progressNotifier] 监听进度变化。下载阶段可点击「取消」；
/// 完成/失败/取消阶段显示对应状态与「关闭」按钮。
class _UpdateProgressDialog extends StatelessWidget {
  const _UpdateProgressDialog({
    required this.progressNotifier,
    required this.sizeBytes,
    required this.onCancel,
    required this.tr,
  });

  final ValueNotifier<_DownloadProgress> progressNotifier;
  final int? sizeBytes;
  final VoidCallback onCancel;
  final dynamic tr;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_DownloadProgress>(
      valueListenable: progressNotifier,
      builder: (ctx, progress, _) {
        final stage = progress.stage;
        final canCancel = stage == _DownloadStage.downloading;
        final isTerminal =
            stage == _DownloadStage.done ||
            stage == _DownloadStage.failed ||
            stage == _DownloadStage.cancelled;

        String title;
        String? message;
        switch (stage) {
          case _DownloadStage.downloading:
            title = tr.get('runtime.update.downloading');
            break;
          case _DownloadStage.installing:
            title = tr.get('runtime.update.installing');
            break;
          case _DownloadStage.done:
            title = tr.get('runtime.update.doneTitle');
            break;
          case _DownloadStage.failed:
            title = tr.get('runtime.update.failedTitle');
            message = progress.error;
            break;
          case _DownloadStage.cancelled:
            title = tr.get('runtime.update.cancelledTitle');
            break;
        }

        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stage == _DownloadStage.downloading ||
                    stage == _DownloadStage.installing) ...[
                  LinearProgressIndicator(
                    value: progress.percent != null
                        ? progress.percent! / 100.0
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (stage == _DownloadStage.downloading)
                    Text(
                      progress.percent != null
                          ? '${progress.percent}% · ${_formatBytes(progress.received)} / ${progress.total != null ? _formatBytes(progress.total!) : '?'}'
                          : _formatBytes(progress.received),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (canCancel)
                TextButton(
                  onPressed: onCancel,
                  child: Text(tr.get('common.cancel')),
                ),
              if (isTerminal)
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr.get('common.close')),
                ),
            ],
          ),
        );
      },
    );
  }
}
