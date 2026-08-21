import 'package:flutter/material.dart';

/// 设置页(占位)。
///
/// 对齐 V1 `home_shell.dart` 的 `SettingsPage`。
/// 后续在此加入 [UiStyle] 切换控件。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('TODO: Settings')),
    );
  }
}
