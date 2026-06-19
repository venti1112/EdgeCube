import 'package:flutter/material.dart';

import 'mcp_controller.dart';

/// 向子树暴露 [McpController]，并在其变化时触发依赖者重建。
class McpScope extends InheritedNotifier<McpController> {
  const McpScope({
    super.key,
    required McpController controller,
    required super.child,
  }) : super(notifier: controller);

  static McpController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<McpScope>();
    assert(scope != null, 'McpScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
