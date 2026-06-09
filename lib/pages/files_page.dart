import 'package:flutter/material.dart';
import '../widgets/placeholder_page.dart';

class FilesPage extends StatelessWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文件')),
      body: const PlaceholderPage(
        icon: Icons.folder,
        title: '文件',
        description: '浏览并编辑服务器文件，如 server.properties 与世界存档。',
      ),
    );
  }
}
