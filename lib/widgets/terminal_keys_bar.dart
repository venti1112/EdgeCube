import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// 终端扩展按键栏：两排补齐软键盘缺失的终端控制键。
///
/// 抽象自控制台页与 Shell 终端页共用的按键栏布局。通过 [TerminalKeysController]
/// 回调接口与具体控制器解耦，[ServerController] 与 [ShellController] 均符合该接口，
/// 无需包装即可直接传入。
///
/// CTRL / ALT 是粘滞修饰键（点亮后对下一次输入生效一次）；其余为瞬时键，
/// 点击后立即发送对应字节到 PTY。
class TerminalKeysBar extends StatelessWidget {
  const TerminalKeysBar(this.controller, {super.key});

  /// 按键行为回调集。两个控制器的 `sendKey` / `sendText` / `toggleCtrl` /
  /// `toggleAlt` / `ctrlDown` / `altDown` 签名一致，故可直接作为此接口实现。
  final TerminalKeysController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
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
                _key(context, 'HOME', () => controller.sendKey(TerminalKey.home)),
                _key(context, '↑', () => controller.sendKey(TerminalKey.arrowUp)),
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

/// [TerminalKeysBar] 所需的按键行为回调集。
///
/// [ServerController] 与 [ShellController] 的对应方法签名一致，隐式实现了本接口，
/// 故无需包装即可直接作为 [TerminalKeysBar.controller] 传入。
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
