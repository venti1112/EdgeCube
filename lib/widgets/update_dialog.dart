import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/locale_scope.dart';
import '../net/download_engine.dart';
import '../net/download_exceptions.dart';
import '../net/download_format.dart';
import '../online/update_service.dart';
import 'miuix_dialog.dart';

enum _DialogState {
  pending,
  downloading,
  verifyingSha256,
  verifyingSignature,
  ready,
  error,
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.updateInfo});

  final AppUpdateInfo updateInfo;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  int _selectedLinkIndex = 0;
  _DialogState _state = _DialogState.pending;
  DownloadProgress? _progress;
  String? _error;
  String? _downloadedPath;

  AppUpdateInfo get _info => widget.updateInfo;

  DownloadLink get _selectedLink => _info.downloadLinks[_selectedLinkIndex];

  List<DownloadLink> get _links => _info.downloadLinks;

  @override
  void initState() {
    super.initState();
    _preselectLink();
  }

  void _preselectLink() {
    final directIndex = _links.indexWhere((l) => l.isDirect);
    if (directIndex >= 0) {
      _selectedLinkIndex = directIndex;
    }
  }

  Future<void> _startDownload() async {
    final link = _selectedLink;
    if (link.isWebPage) {
      await launchUrl(
        Uri.parse(link.url),
        mode: LaunchMode.externalApplication,
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _state = _DialogState.downloading;
      _error = null;
      _progress = null;
    });

    try {
      // 选中的直链优先，其余直链作为多源回退；sha256 校验由引擎内联完成，
      // 失败会自动切到下一个源，全部失败才抛 DownloadHashMismatch。
      final urls = <String>[
        link.url,
        ..._info.directLinks
            .map((l) => l.url)
            .where((u) => u.isNotEmpty && u != link.url),
      ];
      final apkPath = await UpdateService.downloadApkMultiSource(
        urls,
        sha256: _info.sha256,
        onProgress: (progress) {
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;

      // 引擎已通过 sha256 校验，接着做原生签名校验。
      setState(() {
        _downloadedPath = apkPath;
        _state = _DialogState.verifyingSignature;
      });
      final sigOk = await UpdateService.verifyApkSignature(apkPath);
      if (!mounted) return;

      if (!sigOk) {
        setState(() {
          _state = _DialogState.error;
          _error = context.tr('update.signatureMismatch');
        });
        return;
      }

      setState(() => _state = _DialogState.ready);
    } on DownloadHashMismatch {
      if (!mounted) return;
      setState(() {
        _state = _DialogState.error;
        _error = context.tr('update.sha256Mismatch');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DialogState.error;
        _error = context.tr('update.downloadFailed', {'error': '$e'});
      });
    }
  }

  Future<void> _install() async {
    if (_downloadedPath == null) return;
    try {
      await UpdateService.installApk(_downloadedPath!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DialogState.error;
        _error = context.tr('update.downloadFailed', {'error': '$e'});
      });
    }
  }

  /// 速度 + 剩余时间，如 `5.3 MB/s · ~16s`；剩余时间未知时只显示速度。
  String _speedLine(DownloadProgress p) {
    final speed = formatSpeed(p.speedBytesPerSec);
    final eta = formatEta(p.etaMs);
    return eta.isEmpty ? speed : '$speed · $eta';
  }

  /// 「转圈 + 文案」的校验中提示行。
  Widget _verifyingRow(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const MiuixInfiniteProgressIndicator(size: 16),
          const SizedBox(width: 12),
          Expanded(child: MiuixText(label)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final c = theme.colors;
    final info = _info;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: c.errorContainer.withAlpha(80),
                    shape: const MiuixSquircleBorder(cornerRadius: 12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        MiuixIcon(
                          icon: Icons.warning_amber_rounded,
                          size: 18,
                          tint: c.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: MiuixText(
                            '如果继续使用旧版本，遇到问题我们不会受理',
                            style: theme.textStyles.footnote1,
                            color: c.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                MiuixText(
                  context.tr('update.latestVersion', {
                    'version': '${info.version} (Build ${info.build})',
                  }),
                ),
                const SizedBox(height: 12),
                MiuixText(
                  context.tr('update.releaseNotes'),
                  style: theme.textStyles.footnote2,
                  color: c.onSurfaceVariantSummary,
                ),
                const SizedBox(height: 4),
                MiuixText(
                  info.releaseNotes,
                  style: theme.textStyles.footnote1,
                  color: c.onSurfaceVariantSummary,
                  height: 1.5,
                ),
                const SizedBox(height: 12),
                if (_state == _DialogState.pending) ...[
                  MiuixText(
                    context.tr('update.selectSource'),
                    style: theme.textStyles.footnote1,
                    color: c.onSurfaceVariantSummary,
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_links.length, (i) {
                    final link = _links[i];
                    final selected = _selectedLinkIndex == i;
                    return MiuixBasicComponent(
                      title: link.name,
                      summary: link.extra,
                      insideMargin: const EdgeInsets.symmetric(vertical: 6),
                      startAction: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: MiuixRadioButton(
                          selected: selected,
                          onChanged: (_) =>
                              setState(() => _selectedLinkIndex = i),
                        ),
                      ),
                      onClick: () => setState(() => _selectedLinkIndex = i),
                    );
                  }),
                ],
                if (_state == _DialogState.downloading) ...[
                  const SizedBox(height: 12),
                  _progress != null && _progress!.hasTotal
                      ? TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: _progress!.fraction,
                            end: _progress!.fraction,
                          ),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.linear,
                          builder: (context, value, _) =>
                              MiuixLinearProgressIndicator(progress: value),
                        )
                      : const MiuixLinearProgressIndicator(),
                  const SizedBox(height: 8),
                  _progress != null
                      ? TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: _progress!.receivedBytes.toDouble(),
                            end: _progress!.receivedBytes.toDouble(),
                          ),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.linear,
                          builder: (context, bytes, _) {
                            if (_progress!.hasTotal) {
                              final frac = bytes / _progress!.totalBytes!;
                              final pct = (frac * 100).toStringAsFixed(1);
                              return MiuixText(
                                '$pct% · ${formatBytes(bytes.round())} / ${formatBytes(_progress!.totalBytes!)}',
                                style: theme.textStyles.footnote1,
                              );
                            }
                            return MiuixText(
                              formatBytes(bytes.round()),
                              style: theme.textStyles.footnote1,
                            );
                          },
                        )
                      : MiuixText(
                          context.tr('update.downloading'),
                          style: theme.textStyles.footnote1,
                        ),
                  if (_progress != null && _progress!.speedBytesPerSec > 0) ...[
                    const SizedBox(height: 2),
                    MiuixText(
                      _speedLine(_progress!),
                      style: theme.textStyles.footnote1,
                      color: c.onSurfaceVariantSummary,
                    ),
                  ],
                ],
                if (_state == _DialogState.verifyingSha256)
                  _verifyingRow(context.tr('update.verifyingSha256')),
                if (_state == _DialogState.verifyingSignature)
                  _verifyingRow(context.tr('update.verifyingSignature')),
                if (_state == _DialogState.ready) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      MiuixIcon(
                        icon: Icons.check_circle,
                        size: 18,
                        tint: c.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MiuixText(
                          context.tr('update.verificationPassed'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  MiuixText(_error!, color: c.error),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(children: _actions(context)),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (_state) {
      case _DialogState.pending:
        return [
          MiuixTextButton(
            context.tr('update.later'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          MiuixButton(
            onPressed: _startDownload,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: MiuixText(
              _selectedLink.isWebPage
                  ? context.tr('update.openInBrowser')
                  : context.tr('update.downloadAndInstall'),
            ),
          ),
        ];
      case _DialogState.error:
        return [
          MiuixTextButton(
            context.tr('common.close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ];
      case _DialogState.ready:
        return [
          MiuixButton(
            onPressed: _install,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: MiuixText(context.tr('update.install')),
          ),
        ];
      // 下载与校验途中不提供任何按钮，避免中途打断。
      case _DialogState.downloading:
      case _DialogState.verifyingSha256:
      case _DialogState.verifyingSignature:
        return const [];
    }
  }
}
