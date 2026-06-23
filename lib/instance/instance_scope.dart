import 'package:flutter/material.dart';

import 'instance_controller.dart';

/// 向子树暴露 [InstanceController]，并在其变化时触发依赖者重建。
class InstanceScope extends InheritedNotifier<InstanceController> {
  const InstanceScope({
    super.key,
    required InstanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static InstanceController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<InstanceScope>();
    assert(scope != null, 'InstanceScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
