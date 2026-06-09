import 'package:flutter/material.dart';
import '../widgets/placeholder_page.dart';

class PlayersPage extends StatelessWidget {
  const PlayersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('玩家')),
      body: const PlaceholderPage(
        icon: Icons.people,
        title: '玩家',
        description: '查看在线玩家，管理白名单、封禁与 OP 权限。',
      ),
    );
  }
}
