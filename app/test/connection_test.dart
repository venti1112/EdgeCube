import 'dart:convert';

import 'package:edgecube_app/app.dart';
import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 启动 App(复刻 main() 的预加载 + override 路径)。
///
/// [persisted] 非空表示"以前连成功过",此时应当跳过连接页直接进主界面。
Future<({ProviderContainer container, FakeTransportFactory transports})>
_pumpApp(
  WidgetTester tester, {
  ConnectionSettings? persisted,
  FakeTransportFactory? transports,
}) async {
  final factory = transports ?? FakeTransportFactory();
  SharedPreferences.setMockInitialValues({
    if (persisted != null)
      ConnectionSettings.storageKey: jsonEncode(persisted.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final persistedFromStore = loadPersistedConnection(prefs);
  final container = bootContainer(
    storage: prefs,
    persisted: persistedFromStore,
    transportFactory: factory.call,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
  );
  await tester.pumpAndSettle();
  return (container: container, transports: factory);
}

/// 连接页上填表并提交
Future<void> _fillAndSubmit(
  WidgetTester tester, {
  required String host,
  String port = '8787',
  String token = '',
}) async {
  await tester.enterText(find.byKey(const Key('connect_host')), host);
  await tester.enterText(find.byKey(const Key('connect_port')), port);
  if (token.isNotEmpty) {
    await tester.enterText(find.byKey(const Key('connect_token')), token);
  }
  await tester.tap(find.byKey(const Key('connect_submit')));
  await tester.pumpAndSettle();
}

/// 读某个输入框当前的值(TextFormField 内部才是标准 TextField)
String _fieldText(WidgetTester tester, String key) {
  final field = tester.widget<TextField>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
  );
  return field.controller?.text ?? '';
}

Future<ConnectionSettings?> _savedInStorage() async =>
    loadPersistedConnection(await SharedPreferences.getInstance());

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // 输入解析(纯函数,先把边界钉死)
  // ══════════════════════════════════════════════════════════════════════

  group('地址输入解析', () {
    test('裸地址 / 带端口 / 完整 URL 都能认出来', () {
      expect(ConnectionSettings.parseHostInput('192.168.1.10'), (
        host: '192.168.1.10',
        port: null,
      ));
      expect(ConnectionSettings.parseHostInput('192.168.1.10:9000'), (
        host: '192.168.1.10',
        port: 9000,
      ));
      expect(
        ConnectionSettings.parseHostInput('ws://192.168.1.10:9000/ws?token=abc'),
        (host: '192.168.1.10', port: 9000),
      );
      expect(ConnectionSettings.parseHostInput('http://user@host.local/'), (
        host: 'host.local',
        port: null,
      ));
      expect(ConnectionSettings.parseHostInput('[::1]:8787'), (
        host: '::1',
        port: 8787,
      ));
      expect(ConnectionSettings.parseHostInput('  spaced.host  '), (
        host: 'spaced.host',
        port: null,
      ));
      expect(ConnectionSettings.parseHostInput('https://mc.example.com/#/x'), (
        host: 'mc.example.com',
        port: null,
      ));
    });

    test('空输入与越界端口', () {
      expect(ConnectionSettings.parseHostInput(''), (host: '', port: null));
      expect(ConnectionSettings.parseHostInput('   '), (host: '', port: null));
      // 端口越界会被 clamp,不会把非法值带进配置
      expect(
        ConnectionSettings.parseHostInput('host:99999').port,
        ConnectionSettings.portMax,
      );
      expect(
        ConnectionSettings.fromJson({'host': 'h', 'port': -5}).port,
        ConnectionSettings.portMin,
      );
    });

    test('表单校验', () {
      expect(ConnectionSettings.validateHost(''), isNotNull);
      expect(ConnectionSettings.validateHost('has space'), isNotNull);
      expect(ConnectionSettings.validateHost('10.0.0.1'), isNull);
      expect(ConnectionSettings.validatePort(''), isNotNull);
      expect(ConnectionSettings.validatePort('abc'), isNotNull);
      expect(ConnectionSettings.validatePort('0'), isNotNull);
      expect(ConnectionSettings.validatePort('70000'), isNotNull);
      expect(ConnectionSettings.validatePort('8787'), isNull);
    });

    test('wsUri 把令牌放进查询串(浏览器不能自定义 WS 请求头)', () {
      const settings = ConnectionSettings(
        host: '10.0.0.2',
        port: 8787,
        token: 'tk',
      );
      expect(settings.wsUri.toString(), 'ws://10.0.0.2:8787/ws?token=tk');
      expect(
        const ConnectionSettings(host: '10.0.0.2').wsUri.toString(),
        'ws://10.0.0.2:8787/ws',
      );
    });

    test('存储读回:损坏内容与空地址都当作"没配置"', () async {
      SharedPreferences.setMockInitialValues({
        ConnectionSettings.storageKey: '{ 不是 json',
      });
      expect(
        loadPersistedConnection(await SharedPreferences.getInstance()),
        isNull,
      );

      SharedPreferences.setMockInitialValues({
        ConnectionSettings.storageKey: jsonEncode(
          const ConnectionSettings(host: '   ').toJson(),
        ),
      });
      expect(
        loadPersistedConnection(await SharedPreferences.getInstance()),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 首次启动:连接页
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('没有连接配置时,启动先显示 IP / 端口 / Token 输入框', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('connect_host')), findsOneWidget);
    expect(find.byKey(const Key('connect_port')), findsOneWidget);
    expect(find.byKey(const Key('connect_token')), findsOneWidget);
    expect(find.byKey(const Key('connect_submit')), findsOneWidget);
    expect(find.text('连接到 EdgeCube 守护进程'), findsOneWidget);

    // 还没连上,主界面不该出现
    expect(find.byKey(const Key('servers_target')), findsNothing);
    // 端口预填默认值
    expect(_fieldText(tester, 'connect_port'), '${ConnectionSettings.defaultPort}');
  });

  testWidgets('地址为空时提交被拦下,不会发起连接', (tester) async {
    final transports = FakeTransportFactory();
    await _pumpApp(tester, transports: transports);

    await tester.tap(find.byKey(const Key('connect_submit')));
    await tester.pumpAndSettle();

    expect(find.text('请输入服务器地址'), findsOneWidget);
    expect(transports.count, 0, reason: '校验没过就不该去连');
    expect(find.byKey(const Key('connect_host')), findsOneWidget);
  });

  testWidgets('填好地址点连接 → 握手成功 → 进入主界面,并把配置落盘', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(tester, transports: transports);

    await _fillAndSubmit(
      tester,
      host: '192.168.1.10',
      port: '9000',
      token: 's3cret',
    );

    // 1) 已经进主界面(连接页消失)
    expect(find.byKey(const Key('connect_host')), findsNothing);
    expect(find.byKey(const Key('servers_target')), findsOneWidget);
    expect(find.text('192.168.1.10:9000'), findsOneWidget);
    // 主界面显示的是真的从 WS 拿回来的 core.info
    expect(find.text('edgecube-daemon 2.0.0'), findsOneWidget);

    // 2) WS 地址正确(令牌走查询串)
    expect(
      transports.latest.uri.toString(),
      'ws://192.168.1.10:9000/ws?token=s3cret',
    );

    // 3) 配置落盘,下次启动不用再填
    final saved = await _savedInStorage();
    expect(saved?.host, '192.168.1.10');
    expect(saved?.port, 9000);
    expect(saved?.token, 's3cret');

    // 4) 单项 Provider 与聚合状态一致(单一真源)
    expect(app.container.read(daemonHostProvider), '192.168.1.10');
    expect(app.container.read(daemonPortProvider), 9000);
    expect(app.container.read(daemonTokenProvider), 's3cret');
    expect(app.container.read(isConnectedProvider), isTrue);
  });

  testWidgets('地址栏粘贴完整 URL 时自动拆成 host + port', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(tester, transports: transports);

    await _fillAndSubmit(
      tester,
      host: 'ws://10.1.2.3:9999/ws?token=abc',
      port: '1',
    );

    // 端口以地址里的为准,输入框被就地整理过(整理后的值落在全局 Provider 上)
    expect(transports.latest.uri.toString(), 'ws://10.1.2.3:9999/ws');
    expect(app.container.read(daemonHostProvider), '10.1.2.3');
    expect(app.container.read(daemonPortProvider), 9999);
  });

  testWidgets('连接失败:停在连接页并给出原因', (tester) async {
    final transports = FakeTransportFactory(accept: false);
    await _pumpApp(tester, transports: transports);

    await _fillAndSubmit(tester, host: '10.9.9.9', port: '5', token: 'x');

    expect(find.byKey(const Key('connect_error')), findsOneWidget);
    expect(find.textContaining('无法连接到 10.9.9.9:5'), findsOneWidget);
    // 仍然在连接页,且没有落盘
    expect(find.byKey(const Key('connect_host')), findsOneWidget);
    expect(await _savedInStorage(), isNull);
  });

  testWidgets('令牌错误:提示"访问令牌不正确"', (tester) async {
    final transports = FakeTransportFactory(
      accept: false,
      rejectWith: const DaemonException('unauthorized', '无权限'),
    );
    await _pumpApp(tester, transports: transports);

    await _fillAndSubmit(tester, host: '10.0.0.9', token: 'wrong');

    expect(find.text('访问令牌不正确'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 已配置过:直接进主界面
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('已有连接配置时跳过连接页,并自动连上', (tester) async {
    const saved = ConnectionSettings(host: '10.0.0.2', port: 8787, token: 'tk');
    final transports = FakeTransportFactory();
    await _pumpApp(tester, persisted: saved, transports: transports);

    expect(find.byKey(const Key('connect_host')), findsNothing);
    expect(find.byKey(const Key('servers_target')), findsOneWidget);
    expect(find.text('10.0.0.2:8787'), findsOneWidget);
    expect(transports.latest.uri.toString(), 'ws://10.0.0.2:8787/ws?token=tk');
    // 连上了就没有横幅
    expect(find.byKey(const Key('connection_banner')), findsNothing);
  });

  testWidgets('自动连接失败时留在主界面,用顶部横幅提示并可重试', (tester) async {
    const saved = ConnectionSettings(host: '10.0.0.3');
    final transports = FakeTransportFactory(accept: false);
    await _pumpApp(tester, persisted: saved, transports: transports);

    expect(
      find.byKey(const Key('connect_host')),
      findsNothing,
      reason: '不该踢回连接页',
    );
    expect(find.byKey(const Key('connection_banner')), findsOneWidget);
    // 横幅与「服务器」卡片上各有一个重试按钮,这里点横幅上的那个
    final bannerRetry = find.descendant(
      of: find.byKey(const Key('connection_banner')),
      matching: find.text('重试'),
    );
    expect(bannerRetry, findsOneWidget);

    // 服务端起来了 → 点重试就能连上,横幅消失
    transports.accept = true;
    await tester.tap(bannerRetry);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connection_banner')), findsNothing);
    expect(find.text('10.0.0.3:8787'), findsWidgets);
  });

  testWidgets('掉线后显示横幅并自动重连', (tester) async {
    const saved = ConnectionSettings(host: '10.0.0.4');
    final transports = FakeTransportFactory();
    await _pumpApp(tester, persisted: saved, transports: transports);

    expect(transports.count, 1);
    transports.latest.dropConnection();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('connection_banner')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('connection_banner')),
        matching: find.textContaining('连接已断开'),
      ),
      findsOneWidget,
    );

    // 退避 1s 后自动重连(第二条连接)
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(transports.count, 2, reason: '应当自动重连');
    expect(find.byKey(const Key('connection_banner')), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════════════
  // 竞态:连接途中改目标/断开
  // ══════════════════════════════════════════════════════════════════════

  test('连接途中改连另一台,先发起的那次结果作废', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final transports = FakeTransportFactory(
      helloDelay: const Duration(milliseconds: 150),
    );
    final container = bootContainer(
      storage: prefs,
      transportFactory: transports.call,
    );
    addTearDown(container.dispose);
    final notifier = container.read(connectionProvider.notifier);

    const first = ConnectionSettings(host: '10.1.1.1');
    const second = ConnectionSettings(host: '10.2.2.2');

    final firstAttempt = notifier.connect(first);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 第一次还在途中就改目标
    final secondAttempt = notifier.connect(second);

    expect(await firstAttempt, isFalse, reason: '被更新的请求取代');
    expect(await secondAttempt, isTrue);
    expect(container.read(connectionProvider).target, '10.2.2.2:8787');
    expect(container.read(isConnectedProvider), isTrue);
    // 落盘的是后一次
    expect(
      loadPersistedConnection(await SharedPreferences.getInstance())?.host,
      '10.2.2.2',
    );
  });

  test('断开后迟到的连接结果不会把状态改回已连接', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final transports = FakeTransportFactory(
      helloDelay: const Duration(milliseconds: 150),
    );
    final container = bootContainer(
      storage: prefs,
      transportFactory: transports.call,
    );
    addTearDown(container.dispose);
    final notifier = container.read(connectionProvider.notifier);

    final attempt = notifier.connect(const ConnectionSettings(host: '10.3.3.3'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await notifier.disconnect();

    expect(await attempt, isFalse);
    // 等迟到的那次真正回来
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(container.read(connectionPhaseProvider), ConnectionPhase.idle);
    expect(container.read(isConnectedProvider), isFalse);
    expect(
      loadPersistedConnection(await SharedPreferences.getInstance()),
      isNull,
      reason: '断开后不该落盘',
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // 订阅生命周期
  // ══════════════════════════════════════════════════════════════════════
  //
  // 两层语义:
  //   生效订阅 subscriptionsProvider —— 这条连接上真的订了什么,断了就空
  //   期望订阅 notifier.desiredTopics —— 重连后要不要补订的意图
  //
  // 注意:「服务器」页自己会订阅 core.conn_opened/closed,所以断言一律按
  // "包含/不包含"来写,不假设集合里只有测试加的那一条。

  testWidgets('掉线后生效订阅清空;重连成功后自动补订', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(
      tester,
      persisted: const ConnectionSettings(host: '10.0.0.4'),
      transports: transports,
    );
    final notifier = app.container.read(connectionProvider.notifier);

    await notifier.subscribe('ticker.*');
    await tester.pumpAndSettle();
    expect(app.container.read(subscriptionsProvider), contains('ticker.*'));

    transports.latest.dropConnection();
    await tester.pump();
    await tester.pump();

    // 连接没了 → 生效订阅清空(服务端那侧同样已经没了)
    expect(app.container.read(subscriptionsProvider), isEmpty);
    // 但意图还在,并且 UI 明确告诉用户「重连后会恢复」
    expect(notifier.desiredTopics, contains('ticker.*'));
    expect(find.byKey(const Key('servers_pending_subscriptions')), findsOneWidget);

    // 退避 1s 后自动重连 → 自动补订
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(app.container.read(isConnectedProvider), isTrue);
    expect(app.container.read(subscriptionsProvider), contains('ticker.*'));
    final resubscribed = transports.latest.sent
        .where((e) => e['type'] == 'subscribe')
        .map((e) => e['topic']);
    expect(resubscribed, contains('ticker.*'), reason: '重连后应当补订');
  });

  testWidgets('主动断开后订阅全清(生效集合与意图都不留)', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(
      tester,
      persisted: const ConnectionSettings(host: '10.0.0.13'),
      transports: transports,
    );
    final notifier = app.container.read(connectionProvider.notifier);
    await notifier.subscribe('ticker.*');
    await tester.pumpAndSettle();

    await notifier.disconnect();
    await tester.pumpAndSettle();

    expect(app.container.read(subscriptionsProvider), isEmpty);
    // 页面自己声明的订阅会立刻重新登记意图,但用户加的那条必须没了
    expect(notifier.desiredTopics, isNot(contains('ticker.*')));

    // 重新连上也不会把断开的订阅带回来
    await notifier.retry();
    await tester.pumpAndSettle();
    expect(app.container.read(isConnectedProvider), isTrue);
    expect(app.container.read(subscriptionsProvider), isNot(contains('ticker.*')));
  });

  testWidgets('换一台服务器不会把旧订阅带过去', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(
      tester,
      persisted: const ConnectionSettings(host: '10.0.0.9'),
      transports: transports,
    );
    final notifier = app.container.read(connectionProvider.notifier);
    await notifier.subscribe('ticker.*');
    await tester.pumpAndSettle();

    await notifier.connect(const ConnectionSettings(host: '10.0.0.10'));
    await tester.pumpAndSettle();

    expect(app.container.read(isConnectedProvider), isTrue);
    expect(notifier.desiredTopics, isNot(contains('ticker.*')));
    final sentTopics = transports.latest.sent
        .where((e) => e['type'] == 'subscribe')
        .map((e) => e['topic']);
    expect(sentTopics, isNot(contains('ticker.*')), reason: '旧服务器的主題不该发到新连接上');
  });

  testWidgets('自动重试次数用尽后清空订阅意图', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(
      tester,
      persisted: const ConnectionSettings(host: '10.0.0.11'),
      transports: transports,
    );
    final notifier = app.container.read(connectionProvider.notifier);
    await notifier.subscribe('ticker.*');
    await tester.pumpAndSettle();

    // 服务端没了,而且再也起不来
    transports.accept = false;
    transports.latest.dropConnection();
    await tester.pump();
    await tester.pump();

    // 逐轮退避(1/2/4/8/15s),每轮都把时钟推过去
    for (var i = 0; i < maxAutoRetries + 2; i++) {
      await tester.pump(const Duration(seconds: 20));
    }

    expect(
      app.container.read(connectionProvider).attempt,
      greaterThan(maxAutoRetries),
      reason: '重连失败也要接着排下一次,才能真的走到上限',
    );
    expect(app.container.read(subscriptionsProvider), isEmpty);
    expect(notifier.desiredTopics, isEmpty, reason: '不会再恢复了,意图也该清掉');

    // 手动重试成功也不会凭空冒出订阅(「服务器」页自己声明的除外)
    transports.accept = true;
    await notifier.retry();
    await tester.pumpAndSettle();
    expect(app.container.read(isConnectedProvider), isTrue);
    expect(
      app.container.read(subscriptionsProvider),
      isNot(contains('ticker.*')),
      reason: '重试次数用尽时清掉的意图不该复活',
    );
  });

  testWidgets('unsubscribe / unsubscribeAll 会真的发出取消帧', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(
      tester,
      persisted: const ConnectionSettings(host: '10.0.0.14'),
      transports: transports,
    );
    final notifier = app.container.read(connectionProvider.notifier);
    await notifier.subscribe('ticker.*');
    await notifier.subscribe('core.started');
    await tester.pumpAndSettle();

    await notifier.unsubscribe('ticker.*');
    await tester.pumpAndSettle();
    expect(app.container.read(subscriptionsProvider), isNot(contains('ticker.*')));
    expect(
      transports.latest.sent.lastWhere((e) => e['type'] == 'unsubscribe')['topic'],
      'ticker.*',
    );

    await notifier.unsubscribeAll();
    await tester.pumpAndSettle();
    expect(app.container.read(subscriptionsProvider), isEmpty);
    expect(notifier.desiredTopics, isEmpty);
  });

  testWidgets('主界面把当前订阅显示出来,并可一键取消', (tester) async {
    final transports = FakeTransportFactory();
    final app = await _pumpApp(
      tester,
      persisted: const ConnectionSettings(host: '10.0.0.15'),
      transports: transports,
    );
    await app.container.read(connectionProvider.notifier).subscribe('ticker.*');
    await tester.pumpAndSettle();

    final label = tester
        .widget<Text>(find.byKey(const Key('servers_subscriptions')))
        .data!;
    expect(label, contains('ticker.*'));
    // 「服务器」页自己也订了连接事件
    expect(label, contains('core.conn_opened'));

    await tester.tap(find.text('取消全部订阅'));
    await tester.pumpAndSettle();
    expect(app.container.read(subscriptionsProvider), isEmpty);
    expect(
      tester.widget<Text>(find.byKey(const Key('servers_subscriptions'))).data,
      '已订阅：无',
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // 设置页:改地址 / 断开 / 忘记
  // ══════════════════════════════════════════════════════════════════════

  testWidgets('连接设置页可改地址重连,也可忘记服务器回到连接页', (tester) async {
    const saved = ConnectionSettings(host: '10.0.0.5');
    final transports = FakeTransportFactory();
    await _pumpApp(tester, persisted: saved, transports: transports);

    // 设置(侧栏) → 连接
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings_host')), findsOneWidget);

    // 改地址并重连
    await tester.enterText(find.byKey(const Key('settings_host')), '10.0.0.6');
    await tester.tap(find.byKey(const Key('settings_connect')));
    await tester.pumpAndSettle();
    expect(transports.latest.uri!.host, '10.0.0.6');
    expect((await _savedInStorage())?.host, '10.0.0.6');

    // 断开连接:保留配置,留在主界面
    await tester.tap(find.byKey(const Key('settings_disconnect')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings_disconnect')), findsNothing);

    // 忘记服务器 → 清空 → 守卫把人送回连接页
    await tester.tap(find.text('忘记这台服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('忘记'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connect_host')), findsOneWidget);
    expect(await _savedInStorage(), isNull);
    expect(_fieldText(tester, 'connect_host'), '');
  });
}
