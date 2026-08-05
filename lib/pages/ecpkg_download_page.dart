import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/developer_options_store.dart';
import '../ecpkg/ecpkg_catalog_service.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../net/download_engine.dart';
import '../net/download_format.dart';
import '../server/runtime_service.dart';
import '../server/runtime_update_service.dart';
import '../server/signature_verify_result.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/ec_preference.dart';

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

  /// MiuixTabRow 是受控组件，需自持选中项；滑动 TabBarView 时反向同步。
  int _tabIndex = 0;
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
      _tabIndex = 0;
      _tabCtrl = catalog.categories.length > 1
          ? TabController(length: catalog.categories.length, vsync: this)
          : null;
      _tabCtrl?.addListener(() {
        if (_tabCtrl != null && _tabCtrl!.index != _tabIndex && mounted) {
          setState(() => _tabIndex = _tabCtrl!.index);
        }
      });
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

  /// 将 list.json 中 `icon` 字符串解析为图标，未知值回退到默认。
  IconData _iconFromName(String? name) {
    return switch (name) {
      'coffee' => Icons.coffee,
      'code' => Icons.code,
      'wifi' => Icons.wifi,
      'network' => Icons.network_check,
      'memory' => Icons.memory,
      _ => Icons.memory,
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

  /// 下载并安装：自动匹配当前设备架构，走下载→校验→安装流程。
  Future<void> _downloadAndInstall(EcpkgCatalogPackage pkg) async {
    final deviceArch = _deviceArch;

    if (deviceArch.isEmpty) {
      showErrorDialog(context, context.tr('ecpkgDownload.archUnknown'));
      return;
    }

    // detail 已在加载目录时随 metadata 一起取回
    final detail = pkg.detail;

    // 自动匹配架构
    final entry = detail.pickEntry(deviceArch);
    if (entry == null) {
      showErrorDialog(context, context.tr('ecpkgDownload.noMatchingArch'));
      return;
    }

    // 选择下载源
    final url = await _pickDownloadUrl(entry.urls);
    if (url == null || !mounted) return;

    // web 类型：交给系统浏览器打开，不走安装流程
    if (url.isWebPage) {
      await launchUrl(Uri.parse(url.url), mode: LaunchMode.externalApplication);
      return;
    }

    await showMiuixDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InstallDialog(
        pkgName: pkg.name,
        pkgVersion: detail.version,
        entry: entry,
        downloadUrl: url,
      ),
    );
  }

  /// 仅下载：弹出架构列表供用户选择，下载到 Download/EdgeCube。
  Future<void> _downloadOnly(EcpkgCatalogPackage pkg) async {
    // detail 已在加载目录时随 metadata 一起取回
    final detail = pkg.detail;
    final entries = detail.packageEntries;
    if (entries.isEmpty) return;

    final selected = await showMiuixDialog<MapEntry<String, EcpkgDownloadEntry>>(
      context: context,
      builder: (ctx) {
        final keys = entries.keys.toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: MiuixText(
                context.tr('ecpkgDownload.selectArch'),
                textAlign: TextAlign.center,
                style: MiuixTheme.of(context).textStyles.title4,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in keys) ...[
                  if (keys.indexOf(key) > 0) const MiuixHorizontalDivider(),
                  MiuixBasicComponent(
                    content: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(switch (key) {
                            'multi' => context.tr('ecpkgDownload.entryMulti'),
                            _ => key,
                          }),
                          Text(
                            '${entries[key]!.arch.join(', ')} · ${_formatSize(entries[key]!.size)}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                    onClick: () =>
                        Navigator.of(ctx).pop(MapEntry(key, entries[key]!)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            MiuixDialogActions(
              children: [
                MiuixTextButton(
                  context.tr('common.cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;

    // 选择下载源
    final dlUrl = await _pickDownloadUrl(selected.value.urls);
    if (dlUrl == null || !mounted) return;

    // web 类型：交给系统浏览器打开，不写入本地
    if (dlUrl.isWebPage) {
      await launchUrl(
        Uri.parse(dlUrl.url),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // 准备目录
    String dirPath;
    try {
      dirPath = await RuntimeService.getDownloadDir();
    } catch (_) {
      dirPath = (await Directory.systemTemp.createTemp()).path;
    }
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    // 文件名冲突处理，使用 detail.version
    var fileName = '${pkg.id}-${selected.key}.ecpkg';
    var counter = 1;
    while (await File('${dir.path}/$fileName').exists()) {
      fileName = '${pkg.id}-${selected.key}($counter).ecpkg';
      counter++;
    }
    final targetPath = '${dir.path}/$fileName';

    if (!mounted) return;
    await showMiuixDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadOnlyDialog(
        pkgName: pkg.name,
        pkgVersion: detail.version,
        entryKey: selected.key,
        dlUrl: dlUrl,
        sha256: selected.value.sha256,
        size: selected.value.size,
        arch: selected.value.arch,
        targetPath: targetPath,
      ),
    );
  }

  /// 弹出下载源选择对话框；返回用户选中的 [EcpkgDownloadUrl]，取消则 null。
  /// 默认预选第一个 direct 类型（与更新对话框行为一致）。
  Future<EcpkgDownloadUrl?> _pickDownloadUrl(
    List<EcpkgDownloadUrl> urls,
  ) async {
    if (urls.isEmpty) return null;
    if (urls.length == 1) return urls.first;

    final defaultIndex = urls.indexWhere((u) => u.isDirect);
    final preselect = defaultIndex >= 0 ? defaultIndex : 0;

    return showMiuixDialog<EcpkgDownloadUrl>(
      context: context,
      builder: (ctx) =>
          _DownloadSourceDialog(urls: urls, initialIndex: preselect),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);

    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('ecpkgDownload.title'),

        // 只换有 Material 观感的标签条；TabController + TabBarView 保留。
        bottomContent: _tabCtrl == null || _catalog == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: MiuixTabRow(
                  tabs: [for (final cat in _catalog!.categories) cat.nameKey],
                  selectedTabIndex: _tabIndex,
                  onTabSelected: (i) {
                    setState(() => _tabIndex = i);
                    _tabCtrl?.animateTo(i);
                  },
                ),
              ),
      ),
      content: (padding) => Padding(padding: padding, child: _buildBody(theme)),
    );
  }

  Widget _buildBody(MiuixThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorBody(error: _error!, onRetry: _loadCatalog);
    }
    final catalog = _catalog;
    if (catalog == null ||
        catalog.categories.every((c) => c.packages.isEmpty)) {
      return Center(child: Text(context.tr('ecpkgDownload.noPackages')));
    }

    if (_tabCtrl != null) {
      return TabBarView(
        controller: _tabCtrl,
        children: [
          for (final cat in catalog.categories)
            _CategoryView(
              category: cat,
              typeIcon: _iconFromName(cat.icon),
              onDownloadAndInstall: _downloadAndInstall,
              onDownloadOnly: _downloadOnly,
            ),
        ],
      );
    }

    final cat = catalog.categories.first;
    return _CategoryView(
      category: cat,
      typeIcon: _iconFromName(cat.icon),
      onDownloadAndInstall: _downloadAndInstall,
      onDownloadOnly: _downloadOnly,
    );
  }
}

// ── 仅下载对话框（下载进度）────────────────────────────────────────────

class _DownloadOnlyDialog extends StatefulWidget {
  const _DownloadOnlyDialog({
    required this.pkgName,
    required this.pkgVersion,
    required this.entryKey,
    required this.dlUrl,
    required this.sha256,
    required this.size,
    required this.arch,
    required this.targetPath,
  });

  final String pkgName;
  final String pkgVersion;
  final String entryKey;
  final EcpkgDownloadUrl dlUrl;
  final String sha256;
  final int? size;
  final List<String> arch;
  final String targetPath;

  @override
  State<_DownloadOnlyDialog> createState() => _DownloadOnlyDialogState();
}

class _DownloadOnlyDialogState extends State<_DownloadOnlyDialog> {
  bool _done = false;
  String? _error;
  DownloadProgress? _progress;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    // _start() 内会调用 context.tr（经 LocaleScope.of 依赖 inherited widget），
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误，导致下载流程未启动、
    // 对话框卡死无进度。改用 post-frame 回调延迟到 initState 完成后再启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final tr = context.tr;

    setState(() {
      _stage = tr('runtime.update.downloading');
      _progress = null;
    });

    try {
      final tempPath = await RuntimeUpdateService.downloadPackage(
        RuntimeUpdatePackage(
          key: widget.entryKey,
          url: widget.dlUrl.url,
          sha256: widget.sha256,
          size: widget.size,
          arch: widget.arch,
        ),
        onProgress: (progress) {
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;

      setState(() {
        _stage = tr('ecpkgDownload.copying');
        _progress = null;
      });
      await File(tempPath).copy(widget.targetPath);
      try {
        await File(tempPath).delete();
      } catch (_) {}
      if (!mounted) return;

      setState(() {
        _done = true;
        _stage = '';
      });
    } on HashMismatchException {
      if (!mounted) return;
      setState(() {
        _error = context.tr('update.sha256Mismatch');
      });
    } on CancellationException {
      if (!mounted) return;
      setState(() {
        _error = context.tr('runtime.update.cancelled');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final cs = theme.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _done
                    ? context.tr('ecpkgDownload.downloadSuccess')
                    : _error != null
                    ? context.tr('runtime.update.failedTitle')
                    : context.tr('ecpkgDownload.downloadingTitle'),
              ),
            ),
            if (_done) Icon(Icons.check_circle, color: cs.primary, size: 24),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.pkgName} ${widget.pkgVersion}'),
            if (_done) ...[
              const SizedBox(height: 8),
              Text(
                widget.targetPath,
                style: theme.textStyles.footnote1.copyWith(
                  color: cs.onSurfaceVariantSummary,
                ),
              ),
            ],
            if (_progress != null && _stage.isNotEmpty) ...[
              const SizedBox(height: 12),
              _progress!.hasTotal
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: _progress!.fraction,
                        end: _progress!.fraction,
                      ),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.linear,
                      builder: (context, value, _) =>
                          LinearProgressIndicator(value: value),
                    )
                  : const LinearProgressIndicator(),
              TweenAnimationBuilder<double>(
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
                      style: theme.textStyles.footnote1,
                    );
                  }
                  return Text(
                    formatBytes(bytes.round()),
                    style: theme.textStyles.footnote1,
                  );
                },
              ),
              if (_progress!.speedBytesPerSec > 0) ...[
                const SizedBox(height: 2),
                Text(
                  _speedLine(_progress!),
                  style: theme.textStyles.footnote1.copyWith(
                    color: cs.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ],
            if (_stage.isNotEmpty && _progress == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: MiuixInfiniteProgressIndicator(size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(_stage),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(
          children: [
            if (_done || _error != null)
              MiuixButton(
                onPressed: () => Navigator.of(context).pop(),
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText(context.tr('common.close')),
              ),
          ],
        ),
      ],
    );
  }

  String _speedLine(DownloadProgress p) {
    final speed = formatSpeed(p.speedBytesPerSec);
    if (speed.isEmpty) return '';
    final eta = formatEta(p.etaMs);
    return eta.isEmpty ? speed : '$speed · $eta';
  }
}

// ── 安装对话框（下载+安装进度）───────────────────────────────────────

class _InstallDialog extends StatefulWidget {
  const _InstallDialog({
    required this.pkgName,
    required this.pkgVersion,
    required this.entry,
    required this.downloadUrl,
  });

  final String pkgName;
  final String pkgVersion;
  final EcpkgDownloadEntry entry;
  final EcpkgDownloadUrl downloadUrl;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  static const _service = RuntimeService();
  bool _done = false;
  String? _error;
  DownloadProgress? _progress;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    // _start() 内会调用 context.tr（经 LocaleScope.of 依赖 inherited widget），
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误，导致下载流程未启动、
    // 对话框卡死无进度。改用 post-frame 回调延迟到 initState 完成后再启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final tr = context.tr;

    setState(() {
      _stage = tr('runtime.update.downloading');
      _progress = null;
    });

    try {
      final dlPkg = RuntimeUpdatePackage(
        key: widget.entry.key,
        url: widget.downloadUrl.url,
        sha256: widget.entry.sha256,
        size: widget.entry.size,
        arch: widget.entry.arch,
      );

      final path = await RuntimeUpdateService.downloadPackage(
        dlPkg,
        onProgress: (progress) {
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;

      setState(() {
        _stage = tr('runtime.update.installing');
        _progress = null;
      });

      // 安装前验证签名
      final sigResult = await _service.verifyEcpkgSignature(path);
      if (!await _confirmSignature(sigResult)) {
        // 用户拒绝或严格模式下拒绝，中止安装
        return;
      }

      await _service.importPackage(path, force: true);
      if (!mounted) return;

      setState(() {
        _done = true;
        _stage = '';
      });
    } on HashMismatchException {
      if (!mounted) return;
      setState(() {
        _error = tr('update.sha256Mismatch');
      });
    } on CancellationException {
      if (!mounted) return;
      setState(() {
        _error = tr('runtime.update.cancelled');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    }
  }

  /// 验证包签名，根据验证模式和开发者选项决定是否允许安装。
  ///
  /// 返回 `true` 表示可以继续安装（签名有效，或警告模式下用户确认继续）；
  /// 返回 `false` 表示应中止安装（严格模式拒绝，或用户取消）。
  Future<bool> _confirmSignature(SignatureVerifyResult result) async {
    if (result.isTrusted) return true;

    final tr = context.tr;
    final devMode = await DeveloperOptionsStore.loadEnabled();

    if (!devMode) {
      // 严格模式：拒绝安装
      if (!mounted) return false;
      setState(() {
        _error = result.hasSignature
            ? tr('runtime.signature.invalid')
            : tr('runtime.signature.noSignature');
      });
      return false;
    }

    // 警告模式：提示用户选择
    if (!mounted) return false;
    final confirmed = await showMiuixConfirm(
      context,
      title: tr('runtime.signature.warningTitle'),
      message: result.hasSignature
          ? tr('runtime.signature.warningInvalid')
          : tr('runtime.signature.warningNoSig'),
      cancelLabel: tr('common.cancel'),
      confirmLabel: tr('runtime.signature.continueAnyway'),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final cs = theme.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _done
                    ? context.tr('ecpkgDownload.installSuccess')
                    : _error != null
                    ? context.tr('runtime.update.failedTitle')
                    : context.tr('ecpkgDownload.confirmTitle'),
              ),
            ),
            if (_done) Icon(Icons.check_circle, color: cs.primary, size: 24),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.pkgName} ${widget.pkgVersion}'),
            if (_progress != null && _stage.isNotEmpty) ...[
              const SizedBox(height: 12),
              _progress!.hasTotal
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: _progress!.fraction,
                        end: _progress!.fraction,
                      ),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.linear,
                      builder: (context, value, _) =>
                          LinearProgressIndicator(value: value),
                    )
                  : const LinearProgressIndicator(),
              TweenAnimationBuilder<double>(
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
                      style: theme.textStyles.footnote1,
                    );
                  }
                  return Text(
                    formatBytes(bytes.round()),
                    style: theme.textStyles.footnote1,
                  );
                },
              ),
              if (_progress!.speedBytesPerSec > 0) ...[
                const SizedBox(height: 2),
                Text(
                  _speedLine(_progress!),
                  style: theme.textStyles.footnote1.copyWith(
                    color: cs.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ],
            if (_stage.isNotEmpty && _progress == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: MiuixInfiniteProgressIndicator(size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(_stage),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(
          children: [
            if (_done || _error != null)
              MiuixButton(
                onPressed: () => Navigator.of(context).pop(),
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText(context.tr('common.close')),
              ),
          ],
        ),
      ],
    );
  }

  String _speedLine(DownloadProgress p) {
    final speed = formatSpeed(p.speedBytesPerSec);
    if (speed.isEmpty) return '';
    final eta = formatEta(p.etaMs);
    return eta.isEmpty ? speed : '$speed · $eta';
  }
}

// ── 下载源选择对话框 ──────────────────────────────────────────────────

class _DownloadSourceDialog extends StatefulWidget {
  const _DownloadSourceDialog({required this.urls, required this.initialIndex});

  final List<EcpkgDownloadUrl> urls;
  final int initialIndex;

  @override
  State<_DownloadSourceDialog> createState() => _DownloadSourceDialogState();
}

class _DownloadSourceDialogState extends State<_DownloadSourceDialog> {
  late int _selected = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final tr = context.tr;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: MiuixText(
            tr('ecpkgDownload.selectSource'),
            textAlign: TextAlign.center,
            style: MiuixTheme.of(context).textStyles.title4,
          ),
        ),
        const SizedBox(height: 12),
        RadioGroup<int>(
          groupValue: _selected,
          onChanged: (v) {
            if (v != null) setState(() => _selected = v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.urls.length; i++) ...[
                if (i > 0) const MiuixHorizontalDivider(),
                RadioListTile<int>(
                  value: i,
                  title: Text(
                    widget.urls[i].name.isEmpty
                        ? widget.urls[i].url
                        : widget.urls[i].name,
                  ),
                  subtitle: widget.urls[i].extra.isEmpty
                      ? null
                      : Text(
                          widget.urls[i].extra,
                          style: theme.textStyles.footnote1,
                        ),
                  secondary: Icon(
                    widget.urls[i].isDirect
                        ? Icons.cloud_download
                        : Icons.open_in_browser,
                    size: 22,
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(
          children: [
            MiuixTextButton(
              tr('common.cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            MiuixButton(
              onPressed: () =>
                  Navigator.of(context).pop(widget.urls[_selected]),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(tr('ecpkgDownload.download')),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryView extends StatelessWidget {
  const _CategoryView({
    required this.category,
    required this.typeIcon,
    required this.onDownloadAndInstall,
    required this.onDownloadOnly,
  });

  final EcpkgCategory category;
  final IconData typeIcon;
  final void Function(EcpkgCatalogPackage pkg) onDownloadAndInstall;
  final void Function(EcpkgCatalogPackage pkg) onDownloadOnly;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final tr = context.tr;
    final packages = category.packages;

    if (packages.isEmpty) {
      return Center(child: Text(tr('ecpkgDownload.noPackages')));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: packages.length,
      itemBuilder: (_, i) {
        final pkg = packages[i];
        final versionStr = tr('runtime.versionWithBuild', {
          'version': pkg.detail.version,
          'build': pkg.detail.buildVersion.toString(),
        });

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MiuixCard(
            insideMargin: const EdgeInsets.all(16),
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
                            style: theme.textStyles.title4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            versionStr,
                            style: theme.textStyles.footnote1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      style: theme.textStyles.footnote1,
                    ),
                  ),
                if (pkg.author != null && pkg.author!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('ecpkgDownload.author', {'author': pkg.author!}),
                      style: theme.textStyles.footnote1,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: MiuixButton(
                        onPressed: () => onDownloadAndInstall(pkg),
                        colors: MiuixButtonDefaults.buttonColorsPrimary(
                          context,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MiuixIcon(
                              icon: Icons.download_for_offline,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            MiuixText(tr('ecpkgDownload.downloadAndInstall')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    MiuixOverlayIconDropdownMenu(
                      entry: MiuixDropdownEntry(
                        items: [
                          MiuixDropdownItem(
                            text: tr('ecpkgDownload.downloadOnly'),
                            onClick: () => onDownloadOnly(pkg),
                          ),
                          if (pkg.homepage != null && pkg.homepage!.isNotEmpty)
                            MiuixDropdownItem(
                              text: tr('runtime.openHomepage'),
                              onClick: () => launchUrl(
                                Uri.parse(pkg.homepage!),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          if (pkg.repository != null &&
                              pkg.repository!.isNotEmpty)
                            MiuixDropdownItem(
                              text: tr('runtime.openRepository'),
                              onClick: () => launchUrl(
                                Uri.parse(pkg.repository!),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                        ],
                      ),
                      child: const MiuixIcon(icon: Icons.more_vert),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: theme.colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('ecpkgDownload.loadFailed'),
              style: theme.textStyles.title4,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(height: 24),
            MiuixButton(
              onPressed: onRetry,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiuixIcon(icon: Icons.refresh),
                  const SizedBox(width: 8),
                  MiuixText(context.tr('common.retry')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
