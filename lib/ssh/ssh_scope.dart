import 'package:flutter/material.dart';

import 'ssh_controller.dart';

/// 向子树暴露 [SshController]，并在其变化时触发依赖者重建。
class SshScope extends InheritedNotifier<SshController> {
  const SshScope({
    super.key,
    required SshController controller,
    required super.child,
  }) : super(notifier: controller);

  static SshController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SshScope>();
    assert(scope != null, 'SshScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
