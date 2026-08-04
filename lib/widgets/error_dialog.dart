import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import 'miuix_dialog.dart';

/// 通用错误弹窗：以 Miuix 对话框展示错误信息。
///
/// 错误提示统一用弹窗而非 Snackbar，避免信息一闪而过；
/// 成功/普通通知仍用 Snackbar（见 [showMiuixSnackbar]）。
Future<void> showErrorDialog(BuildContext context, String message) {
  return showMiuixDialog<void>(
    context: context,
    title: context.tr('common.error'),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 崩溃日志之类的长文本可能远超屏幕高度，限高后可滚动。
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: MiuixText(message, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(
          children: [
            MiuixButton(
              onPressed: () => Navigator.of(ctx).pop(),
              colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
              child: MiuixText(ctx.tr('common.ok')),
            ),
          ],
        ),
      ],
    ),
  );
}
