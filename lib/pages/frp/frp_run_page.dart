import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../tunnel/tunnel_service.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/ec_preference.dart';
import '../../widgets/miuix_snackbar.dart';

/// 单隧道运行页：启停开关 + 公网地址复制 + 实时 frpc 日志。
class FrpRunPage extends StatefulWidget {
  const FrpRunPage({super.key, required this.tunnel});

  final SavedFrpTunnel tunnel;

  @override
  State<FrpRunPage> createState() => _FrpRunPageState();
}

class _FrpRunPageState extends State<FrpRunPage> {
  final _tunnelService = TunnelService();
  final List<String> _logs = [];
  final _logScroll = ScrollController();
  StreamSubscription<TunnelEvent>? _sub;
  String? _status;
  int? _exitCode;

  @override
  void initState() {
    super.initState();
    _sub = _tunnelService.events().listen((e) {
      if (!mounted) return;
      if (e is TunnelLogEvent) {
        setState(() {
          _logs.add(e.line);
          if (_logs.length > 2000) _logs.removeRange(0, _logs.length - 2000);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      } else if (e is TunnelStateEvent) {
        setState(() {
          if (e.status != null) {
            _status = e.status;
            _exitCode = null;
          } else if (e.exitCode != null) {
            _status = null;
            _exitCode = e.exitCode;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  /// 本隧道是否在运行：独立运行或作为默认隧道随服务端自动运行。
  bool get _isThisRunning {
    final frp = FrpScope.of(context);
    return frp.runningLocalId == widget.tunnel.localId ||
        frp.autoRunningLocalId == widget.tunnel.localId;
  }

  Future<void> _toggle(bool value) async {
    final frp = FrpScope.of(context);
    final trans = LocaleScope.of(context).translations;
    if (!value) {
      if (frp.autoRunningLocalId == widget.tunnel.localId) {
        // 本隧道正以自动隧道身份随服务端运行：走自动隧道停止通路。
        frp.stopAutoTunnel();
      } else if (_isThisRunning) {
        frp.stop();
      }
      return;
    }
    try {
      await frp.run(widget.tunnel);
    } on StateError catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        e.message == 'auto-active'
            ? trans.get('frp.occupiedByAuto')
            : trans.get('frp.occupiedByStandalone'),
      );
    } on FrpApiException catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        e.message == 'frpc-runtime-missing'
            ? trans.get('portMapping.frpcRequiredContent')
            : trans.get('frp.startFailed', {'error': e.message}),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, trans.get('frp.startFailed', {'error': '$e'}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final frp = FrpScope.of(context);
    final tunnel = widget.tunnel;
    final running = _isThisRunning;
    final starting = frp.startingLocalId == tunnel.localId;
    final providerName = tunnel.provider == FrpProvider.custom
        ? context.tr('frp.provider.custom')
        : tunnel.provider.displayName;
    final address = tunnel.displayAddress;

    final String? statusText;
    Color statusColor = theme.colors.onTertiaryContainer;
    if (running && _status == 'running') {
      statusText = context.tr('portMapping.tunnelRunning');
      statusColor = theme.colors.primary;
    } else if (starting || (running && _status != null)) {
      statusText = context.tr('portMapping.tunnelConnecting');
    } else if (_exitCode != null && _exitCode != 0) {
      statusText = context.tr('portMapping.tunnelExitedWithError', {
        'code': '$_exitCode',
      });
      statusColor = theme.colors.error;
    } else {
      statusText = null;
    }

    return MiuixScaffold(
      topBar: EcTopAppBar(title: tunnel.name),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MiuixCard(
                insideMargin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_outlined,
                            size: 20,
                            color: theme.colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$providerName · ${tunnel.type.toUpperCase()}',
                              style: theme.textStyles.subtitle.copyWith(
                                color: theme.colors.primary,
                              ),
                            ),
                          ),
                          if (statusText != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusText,
                                style: theme.textStyles.footnote2.copyWith(
                                  color: statusColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    MiuixSwitchPreference(
                      title: context.tr('frp.runTunnel'),
                      summary: context.tr('frp.runTunnelSubtitle'),
                      value: running || starting,
                      enabled: !starting,
                      onChanged: _toggle,
                    ),
                    if (address.isNotEmpty)
                      MiuixBasicComponent(
                        insideMargin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        startAction: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: MiuixIcon(icon: Icons.link, size: 20),
                        ),
                        title: address,
                        endActions: [
                          MiuixIconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: address));
                              showMiuixSnackbar(
                                context.tr('frp.addressCopied'),
                              );
                            },
                            child: const MiuixIcon(icon: Icons.copy, size: 18),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    context.tr('portMapping.tunnelLog'),
                    style: theme.textStyles.subtitle.copyWith(
                      color: theme.colors.primary,
                    ),
                  ),
                  const Spacer(),
                  MiuixIconButton(
                    onPressed: () {
                      _tunnelService.clearLog();
                      setState(() => _logs.clear());
                    },
                    child: MiuixIcon(
                      icon: Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                  ),
                ],
              ),
              Container(
                height: 280,
                decoration: BoxDecoration(
                  color: theme.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: _logs.isEmpty
                    ? Center(
                        child: Text(
                          context.tr('portMapping.noLogs'),
                          style: theme.textStyles.footnote1.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _logScroll,
                        padding: EdgeInsets.zero,
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Text(
                          _logs[i],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
