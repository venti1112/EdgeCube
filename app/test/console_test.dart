import 'dart:convert';

import 'package:edgecube_app/console/console_page.dart';
import 'package:edgecube_app/console/pty_client.dart';
import 'package:edgecube_app/console/terminal_keys_bar.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/instance/models.dart';
import 'package:edgecube_app/settings/appearance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm2/xterm.dart' as xterm;

import 'support/fake_transport.dart';

/// `FakePtyTransport` 在 `support/fake_transport.dart`（玩家管理测试也用）。
PtyClient clientFor(FakePtyTransport transport) => PtyClient(
  Uri.parse('ws://127.0.0.1:8787/pty/abc?token=t'),
  transport: (_) => transport,
);

void main() {
  test('历史：begin → 二进制 → end，end 里的 state 立刻反映到状态上', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    final begins = <void>[];
    final ends = <void>[];
    final statuses = <PtyStatus>[];
    client.historyBegin.listen(begins.add);
    client.historyEnd.listen(ends.add);
    client.status.listen(statuses.add);
    client.connect();

    transport.pushControl({'type': 'history_begin'});
    transport.pushBytes(utf8.encode('之前的输出\n'));
    transport.pushControl({
      'type': 'history_end',
      'state': {
        'phase': 'running',
        'pid': 4321,
        'exit_code': null,
      },
    });
    await pumpEventQueue();

    expect(await client.output.first, '之前的输出\n');
    expect(begins, hasLength(1), reason: 'begin 只来一次：页面靠它清屏，重放之前擦');
    expect(ends, hasLength(1), reason: 'end 只来一次：页面靠它知道后面是实时输出');
    expect(statuses.last.phase, ServerPhase.running);
    expect(statuses.last.alive, isTrue);
    expect(statuses.last.label, '运行中');

    await client.close();
  });

  test('重放顺序：begin 在历史之前、end 在历史之后（页面靠这个顺序清屏）', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    final events = <String>[];
    client.historyBegin.listen((_) => events.add('begin'));
    client.output.listen(events.add);
    client.historyEnd.listen((_) => events.add('end'));
    client.connect();

    transport.pushControl({'type': 'history_begin'});
    transport.pushBytes(utf8.encode('旧输出\n'));
    transport.pushControl({
      'type': 'history_end',
      'state': {'phase': 'stopped'},
    });
    await pumpEventQueue();

    expect(
      events,
      ['begin', '旧输出\n', 'end'],
      reason: '清屏必须发生在历史重放之前，否则重放完再清一次就把历史擦掉了',
    );

    await client.close();
  });

  test('输出按 UTF-8 解码，跨块的多字节字符不会被打断', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    final chunks = <String>[];
    client.output.listen(chunks.add);
    client.connect();

    // 「世」= E4 B8 96，故意把它切成两帧
    final bytes = utf8.encode('世界 hello');
    transport.pushBytes(bytes.sublist(0, 2));
    transport.pushBytes(bytes.sublist(2));
    await pumpEventQueue();

    expect(chunks.join(), '世界 hello', reason: '不能在字符中间切开');

    await client.close();
  });

  test('敲键走二进制帧、resize 走文本帧', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    client.connect();

    client.write('ls\n');
    client.resize(120, 40);
    await pumpEventQueue();

    expect(transport.sent[0], utf8.encode('ls\n'));
    expect(transport.sent[0], isA<List<int>>());
    final control = jsonDecode(transport.sent[1] as String) as Map;
    expect(control['resize'], {'cols': 120, 'rows': 40});

    await client.close();
  });

  test('连接前量好的尺寸，连上后补发一次（否则服务端一直是 80×24）', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    // 终端先于控制台连接完成布局：这时客户端还没连上，帧发不出去
    client.resize(120, 40);
    expect(transport.sent, isEmpty, reason: '没连上就先别发');

    client.connect();
    await pumpEventQueue();

    final first = jsonDecode(transport.sent.first as String) as Map;
    expect(
      first['resize'],
      {'cols': 120, 'rows': 40},
      reason: '连接一建立就该把尺寸补发下去',
    );

    // 之后的 resize 照旧即时发送
    client.resize(100, 30);
    await pumpEventQueue();
    expect(jsonDecode(transport.sent.last as String), {
      'resize': {'cols': 100, 'rows': 30},
    });

    await client.close();
  });

  test('exit 控制帧带上退出码与阶段', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    final statuses = <PtyStatus>[];
    client.status.listen(statuses.add);
    client.connect();

    transport.pushControl({
      'type': 'exit',
      'code': 3,
      'phase': 'crashed',
    });
    await pumpEventQueue();

    final status = statuses.last;
    expect(status.phase, ServerPhase.crashed);
    expect(status.exitCode, 3);
    expect(status.alive, isFalse);
    expect(status.label, '异常退出');

    await client.close();
  });

  test('连接断了要变成一个可显示的错误状态，而不是静默', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    final statuses = <PtyStatus>[];
    client.status.listen(statuses.add);
    client.connect();
    expect(client.isConnected, isTrue);

    transport.drop();
    await pumpEventQueue();

    expect(client.isConnected, isFalse);
    expect(statuses.last.hasError, isTrue);
    expect(statuses.last.label, contains('断开'));

    await client.close();
  });

  test('没连上时 write / resize 不抛（页面可能在连接前就渲染了）', () async {
    final transport = FakePtyTransport();
    final client = clientFor(transport);
    // 故意不 connect
    client.write('x');
    client.resize(80, 24);
    expect(transport.sent, isEmpty);
    await client.close();
  });

  test('状态文案：停止时带上上次退出码', () {
    final status = PtyStatus.fromState(
      {'phase': 'stopped', 'exit_code': 1},
      connected: true,
    );
    expect(status.label, '已停止（上次退出码 1）');
    expect(status.alive, isFalse);

    // state 缺失 / 类型不对都不该炸
    final bare = PtyStatus.fromState(null, connected: true);
    expect(bare.phase, isNull);
    expect(bare.label, '读取状态中…');
  });

  group('扩展按键栏', () {
    /// 照 `ConsolePage` 的接法：终端的输出与按键栏都汇到 [sendText]。
    ({List<String> sent, TerminalKeysController keys}) keypad() {
      final terminal = xterm.Terminal();
      final sent = <String>[];
      final keys = TerminalKeysController(terminal, write: sent.add);
      terminal.onOutput = keys.sendText;
      return (sent: sent, keys: keys);
    }

    test('特殊键走 xterm2 生成转义序列', () {
      final k = keypad();

      k.keys.sendKey(xterm.TerminalKey.escape);
      k.keys.sendKey(xterm.TerminalKey.tab);
      k.keys.sendKey(xterm.TerminalKey.arrowUp);
      k.keys.sendKey(xterm.TerminalKey.arrowLeft);

      expect(k.sent, ['\x1b', '\t', '\x1b[A', '\x1b[D']);
    });

    test('粘滞 CTRL：只对下一次输入生效，且由 xterm2 施加在特殊键上', () {
      final k = keypad();

      k.keys.toggleCtrl();
      expect(k.keys.ctrlDown, isTrue);
      k.keys.sendText('c');
      expect(k.sent, ['\x03'], reason: 'Ctrl+C 就是 0x03');
      expect(k.keys.ctrlDown, isFalse, reason: '用完自动复位');

      k.keys.sendText('c');
      expect(k.sent.last, 'c', reason: '复位后不再施加修饰');
    });

    test('粘滞 ALT：给下一次输入加 ESC 前缀', () {
      final k = keypad();

      k.keys.toggleAlt();
      k.keys.sendText('-');
      expect(k.sent, ['\x1b-']);
      expect(k.keys.altDown, isFalse);

      // CTRL 与 ALT 同时点亮 → ESC + 控制字节
      k.keys.toggleCtrl();
      k.keys.toggleAlt();
      k.keys.sendText('d');
      expect(k.sent.last, '\x1b\x04');
    });

    test('多字符输入不施加修饰（粘贴、转义序列照原样过）', () {
      final k = keypad();

      k.keys.toggleCtrl();
      k.keys.sendText('\x1b[A');
      expect(k.sent, ['\x1b[A']);
    });

    test('在按键栏上按特殊键也会把已点亮的修饰键消费掉', () {
      final k = keypad();

      k.keys.toggleAlt();
      k.keys.sendKey(xterm.TerminalKey.tab);
      expect(k.sent, ['\t'], reason: 'ESC 前缀是 xterm2 按 alt 自己加的，别重复加');
      expect(k.keys.altDown, isFalse);
    });
  });

  testWidgets('按键栏：默认显示，设置里关掉后整条消失', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = bootContainer(
      storage: prefs,
      persisted: const ConnectionSettings(host: '127.0.0.1', token: 't'),
      transportFactory: FakeTransportFactory().call,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConsolePage()),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['ESC', 'TAB', 'CTRL', 'ALT', 'PgUp', 'PgDn']) {
      expect(find.text(label), findsOneWidget, reason: '默认应当显示按键栏');
    }

    await container.read(showConsoleKeysProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(find.text('ESC'), findsNothing, reason: '关掉后按键栏整条不渲染');

    await container.read(showConsoleKeysProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(find.text('ESC'), findsOneWidget);
  });
}
