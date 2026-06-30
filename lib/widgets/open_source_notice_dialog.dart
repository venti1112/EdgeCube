import 'dart:async';

import 'package:flutter/material.dart';

/// 开源免费声明弹窗。
///
/// 在用户协议之前展示，告知用户本项目完全开源免费，不存在任何付费内容。
/// 确认按钮需等待 5 秒倒计时结束后才可点击；倒计时期间只能选择退出应用。
/// 所有文案硬编码，不依赖语言文件。
class OpenSourceNoticeDialog extends StatefulWidget {
  const OpenSourceNoticeDialog({super.key});

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
    final canConfirm = _remaining <= 0;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('开源免费声明'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EdgeCube 是一个完全开源、免费的项目。',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(height: 12),
                Text(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('退出应用'),
          ),
          FilledButton(
            onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
            child: Text(
              canConfirm ? '我已知悉' : '请仔细阅读 ($_remaining秒)',
            ),
          ),
        ],
      ),
    );
  }
}
