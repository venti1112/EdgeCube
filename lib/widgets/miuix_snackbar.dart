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

/// 把全局 Snackbar 宿主叠在**整个 Navigator 之上**。
///
/// 不能把宿主挂进首页 [MiuixScaffold] 的 `snackbarHost` 槽：那样它只是首页路由
/// 里的一个普通 widget，一旦压入不透明的子路由（关于页、FTP 页等），消息会被整个
/// 盖住而静默失效——不报错、只是看不见。故改为在 `MaterialApp.builder` 里包一层，
/// 位置高于所有路由。
///
/// [bottomPadding] 用于在有底部导航栏时把消息抬到栏上方。
class MiuixSnackbarOverlay extends StatelessWidget {
  const MiuixSnackbarOverlay({
    super.key,
    required this.child,
    this.bottomPadding = 0,
  });

  final Widget child;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // 只在底部留出一条带子接收手势，其余区域不拦截点击。
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomPadding,
          child: MiuixSnackbarHost(state: miuixSnackbarHost),
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
