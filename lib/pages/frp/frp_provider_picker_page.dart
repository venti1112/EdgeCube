import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../frp/frp_provider.dart';
import '../../frp/frp_provider_service.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/ec_preference.dart';
import 'frp_custom_config_page.dart';
import 'frp_provider_login_page.dart';
import 'frp_provider_tunnels_page.dart';

/// 「添加隧道」供应商选择页。
class FrpProviderPickerPage extends StatelessWidget {
  const FrpProviderPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: context.tr('frp.pickProvider'),
        navigationIcon: const EcBackButton(),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final provider in FrpProvider.values) ...[
                _ProviderTile(provider: provider, theme: theme),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatefulWidget {
  const _ProviderTile({required this.provider, required this.theme});

  final FrpProvider provider;
  final MiuixThemeData theme;

  @override
  State<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<_ProviderTile> {
  bool _checking = false;

  FrpProvider get _provider => widget.provider;
  MiuixThemeData get _theme => widget.theme;

  Future<void> _onTap() async {
    if (_provider == FrpProvider.custom) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const FrpCustomConfigPage()));
      return;
    }
    // 已登录（本地有 token + 缓存账号）：直接进操作页，跳过登录页。
    setState(() => _checking = true);
    try {
      final token = await FrpProviderService.savedToken(_provider);
      final account = await FrpProviderService.savedAccount(_provider);
      if (!mounted) return;
      if (token != null &&
          token.isNotEmpty &&
          account != null &&
          account.username.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FrpProviderTunnelsPage(
              provider: _provider,
              token: token,
              account: account,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FrpProviderLoginPage(provider: _provider),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = _provider == FrpProvider.custom;
    final name = isCustom
        ? context.tr('frp.provider.custom')
        : _provider.displayName;
    final subtitle = context.tr('frp.provider.${_provider.key}.subtitle');
    return MiuixCard(
      insideMargin: EdgeInsets.zero,
      child: MiuixArrowPreference(
        startAction: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: MiuixIcon(
            icon: isCustom ? Icons.edit_note : Icons.cloud_outlined,
            size: 36,
            tint: _theme.colors.primary,
          ),
        ),
        title: name,
        summary: subtitle,
        endActions: _checking
            ? const [MiuixInfiniteProgressIndicator(size: 20)]
            : null,
        enabled: !_checking,
        onClick: _checking ? null : _onTap,
      ),
    );
  }
}
