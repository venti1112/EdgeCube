import 'package:flutter/material.dart';
import '../i18n/locale_scope.dart';
import '../net/download_engine.dart';
import '../net/download_format.dart';

class DownloadingStep extends StatelessWidget {
  const DownloadingStep({
    super.key,
    required this.progress,
    required this.error,
    required this.onRetry,
    required this.onCancel,
  });

  final DownloadProgress? progress;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error == null) ...[
              SizedBox(
                width: 48,
                height: 48,
                child: (progress != null && progress!.hasTotal)
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(begin: progress!.fraction, end: progress!.fraction),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.linear,
                        builder: (context, value, _) =>
                            CircularProgressIndicator(value: value),
                      )
                    : const CircularProgressIndicator(),
              ),
              const SizedBox(height: 16),
              Text(
                progress != null
                    ? context.tr('instance.downloadingServer')
                    : context.tr('instance.preparingDownload'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: progress!.receivedBytes.toDouble(),
                    end: progress!.receivedBytes.toDouble(),
                  ),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.linear,
                  builder: (context, bytes, _) {
                    if (progress!.hasTotal) {
                      final frac = bytes / progress!.totalBytes!;
                      final pct = (frac * 100).toStringAsFixed(1);
                      return Text(
                        '$pct% · ${formatBytes(bytes.round())} / ${formatBytes(progress!.totalBytes!)}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      );
                    }
                    return Text(
                      formatBytes(bytes.round()),
                      style: Theme.of(context).textTheme.bodyLarge,
                    );
                  },
                ),
                if (progress!.speedBytesPerSec > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    _speedLine(progress!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ] else ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: onCancel,
                    child: Text(context.tr('common.cancel')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(context.tr('instance.reselect')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _speedLine(DownloadProgress p) {
    final speed = formatSpeed(p.speedBytesPerSec);
    final eta = formatEta(p.etaMs);
    return eta.isEmpty ? speed : '$speed · $eta';
  }
}

class ForgeInstallingStep extends StatelessWidget {
  const ForgeInstallingStep({
    super.key,
    required this.logs,
    required this.installing,
    required this.error,
    required this.onCancel,
    this.installerType = 'forge',
    this.onExportLogs,
    this.onReselect,
  });

  final List<String> logs;
  final bool installing;
  final String? error;
  final VoidCallback onCancel;
  final String installerType;
  final VoidCallback? onExportLogs;
  final VoidCallback? onReselect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (installing)
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(),
                    )
                  else if (error == null)
                    Icon(
                      Icons.check_circle_outline,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  else
                    Icon(
                      Icons.error_outline,
                      size: 36,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    installing
                        ? (installerType == 'neoforge'
                              ? context.tr('instance.installingNeoforge')
                              : context.tr('instance.installingForge'))
                        : (error != null
                              ? context.tr('instance.installFailed')
                              : context.tr('instance.installComplete')),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (onExportLogs != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.save_outlined, size: 18),
                            onPressed: onExportLogs,
                            label: Text(context.tr('instance.exportForgeLog')),
                          ),
                        OutlinedButton(
                          onPressed: onCancel,
                          child: Text(context.tr('common.cancel')),
                        ),
                        if (onReselect != null)
                          FilledButton(
                            onPressed: onReselect,
                            child: Text(context.tr('instance.reselect')),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          context.tr('instance.waitingInstallerOutput'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (_, i) => Text(
                          logs[i],
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportingStep extends StatelessWidget {
  const ImportingStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(context.tr('instance.selectFileHint')),
    );
  }
}

class ExtractingArchiveStep extends StatelessWidget {
  const ExtractingArchiveStep({
    super.key,
    required this.extracting,
    required this.progress,
    required this.error,
    required this.onCancel,
    this.onReselect,
  });

  final bool extracting;
  final double? progress;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback? onReselect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: onCancel,
                child: Text(context.tr('common.cancel')),
              ),
              if (onReselect != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onReselect,
                  child: Text(context.tr('instance.reselect')),
                ),
              ],
            ] else if (extracting) ...[
              if (progress != null)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: progress, end: progress),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.linear,
                  builder: (context, value, _) =>
                      CircularProgressIndicator(value: value),
                )
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.tr('instance.extractingArchive')),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: progress, end: progress),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.linear,
                    builder: (context, value, _) =>
                        Text('${(value * 100).toStringAsFixed(1)}%'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class ModpackImportStep extends StatelessWidget {
  const ModpackImportStep({
    super.key,
    required this.phase,
    required this.current,
    required this.total,
    required this.currentFile,
    required this.error,
    required this.onCancel,
  });

  final String phase;
  final int current;
  final int total;
  final String currentFile;
  final String? error;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: onCancel,
                child: Text(context.tr('common.cancel')),
              ),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                switch (phase) {
                  'parsing' => context.tr('instance.modpackParsing'),
                  'downloading' => context.tr('instance.modpackDownloading'),
                  'extracting' => context.tr('instance.modpackExtracting'),
                  'preparing' => context.tr('instance.modpackPreparing'),
                  _ => context.tr('instance.modpackImporting'),
                },
              ),
              if (phase == 'downloading' && total > 0) ...[
                const SizedBox(height: 8),
                Text('$current / $total'),
                if (currentFile.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      currentFile,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
