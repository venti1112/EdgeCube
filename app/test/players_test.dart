import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/players/players_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

// ══════════════════════════════════════════════════════════════════════════
// 夹具
// ══════════════════════════════════════════════════════════════════════════

typedef PlayersFixture = ({
  ProviderContainer container,
  FakeInstanceStore store,
  FakeDaemonTransport transport,
  String id,
});

/// 连上假 daemon。名单怎么读、在线玩家怎么解析都在 daemon 侧，所以这里
/// **不用**铺文件树，直接摆 daemon 的返回值（[FakeInstanceStore.seedList] /
/// [FakeInstanceStore.online]）。
///
/// 默认实例处于 `running`（玩家管理的可操作态）；`withInstance: false` 用来验
/// 「没选实例」的提示。
Future<PlayersFixture> bootPlayers({
  bool running = true,
  bool withInstance = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = FakeInstanceStore();
  final id = withInstance ? store.seed(name: '生存服') : '';
  store.phase = running ? 'running' : 'stopped';
  final factory = FakeTransportFactory(instances: store);
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: factory.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  return (
    container: container,
    store: store,
    transport: factory.latest,
    id: id,
  );
}

Future<void> pumpPage(WidgetTester tester, PlayersFixture fixture) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: const MaterialApp(home: PlayersPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 推一次在线玩家变化：daemon 在输出里认出了新人/有人退出，就把整份名单推出来。
Future<void> pushOnline(
  WidgetTester tester,
  PlayersFixture fixture,
  List<String> players,
) async {
  fixture.store.online[fixture.id] = players;
  fixture.transport.pushEvent('instance.players', {
    'id': fixture.id,
    'players': players,
    'count': players.length,
    'ts': 0,
  });
  await tester.pumpAndSettle();
}

/// 切到某个标签页（按 TabBar 里的标签点，避免和正文里的同名文字撞上）。
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// 点开某个在线玩家的 ⋮ 菜单，选 [label]。
Future<void> tapPlayerMenu(
  WidgetTester tester,
  String name,
  String label,
) async {
  await tester.tap(find.byKey(Key('player_menu_$name')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// 命令发出去 500 ms 才重读名单，把这两个 Timer 走完。
Future<void> flushDelayedRefresh(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// 某一行里的文字（正文里会有同名文字，比如标签页上的「白名单」）。
Finder inRow(String name, String text) => find.descendant(
  of: find.byKey(Key('player_row_$name')),
  matching: find.text(text),
);

IconButton addButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('players_add')));

IconButton refreshButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('players_refresh')));

/// 客户端写进控制台的那一行（真后端会把它原样喂给 PTY）。
String? lastInput(PlayersFixture fixture) =>
    fixture.store.consoleInput[fixture.id]?.lastOrNull;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // 在线玩家（daemon 解析、App 只读结果）
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('没选实例：只给一句提示', (tester) async {
    final fixture = await bootPlayers(withInstance: false);
    await pumpPage(tester, fixture);

    expect(find.text('请先在「服务器」页选择一个实例。'), findsOneWidget);
  });

  testWidgets('在线页：连上先拉一次快照，之后由事件整份替换', (tester) async {
    final fixture = await bootPlayers();
    // 页面还没开，daemon 那边已经有人在服务器里：快照要能补出来
    fixture.store.online[fixture.id] = ['Bob'];
    await pumpPage(tester, fixture);
    expect(find.text('在线（1）'), findsOneWidget);
    expect(find.byKey(const Key('player_row_Bob')), findsOneWidget);

    // 事件里是完整名单，不是增量：新来一个人就是整份替换
    await pushOnline(tester, fixture, ['Alice', 'Bob', 'Carol']);
    expect(find.text('在线（3）'), findsOneWidget);
    // 名单排过序再显示
    expect(
      tester.getTopLeft(find.byKey(const Key('player_row_Alice'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('player_row_Bob'))).dy),
    );

    // 有人退出 → 只剩两个
    await pushOnline(tester, fixture, ['Alice', 'Carol']);
    expect(find.text('在线（2）'), findsOneWidget);
    expect(find.byKey(const Key('player_row_Bob')), findsNothing);

    // 都走了 → 空态
    await pushOnline(tester, fixture, const []);
    expect(find.text('在线（0）'), findsOneWidget);
    expect(find.text('暂无在线玩家'), findsOneWidget);
  });

  testWidgets('在线页：按 daemon 给的名单打白名单 / OP / 已封禁标签', (tester) async {
    final fixture = await bootPlayers();
    fixture.store.seedList(
      fixture.id,
      'whitelist',
      entries: [
        {'name': 'Alice', 'uuid': 'u1'},
      ],
    );
    fixture.store.seedList(
      fixture.id,
      'ops',
      entries: [
        {'name': 'Bob', 'uuid': 'u2'},
      ],
    );
    fixture.store.seedList(
      fixture.id,
      'bans',
      entries: [
        {'name': 'Carol', 'uuid': 'u3'},
      ],
    );
    await pumpPage(tester, fixture);
    await pushOnline(tester, fixture, ['Alice', 'Bob', 'Carol']);

    expect(inRow('Alice', '白名单'), findsOneWidget);
    expect(inRow('Bob', 'OP'), findsOneWidget);
    expect(inRow('Bob', '白名单'), findsNothing);
    expect(inRow('Carol', '已封禁'), findsOneWidget);
  });

  testWidgets('在线玩家变化不重拉实例列表 / 详情', (tester) async {
    final fixture = await bootPlayers();
    await pumpPage(tester, fixture);

    final before = Map<String, int>.from(fixture.store.calls);
    await pushOnline(tester, fixture, ['Alice']);
    expect(fixture.store.calls, before, reason: 'instance.players 不该触发重新拉取');

    // 对照组：阶段事件照旧要刷新详情（页面靠它决定能不能操作）
    fixture.transport.pushEvent('instance.phase', {
      'id': fixture.id,
      'phase': 'running',
    });
    await tester.pumpAndSettle();
    expect(
      fixture.store.calls['instance.get'],
      greaterThan(before['instance.get'] ?? 0),
    );
  });

  testWidgets('服务端退出：daemon 推的空名单让页面回到未运行状态', (tester) async {
    final fixture = await bootPlayers();
    await pumpPage(tester, fixture);
    await pushOnline(tester, fixture, ['Alice', 'Bob']);
    expect(find.text('在线（2）'), findsOneWidget);

    // 进程退出：daemon 清空名单并推一份空的
    await pushOnline(tester, fixture, const []);
    fixture.store.phase = 'stopped';
    fixture.transport.pushEvent('instance.phase', {
      'id': fixture.id,
      'phase': 'stopped',
    });
    await tester.pumpAndSettle();

    expect(find.text('在线（0）'), findsOneWidget);
    expect(find.text('服务端未运行'), findsOneWidget);
    expect(find.text('启动服务器后，在线玩家将自动显示在这里。'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 命令（写进控制台，命令 + 行尾一起发）
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('在线页命令：刷新发 list，菜单命令发的是固定字符串', (tester) async {
    final fixture = await bootPlayers();
    await pumpPage(tester, fixture);
    await pushOnline(tester, fixture, ['Alice', 'Bob']);

    await tester.tap(find.byKey(const Key('players_refresh')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'list\n');

    await tapPlayerMenu(tester, 'Alice', '加入白名单');
    expect(lastInput(fixture), 'whitelist add Alice\n');
    await flushDelayedRefresh(tester);

    await tapPlayerMenu(tester, 'Bob', '给予 OP');
    expect(lastInput(fixture), 'op Bob\n');
    await flushDelayedRefresh(tester);

    // 踢出：取消不发命令
    await tapPlayerMenu(tester, 'Alice', '踢出');
    expect(find.text('踢出 Alice'), findsOneWidget);
    expect(find.byKey(const Key('player_name_field')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('player_reason_field')),
      '挂机',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'op Bob\n');

    // 踢出：带原因
    await tapPlayerMenu(tester, 'Alice', '踢出');
    await tester.enterText(
      find.byKey(const Key('player_reason_field')),
      '开挂',
    );
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'kick Alice 开挂\n');

    // 封禁：不填原因时命令里不补空格
    await tapPlayerMenu(tester, 'Bob', '封禁');
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'ban Bob\n');
    await flushDelayedRefresh(tester);
  });

  testWidgets('命令按实例配置的换行符收尾', (tester) async {
    final fixture = await bootPlayers();
    fixture.store.instances[fixture.id]!['line_ending'] = '\r\n';
    await pumpPage(tester, fixture);
    await pushOnline(tester, fixture, ['Alice']);

    await tester.tap(find.byKey(const Key('players_refresh')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'list\r\n');
  });

  testWidgets('列表页命令：删 / 加拉名单的命令', (tester) async {
    final fixture = await bootPlayers();
    fixture.store.seedList(
      fixture.id,
      'whitelist',
      entries: [
        {'name': 'Zed', 'uuid': 'uuid-zed'},
      ],
    );
    await pumpPage(tester, fixture);
    await openTab(tester, '白名单');

    expect(find.text('白名单（1）'), findsOneWidget);
    expect(find.byKey(const Key('player_row_Zed')), findsOneWidget);
    expect(find.text('uuid-zed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player_delete_Zed')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'whitelist remove Zed\n');

    // 名字空着点确定：不发命令
    await tester.tap(find.byKey(const Key('players_add')));
    await tester.pumpAndSettle();
    expect(find.text('添加白名单'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(find.text('添加白名单'), findsNothing);
    expect(lastInput(fixture), 'whitelist remove Zed\n');

    await tester.tap(find.byKey(const Key('players_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player_name_field')), 'Kim');
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'whitelist add Kim\n');
    await flushDelayedRefresh(tester);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 名单页（内容由 daemon 读盘，App 只渲染）
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('服务端没在跑：在线页不给刷新/添加，名单页只读', (tester) async {
    final fixture = await bootPlayers(running: false);
    fixture.store.seedList(
      fixture.id,
      'whitelist',
      entries: [
        {'name': 'Alice', 'uuid': ''},
      ],
    );
    await pumpPage(tester, fixture);

    expect(find.text('服务端未运行'), findsOneWidget);
    expect(find.byKey(const Key('players_add')), findsNothing);
    expect(refreshButton(tester).onPressed, isNull);

    await openTab(tester, '白名单');
    expect(find.text('白名单（1）'), findsOneWidget);
    expect(find.byKey(const Key('player_row_Alice')), findsOneWidget);
    expect(find.text('只读模式，启动服务端后可进行操作'), findsOneWidget);
    expect(addButton(tester).onPressed, isNull);
    expect(find.byKey(const Key('player_delete_Alice')), findsNothing);
  });

  testWidgets('空名单：空态文案', (tester) async {
    final fixture = await bootPlayers();
    await pumpPage(tester, fixture);

    await openTab(tester, '白名单');
    expect(find.text('白名单（0）'), findsOneWidget);
    expect(find.text('白名单为空'), findsOneWidget);
    expect(find.text('点击上方「添加」按钮加入玩家。'), findsOneWidget);

    await openTab(tester, '封禁');
    expect(find.text('封禁名单（0）'), findsOneWidget);
    expect(find.text('暂无封禁'), findsOneWidget);
    expect(find.text('没有被封禁的玩家。'), findsOneWidget);

    await openTab(tester, 'IP 封禁');
    expect(find.text('IP 封禁（0）'), findsOneWidget);
    expect(find.text('暂无封禁 IP'), findsOneWidget);
    expect(find.text('没有被封禁的 IP 地址。'), findsOneWidget);

    await openTab(tester, 'OP');
    expect(find.text('OP 列表（0）'), findsOneWidget);
    expect(find.text('暂无 OP'), findsOneWidget);
    expect(find.text('点击上方「添加」按钮授予玩家管理权限。'), findsOneWidget);
  });

  testWidgets('封禁页：默认原因与永久到期不显示，命令照常发', (tester) async {
    final fixture = await bootPlayers();
    fixture.store.seedList(
      fixture.id,
      'bans',
      entries: [
        {
          'name': 'Alice',
          'uuid': 'u1',
          'reason': 'Banned by an operator.',
          'source': 'Server',
          'expires': 'forever',
          'created': '2026-01-01 00:00:00 +0800',
        },
        {
          'name': 'Bob',
          'uuid': 'u2',
          'reason': '开挂',
          'source': 'Server',
          'expires': '2026-02-01 00:00:00 +0800',
          'created': '2026-01-01 00:00:00 +0800',
        },
      ],
    );
    await pumpPage(tester, fixture);
    await openTab(tester, '封禁');

    expect(find.text('封禁名单（2）'), findsOneWidget);
    expect(find.text('原因：Banned by an operator.'), findsNothing);
    expect(find.text('forever'), findsNothing);
    expect(find.text('原因：开挂'), findsOneWidget);
    expect(find.text('到期：2026-02-01 00:00:00 +0800'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player_delete_Bob')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'pardon Bob\n');

    await tester.tap(find.byKey(const Key('players_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player_name_field')), 'Dana');
    await tester.enterText(find.byKey(const Key('player_reason_field')), '刷屏');
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'ban Dana 刷屏\n');
    await flushDelayedRefresh(tester);

    await tester.tap(find.byKey(const Key('players_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('player_name_field')), 'Eve');
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'ban Eve\n');
    await flushDelayedRefresh(tester);
  });

  testWidgets('IP 封禁页：原因不过滤默认值，命令用 ban-ip / pardon-ip', (tester) async {
    final fixture = await bootPlayers();
    fixture.store.seedList(
      fixture.id,
      'ip_bans',
      entries: [
        {
          'ip': '10.0.0.1',
          'reason': 'Banned by an operator.',
          'source': 'Server',
          'expires': 'forever',
          'created': '2026-01-01 00:00:00 +0800',
        },
      ],
    );
    await pumpPage(tester, fixture);
    await openTab(tester, 'IP 封禁');

    expect(find.text('IP 封禁（1）'), findsOneWidget);
    expect(find.byKey(const Key('player_row_10.0.0.1')), findsOneWidget);
    expect(find.text('原因：Banned by an operator.'), findsOneWidget);
    expect(find.textContaining('到期'), findsNothing);

    await tester.tap(find.byKey(const Key('player_delete_10.0.0.1')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'pardon-ip 10.0.0.1\n');

    await tester.tap(find.byKey(const Key('players_add')));
    await tester.pumpAndSettle();
    expect(find.text('封禁 IP'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('player_name_field')),
      '10.0.0.2',
    );
    await tester.enterText(find.byKey(const Key('player_reason_field')), '扫描');
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'ban-ip 10.0.0.2 扫描\n');
    await flushDelayedRefresh(tester);
  });

  testWidgets('OP 页：删发 deop、加发 op', (tester) async {
    final fixture = await bootPlayers();
    fixture.store.seedList(
      fixture.id,
      'ops',
      entries: [
        {'name': 'Alice', 'uuid': 'u1'},
      ],
    );
    await pumpPage(tester, fixture);
    await openTab(tester, 'OP');

    expect(find.text('OP 列表（1）'), findsOneWidget);
    expect(find.byKey(const Key('player_row_Alice')), findsOneWidget);
    expect(find.text('u1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player_delete_Alice')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'deop Alice\n');

    await tester.tap(find.byKey(const Key('players_add')));
    await tester.pumpAndSettle();
    expect(find.text('添加 OP'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('player_name_field')), 'Bob');
    await tester.tap(find.byKey(const Key('player_dialog_ok')));
    await tester.pumpAndSettle();
    expect(lastInput(fixture), 'op Bob\n');
    await flushDelayedRefresh(tester);
  });
}
