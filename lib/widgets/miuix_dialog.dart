import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';

/// Miuix 对话框的**命令式**适配层。
///
/// flutter_miuix 的 [MiuixOverlayDialog] 是声明式组件：常驻 widget 树中，由
/// `show` 布尔驱动开合。而本项目有大量 `await showDialog<T>(...)` 取返回值决定
/// 后续流程的写法，逐个改成声明式意味着每个调用点都要加 state 字段并拆开异步
/// 控制流。本文件用一个自定义 [PopupRoute] 把声明式弹窗包成命令式接口，使调用
/// 方的写法与 `showDialog` 完全一致，**弹窗内部的 `Navigator.of(ctx).pop(value)`
/// 也原样可用**。
///
/// 三条关闭路径（内容里 pop、系统返回键、点击遮罩）统一收敛到「路由反向」这一个
/// 信号上：路由一旦开始反向，[_MiuixDialogPage] 就把 `show` 置 false 让 Miuix
/// 播退场动效，而路由的 `reverseTransitionDuration` 给足了动效播完的时间窗。
Future<T?> showMiuixDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  String? summary,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    MiuixDialogRoute<T>(
      builder: builder,
      title: title,
      summary: summary,
      dismissible: barrierDismissible,
    ),
  );
}

/// 「取消 / 确定」二选一确认弹窗，返回 `true` 表示用户确认。
///
/// 收敛全库重复的确认框样板。[confirmLabel] 缺省用 `common.confirm`，
/// [cancelLabel] 缺省用 `common.cancel`。
Future<bool> showMiuixConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  final result = await showMiuixDialog<bool>(
    context: context,
    title: title,
    summary: message,
    builder: (ctx) => MiuixDialogActions(
      children: [
        MiuixTextButton(
          cancelLabel ?? ctx.tr('common.cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        MiuixButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
          child: MiuixText(confirmLabel ?? ctx.tr('common.confirm')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 对话框底部按钮行：等宽平分、水平排布，符合 Miuix 的双按钮布局。
///
/// 单按钮时占满整行。按钮之间的间距为 [spacing]。
class MiuixDialogActions extends StatelessWidget {
  const MiuixDialogActions({
    super.key,
    required this.children,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final row = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) row.add(SizedBox(width: spacing));
      row.add(Expanded(child: children[i]));
    }
    return Row(children: row);
  }
}

/// 承载 [MiuixOverlayDialog] 的模态路由。
///
/// - `barrierColor` 为 null：遮罩由 Miuix 自己绘制（含淡入淡出动效），
///   路由只提供一层透明的 [ModalBarrier] 兜住穿透的点击；
/// - `barrierDismissible` 为 false：点击遮罩关闭由 Miuix 的
///   `onDismissRequest` 处理，避免两套关闭逻辑打架；
/// - `transitionDuration` 为零：进场动效由 Miuix 在挂载时自行播放；
/// - `reverseTransitionDuration` 覆盖 Miuix 的退场耗时（内容 200ms /
///   遮罩 250ms），留出余量取 280ms。
class MiuixDialogRoute<T> extends PopupRoute<T> {
  MiuixDialogRoute({
    required this.builder,
    this.title,
    this.summary,
    this.dismissible = true,
  });

  final WidgetBuilder builder;
  final String? title;
  final String? summary;

  /// 是否允许点击遮罩关闭。
  final bool dismissible;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _MiuixDialogPage<T>(
      route: this,
      builder: builder,
      title: title,
      summary: summary,
      dismissible: dismissible,
    );
  }
}

class _MiuixDialogPage<T> extends StatefulWidget {
  const _MiuixDialogPage({
    required this.route,
    required this.builder,
    required this.dismissible,
    this.title,
    this.summary,
  });

  final MiuixDialogRoute<T> route;
  final WidgetBuilder builder;
  final bool dismissible;
  final String? title;
  final String? summary;

  @override
  State<_MiuixDialogPage<T>> createState() => _MiuixDialogPageState<T>();
}

class _MiuixDialogPageState<T> extends State<_MiuixDialogPage<T>> {
  // 挂载即 true：MiuixOverlayDialog 以 show=true 创建时会正常播进场动效
  // （宿主 _MiuixHostedEntry 在 didChangeDependencies 里触发 _open）。
  bool _show = true;

  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _routeAnimation = widget.route.animation
      ?..addStatusListener(_onRouteStatusChanged);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatusChanged);
    super.dispose();
  }

  /// 路由开始反向即触发退场动效——无论这次关闭来自弹窗内容里的
  /// `Navigator.pop(value)`、系统返回键，还是点击遮罩。
  void _onRouteStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse && _show && mounted) {
      setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 路由在 Navigator 的 overlay 中是页面 Scaffold 的**兄弟**而非后代，找不到
    // 祖先的 MiuixPopupScope 时 MiuixDialogLayout 会退化到无人渲染的
    // MiuixPopupRegistry.fallback（表现为「点了没反应」）。故此处必须自建一个
    // establishRoot 的作用域与配套的 MiuixPopupHost。
    return MiuixPopupScope(
      establishRoot: true,
      child: MiuixPopupHost(
        child: MiuixOverlayDialog(
          show: _show,
          title: widget.title,
          summary: widget.summary,
          onDismissRequest: widget.dismissible
              ? () => Navigator.of(context).maybePop()
              : null,
          content: Builder(builder: widget.builder),
        ),
      ),
    );
  }
}
