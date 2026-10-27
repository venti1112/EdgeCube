import 'dart:convert';

import 'package:edgecube_app/app.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/local_service/model.dart';
import 'package:edgecube_app/local_service/settings.dart';
import 'package:edgecube_app/local_service/state.dart';
import 'package:edgecube_app/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/local_service_fake.dart';

/// 启动 App(复刻 main() 的预加载 + override 路径)。
///
/// 本地服务准备阶段有一直转的进度圈,所以这里只推进有限帧,
/// 需要 settle 的用例在服务就绪后自行 `pumpAndSettle`。
Future<({ProviderContainer container, FakeTransportFactory transports})>
_pumpApp(
  WidgetTester tester, {
  FakeLocalServicePlatform? local,
  bool localEnabled = false,
  ConnectionSettings? persisted,
  FakeTransportFactory? transports,
}) async {
  final platform = local ?? FakeLocalServicePlatform();
  final factory = transports ?? FakeTransportFactory();
  SharedPreferences.setMockInitialValues({
    if (persisted != null)
      ConnectionSettings.storageKey: jsonEncode(persisted.toJson()),
    if (localEnabled) localServiceEnabledStorageKey: true,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = bootContainer(
    storage: prefs,
    persisted: loadPersistedConnection(prefs),
    localServiceEnabled: loadLocalServiceEnabled(prefs),
    localServicePlatform: platform,
    transportFactory: factory.call,
  );
  addTearDown(container.dispose);
  addTearDown(platform.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return (container: container, transports: factory);
}

Future<void> _tapStart(WidgetTester tester) async {
  final start = find.byKey(const Key('local_service_start'));
  await tester.ensureVisible(start);
  await tester.tap(start);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  test('状态解析:字段缺失与未知阶段都按停止处理', () {
    final running = LocalServiceStatus.fromMap({
      'state': 'running',
      'host': '127.0.0.1',
      'port': 9000,
      'wsPath': '/ws',
      'token': 'tk',
      'version': '2.0.0',
      'prepared': true,
    });
    expect(running.phase, LocalServicePhase.running);
    expect(running.connection?.target, '127.0.0.1:9000');
    expect(running.connection?.token, 'tk');
    expect(running.prepared, isTrue);

    expect(
      LocalServiceStatus.fromMap({'state': 'wat'}).phase,
      LocalServicePhase.stopped,
    );
    expect(
      const LocalServiceStatus(phase: LocalServicePhase.preparing).connection,
      isNull,
      reason: '没就绪时不能拿去连接',
    );
  });

  testWidgets('连接页显示本地服务入口与日志框', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('local_service_panel')), findsOneWidget);
    expect(find.byKey(const Key('local_service_start')), findsOneWidget);
    expect(find.byKey(const Key('local_service_status')), findsOneWidget);
    expect(find.byKey(const Key('local_service_logs')), findsOneWidget);
    expect(find.text('暂无日志'), findsOneWidget);
  });

  testWidgets('启动本地服务:准备中留在连接页,就绪后自动连接且不落盘', (tester) async {
    final platform = FakeLocalServicePlatform();
    final app = await _pumpApp(tester, local: platform);

    await _tapStart(tester);

    expect(platform.startCalls, 1);
    expect(
      find.byKey(const Key('connect_host')),
      findsOneWidget,
      reason: '准备期间要留在连接页显示进度与日志',
    );
    expect(find.textContaining('正在准备本地环境'), findsWidgets);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        localServiceEnabledStorageKey,
      ),
      isTrue,
      reason: '开关要在启动时落盘,下次打开才会自动启动',
    );

    platform.log('[EdgeCube] 解压本地环境…');
    await tester.pump();
    expect(find.text('[EdgeCube] 解压本地环境…'), findsOneWidget);

    platform.finishStart(port: 41001, token: 'local-token');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connect_host')), findsNothing);
    expect(find.byKey(const Key('servers_instance_selector')), findsOneWidget);
    expect(app.container.read(connectionProvider).target, '127.0.0.1:41001');
    expect(
      app.transports.latest.uri.toString(),
      'ws://127.0.0.1:41001/ws?token=local-token',
    );
    // 本地端口/令牌是临时的:不能覆盖「已保存的服务器」
    expect(
      loadPersistedConnection(await SharedPreferences.getInstance()),
      isNull,
    );
  });

  testWidgets('配置里开着本地服务:启动即自动准备并连接,不闪连接页', (tester) async {
    final platform = FakeLocalServicePlatform();
    final app = await _pumpApp(tester, local: platform, localEnabled: true);

    expect(platform.startCalls, 1);
    expect(
      find.byKey(const Key('connect_host')),
      findsNothing,
      reason: '开关为开时初始路由直接进主界面',
    );
    expect(find.textContaining('正在准备本地环境'), findsWidgets);

    platform.finishStart(port: 41002, token: 'tk2');
    await tester.pumpAndSettle();

    expect(app.container.read(connectionProvider).target, '127.0.0.1:41002');
    expect(find.byKey(const Key('servers_instance_selector')), findsOneWidget);
    expect(find.byKey(const Key('connection_banner')), findsNothing);
  });

  testWidgets('本地环境准备失败:留在连接页显示原因并可重试', (tester) async {
    final platform = FakeLocalServicePlatform();
    await _pumpApp(tester, local: platform);

    await _tapStart(tester);
    platform.fail('本地环境解压失败');
    await tester.pump();

    expect(find.text('本地环境解压失败'), findsWidgets);
    expect(find.byKey(const Key('connect_host')), findsOneWidget);
    expect(find.byKey(const Key('local_service_start')), findsOneWidget);
  });

  testWidgets('手工连接 127.0.0.1 不等于开启本地服务', (tester) async {
    final platform = FakeLocalServicePlatform();
    final app = await _pumpApp(tester, local: platform);

    await tester.enterText(find.byKey(const Key('connect_host')), '127.0.0.1');
    await tester.enterText(find.byKey(const Key('connect_port')), '8787');
    await tester.tap(find.byKey(const Key('connect_submit')));
    await tester.pumpAndSettle();

    expect(app.container.read(connectionProvider).target, '127.0.0.1:8787');
    expect(platform.startCalls, 0);
    expect(app.container.read(localServiceEnabledProvider), isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        localServiceEnabledStorageKey,
      ),
      isNull,
    );
  });

  test('停止本地服务会断开它拉起的连接并关闭开关', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final platform = FakeLocalServicePlatform();
    final transports = FakeTransportFactory();
    final container = bootContainer(
      storage: prefs,
      localServicePlatform: platform,
      transportFactory: transports.call,
    );
    addTearDown(container.dispose);
    addTearDown(platform.dispose);

    final local = container.read(localServiceProvider.notifier);
    await local.start();
    platform.finishStart(port: 41003, token: 'tk3');
    await pumpEventQueue();
    expect(container.read(isConnectedProvider), isTrue);
    expect(container.read(connectionProvider).target, '127.0.0.1:41003');
    expect(container.read(localServiceEnabledProvider), isTrue);

    await local.stop();
    await pumpEventQueue();

    expect(platform.stopCalls, 1);
    expect(container.read(localServiceEnabledProvider), isFalse);
    expect(container.read(connectionPhaseProvider), ConnectionPhase.idle);
  });

  testWidgets('连接设置页有独立的本地服务开关', (tester) async {
    const saved = ConnectionSettings(host: '10.0.0.8', port: 8787);
    final platform = FakeLocalServicePlatform();
    final app = await _pumpApp(tester, local: platform, persisted: saved);

    app.container.read(routerProvider).go('/settings/connection');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local_service_switch')), findsOneWidget);
    expect(find.byKey(const Key('local_service_start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('local_service_switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(platform.startCalls, 1);
    expect(app.container.read(localServiceEnabledProvider), isTrue);

    // 收尾:停掉服务,别把转圈动画留到测试结束
    await app.container.read(localServiceProvider.notifier).stop();
    await tester.pumpAndSettle();
    expect(platform.stopCalls, 1);
  });
}
