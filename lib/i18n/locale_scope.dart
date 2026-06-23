import 'package:flutter/widgets.dart';

import 'locale_controller.dart';

/// 向子树暴露 [LocaleController]，并在语言变化时触发依赖者重建。
///
/// 因 [InheritedNotifier] 会监听 controller 的 notifyListeners，
/// 即使中间存在被缓存、未随父级重建的子树（如 IndexedStack 中的标签页），
/// 只要其 build 调用过 `context.tr(...)` 就会在语言切换时自动重建。
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope 未在 widget 树中找到');
    return scope!.notifier!;
  }
}

/// 便捷的翻译取值扩展：`context.tr('settings.title')`。
///
/// 内部经 [LocaleScope.of] 建立依赖，语言切换时使用处会自动重建。
/// [params] 用于替换译文中的 `{name}` 占位符。
extension TrX on BuildContext {
  String tr(String key, [Map<String, String>? params]) =>
      LocaleScope.of(this).translations.get(key, params);
}
