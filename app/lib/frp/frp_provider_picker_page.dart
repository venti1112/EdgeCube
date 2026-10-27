import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 「添加隧道」的平台选择页。
///
/// 平台清单来自 daemon（`frp.providers`），本页只负责挑一个：
///
/// * 自定义 FRP → 自定义配置页；
/// * 其它平台 → 先问一次本地登录态（`frp.account`，不联网）：**令牌非空且
///   账号名非空**就直接进隧道管理页，否则去登录页。
class FrpProviderPickerPage extends ConsumerWidget {
  const FrpProviderPickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(frpProvidersProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择映射平台'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: providers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(describeFrpError(error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(frpProvidersProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final provider in list) ...[
              _ProviderTile(provider: provider),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProviderTile extends ConsumerStatefulWidget {
  const _ProviderTile({required this.provider});

  final FrpProvider provider;

  @override
  ConsumerState<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends ConsumerState<_ProviderTile> {
  bool _checking = false;

  FrpProvider get _provider => widget.provider;

  Future<void> _onTap() async {
    if (_provider.isCustom) {
      context.push('/manage/network/tunnels/custom');
      return;
    }
    final api = ref.read(frpApiProvider);
    if (api == null) {
      showSnack(context, '还没有连接到守护进程');
      return;
    }
    setState(() => _checking = true);
    try {
      final status = await api.account(_provider.key);
      if (!mounted) return;
      context.push(
        status.canSkipLogin
            ? '/manage/network/tunnels/provider/${_provider.key}'
            : '/manage/network/tunnels/login/${_provider.key}',
      );
    } on DaemonException catch (error) {
      if (mounted) await showErrorDialog(context, describeFrpError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: !_checking,
        onTap: _checking ? null : _onTap,
        leading: Icon(
          _provider.isCustom ? Icons.edit_note : Icons.cloud_outlined,
          size: 36,
          color: scheme.primary,
        ),
        title: Text(_provider.displayName),
        subtitle: Text(_provider.subtitle),
        trailing: _checking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}
