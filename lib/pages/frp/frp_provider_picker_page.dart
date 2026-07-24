import 'package:flutter/material.dart';

import '../../frp/frp_provider.dart';
import '../../i18n/locale_scope.dart';
import 'frp_custom_config_page.dart';
import 'frp_provider_login_page.dart';

/// 「添加隧道」供应商选择页。
class FrpProviderPickerPage extends StatelessWidget {
  const FrpProviderPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('frp.pickProvider'))),
      body: SafeArea(
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
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.theme});

  final FrpProvider provider;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isCustom = provider == FrpProvider.custom;
    final name = isCustom
        ? context.tr('frp.provider.custom')
        : provider.displayName;
    final subtitle = context.tr('frp.provider.${provider.key}.subtitle');
    return Card(
      child: ListTile(
        leading: Icon(
          isCustom ? Icons.edit_note : Icons.cloud_outlined,
          size: 36,
          color: theme.colorScheme.primary,
        ),
        title: Row(
          children: [
            Flexible(child: Text(name, style: const TextStyle(fontSize: 16))),
            if (provider.experimental) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.tr('frp.experimental'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => isCustom
                  ? const FrpCustomConfigPage()
                  : FrpProviderLoginPage(provider: provider),
            ),
          );
        },
      ),
    );
  }
}
