import 'dart:convert';

import 'package:edgecube_app/app.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/pages/manage_page.dart';
import 'package:edgecube_app/pages/shell_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

const _savedConnection = ConnectionSettings(host: '127.0.0.1', token: 't');

/// 一块收集 PTY 连接信息的用具：地址 + 每次新建的假传输。
class _PtyProbe {
  final List<Uri> urls = [];
  final List<FakePtyTransport> transports = [];
}

/// 直接 pump 主机终端页（不经过路由）。
Future<({ProviderContainer container, FakeTransportFactory daemon, _PtyProbe pty})>
_pumpShell(
  WidgetTester tester, {
  ConnectionSettings? persisted = _savedConnection,
  Map<String, Object? Function(Map<String, dynamic>)>? responders,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final daemon = FakeTransportFactory(responders: responders);
  final probe = _PtyProbe();
  final container = bootContainer(
    storage: prefs,
    persisted: persisted,
    transportFactory: daemon.call,
    ptyTransportFactory: (uri) {
      probe.urls.add(uri);
      final transport = FakePtyTransport();
      probe.transports.add(transport);
      return transport;
    },
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ShellPage()),
    ),
  );
  // 页面单独 pump 时没人替我们发起连接（正式启动走 app.dart 的
  // connectIfConfigured）；这里补上，否则 url 一直是 null。
  if (persisted != null) {
    await container.read(connectionProvider.notifier).connectIfConfigured();
  }
  await tester.pumpAndSettle();
  return (container: container, daemon: daemon, pty: probe);
}

void main() {
  testWidgets('主机终端连的是 /shell，令牌挂在查询串上', (tester) async {
    final shell = await _pumpShell(tester);

    expect(shell.pty.urls, hasLength(1), reason: '进页面就该连一次');
    expect(shell.pty.urls.single.path, '/shell');
    expect(shell.pty.urls.single.queryParameters['token'], 't');
  });

  testWidgets('history_end 的 state 反映到副标题：运行中', (tester) async {
    final shell = await _pumpShell(tester);
    final transport = shell.pty.transports.single;

    transport.pushControl({'type': 'history_begin'});
    transport.pushBytes(utf8.encode('\$ ls\n'));
    transport.pushControl({
      'type': 'history_end',
      'state': {'phase': 'running', 'pid': 4321, 'exit_code': null},
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('daemon 主机 · 运行中'), findsOneWidget);
    expect(find.text('主机终端'), findsOneWidget);
  });

  testWidgets('退出帧带上退出码：副标题变成已退出', (tester) async {
    final shell = await _pumpShell(tester);
    final transport = shell.pty.transports.single;

    transport.pushControl({
      'type': 'history_end',
      'state': {'phase': 'running'},
    });
    transport.pushControl({'type': 'exit', 'code': 3, 'phase': 'stopped'});
    await tester.pump();
    await tester.pump();

    expect(find.text('daemon 主机 · 已退出（退出码 3）'), findsOneWidget);
  });

  testWidgets('重启按钮：先调 shell.restart，再重连一条新流', (tester) async {
    final shell = await _pumpShell(
      tester,
      responders: {
        'shell.restart': (_) => {'restarted': true},
      },
    );
    expect(shell.pty.transports, hasLength(1));

    await tester.tap(find.byKey(const Key('shell_restart')));
    // 重启是「先发 WS 请求、回来再重连」，要等异步链跑完
    await tester.pumpAndSettle();

    final sent = shell.daemon.created.single.sent;
    expect(
      sent.any((envelope) => envelope['method'] == 'shell.restart'),
      isTrue,
      reason: '重启要落到 daemon 上，不是只重连',
    );
    expect(
      shell.pty.transports,
      hasLength(2),
      reason: '重启后应当丢掉旧连接、重新连一条',
    );
  });

  testWidgets('没连上 daemon：显示空态，不去连 PTY', (tester) async {
    final shell = await _pumpShell(tester, persisted: null);

    // 副标题与空态各有一句，所以是 findsWidgets
    expect(find.text('未连接到守护进程'), findsWidgets);
    expect(shell.pty.urls, isEmpty);
  });

  testWidgets('管理页入口：点「主机终端」进页面，底栏还在', (tester) async {
    SharedPreferences.setMockInitialValues({
      ConnectionSettings.storageKey: jsonEncode(_savedConnection.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final probe = _PtyProbe();
    final container = bootContainer(
      storage: prefs,
      persisted: loadPersistedConnection(prefs),
      transportFactory: FakeTransportFactory().call,
      ptyTransportFactory: (uri) {
        probe.urls.add(uri);
        final transport = FakePtyTransport();
        probe.transports.add(transport);
        return transport;
      },
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('管理'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ManagePage), findsOneWidget);
    expect(find.text('主机终端'), findsOneWidget);

    await tester.tap(find.text('主机终端'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(ShellPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget, reason: '子页也要带底栏');
    expect(probe.urls.single.path, '/shell');
  });
}
