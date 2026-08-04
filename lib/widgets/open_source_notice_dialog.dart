import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'miuix_dialog.dart';

/// 开源免费声明弹窗的内容体（标题由 [showMiuixDialog] 的 `title` 提供）。
///
/// 在用户协议之前展示，告知用户本项目完全开源免费，不存在任何付费内容。
/// 确认按钮需等待 5 秒倒计时结束后才可点击；倒计时期间只能选择退出应用。
/// 所有文案硬编码，不依赖语言文件。
class OpenSourceNoticeDialog extends StatefulWidget {
  const OpenSourceNoticeDialog({super.key});

  /// 弹窗标题，供调用方传给 [showMiuixDialog]。
  static const String title = '开源免费声明';

  @override
  State<OpenSourceNoticeDialog> createState() => _OpenSourceNoticeDialogState();
}

class _OpenSourceNoticeDialogState extends State<OpenSourceNoticeDialog> {
  static const int _countdownSeconds = 5;
  int _remaining = _countdownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final canConfirm = _remaining <= 0;

    return PopScope(
      canPop: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    'EdgeCube 是一个完全开源、免费的项目。',
                    style: theme.textStyles.subtitle,
                  ),
                  const SizedBox(height: 12),
                  const MiuixText(
                    '本项目基于 GPL-3.0 开源协议发布，源代码托管于 GitHub，'
                    '任何人都可以免费获取、使用和修改。\n\n'
                    '本项目不存在任何形式的付费内容，包括但不限于：\n'
                    '• 使用卡密或类似物解锁软件使用权\n'
                    '• 付费功能或高级版\n'
                    '• 应用内购买或订阅\n'
                    '• 广告或推广内容\n'
                    '• 任何形式的收费服务\n\n'
                    '如果您在任何渠道看到以本项目名义进行的收费行为，'
                    '那并非官方所为，请注意甄别并提高警惕，并向我们举报！\n'
                    '如果你已支付费用，请立即卸载本软件并凭此弹窗截图向商家退款！\n\n'
                    '使用本软件即表示您已知悉并认同上述声明。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                '退出应用',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              MiuixButton(
                enabled: canConfirm,
                onPressed: canConfirm
                    ? () => Navigator.of(context).pop(true)
                    : null,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText(canConfirm ? '我已知悉' : '请仔细阅读 ($_remaining秒)'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
