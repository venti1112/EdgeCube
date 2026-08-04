import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';

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
      return const Center(child: MiuixInfiniteProgressIndicator());
    }
    if (error != null) {
      return EcErrorRetry(
        message: error!,
        retryLabel: context.tr('common.retry'),
        onRetry: onRetry,
      );
    }
    if (versions.isEmpty) {
      return Center(
        child: MiuixText(
          context.tr('instance.noVersionsAvailable'),
          color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: versions.length,
      itemBuilder: (context, index) {
        final version = versions[index];
        final subtitle = subtitles?[version];
        return EcCardTile(
          title: version,
          summary: subtitle,
          onTap: () => onSelect(version),
        );
      },
    );
  }
}
