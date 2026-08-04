import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../widgets/ec_preference.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ServerTypeTile extends StatelessWidget {
  const ServerTypeTile({
    super.key,
    this.icon,
    this.imageAssetPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData? icon;
  final String? imageAssetPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EcCardTile(
      leading: SizedBox(width: 36, height: 36, child: _buildLeading()),
      title: title,
      summary: subtitle,
      onTap: onTap,
    );
  }

  Widget _buildLeading() {
    if (imageAssetPath != null) {
      if (imageAssetPath!.endsWith('.svg')) {
        return SvgPicture.asset(
          imageAssetPath!,
          width: 36,
          height: 36,
          placeholderBuilder: (_) => _fallbackIcon(),
        );
      }
      return Image.asset(
        imageAssetPath!,
        width: 36,
        height: 36,
        errorBuilder: (_, _, _) => _fallbackIcon(),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return MiuixIcon(icon: icon ?? Icons.help_outline, size: 36);
  }
}
