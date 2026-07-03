import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ecpkg/ecpkg_catalog_service.dart';
import '../i18n/locale_scope.dart';
import '../server/runtime_service.dart';
import '../server/runtime_update_service.dart';

class EcpkgDownloadPage extends StatefulWidget {
  const EcpkgDownloadPage({super.key});

  @override
  State<EcpkgDownloadPage> createState() => _EcpkgDownloadPageState();
}

class _EcpkgDownloadPageState extends State<EcpkgDownloadPage>
    with SingleTickerProviderStateMixin {
  final _service = const RuntimeService();

  EcpkgCatalog? _catalog;
  bool _loading = true;
  String? _error;
  TabController? _tabCtrl;
  String _deviceArch = '';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await EcpkgCatalogService.fetchCatalog();
      final deviceArch = await _service.getDeviceArch();
      if (!mounted) return;
      _tabCtrl?.dispose();
      _tabCtrl = catalog.categories.length > 1
          ? TabController(length: catalog.categories.length, vsync: this)
          : null;
      setState(() {
        _catalog = catalog;
        _deviceArch = deviceArch;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'jre' => Icons.coffee,
      'php' => Icons.code,
      'frpc' => Icons.network_check,
      _ => Icons.memory,
    };
  }

  String _typeLabel(String type) {
    return switch (type) {
      'jre' => 'Java',
      'php' => 'PHP',
      'frpc' => 'FRP',
      _ => type,
    };
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '?';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _downloadEntry(EcpkgCatalogPackage pkg, EcpkgDownloadEntry entry) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);
    final urls = entry.urls;

    if (!mounted) return;

    // 选择下载源
    EcpkgDownloadUrl? selectedUrl;
    if (urls.length == 1) {
      selectedUrl = urls.first;
    } else {
      selectedUrl = await showDialog<EcpkgDownloadUrl>(
        context: context,
        builder: (ctx) {
          var selectedIndex = 0;
          return StatefulBuilder(
            builder: (ctx, setState) => AlertDialog(
              title: Text(tr.get('ecpkgDownload.confirmTitle')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${pkg.name} ${pkg.version}'),
                  if (pkg.description != null && pkg.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        pkg.description!,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  _infoRow(ctx, tr.get('ecpkgDownload.arch'), entry.arch.join(', ')),
                  if (entry.size != null)
                    _infoRow(ctx, tr.get('ecpkgDownload.size'), _formatSize(entry.size)),
                  if (pkg.author != null && pkg.author!.isNotEmpty)
                    _infoRow(ctx, tr.get('ecpkgDownload.author'), pkg.author!),
                  if (urls.length > 1) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr.get('ecpkgDownload.selectSource'),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < urls.length; i++) ...[
                      if (i > 0) const SizedBox(height: 2),
                      ListTile(
                        leading: Icon(
                          selectedIndex == i
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: selectedIndex == i
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          urls[i].name.isNotEmpty ? urls[i].name : 'Source ${i + 1}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        subtitle: urls[i].extra.isNotEmpty
                            ? Text(
                                urls[i].extra,
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        selected: selectedIndex == i,
                        onTap: () => setState(() => selectedIndex = i),
                      ),
                    ],
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr.get('common.cancel')),
                ),
                if (urls[selectedIndex].isWebPage)
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () => Navigator.of(ctx).pop(urls[selectedIndex]),
                    label: Text(tr.get('ecpkgDownload.openInBrowser')),
                  )
                else
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(urls[selectedIndex]),
                    child: Text(tr.get('ecpkgDownload.download')),
                  ),
              ],
            ),
          );
        },
      );
      if (selectedUrl == null) return;
    }

    // web 类型：打开浏览器
    if (selectedUrl.isWebPage) {
      await launchUrl(Uri.parse(selectedUrl.url),
          mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;

    // direct 类型：检查运行时是否在运行
    final running = await _service.isRuntimeRunning(pkg.id);
    if (running) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.cannotUpdateRunning'))),
      );
      return;
    }

    if (!mounted) return;
    final downloadPkg = RuntimeUpdatePackage(
      key: entry.key,
      url: selectedUrl.url,
      sha256: entry.sha256,
      size: entry.size,
      arch: entry.arch,
    );
    await _doDownload(pkg, downloadPkg);
  }

  Future<void> _doDownload(
    EcpkgCatalogPackage pkg,
    RuntimeUpdatePackage downloadPkg,
  ) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);

    final progressNotifier = ValueNotifier<_DlProgress>(
      _DlProgress(
        stage: _DlStage.downloading,
        received: 0,
        total: downloadPkg.size,
      ),
    );
    var cancelled = false;

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DlProgressDialog(
        progressNotifier: progressNotifier,
        sizeBytes: downloadPkg.size,
        onCancel: () => cancelled = true,
        tr: tr,
      ),
    );

    String? downloadedPath;
    String? error;
    try {
      downloadedPath = await RuntimeUpdateService.downloadPackage(
        downloadPkg,
        onProgress: (received, total) {
          progressNotifier.value = _DlProgress(
            stage: _DlStage.downloading,
            received: received,
            total: total ?? downloadPkg.size,
          );
        },
        isCancelled: () => cancelled,
      );
    } on CancellationException {
      // 用户取消，不做处理
    } catch (e) {
      error = '$e';
    }

    if (!mounted) {
      progressNotifier.dispose();
      return;
    }

    if (error != null) {
      progressNotifier.value = _DlProgress(
        stage: _DlStage.failed,
        received: 0,
        total: downloadPkg.size,
        error: error,
      );
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
      progressNotifier.value = _DlProgress(
        stage: _DlStage.cancelled,
        received: 0,
        total: downloadPkg.size,
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

    progressNotifier.value = _DlProgress(
      stage: _DlStage.installing,
      received: downloadPkg.size ?? 0,
      total: downloadPkg.size,
    );

    try {
      await _service.importPackage(downloadedPath, force: true);
      if (!mounted) {
        progressNotifier.dispose();
        return;
      }
      progressNotifier.value = _DlProgress(
        stage: _DlStage.done,
        received: downloadPkg.size ?? 0,
        total: downloadPkg.size,
      );
      await dialogFuture;
      progressNotifier.dispose();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('ecpkgDownload.installSuccess'))),
        );
      }
    } catch (e) {
      if (!mounted) {
        progressNotifier.dispose();
        return;
      }
      progressNotifier.value = _DlProgress(
        stage: _DlStage.failed,
        received: downloadPkg.size ?? 0,
        total: downloadPkg.size,
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

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ecpkgDownload.title')),
        bottom: _tabCtrl == null || _catalog == null
            ? null
            : TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final cat in _catalog!.categories)
                    Tab(text: _typeLabel(cat.type)),
                ],
              ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorBody(
        error: _error!,
        onRetry: _loadCatalog,
      );
    }
    final catalog = _catalog;
    if (catalog == null || catalog.categories.every((c) => c.packages.isEmpty)) {
      return Center(
        child: Text(context.tr('ecpkgDownload.noPackages')),
      );
    }

    if (_tabCtrl != null) {
      return TabBarView(
        controller: _tabCtrl,
        children: [
          for (final cat in catalog.categories)
            _CategoryView(
              category: cat,
              typeIcon: _typeIcon(cat.type),
              typeLabel: _typeLabel(cat.type),
              formatSize: _formatSize,
              deviceArch: _deviceArch,
              onDownloadEntry: _downloadEntry,
            ),
        ],
      );
    }

    // 只有一个分类时不显示 TabBar
    final cat = catalog.categories.first;
    return _CategoryView(
      category: cat,
      typeIcon: _typeIcon(cat.type),
      typeLabel: _typeLabel(cat.type),
      formatSize: _formatSize,
      deviceArch: _deviceArch,
      onDownloadEntry: _downloadEntry,
    );
  }
}

class _CategoryView extends StatelessWidget {
  const _CategoryView({
    required this.category,
    required this.typeIcon,
    required this.typeLabel,
    required this.formatSize,
    required this.deviceArch,
    required this.onDownloadEntry,
  });

  final EcpkgCategory category;
  final IconData typeIcon;
  final String typeLabel;
  final String Function(int? bytes) formatSize;
  final String deviceArch;
  final void Function(EcpkgCatalogPackage pkg, EcpkgDownloadEntry entry) onDownloadEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = context.tr;
    final packages = category.packages;

    if (packages.isEmpty) {
      return Center(
        child: Text(tr('ecpkgDownload.noPackages')),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: packages.length,
      itemBuilder: (_, i) {
        final pkg = packages[i];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(typeIcon, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pkg.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pkg.version,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (pkg.description != null && pkg.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      pkg.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (pkg.author != null && pkg.author!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _chip(theme, pkg.author!),
                  ),
                if (pkg.arch.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _chip(theme, pkg.arch.join(', ')),
                  ),
                const SizedBox(height: 12),
                for (final entry in pkg.packageEntries.entries)
                  _entryRow(theme, tr, pkg, entry.key, entry.value),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _entryRow(
    ThemeData theme,
    dynamic tr,
    EcpkgCatalogPackage pkg,
    String key,
    EcpkgDownloadEntry entry,
  ) {
    final supportsDevice = deviceArch.isNotEmpty && entry.arch.contains(deviceArch);
    final keyLabel = switch (key) {
      'multi' => tr('ecpkgDownload.entryMulti'),
      _ => key,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              keyLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (entry.size != null) ...[
            const SizedBox(width: 8),
            Text(
              formatSize(entry.size),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            supportsDevice ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: supportsDevice
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              supportsDevice
                  ? tr('ecpkgDownload.supported')
                  : tr('ecpkgDownload.unsupported'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: supportsDevice
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => onDownloadEntry(pkg, entry),
            icon: const Icon(Icons.download, size: 16),
            label: Text(tr('ecpkgDownload.download')),
          ),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('ecpkgDownload.loadFailed'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('common.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DlStage { downloading, installing, done, failed, cancelled }

class _DlProgress {
  const _DlProgress({
    required this.stage,
    required this.received,
    required this.total,
    this.error,
  });

  final _DlStage stage;
  final int received;
  final int? total;
  final String? error;

  int? get percent {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received * 100 ~/ t).clamp(0, 100);
  }
}

class _DlProgressDialog extends StatelessWidget {
  const _DlProgressDialog({
    required this.progressNotifier,
    required this.sizeBytes,
    required this.onCancel,
    required this.tr,
  });

  final ValueNotifier<_DlProgress> progressNotifier;
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
    return ValueListenableBuilder<_DlProgress>(
      valueListenable: progressNotifier,
      builder: (ctx, progress, _) {
        final stage = progress.stage;
        final canCancel = stage == _DlStage.downloading;
        final isTerminal = stage == _DlStage.done ||
            stage == _DlStage.failed ||
            stage == _DlStage.cancelled;

        String title;
        String? message;
        switch (stage) {
          case _DlStage.downloading:
            title = tr.get('runtime.update.downloading');
            break;
          case _DlStage.installing:
            title = tr.get('runtime.update.installing');
            break;
          case _DlStage.done:
            title = tr.get('runtime.update.doneTitle');
            break;
          case _DlStage.failed:
            title = tr.get('runtime.update.failedTitle');
            message = progress.error;
            break;
          case _DlStage.cancelled:
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
                if (stage == _DlStage.downloading ||
                    stage == _DlStage.installing)
                  LinearProgressIndicator(
                    value: progress.percent != null
                        ? progress.percent! / 100.0
                        : null,
                  ),
                if (stage == _DlStage.downloading &&
                    progress.percent != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${progress.percent}% · ${_formatBytes(progress.received)} / ${progress.total != null ? _formatBytes(progress.total!) : '?'}',
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
