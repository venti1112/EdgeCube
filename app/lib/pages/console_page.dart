import 'package:flutter/material.dart';

/// 终端页(占位)。
///
/// 对齐 V1 `home_shell.dart` 的 `ConsolePage`。
class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Console')),
      body: const Center(child: Text('TODO: Console')),
    );
  }
}
