import 'package:flutter/material.dart';
import '../i18n/locale_scope.dart';
import 'server_type_tile.dart';

class EditionSelectStep extends StatelessWidget {
  const EditionSelectStep({
    super.key,
    required this.onSelectJavaEdition,
    required this.onSelectBedrockEdition,
    this.onSelectSurvivalcraftEdition,
  });

  final VoidCallback onSelectJavaEdition;
  final VoidCallback onSelectBedrockEdition;
  final VoidCallback? onSelectSurvivalcraftEdition;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        ServerTypeTile(
          icon: Icons.coffee_outlined,
          title: context.tr('instance.javaEditionTitle'),
          subtitle: context.tr('instance.javaEditionSubtitle'),
          onTap: onSelectJavaEdition,
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.diamond_outlined,
          title: context.tr('instance.bedrockEditionTitle'),
          subtitle: context.tr('instance.bedrockEditionSubtitle'),
          onTap: onSelectBedrockEdition,
        ),
        if (onSelectSurvivalcraftEdition != null) ...[
          const SizedBox(height: 12),
          ServerTypeTile(
            icon: Icons.public_outlined,
            title: context.tr('instance.survivalcraftEditionTitle'),
            subtitle: context.tr('instance.survivalcraftEditionSubtitle'),
            onTap: onSelectSurvivalcraftEdition!,
          ),
        ],
      ],
    );
  }
}

class JavaServerCategoryStep extends StatelessWidget {
  const JavaServerCategoryStep({super.key, required this.onSelectCategory});

  final void Function(String category) onSelectCategory;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        ServerTypeTile(
          icon: Icons.storage_outlined,
          title: context.tr('instance.vanillaCategoryTitle'),
          subtitle: context.tr('instance.vanillaCategorySubtitle'),
          onTap: () => onSelectCategory('vanilla'),
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.extension_outlined,
          title: context.tr('instance.pluginCategoryTitle'),
          subtitle: context.tr('instance.pluginCategorySubtitle'),
          onTap: () => onSelectCategory('plugin'),
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.auto_awesome_mosaic_outlined,
          title: context.tr('instance.modCategoryTitle'),
          subtitle: context.tr('instance.modCategorySubtitle'),
          onTap: () => onSelectCategory('mod'),
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.lan_outlined,
          title: context.tr('instance.proxyCategoryTitle'),
          subtitle: context.tr('instance.proxyCategorySubtitle'),
          onTap: () => onSelectCategory('proxy'),
        ),
      ],
    );
  }
}

class ServerTypeEntry {
  const ServerTypeEntry({
    this.icon,
    this.imageAssetPath,
    required this.titleKey,
    required this.subtitleKey,
  });

  final IconData? icon;
  final String? imageAssetPath;
  final String titleKey;
  final String subtitleKey;
}

const Map<String, ServerTypeEntry> _serverTypeEntries = {
  'vanilla': ServerTypeEntry(
    imageAssetPath: 'assets/images/vanilla_logo.png',
    titleKey: 'instance.vanillaTitle',
    subtitleKey: 'instance.vanillaSubtitle',
  ),
  'paper': ServerTypeEntry(
    imageAssetPath: 'assets/images/paper_logo.svg',
    titleKey: 'instance.paperTitle',
    subtitleKey: 'instance.paperSubtitle',
  ),
  'spigot': ServerTypeEntry(
    imageAssetPath: 'assets/images/spigot_logo.png',
    titleKey: 'instance.spigotTitle',
    subtitleKey: 'instance.spigotSubtitle',
  ),
  'craftbukkit': ServerTypeEntry(
    imageAssetPath: 'assets/images/craftbukkit_logo.png',
    titleKey: 'instance.craftbukkitTitle',
    subtitleKey: 'instance.craftbukkitSubtitle',
  ),
  'purpur': ServerTypeEntry(
    imageAssetPath: 'assets/images/purpur_logo.svg',
    titleKey: 'instance.purpurTitle',
    subtitleKey: 'instance.purpurSubtitle',
  ),
  'leaf': ServerTypeEntry(
    imageAssetPath: 'assets/images/leaf_logo.svg',
    titleKey: 'instance.leafTitle',
    subtitleKey: 'instance.leafSubtitle',
  ),
  'leaves': ServerTypeEntry(
    icon: Icons.energy_savings_leaf_outlined,
    titleKey: 'instance.leavesTitle',
    subtitleKey: 'instance.leavesSubtitle',
  ),
  'velocity': ServerTypeEntry(
    imageAssetPath: 'assets/images/velocity_logo.svg',
    titleKey: 'instance.velocityTitle',
    subtitleKey: 'instance.velocitySubtitle',
  ),
  'bungeecord': ServerTypeEntry(
    imageAssetPath: 'assets/images/bungeecord_logo.png',
    titleKey: 'instance.bungeecordTitle',
    subtitleKey: 'instance.bungeecordSubtitle',
  ),
  'fabric': ServerTypeEntry(
    imageAssetPath: 'assets/images/fabric_logo.png',
    titleKey: 'instance.fabricTitle',
    subtitleKey: 'instance.fabricSubtitle',
  ),
  'forge': ServerTypeEntry(
    imageAssetPath: 'assets/images/forge_logo.svg',
    titleKey: 'instance.forgeTitle',
    subtitleKey: 'instance.forgeSubtitle',
  ),
  'neoforge': ServerTypeEntry(
    imageAssetPath: 'assets/images/neoforge.png',
    titleKey: 'instance.neoforgeTitle',
    subtitleKey: 'instance.neoforgeSubtitle',
  ),
  'pocketmine': ServerTypeEntry(
    imageAssetPath: 'assets/images/pmmp_logo.png',
    titleKey: 'instance.pocketmineTitle',
    subtitleKey: 'instance.pocketmineSubtitle',
  ),
  'powernukkitx': ServerTypeEntry(
    imageAssetPath: 'assets/images/powernukkitx_logo.png',
    titleKey: 'instance.powernukkitxTitle',
    subtitleKey: 'instance.powernukkitxSubtitle',
  ),
  'allay': ServerTypeEntry(
    imageAssetPath: 'assets/images/allay_logo.png',
    titleKey: 'instance.allayTitle',
    subtitleKey: 'instance.allaySubtitle',
  ),
  'survivalcraft': ServerTypeEntry(
    icon: Icons.public_outlined,
    titleKey: 'instance.survivalcraftTitle',
    subtitleKey: 'instance.survivalcraftSubtitle',
  ),
};

class ServerTypeTileList extends StatelessWidget {
  const ServerTypeTileList({
    super.key,
    required this.types,
    required this.onSelect,
  });

  final List<String> types;
  final void Function(String type) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        for (final type in types) ...[
          ServerTypeTile(
            icon: _serverTypeEntries[type]!.icon,
            imageAssetPath: _serverTypeEntries[type]!.imageAssetPath,
            title: context.tr(_serverTypeEntries[type]!.titleKey),
            subtitle: context.tr(_serverTypeEntries[type]!.subtitleKey),
            onTap: () => onSelect(type),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
