import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 通用占位页面内容
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MiuixIcon(icon: icon, size: 72, tint: theme.colors.primary),
          const SizedBox(height: 16),
          MiuixText(title, style: theme.textStyles.title3),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: MiuixText(
              description,
              textAlign: TextAlign.center,
              style: theme.textStyles.body2,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }
}
