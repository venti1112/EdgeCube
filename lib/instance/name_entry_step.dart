import 'package:flutter/material.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_text_field.dart';
import 'server_type_tile.dart';

class NameEntryStep extends StatelessWidget {
  const NameEntryStep({
    super.key,
    required this.controller,
    required this.showBungeeCordTile,
    required this.onGoToServerType,
    required this.onStartImport,
    required this.onStartArchive,
    required this.onStartModpack,
    required this.onCreateBungeeCord,
    required this.onCreateEmpty,
  });

  final TextEditingController controller;
  final bool showBungeeCordTile;
  final VoidCallback onGoToServerType;
  final VoidCallback onStartImport;
  final VoidCallback onStartArchive;
  final VoidCallback onStartModpack;
  final VoidCallback onCreateBungeeCord;
  final VoidCallback onCreateEmpty;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        EcTextField(
          controller: controller,
          label: context.tr('instance.nameLabel'),
          hint: context.tr('instance.nameHint'),
        ),
        const SizedBox(height: 24),
        ServerTypeTile(
          icon: Icons.cloud_download_outlined,
          title: context.tr('instance.titleDownloadServer'),
          subtitle: context.tr('instance.downloadServerSubtitle'),
          onTap: onGoToServerType,
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.file_upload_outlined,
          title: context.tr('instance.titleImportServer'),
          subtitle: context.tr('instance.importServerSubtitle'),
          onTap: onStartImport,
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.archive_outlined,
          title: context.tr('instance.titleImportArchive'),
          subtitle: context.tr('instance.importArchiveSubtitle'),
          onTap: onStartArchive,
        ),
        const SizedBox(height: 12),
        ServerTypeTile(
          icon: Icons.inventory_2_outlined,
          title: context.tr('instance.titleModpackImport'),
          subtitle: context.tr('instance.modpackImportSubtitle'),
          onTap: onStartModpack,
        ),
        const SizedBox(height: 12),
        if (showBungeeCordTile)
          ServerTypeTile(
            icon: Icons.account_tree_outlined,
            title: context.tr('instance.bungeecordTitle'),
            subtitle: context.tr('instance.bungeecordSubtitle'),
            onTap: onCreateBungeeCord,
          )
        else
          ServerTypeTile(
            icon: Icons.create_new_folder_outlined,
            title: context.tr('instance.createEmptyTitle'),
            subtitle: context.tr('instance.createEmptySubtitle'),
            onTap: onCreateEmpty,
          ),
      ],
    );
  }
}
