import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 一条隧道的 frpc 配置页：看 / 复制 / 重新生成
/// `config/frp/toml/<localId>.toml`。
///
/// 本期不做 frpc 的下载与启动，所以生成配置本身成了终点的动作，
/// 单独给一页看结果，顺带说明文件落在守护进程那台机器上。
class FrpTunnelConfigPage extends ConsumerStatefulWidget {
  const FrpTunnelConfigPage({super.key, required this.localId});

  final String localId;

  @override
  ConsumerState<FrpTunnelConfigPage> createState() =>
      _FrpTunnelConfigPageState();
}

class _FrpTunnelConfigPageState extends ConsumerState<FrpTunnelConfigPage> {
  FrpTunnelConfig? _config;
  String? _error;
  bool _loading = true;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final api = ref.read(frpApiProvider);
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '还没有连接到守护进程';
      });
      return;
    }
    setState(() {
      if (refresh) {
        _regenerating = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final config = await api.tunnelConfig(
        widget.localId,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() => _config = config);
    } on DaemonException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeFrpError(error));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _regenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _tunnelName();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(name.isEmpty ? '映射配置' : name),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '重新生成',
            onPressed: _regenerating || _loading
                ? null
                : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: () => _load(),
                        child: const Text('重试'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_config != null) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      // 显示盘上那个文件自己的名字：`toml/<localId>.toml`
                      title: Text(_fileName(_config!.path)),
                      subtitle: Text(
                        _config!.path,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        tooltip: '复制',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _config!.config),
                          );
                          showSnack(context, '配置已复制');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _config!.generated
                        ? '已生成并写入守护进程的磁盘：'
                        : '读取的是已生成的配置（点右上角可重新生成）：',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _config!.config,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  /// 隧道名从本地列表里找（找不到就只显示「映射配置」）。
  String _tunnelName() {
    for (final tunnel in ref.watch(frpTunnelsProvider).value ??
        const <FrpSavedTunnel>[]) {
      if (tunnel.localId == widget.localId) return tunnel.name;
    }
    return '';
  }

  /// 路径最后一段（守护进程在 Windows 上时是 `\`，两种分隔符都认）。
  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;
}
