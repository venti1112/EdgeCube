import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../i18n/locale_scope.dart';
import '../mods/modpack_service.dart';
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
    this.tasks = const [],
  });

  final String phase;
  final int current;
  final int total;
  final String currentFile;
  final String? error;
  final VoidCallback onCancel;

  /// 下载任务列表快照（仅 downloading 阶段有意义）。
  final List<ModDownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    // 错误态：保持原有的居中错误展示。
    if (error != null) {
      return _CenteredColumn(
        children: [
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
        ],
      );
    }

    // 下载阶段且有任务列表：顶部整体进度 + 下方可滚动任务列表。
    if (phase == 'downloading' && tasks.isNotEmpty) {
      return _DownloadListBody(
        current: current,
        total: total,
        tasks: tasks,
        onCancel: onCancel,
      );
    }

    // 其余阶段（parsing/extracting/preparing）：居中无限进度。
    return _CenteredColumn(
      children: [
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
                  color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 居中纵向排列的内容列（保留原 ModpackImportStep 的视觉）。
class _CenteredColumn extends StatelessWidget {
  const _CenteredColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// 下载阶段主体：顶部整体进度卡片 + 下方任务列表。
class _DownloadListBody extends StatelessWidget {
  const _DownloadListBody({
    required this.current,
    required this.total,
    required this.tasks,
    required this.onCancel,
  });

  final int current;
  final int total;
  final List<ModDownloadTask> tasks;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final fraction = total > 0 ? current / total : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部整体进度卡片。
          MiuixCard(
            insideMargin: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: fraction, end: fraction),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, value, _) =>
                        MiuixCircularProgressIndicator(progress: value),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('instance.modpackDownloading'),
                        style: theme.textStyles.title4,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$current / $total',
                        style: theme.textStyles.body1.copyWith(
                          color: theme.colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ],
                  ),
                ),
                MiuixTextButton(
                  context.tr('common.cancel'),
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 任务列表标题。
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: MiuixText(
              context.tr('instance.modpackDownloadList'),
              style: theme.textStyles.footnote1,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
          // 任务列表。
          Expanded(
            child: MiuixCard(
              insideMargin: const EdgeInsets.symmetric(vertical: 4),
              child: tasks.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: tasks.length,
                      itemBuilder: (_, i) => _ModTaskTile(task: tasks[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个下载任务行。
class _ModTaskTile extends StatelessWidget {
  const _ModTaskTile({required this.task});

  final ModDownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _StatusIcon(status: task.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.main,
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote1.copyWith(
                    color: task.status == ModDownloadStatus.failed
                        ? theme.colors.error
                        : theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _trailing(context),
        ],
      ),
    );
  }

  String _subtitle(BuildContext context) {
    switch (task.status) {
      case ModDownloadStatus.pending:
        return context.tr('instance.modpackTaskPending');
      case ModDownloadStatus.downloading:
        if (task.hasTotal) {
          return '${formatBytes(task.receivedBytes)} / ${formatBytes(task.totalBytes!)}';
        }
        return task.receivedBytes > 0
            ? formatBytes(task.receivedBytes)
            : context.tr('instance.modpackTaskDownloading');
      case ModDownloadStatus.completed:
        return task.hasTotal
            ? formatBytes(task.totalBytes!)
            : context.tr('instance.modpackTaskCompleted');
      case ModDownloadStatus.failed:
        return task.error ?? context.tr('instance.modpackTaskFailed');
      case ModDownloadStatus.skipped:
        return context.tr('instance.modpackTaskSkipped');
    }
  }

  Widget _trailing(BuildContext context) {
    switch (task.status) {
      case ModDownloadStatus.downloading:
        if (task.hasTotal) {
          final pct = (task.fraction * 100).clamp(0, 100).toStringAsFixed(0);
          return Text(
            '$pct%',
            style: MiuixTheme.of(context).textStyles.footnote1,
          );
        }
        return const SizedBox(
          width: 16,
          height: 16,
          child: MiuixInfiniteProgressIndicator(size: 16),
        );
      case ModDownloadStatus.pending:
        return const SizedBox(
          width: 16,
          height: 16,
          child: MiuixInfiniteProgressIndicator(size: 16),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// 状态对应的图标。
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final ModDownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final double size = 20;
    switch (status) {
      case ModDownloadStatus.completed:
        return MiuixIcon(
          icon: Icons.check_circle,
          size: size,
          tint: theme.colors.primary,
        );
      case ModDownloadStatus.failed:
        return MiuixIcon(
          icon: Icons.cancel,
          size: size,
          tint: theme.colors.error,
        );
      case ModDownloadStatus.skipped:
        return MiuixIcon(
          icon: Icons.remove_circle_outline,
          size: size,
          tint: theme.colors.onSurfaceVariantSummary,
        );
      case ModDownloadStatus.downloading:
        return SizedBox(
          width: size,
          height: size,
          child: const MiuixInfiniteProgressIndicator(size: 16),
        );
      case ModDownloadStatus.pending:
        return MiuixIcon(
          icon: Icons.access_time,
          size: size,
          tint: theme.colors.onSurfaceVariantSummary,
        );
    }
  }
}
