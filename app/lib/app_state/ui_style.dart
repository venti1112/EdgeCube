import 'package:flutter/foundation.dart';

/// 全局 UI 风格枚举。
///
/// 通过 [UiStyleController] 控制,影响根布局是否用
/// `LiquidGlassWidgets.wrap` 包裹,以及 Shell 底栏组件选择。
enum UiStyle {
  /// Material Design 3(纯 Flutter M3 组件)。
  material3,

  /// Liquid Glass(liquid_glass_widgets 的 glass 组件体系)。
  liquidGlass,
}

/// 全局 UI 风格状态(对齐 V1 `ThemeStore` 模式)。
///
/// 通过 [UiStyleScope] 注入 widget 树。
/// 切换 [value] 即时触发根重建(EdgeCubeApp)与 Shell 重建。
class UiStyleController extends ValueNotifier<UiStyle> {
  UiStyleController([super.value = UiStyle.material3]);

  /// 切换 [UiStyle.material3] ↔ [UiStyle.liquidGlass]。
  void toggle() {
    value = value == UiStyle.material3
        ? UiStyle.liquidGlass
        : UiStyle.material3;
  }
}
