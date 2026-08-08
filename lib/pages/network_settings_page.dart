import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/download_store.dart';
import '../config/network_store.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/error_dialog.dart';
import '../widgets/miuix_dialog.dart';
import '../net/download_engine.dart';
import '../net/msl_mirror.dart';
import '../online/online_service.dart';
import '../server/proot_service.dart';

/// 网络设置页面：镜像源、自定义 DNS、更新检查与运行环境下载地址。
///
/// 开启镜像源后，新建实例下载服务端时优先通过 MSL 镜像源加速；
/// 镜像不可用时自动回退官方源。
class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  bool _useMirror = false;
  bool _loaded = false;

  final _dnsController = TextEditingController();
  String _dnsOriginal = '';
  bool _dnsLoaded = false;

  bool _enableBetaUpdates = true;
  bool _betaLoaded = false;

  String _updateCheckUrl = '';
  bool _updateCheckLoaded = false;
  bool _updateCheckIsCustom = false;

  String _ecpkgCatalogUrl = '';
  bool _ecpkgCatalogLoaded = false;
  bool _ecpkgCatalogIsCustom = false;

  int _maxParallel = DownloadStore.defaultMaxParallel;
  int _targetChunkCount = DownloadStore.defaultTargetChunkCount;
  int _minChunkSizeMiB = 1;
  int _requestTimeoutSec = 30;
  int _speedLimitKiBps = 0;
  bool _downloadLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDns();
    _loadBetaUpdates();
    _loadUpdateCheckUrl();
    _loadEcpkgCatalogUrl();
    _loadDownloadSettings();
  }

  Future<void> _load() async {
    final v = await NetworkStore.loadUseMirror();
    if (!mounted) return;
    setState(() {
      _useMirror = v;
      _loaded = true;
    });
  }

  Future<void> _onToggle(bool value) async {
    setState(() => _useMirror = value);
    await NetworkStore.saveUseMirror(value);
  }

  Future<void> _loadDns() async {
    final v = await NetworkStore.loadCustomDns();
    if (!mounted) return;
    setState(() {
      _dnsController.text = v;
      _dnsOriginal = v;
      _dnsLoaded = true;
    });
  }

  /// 校验 DNS 字符串：逗号分隔的 IP 地址，至少一个有效项。
  bool _validateDns(String text) {
    final parts = text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final ips = parts.toList();
    if (ips.isEmpty) return false;
    final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
    for (final ip in ips) {
      if (!ipv4.hasMatch(ip) && !ipv6.hasMatch(ip)) return false;
    }
    return true;
  }

  Future<void> _saveDns() async {
    final text = _dnsController.text.trim();
    if (!_validateDns(text)) {
      showErrorDialog(context, context.tr('network.dnsInvalid'));
      return;
    }
    await NetworkStore.saveCustomDns(text);
    // 立即同步到所有 proot rootfs 的 /etc/resolv.conf
    try {
      await const ProotService().updateProotDns();
    } catch (_) {}
    setState(() => _dnsOriginal = text);
  }

  Future<void> _resetDns() async {
    const defaults = '8.8.8.8,1.1.1.1';
    _dnsController.text = defaults;
    await NetworkStore.saveCustomDns(defaults);
    // 立即同步到所有 proot rootfs 的 /etc/resolv.conf
    try {
      await const ProotService().updateProotDns();
    } catch (_) {}
    setState(() => _dnsOriginal = defaults);
  }

  // ── 测试版更新 ──

  Future<void> _loadBetaUpdates() async {
    final value = await NetworkStore.loadBetaUpdates();
    if (!mounted) return;
    setState(() {
      _enableBetaUpdates = value;
      _betaLoaded = true;
    });
  }

  Future<void> _saveBetaUpdates(bool value) async {
    setState(() => _enableBetaUpdates = value);
    await NetworkStore.saveBetaUpdates(value);
  }

  // ── 更新检查地址 ──

  Future<void> _loadUpdateCheckUrl() async {
    final urls = await NetworkStore.loadUpdateCheckUrls();
    if (!mounted) return;
    setState(() {
      _updateCheckIsCustom = urls.isNotEmpty;
      _updateCheckUrl = urls.isNotEmpty
          ? urls.first
          : OnlineService.defaultUpdateCheckUrls.first;
      _updateCheckLoaded = true;
    });
  }

  Future<void> _saveUpdateCheckUrl(String? url) async {
    if (url != null && url.isNotEmpty) {
      await NetworkStore.saveUpdateCheckUrls([url]);
    } else {
      await NetworkStore.saveUpdateCheckUrls([]);
    }
    await _loadUpdateCheckUrl();
  }

  // ── 运行环境下载地址 ──

  Future<void> _loadEcpkgCatalogUrl() async {
    final urls = await NetworkStore.loadEcpkgCatalogUrls();
    if (!mounted) return;
    setState(() {
      _ecpkgCatalogIsCustom = urls.isNotEmpty;
      _ecpkgCatalogUrl = urls.isNotEmpty
          ? urls.first
          : OnlineService.defaultEcpkgCatalogUrls.first;
      _ecpkgCatalogLoaded = true;
    });
  }

  Future<void> _saveEcpkgCatalogUrl(String? url) async {
    if (url != null && url.isNotEmpty) {
      await NetworkStore.saveEcpkgCatalogUrls([url]);
    } else {
      await NetworkStore.saveEcpkgCatalogUrls([]);
    }
    await _loadEcpkgCatalogUrl();
  }

  // ── 下载设置 ──

  Future<void> _loadDownloadSettings() async {
    final results = await Future.wait([
      DownloadStore.loadMaxParallel(),
      DownloadStore.loadTargetChunkCount(),
      DownloadStore.loadMinChunkSize(),
      DownloadStore.loadRequestTimeout(),
      DownloadStore.loadSpeedLimit(),
    ]);
    if (!mounted) return;
    setState(() {
      _maxParallel = results[0];
      _targetChunkCount = results[1];
      _minChunkSizeMiB = (results[2] ~/ (1024 * 1024)).clamp(1, 16);
      _requestTimeoutSec = (results[3] ~/ 1000).clamp(1, 300);
      _speedLimitKiBps = results[4] ~/ 1024;
      _downloadLoaded = true;
    });
  }

  Future<void> _saveMaxParallel(int value) async {
    setState(() => _maxParallel = value);
    await DownloadStore.saveMaxParallel(value);
    await DownloadEngine.instance.applyMaxParallel(value);
  }

  Future<void> _saveTargetChunkCount(int value) async {
    setState(() => _targetChunkCount = value);
    await DownloadStore.saveTargetChunkCount(value);
    await DownloadEngine.instance.applyTargetChunkCount(value);
  }

  Future<void> _saveMinChunkSize(int mib) async {
    setState(() => _minChunkSizeMiB = mib);
    final bytes = mib * 1024 * 1024;
    await DownloadStore.saveMinChunkSize(bytes);
    await DownloadEngine.instance.applyMinChunkSize(bytes);
  }

  Future<void> _saveSpeedLimit(int kibps) async {
    setState(() => _speedLimitKiBps = kibps);
    final bytes = kibps * 1024;
    await DownloadStore.saveSpeedLimit(bytes);
    await DownloadEngine.instance.applySpeedLimit(bytes);
  }

  Future<void> _saveRequestTimeout(int sec) async {
    setState(() => _requestTimeoutSec = sec);
    await DownloadStore.saveRequestTimeout(sec * 1000);
    // requestTimeout 无运行时 setter，仅重启后生效。
  }

  // ── URL 编辑对话框 ──

  Future<void> _editUrl({
    required String title,
    required String hint,
    required String currentValue,
    required Future<void> Function(String value) onSave,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showMiuixDialog<String>(
      context: context,
      title: title,
      builder: (ctx) {
        final theme = MiuixTheme.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixText(
              ctx.tr('network.urlEditHint'),
              style: theme.textStyles.footnote1,
              color: theme.colors.error,
            ),
            const SizedBox(height: 12),
            EcTextField(
              controller: controller,
              label: hint,
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 20),
            MiuixDialogActions(
              children: [
                MiuixTextButton(
                  ctx.tr('common.cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                MiuixButton(
                  onPressed: () => Navigator.of(ctx).pop(controller.text),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
                  child: MiuixText(ctx.tr('common.save')),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null && result != currentValue) {
      await onSave(result);
    }
  }

  // ── 数值编辑对话框（下载参数） ──

  Future<void> _editNumber({
    required String title,
    required int currentValue,
    String suffix = '',
    String? zeroLabel,
    int min = 0,
    int max = 0,
    required Future<void> Function(int value) onSave,
  }) async {
    final controller = TextEditingController(text: '$currentValue');
    final result = await showMiuixDialog<String>(
      context: context,
      title: title,
      builder: (ctx) {
        final theme = MiuixTheme.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (zeroLabel != null)
              MiuixText(
                ctx.tr('network.downloadNumberHint', {'zero': zeroLabel}),
                style: theme.textStyles.footnote1,
                color: theme.colors.onSurfaceVariantSummary,
              ),
            const SizedBox(height: 12),
            EcTextField(
              controller: controller,
              label: suffix,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            MiuixDialogActions(
              children: [
                MiuixTextButton(
                  ctx.tr('common.cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                MiuixButton(
                  onPressed: () => Navigator.of(ctx).pop(controller.text),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
                  child: MiuixText(ctx.tr('common.save')),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    final v = int.tryParse(result.trim());
    if (v == null) return;
    final clamped = (max > min) ? v.clamp(min, max) : (v < min ? min : v);
    if (clamped != currentValue) await onSave(clamped);
  }

  @override
  void dispose() {
    _dnsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);

    return EcSettingsPage(
      title: context.tr('network.title'),
      children: [
        MiuixSmallTitle(context.tr('network.downloadSource')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.cloud_sync_outlined),
          title: context.tr('network.useMirror'),
          summary: context.tr('network.useMirrorDesc'),
          value: _useMirror,
          enabled: _loaded,
          onChanged: _onToggle,
        ),

        MiuixSmallTitle(context.tr('network.downloadSection')),
        MiuixSliderPreference(
          startAction: prefIcon(Icons.sync_alt),
          title: context.tr('network.downloadMaxParallel'),
          summary: context.tr('network.downloadMaxParallelDesc'),
          value: _maxParallel.toDouble(),
          valueText: '$_maxParallel',
          min: 1,
          max: 16,
          steps: 15,
          enabled: _downloadLoaded,
          onValueChange: (v) => setState(() => _maxParallel = v.round()),
          onValueChangeFinished: () => _saveMaxParallel(_maxParallel),
        ),
        MiuixSliderPreference(
          startAction: prefIcon(Icons.grain),
          title: context.tr('network.downloadTargetChunkCount'),
          summary: context.tr('network.downloadTargetChunkCountDesc'),
          value: _targetChunkCount.toDouble(),
          valueText: '$_targetChunkCount',
          min: 1,
          max: 8,
          steps: 7,
          enabled: _downloadLoaded,
          onValueChange: (v) => setState(() => _targetChunkCount = v.round()),
          onValueChangeFinished: () => _saveTargetChunkCount(_targetChunkCount),
        ),
        MiuixSliderPreference(
          startAction: prefIcon(Icons.straighten),
          title: context.tr('network.downloadMinChunkSize'),
          summary: context.tr('network.downloadMinChunkSizeDesc'),
          value: _minChunkSizeMiB.toDouble(),
          valueText: '$_minChunkSizeMiB MiB',
          min: 1,
          max: 16,
          steps: 15,
          enabled: _downloadLoaded,
          onValueChange: (v) => setState(() => _minChunkSizeMiB = v.round()),
          onValueChangeFinished: () => _saveMinChunkSize(_minChunkSizeMiB),
        ),
        MiuixBasicComponent(
          startAction: prefIcon(Icons.speed),
          title: context.tr('network.downloadSpeedLimit'),
          summary: _downloadLoaded
              ? (_speedLimitKiBps == 0
                  ? context.tr('network.downloadUnlimited')
                  : '$_speedLimitKiBps KiB/s')
              : context.tr('common.loading'),
          enabled: _downloadLoaded,
          endActions: [const MiuixIcon(icon: Icons.edit_outlined, size: 18)],
          onClick: _downloadLoaded
              ? () => _editNumber(
                    title: context.tr('network.downloadSpeedLimit'),
                    currentValue: _speedLimitKiBps,
                    suffix: 'KiB/s',
                    zeroLabel: context.tr('network.downloadUnlimited'),
                    onSave: _saveSpeedLimit,
                  )
              : null,
        ),
        MiuixBasicComponent(
          startAction: prefIcon(Icons.timer_outlined),
          title: context.tr('network.downloadRequestTimeout'),
          summary: _downloadLoaded
              ? '$_requestTimeoutSec s · ${context.tr('network.downloadRequestTimeoutDesc')}'
              : context.tr('common.loading'),
          enabled: _downloadLoaded,
          endActions: [const MiuixIcon(icon: Icons.edit_outlined, size: 18)],
          onClick: _downloadLoaded
              ? () => _editNumber(
                    title: context.tr('network.downloadRequestTimeout'),
                    currentValue: _requestTimeoutSec,
                    suffix: 's',
                    min: 1,
                    max: 300,
                    onSave: _saveRequestTimeout,
                  )
              : null,
        ),

        MiuixSmallTitle(context.tr('network.dns')),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
          child: MiuixText(
            context.tr('network.dnsDesc'),
            style: theme.textStyles.footnote1,
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: EcTextField(
                  controller: _dnsController,
                  label: context.tr('network.dns'),
                  hint: context.tr('network.dnsHint'),
                  enabled: _dnsLoaded,
                  prefixIcon: prefIcon(Icons.dns_outlined),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              MiuixButton(
                enabled:
                    _dnsLoaded && _dnsController.text.trim() != _dnsOriginal,
                onPressed:
                    (_dnsLoaded && _dnsController.text.trim() != _dnsOriginal)
                    ? _saveDns
                    : null,
                child: MiuixText(context.tr('common.save')),
              ),
            ],
          ),
        ),
        if (_dnsLoaded && _dnsController.text.trim() != '8.8.8.8,1.1.1.1')
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MiuixTextButton(
                context.tr('network.dnsReset'),
                onPressed: _resetDns,
              ),
            ),
          ),

        MiuixSmallTitle(context.tr('network.updateSection')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.science_outlined),
          title: context.tr('settings.enableBetaUpdates'),
          summary: context.tr('settings.enableBetaUpdatesDesc'),
          value: _enableBetaUpdates,
          enabled: _betaLoaded,
          onChanged: _saveBetaUpdates,
        ),
        _urlPreference(
          icon: Icons.system_update_outlined,
          title: context.tr('network.updateCheckUrl'),
          loaded: _updateCheckLoaded,
          isCustom: _updateCheckIsCustom,
          value: _updateCheckUrl,
          onClear: () => _saveUpdateCheckUrl(null),
          onEdit: () => _editUrl(
            title: context.tr('network.updateCheckUrl'),
            hint: 'URL',
            currentValue: _updateCheckUrl,
            onSave: (v) => _saveUpdateCheckUrl(v),
          ),
        ),
        _urlPreference(
          icon: Icons.download_outlined,
          title: context.tr('network.ecpkgCatalogUrl'),
          loaded: _ecpkgCatalogLoaded,
          isCustom: _ecpkgCatalogIsCustom,
          value: _ecpkgCatalogUrl,
          onClear: () => _saveEcpkgCatalogUrl(null),
          onEdit: () => _editUrl(
            title: context.tr('network.ecpkgCatalogUrl'),
            hint: 'URL',
            currentValue: _ecpkgCatalogUrl,
            onSave: (v) => _saveEcpkgCatalogUrl(v),
          ),
        ),

        MiuixSmallTitle(context.tr('network.aboutMirror')),
        MiuixBasicComponent(
          startAction: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/msl_logo.png',
                width: 40,
                height: 40,
              ),
            ),
          ),
          title: context.tr('network.mirrorByMsl'),
          summary: context.tr('network.mirrorSite'),
          endActions: [const MiuixIcon(icon: Icons.open_in_new, size: 18)],
          onClick: () => launchUrl(
            Uri.parse(MslMirror.officialSite),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    );
  }

  /// 可自定义 URL 的设置行：未自定义时显示「使用默认」，自定义后额外给一个清除按钮。
  Widget _urlPreference({
    required IconData icon,
    required String title,
    required bool loaded,
    required bool isCustom,
    required String value,
    required VoidCallback onClear,
    required VoidCallback onEdit,
  }) {
    return MiuixBasicComponent(
      startAction: prefIcon(icon),
      title: title,
      summary: loaded
          ? (isCustom ? value : context.tr('network.useDefaultUrl'))
          : context.tr('common.loading'),
      enabled: loaded,
      endActions: [
        if (isCustom)
          MiuixIconButton(
            onPressed: onClear,
            child: const MiuixIcon(icon: Icons.clear, size: 18),
          ),
        const MiuixIcon(icon: Icons.edit_outlined, size: 18),
      ],
      onClick: loaded ? onEdit : null,
    );
  }
}
