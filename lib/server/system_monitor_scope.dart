import 'package:flutter/material.dart';

import 'system_monitor_controller.dart';

/// 向子树暴露 [SystemMonitorController]，在其变化时触发依赖者重建。
class SystemMonitorScope extends InheritedNotifier<SystemMonitorController> {
  const SystemMonitorScope({
    super.key,
    required SystemMonitorController controller,
    required super.child,
  }) : super(notifier: controller);

  static SystemMonitorController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SystemMonitorScope>();
    assert(scope != null, 'SystemMonitorScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
