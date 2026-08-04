import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:xterm/xterm.dart';

/// 终端扩展按键栏
class TerminalKeysBar extends StatelessWidget {
  const TerminalKeysBar(this.controller, {super.key});

  final TerminalKeysController controller;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Material(
      color: theme.colors.surfaceContainerHigh,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _key(
                  context,
                  'ESC',
                  () => controller.sendKey(TerminalKey.escape),
                ),
                _key(context, '/', () => controller.sendText('/')),
                _key(context, '-', () => controller.sendText('-')),
                _key(
                  context,
                  'HOME',
                  () => controller.sendKey(TerminalKey.home),
                ),
                _key(
                  context,
                  '↑',
                  () => controller.sendKey(TerminalKey.arrowUp),
                ),
                _key(context, 'END', () => controller.sendKey(TerminalKey.end)),
                _key(
                  context,
                  'PgUp',
                  () => controller.sendKey(TerminalKey.pageUp),
                ),
              ],
            ),
            Row(
              children: [
                _key(context, 'TAB', () => controller.sendKey(TerminalKey.tab)),
                _key(
                  context,
                  'CTRL',
                  controller.toggleCtrl,
                  active: controller.ctrlDown,
                ),
                _key(
                  context,
                  'ALT',
                  controller.toggleAlt,
                  active: controller.altDown,
                ),
                _key(
                  context,
                  '←',
                  () => controller.sendKey(TerminalKey.arrowLeft),
                ),
                _key(
                  context,
                  '↓',
                  () => controller.sendKey(TerminalKey.arrowDown),
                ),
                _key(
                  context,
                  '→',
                  () => controller.sendKey(TerminalKey.arrowRight),
                ),
                _key(
                  context,
                  'PgDn',
                  () => controller.sendKey(TerminalKey.pageDown),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _key(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) => Expanded(
    child: _KeyButton(label: label, onTap: onTap, active: active),
  );
}

abstract class TerminalKeysController {
  bool get ctrlDown;
  bool get altDown;
  void toggleCtrl();
  void toggleAlt();
  void sendKey(TerminalKey key);
  void sendText(String text);
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = active ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = active ? scheme.onPrimary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          // 不抢焦点，避免点击扩展键时收起软键盘 / 让终端失焦。
          canRequestFocus: false,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
