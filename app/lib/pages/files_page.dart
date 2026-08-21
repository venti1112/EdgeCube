import 'package:flutter/material.dart';

/// 文件管理页(占位)。
///
/// 对齐 V1 `home_shell.dart` 的 `FilesPage`。
class FilesPage extends StatelessWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      body: const Center(child: Text('TODO: Files')),
    );
  }
}
