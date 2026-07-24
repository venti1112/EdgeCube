import 'package:flutter/widgets.dart';

import 'frp_controller.dart';

/// 把 [FrpController] 注入 widget 树（与 ServerScope 等同构）。
class FrpScope extends InheritedNotifier<FrpController> {
  const FrpScope({
    super.key,
    required FrpController controller,
    required super.child,
  }) : super(notifier: controller);

  static FrpController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FrpScope>();
    assert(scope != null, 'FrpScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}
