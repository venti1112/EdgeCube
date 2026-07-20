import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';

/// 通用错误弹窗：以 [AlertDialog] 展示错误信息。
///
/// 错误提示统一用弹窗而非 SnackBar，避免信息一闪而过；
/// 成功/普通通知仍用 SnackBar。
Future<void> showErrorDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('common.error')),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(ctx.tr('common.ok')),
        ),
      ],
    ),
  );
}
