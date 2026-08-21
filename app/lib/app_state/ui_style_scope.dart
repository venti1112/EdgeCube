import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ui_style.dart';

export 'ui_style.dart' show UiStyle, UiStyleController;

/// 在 widget 树注入全局 [UiStyle] 状态(对齐 V1 `ThemeScope` 模式)。
///
/// 通过 [UiStyleScope.of] 读取当前 [UiStyle] 与 [UiStyleController]。
/// 切换 [UiStyleController.value] 即时触发依赖本 scope 的 widget 重建。
class UiStyleScope extends InheritedNotifier<ValueListenable<UiStyle>> {
  const UiStyleScope({
    super.key,
    required this.controller,
    required super.child,
  }) : super(notifier: controller);

  /// 全局 UI 风格控制器。
  final UiStyleController controller;

  /// 读取当前 [UiStyle] 与 [UiStyleController]。
  ///
  /// 调用方会建立对本 scope 的依赖,controller 变化时重建。
  static UiStyleScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<UiStyleScope>();
    if (scope == null) {
      throw StateError('UiStyleScope not found in widget tree');
    }
    return scope;
  }
}
