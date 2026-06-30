import 'dart:io';

import 'package:flutter/material.dart';

import '../files/file_browser.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../widgets/placeholder_page.dart';

class FilesPage extends StatelessWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final selected = controller.selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected == null
              ? context.tr('filesPage.title')
              : context.tr('filesPage.titleWithName', {'name': selected.name}),
        ),
      ),
      body: selected == null
          ? PlaceholderPage(
              icon: Icons.folder_outlined,
              title: context.tr('filesPage.emptyTitle'),
              description: context.tr('filesPage.emptyDescription'),
            )
          : _InstanceFiles(
              // 切换实例时重建浏览器，回到新实例根目录。
              key: ValueKey(selected.id),
              controller: controller,
              instance: selected,
            ),
    );
  }
}

class _InstanceFiles extends StatefulWidget {
  const _InstanceFiles({
    super.key,
    required this.controller,
    required this.instance,
  });

  final InstanceController controller;
  final Instance instance;

  @override
  State<_InstanceFiles> createState() => _InstanceFilesState();
}

class _InstanceFilesState extends State<_InstanceFiles> {
  late Future<Directory> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.directoryFor(widget.instance);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Text(
              context.tr('filesPage.openDirError', {
                'error': '${snapshot.error}',
              }),
            ),
          );
        }
        return FileBrowser(rootDir: snapshot.data!);
      },
    );
  }
}
