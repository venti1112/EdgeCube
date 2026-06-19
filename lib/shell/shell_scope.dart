import 'package:flutter/material.dart';

import 'shell_controller.dart';

/// 向子树暴露 [ShellController]，并在其变化时触发依赖者重建。
class ShellScope extends InheritedNotifier<ShellController> {
  const ShellScope({
    super.key,
    required ShellController controller,
    required super.child,
  }) : super(notifier: controller);

  static ShellController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
