import 'package:flutter/material.dart';

import 'account_controller.dart';

/// 向子树暴露 [AccountController]，并在登录态变化时触发依赖者重建。
class AccountScope extends InheritedNotifier<AccountController> {
  const AccountScope({
    super.key,
    required AccountController controller,
    required super.child,
  }) : super(notifier: controller);

  static AccountController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AccountScope>();
    assert(scope != null, 'AccountScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
