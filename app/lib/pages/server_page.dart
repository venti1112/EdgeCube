import 'package:flutter/material.dart';

/// 服务端列表页(占位)。
///
/// 对齐 V1 `home_shell.dart` 的 `ServerPage`。
class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: const Center(child: Text('TODO: Server')),
    );
  }
}
