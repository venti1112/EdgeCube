import 'package:flutter/material.dart';

import 'server_controller.dart';

/// 向子树暴露 [ServerController]，并在其变化时触发依赖者重建。
class ServerScope extends InheritedNotifier<ServerController> {
  const ServerScope({
    super.key,
    required ServerController controller,
    required super.child,
  }) : super(notifier: controller);

  static ServerController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServerScope>();
    assert(scope != null, 'ServerScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
