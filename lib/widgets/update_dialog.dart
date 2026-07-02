import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/locale_scope.dart';
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
  double? _progress;
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
      final apkPath = await UpdateService.downloadApk(
        link.url,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;

      setState(() {
        _downloadedPath = apkPath;
        _state = _DialogState.verifyingSha256;
      });

      final sha256Ok = await UpdateService.verifySha256(apkPath, _info.sha256);
      if (!mounted) return;

      if (!sha256Ok) {
        final nextDirect = _info.directLinks
            .where((l) => l.url != link.url)
            .toList();
        if (nextDirect.isNotEmpty) {
          _retryWithNextLink(nextDirect.first.url);
          return;
        }
        setState(() {
          _state = _DialogState.error;
          _error = context.tr('update.sha256Mismatch');
        });
        return;
      }

      setState(() => _state = _DialogState.verifyingSignature);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DialogState.error;
        _error = context.tr('update.downloadFailed', {'error': '$e'});
      });
    }
  }

  Future<void> _retryWithNextLink(String nextUrl) async {
    setState(() {
      _state = _DialogState.downloading;
      _progress = null;
    });
    try {
      final apkPath = await UpdateService.downloadApk(
        nextUrl,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;

      setState(() {
        _downloadedPath = apkPath;
        _state = _DialogState.verifyingSha256;
      });

      final sha256Ok = await UpdateService.verifySha256(apkPath, _info.sha256);
      if (!mounted) return;

      if (!sha256Ok) {
        setState(() {
          _state = _DialogState.error;
          _error = context.tr('update.sha256Mismatch');
        });
        return;
      }

      setState(() => _state = _DialogState.verifyingSignature);
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
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress != null
                    ? context.tr('update.downloadingProgress', {
                        'progress': (_progress! * 100).toStringAsFixed(0),
                      })
                    : context.tr('update.downloading'),
                style: theme.textTheme.bodySmall,
              ),
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
