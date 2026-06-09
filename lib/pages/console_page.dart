import 'package:flutter/material.dart';
import '../widgets/placeholder_page.dart';

class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('控制台')),
      body: const PlaceholderPage(
        icon: Icons.terminal,
        title: '控制台',
        description: '实时查看服务器日志，并在此输入服务器命令。',
      ),
    );
  }
}
