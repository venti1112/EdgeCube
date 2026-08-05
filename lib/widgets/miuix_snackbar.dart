import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 全局 Snackbar 宿主状态。
///
/// [MiuixSnackbarHostState] 是 [ChangeNotifier]，队列、自动消失、进退场与滑动
/// 关闭全部由它和 [MiuixSnackbarHost] 内部管理，因此做成全局单例最省事：
/// 宿主只需经 [MiuixSnackbarOverlay] 挂一次，任何位置都能直接调
/// [showMiuixSnackbar]，无需 BuildContext。
///
/// 这也顺带解决了 Material 时代 `ScaffoldMessenger.of(context)` 在跨页面/
/// 异步回调里拿不到（或拿到已失效的）messenger 的老问题。
final MiuixSnackbarHostState miuixSnackbarHost = MiuixSnackbarHostState();

/// 当前底部需要为 Snackbar 预留的高度（底部导航栏高度 + 间距）。
///
/// [HomeShell] 在成为顶层路由时更新此值为导航栏高度，压入子路由时归零。
/// [MiuixSnackbarOverlay] 监听此值动态调整 Snackbar 位置，避免遮挡导航栏。
final ValueNotifier<double> snackbarBottomPadding = ValueNotifier<double>(0);

/// 把全局 Snackbar 宿主叠在**整个 Navigator 之上**。
///
/// 不能把宿主挂进首页 [MiuixScaffold] 的 `snackbarHost` 槽：那样它只是首页路由
/// 里的一个普通 widget，一旦压入不透明的子路由（关于页、FTP 页等），消息会被整个
/// 盖住而静默失效——不报错、只是看不见。故改为在 `MaterialApp.builder` 里包一层，
/// 位置高于所有路由。
class MiuixSnackbarOverlay extends StatelessWidget {
  const MiuixSnackbarOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // 只在底部留出一条带子接收手势，其余区域不拦截点击。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: snackbarBottomPadding,
            builder: (context, padding, _) => AnimatedPadding(
              padding: EdgeInsets.only(bottom: padding),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1.0,
                child: MiuixSnackbarHost(state: miuixSnackbarHost),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 弹出一条 Snackbar。
///
/// 对应原先的 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`，
/// 但不需要 BuildContext。
///
/// [actionLabel] 非空时显示操作按钮；返回的 Future 在 Snackbar 消失时完成，
/// 值为 [MiuixSnackbarResult.actionPerformed] 表示用户点了该按钮。
Future<MiuixSnackbarResult> showMiuixSnackbar(
  String message, {
  String? actionLabel,
  bool withDismissAction = false,
  MiuixSnackbarDuration duration = MiuixSnackbarDuration.short,
}) {
  return miuixSnackbarHost.showSnackbar(
    message,
    actionLabel: actionLabel,
    withDismissAction: withDismissAction,
    duration: duration,
  );
}
