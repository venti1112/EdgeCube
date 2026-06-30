import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n_service.dart';
import '../i18n/locale_scope.dart';

/// 首次启动用户协议对话框。
///
/// 加载 `assets/markdown/user_agreement.md` 全文并以 Markdown 格式渲染供用户阅读，
/// 必须选择「同意」才能继续；选择「不同意」时调用方应退出应用。
///
/// 同意按钮需同时满足两个条件才可点击：
/// 1. 用户已将协议内容滚动至底部；
/// 2. 弹窗已展示超过 10 秒（倒计时）。
///
/// 弹窗禁止返回键与外部点击关闭（[PopScope] + `barrierDismissible: false`），
/// 用户只能在「同意」与「不同意」之间二选一。
class UserAgreementDialog extends StatefulWidget {
  const UserAgreementDialog({super.key});

  @override
  State<UserAgreementDialog> createState() => _UserAgreementDialogState();
}

class _UserAgreementDialogState extends State<UserAgreementDialog> {
  static const int _countdownSeconds = 10;

  String _text = tr('common.loading');
  int _remaining = _countdownSeconds;
  Timer? _timer;
  bool _scrolledToBottom = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    rootBundle.loadString('assets/markdown/user_agreement.md').then((t) {
      if (mounted) {
        setState(() => _text = t);
        // 文本加载后延迟一帧再检查是否需要滚动（内容可能不足以溢出）
        WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
      }
    });
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // 内容不足以滚动或已滚动至底部（留 2px 容差）
    final atBottom = pos.maxScrollExtent <= 0 ||
        pos.pixels >= pos.maxScrollExtent - 2;
    if (atBottom && !_scrolledToBottom) {
      setState(() => _scrolledToBottom = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timerDone = _remaining <= 0;
    final canAgree = timerDone && _scrolledToBottom;

    String buttonLabel;
    if (!timerDone && !_scrolledToBottom) {
      buttonLabel = '请阅读完整协议 ($_remaining秒)';
    } else if (!timerDone) {
      buttonLabel = '请等待 ($_remaining秒)';
    } else if (!_scrolledToBottom) {
      buttonLabel = '请阅读完整协议';
    } else {
      buttonLabel = context.tr('common.agree');
    }

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(context.tr('userAgreement.title')),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context.tr('userAgreement.intro'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _onScroll();
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: MarkdownBody(
                        data: _text,
                        selectable: true,
                        onTapLink: (text, href, title) {
                          if (href != null) {
                            launchUrl(
                              Uri.parse(href),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('userAgreement.declineAndExit')),
          ),
          FilledButton(
            onPressed: canAgree ? () => Navigator.of(context).pop(true) : null,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
