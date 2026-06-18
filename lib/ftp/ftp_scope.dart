import 'package:flutter/material.dart';

import 'ftp_controller.dart';

/// 向子树暴露 [FtpController]，并在其变化时触发依赖者重建。
class FtpScope extends InheritedNotifier<FtpController> {
  const FtpScope({
    super.key,
    required FtpController controller,
    required super.child,
  }) : super(notifier: controller);

  static FtpController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<FtpScope>();
    assert(scope != null, 'FtpScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
