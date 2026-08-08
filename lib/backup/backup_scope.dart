import 'package:flutter/material.dart';

import 'backup_controller.dart';

/// 向子树暴露 [BackupController]，在其变化时触发依赖者重建。
class BackupScope extends InheritedNotifier<BackupController> {
  const BackupScope({
    super.key,
    required BackupController controller,
    required super.child,
  }) : super(notifier: controller);

  static BackupController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BackupScope>();
    assert(scope != null, 'BackupScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
