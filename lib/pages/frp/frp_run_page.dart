import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../tunnel/tunnel_service.dart';
import '../../widgets/error_dialog.dart';

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
    final theme = Theme.of(context);
    final frp = FrpScope.of(context);
    final tunnel = widget.tunnel;
    final running = _isThisRunning;
    final starting = frp.startingLocalId == tunnel.localId;
    final providerName = tunnel.provider == FrpProvider.custom
        ? context.tr('frp.provider.custom')
        : tunnel.provider.displayName;
    final address = tunnel.displayAddress;

    final String? statusText;
    Color statusColor = theme.colorScheme.tertiary;
    if (running && _status == 'running') {
      statusText = context.tr('portMapping.tunnelRunning');
      statusColor = theme.colorScheme.primary;
    } else if (starting || (running && _status != null)) {
      statusText = context.tr('portMapping.tunnelConnecting');
    } else if (_exitCode != null && _exitCode != 0) {
      statusText = context.tr('portMapping.tunnelExitedWithError', {
        'code': '$_exitCode',
      });
      statusColor = theme.colorScheme.error;
    } else {
      statusText = null;
    }

    return Scaffold(
      appBar: AppBar(title: Text(tunnel.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$providerName · ${tunnel.type.toUpperCase()}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
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
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: statusColor),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: Text(context.tr('frp.runTunnel')),
                      subtitle: Text(context.tr('frp.runTunnelSubtitle')),
                      value: running || starting,
                      onChanged: starting ? null : _toggle,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    if (address.isNotEmpty)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.link, size: 20),
                        title: Text(
                          address,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: context.tr('frp.copyAddress'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: address));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(context.tr('frp.addressCopied')),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  context.tr('portMapping.tunnelLog'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  tooltip: context.tr('portMapping.clearLog'),
                  onPressed: () {
                    _tunnelService.clearLog();
                    setState(() => _logs.clear());
                  },
                ),
              ],
            ),
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: _logs.isEmpty
                  ? Center(
                      child: Text(
                        context.tr('portMapping.noLogs'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScroll,
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
    );
  }
}
