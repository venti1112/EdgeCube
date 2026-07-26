import 'package:flutter/material.dart';

/// 通用加载对话框：与压缩/导出等长任务一致的「转圈 + 文案」模态样式。
///
/// 不可点遮罩关闭、不可返回键关闭；任务结束后由调用方
/// `Navigator.of(context).pop()` 关闭，或直接使用 [runWithLoadingDialog]
/// 自动管理弹出与关闭。
void showLoadingDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

/// 显示加载对话框并执行 [task]，任务结束（含抛错）后自动关闭对话框。
///
/// 返回任务结果；异常原样向上抛出，由调用方决定如何提示。
Future<T> runWithLoadingDialog<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  showLoadingDialog(context, message);
  try {
    return await task();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
