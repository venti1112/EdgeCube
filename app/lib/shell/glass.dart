import 'package:material_ui/material_ui.dart';

/// 毛玻璃模式下「条目表面」的玻璃配方。
///
/// 外壳（`home_shell.dart`）已经用**单层** BackdropFilter 把背景模糊好、
/// 铺上不透明度可调的内容表面；条目（列表卡、设置块…）要做的只是
/// 别再用实心填充把它盖回去 ——
///
/// * [glassEntryFill]：比内容面板亮一档的容器色，半透明，透出模糊后的背景；
/// * [glassEntryBorder] / [glassEntryShape]：一圈很淡的描边，勾出条目边缘，
///   免得半透明和面板糊成一片。
///
/// 条目**不要**各自再挂 BackdropFilter：逐条模糊是离屏采样大户，玻璃观感
/// 由外壳那一层统一负责（`glass_ui_test` 对模糊图层数量有精确断言）。

/// 玻璃条目的填充色（`alpha` 留给「禁用」这类要再压暗一档的变体）。
Color glassEntryFill(ColorScheme scheme, {double alpha = 0.5}) =>
    scheme.surfaceContainerHighest.withValues(alpha: alpha);

/// 玻璃条目的描边色（很淡的一圈）。
Color glassEntryBorder(ColorScheme scheme) =>
    scheme.outlineVariant.withValues(alpha: 0.45);

/// 玻璃条目的形状：圆角 12（同 M3 卡片）+ 一圈细描边。
RoundedRectangleBorder glassEntryShape(ColorScheme scheme) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: glassEntryBorder(scheme)),
    );

/// 毛玻璃模式下的卡片主题：半透明填充 + 无投影 + 细描边。
///
/// 挂在 `ThemeData.cardTheme` 上，全局覆盖所有没写死 `color` 的 `Card`
/// （列表条目的大头都在那里）。
CardThemeData glassCardTheme(ColorScheme scheme) => CardThemeData(
  color: glassEntryFill(scheme),
  elevation: 0,
  shape: glassEntryShape(scheme),
);

/// 把子树里 canvas 材质的底色也换成玻璃填充。
///
/// `ActionChip` 内部自带一层 `Material(type: canvas)`，底色只认
/// `ThemeData.canvasColor`（`chipTheme` 够不着它），落在玻璃面板上就是
/// 一颗颗实心小药丸。这里只对子树局部换色，不动全局 canvasColor
/// （下拉菜单等也吃这个值，全局改会把弹层一起透掉）。
Widget glassCanvas(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(canvasColor: glassEntryFill(theme.colorScheme)),
    child: child,
  );
}
