import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
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
                        tween: Tween(
                          begin: progress!.fraction,
                          end: progress!.fraction,
                        ),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.linear,
                        builder: (context, value, _) =>
                            MiuixCircularProgressIndicator(progress: value),
                      )
                    : const MiuixInfiniteProgressIndicator(size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                progress != null
                    ? context.tr('instance.downloadingServer')
                    : context.tr('instance.preparingDownload'),
                style: MiuixTheme.of(context).textStyles.title4,
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
                        style: MiuixTheme.of(context).textStyles.body1,
                      );
                    }
                    return Text(
                      formatBytes(bytes.round()),
                      style: MiuixTheme.of(context).textStyles.body1,
                    );
                  },
                ),
                if (progress!.speedBytesPerSec > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    _speedLine(progress!),
                    style: MiuixTheme.of(context).textStyles.footnote1.copyWith(
                      color: MiuixTheme.of(
                        context,
                      ).colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ],
            ] else ...[
              MiuixIcon(
                icon: Icons.error_outline,
                size: 48,
                tint: MiuixTheme.of(context).colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: MiuixTheme.of(context).colors.error),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiuixTextButton(
                    context.tr('common.cancel'),
                    onPressed: onCancel,
                  ),
                  const SizedBox(width: 12),
                  MiuixButton(
                    onPressed: onRetry,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText(context.tr('instance.reselect')),
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
          MiuixCard(
            insideMargin: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (installing)
                  const MiuixInfiniteProgressIndicator(size: 36)
                else if (error == null)
                  MiuixIcon(
                    icon: Icons.check_circle_outline,
                    size: 36,
                    tint: MiuixTheme.of(context).colors.primary,
                  )
                else
                  MiuixIcon(
                    icon: Icons.error_outline,
                    size: 36,
                    tint: MiuixTheme.of(context).colors.error,
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
                  style: MiuixTheme.of(context).textStyles.title4,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      color: MiuixTheme.of(context).colors.error,
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
                        MiuixButton(
                          onPressed: onExportLogs,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const MiuixIcon(
                                icon: Icons.save_outlined,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              MiuixText(context.tr('instance.exportForgeLog')),
                            ],
                          ),
                        ),
                      MiuixTextButton(
                        context.tr('common.cancel'),
                        onPressed: onCancel,
                      ),
                      if (onReselect != null)
                        MiuixButton(
                          onPressed: onReselect,
                          colors: MiuixButtonDefaults.buttonColorsPrimary(
                            context,
                          ),
                          child: MiuixText(context.tr('instance.reselect')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: MiuixCard(
              insideMargin: const EdgeInsets.all(8),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        context.tr('instance.waitingInstallerOutput'),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
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
        ],
      ),
    );
  }
}

class ImportingStep extends StatelessWidget {
  const ImportingStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(context.tr('instance.selectFileHint')));
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
              MiuixIcon(
                icon: Icons.error_outline,
                size: 48,
                tint: MiuixTheme.of(context).colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: MiuixTheme.of(context).colors.error),
              ),
              const SizedBox(height: 24),
              MiuixTextButton(context.tr('common.cancel'), onPressed: onCancel),
              if (onReselect != null) ...[
                const SizedBox(height: 12),
                MiuixButton(
                  onPressed: onReselect,
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(context.tr('instance.reselect')),
                ),
              ],
            ] else if (extracting) ...[
              if (progress != null)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: progress, end: progress),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.linear,
                  builder: (context, value, _) =>
                      MiuixCircularProgressIndicator(progress: value),
                )
              else
                const MiuixInfiniteProgressIndicator(),
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
              MiuixIcon(
                icon: Icons.error_outline,
                size: 48,
                tint: MiuixTheme.of(context).colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: MiuixTheme.of(context).colors.error),
              ),
              const SizedBox(height: 24),
              MiuixTextButton(context.tr('common.cancel'), onPressed: onCancel),
            ] else ...[
              const MiuixInfiniteProgressIndicator(),
              const SizedBox(height: 16),
              Text(switch (phase) {
                'parsing' => context.tr('instance.modpackParsing'),
                'downloading' => context.tr('instance.modpackDownloading'),
                'extracting' => context.tr('instance.modpackExtracting'),
                'preparing' => context.tr('instance.modpackPreparing'),
                _ => context.tr('instance.modpackImporting'),
              }),
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
                        color: MiuixTheme.of(
                          context,
                        ).colors.onSurfaceVariantSummary,
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
