import 'dart:io';

import 'package:flutter/material.dart';

import '../files/file_browser.dart';
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
        title: Text(selected == null ? '文件' : '文件 · ${selected.name}'),
      ),
      body: selected == null
          ? const PlaceholderPage(
              icon: Icons.folder_outlined,
              title: '还没有实例',
              description: '请先在「服务器」页新建并选择一个实例，再管理其文件。',
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

class _InstanceFiles extends StatelessWidget {
  const _InstanceFiles({
    super.key,
    required this.controller,
    required this.instance,
  });

  final InstanceController controller;
  final Instance instance;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: controller.directoryFor(instance),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Text('无法打开实例目录：${snapshot.error}'));
        }
        return FileBrowser(rootDir: snapshot.data!);
      },
    );
  }
}
