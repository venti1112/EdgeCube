import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/locale_scope.dart';
import '../net/download_engine.dart';
import '../net/download_exceptions.dart';
import '../net/download_format.dart';
import '../online/update_service.dart';

enum _DialogState { pending, downloading, verifyingSha256, verifyingSignature, ready, error }

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

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
      await launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final info = _info;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(context.tr('update.newVersionFound'))),
          if (_state == _DialogState.ready)
            Icon(Icons.check_circle, color: cs.primary, size: 24),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('update.latestVersion', {'version': '${info.version} (Build ${info.build})'}),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('update.releaseNotes'),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              info.releaseNotes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            if (_state == _DialogState.pending) ...[
              Text(
                context.tr('update.selectSource'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ...List.generate(_links.length, (i) {
                final link = _links[i];
                final selected = _selectedLinkIndex == i;
                return ListTile(
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                  title: Text(link.name),
                  subtitle: Text(link.extra, style: theme.textTheme.bodySmall),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  enabled: _state == _DialogState.pending,
                  selected: selected,
                  onTap: _state == _DialogState.pending
                      ? () => setState(() => _selectedLinkIndex = i)
                      : null,
                );
              }),
            ],
            if (_state == _DialogState.downloading) ...[
              const SizedBox(height: 12),
              _progress != null && _progress!.hasTotal
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: _progress!.fraction, end: _progress!.fraction),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.linear,
                      builder: (context, value, _) =>
                          LinearProgressIndicator(value: value),
                    )
                  : const LinearProgressIndicator(),
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
                          return Text(
                            '$pct% · ${formatBytes(bytes.round())} / ${formatBytes(_progress!.totalBytes!)}',
                            style: theme.textTheme.bodySmall,
                          );
                        }
                        return Text(
                          formatBytes(bytes.round()),
                          style: theme.textTheme.bodySmall,
                        );
                      },
                    )
                  : Text(
                      context.tr('update.downloading'),
                      style: theme.textTheme.bodySmall,
                    ),
              if (_progress != null && _progress!.speedBytesPerSec > 0) ...[
                const SizedBox(height: 2),
                Text(
                  _speedLine(_progress!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
            if (_state == _DialogState.verifyingSha256) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(context.tr('update.verifyingSha256')),
                ],
              ),
            ],
            if (_state == _DialogState.verifyingSignature) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(context.tr('update.verifyingSignature')),
                ],
              ),
            ],
            if (_state == _DialogState.ready) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(context.tr('update.verificationPassed')),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (_state == _DialogState.pending && _selectedLink.isWebPage) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('update.later')),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: _startDownload,
            label: Text(context.tr('update.openInBrowser')),
          ),
        ],
        if (_state == _DialogState.pending && _selectedLink.isDirect) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('update.later')),
          ),
          FilledButton(
            onPressed: _startDownload,
            child: Text(context.tr('update.downloadAndInstall')),
          ),
        ],
        if (_state == _DialogState.error)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('common.close')),
          ),
        if (_state == _DialogState.ready)
          FilledButton(
            onPressed: _install,
            child: Text(context.tr('update.install')),
          ),
      ],
    );
  }
}
