import 'package:material_ui/material_ui.dart';
import 'package:xterm2/xterm.dart' as xterm;

/// 终端扩展按键栏。
///
/// 两行 7 键，补手机软键盘上没有、控制台又离不开的那些：
///
/// ```
/// ESC   /     -    HOME  ↑  END   PgUp
/// TAB  CTRL  ALT    ←    ↓   →    PgDn
/// ```
///
/// `CTRL` / `ALT` 是**粘滞修饰键**：点亮后只对下一次输入生效一次，随即自动复位。
/// 那个「下一次输入」既可以是按键栏里的键，也可以是软键盘敲进来的字符 ——
/// 终端产生的输入统一经过 [TerminalKeysController.sendText]。
class TerminalKeysBar extends StatelessWidget {
  const TerminalKeysBar(this.controller, {super.key});

  final TerminalKeysController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Material(
        color: scheme.surfaceContainerHigh,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _key(
                    'ESC',
                    () => controller.sendKey(xterm.TerminalKey.escape),
                  ),
                  _key('/', () => controller.sendText('/')),
                  _key('-', () => controller.sendText('-')),
                  _key(
                    'HOME',
                    () => controller.sendKey(xterm.TerminalKey.home),
                  ),
                  _key('↑', () => controller.sendKey(xterm.TerminalKey.arrowUp)),
                  _key('END', () => controller.sendKey(xterm.TerminalKey.end)),
                  _key(
                    'PgUp',
                    () => controller.sendKey(xterm.TerminalKey.pageUp),
                  ),
                ],
              ),
              Row(
                children: [
                  _key('TAB', () => controller.sendKey(xterm.TerminalKey.tab)),
                  _key('CTRL', controller.toggleCtrl, active: controller.ctrlDown),
                  _key('ALT', controller.toggleAlt, active: controller.altDown),
                  _key(
                    '←',
                    () => controller.sendKey(xterm.TerminalKey.arrowLeft),
                  ),
                  _key(
                    '↓',
                    () => controller.sendKey(xterm.TerminalKey.arrowDown),
                  ),
                  _key(
                    '→',
                    () => controller.sendKey(xterm.TerminalKey.arrowRight),
                  ),
                  _key(
                    'PgDn',
                    () => controller.sendKey(xterm.TerminalKey.pageDown),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap, {bool active = false}) =>
      Expanded(child: _KeyButton(label: label, onTap: onTap, active: active));
}

/// 按键栏的输入控制器：粘滞修饰键 + 发送。
///
/// 把终端与按键栏**两条输入路径合到一处**：`Terminal.onOutput` 指向
/// [sendText]，于是「点亮 CTRL 再敲软键盘的 c」和「点亮 CTRL 再按按键栏的键」
/// 走的是同一段代码，修饰键语义只写一份。
///
/// 与 [xterm.Terminal] 之间只有一个方向是反向的：[sendKey] 把键交给
/// `Terminal.keyInput` 生成转义序列，而它转手就会调 `onOutput`（也就是
/// [sendText]）—— 所以那里必须**先复位修饰键再发送**，否则同一次按键会被
/// 施加两遍。
class TerminalKeysController extends ChangeNotifier {
  TerminalKeysController(this._terminal, {required this.write});

  /// 往 PTY 写字节（控制台未连上时应当静默丢弃）。
  final void Function(String data) write;

  final xterm.Terminal _terminal;

  bool _ctrlDown = false;
  bool _altDown = false;

  bool get ctrlDown => _ctrlDown;
  bool get altDown => _altDown;

  /// 切换粘滞 Ctrl。
  void toggleCtrl() {
    _ctrlDown = !_ctrlDown;
    notifyListeners();
  }

  /// 切换粘滞 Alt。
  void toggleAlt() {
    _altDown = !_altDown;
    notifyListeners();
  }

  /// 发送一段字面文本（按键栏的 `/` `-`，以及软键盘敲进来的字符）。
  void sendText(String data) {
    write(_applyModifiers(data) ?? data);
    _clearModifiers();
  }

  /// 发送一个特殊键（ESC / TAB / 方向键 / HOME / END / PgUp / PgDn）。
  void sendKey(xterm.TerminalKey key) {
    final ctrl = _ctrlDown;
    final alt = _altDown;
    _clearModifiers();
    _terminal.keyInput(key, ctrl: ctrl, alt: alt);
  }

  /// 对单个字符施加粘滞的 Ctrl / Alt：
  /// Ctrl 把 `a–z` / `@[\]^_` 映射到 `0x00–0x1f`，Alt 加 ESC 前缀。
  /// 不适用（多字符或无映射）时返回 `null`，由调用方原样发送。
  String? _applyModifiers(String data) {
    if (data.length != 1) return null;
    var code = data.codeUnitAt(0);
    if (_ctrlDown) {
      if (code >= 0x61 && code <= 0x7a) code -= 0x20; // 小写转大写
      if (code >= 0x40 && code <= 0x5f) {
        final ctrl = String.fromCharCode(code & 0x1f);
        return _altDown ? '\x1b$ctrl' : ctrl;
      }
    }
    if (_altDown) return '\x1b$data';
    return null;
  }

  /// 复位粘滞修饰键（每次输入消费后调用）。
  void _clearModifiers() {
    if (!_ctrlDown && !_altDown) return;
    _ctrlDown = false;
    _altDown = false;
    notifyListeners();
  }
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
