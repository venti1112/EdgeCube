import 'package:flutter/material.dart';

/// 实例管理页(占位)。
///
/// 对齐 V1 `home_shell.dart` 的 `ManagePage`。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: const Center(child: Text('TODO: Manage')),
    );
  }
}
