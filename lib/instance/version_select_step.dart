import 'package:flutter/material.dart';
import '../i18n/locale_scope.dart';

class VersionSelectStep extends StatelessWidget {
  const VersionSelectStep({
    super.key,
    required this.versions,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onSelect,
    this.subtitles,
  });

  final List<String> versions;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final void Function(String version) onSelect;
  final Map<String, String>? subtitles;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: Text(context.tr('instance.retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (versions.isEmpty) {
      return Center(
        child: Text(
          context.tr('instance.noVersions'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: versions.length,
      itemBuilder: (context, index) {
        final version = versions[index];
        final subtitle = subtitles?[version];
        return Card(
          child: ListTile(
            title: Text(version),
            subtitle: subtitle != null ? Text(subtitle) : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelect(version),
          ),
        );
      },
    );
  }
}
