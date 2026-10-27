import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/settings/about.dart';
import 'package:edgecube_app/settings/about_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 关于页。
///
/// 钉四件事：前端/后端两张卡的数据来源各自独立、未连接不是错误、旧 daemon
/// 缺 `core.host` 时只降级不炸卡，以及 `core.host` 的线上字段能被宽容解析。

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

const _clientInfo = ClientDeviceInfo(
  appVersion: '2.0.0+200',
  platform: 'Android',
  system: 'Android 14 · SDK 34',
  device: 'Xiaomi 23127PN0CC',
  cpuCores: 8,
  memoryMb: 8192,
);

const _hostInfo = DaemonHostInfo(
  hostname: 'mc-host',
  osName: 'Ubuntu',
  osVersion: '24.04 LTS',
  kernelVersion: '6.8.0-31-generic',
  arch: 'x86_64',
  cpuBrand: 'AMD Ryzen 7 5800X',
  cpuCores: 16,
  cpuPhysicalCores: 8,
  memoryTotalMb: 32768,
  uptimeSecs: 90061,
);

/// 建好容器并连上假 daemon；页面/Provider 都要有人按住才不会被回收。
Future<({ProviderContainer container, FakeTransportFactory transports})>
_bootDaemon({
  Map<String, Object?>? responses,
  Map<String, Object? Function(Map<String, dynamic>)>? responders,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final transports = FakeTransportFactory(
    responses: responses,
    responders: responders,
  );
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: transports.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  container.listen(daemonDeviceInfoProvider, (_, _) {}, fireImmediately: true);
  await pumpEventQueue();
  return (container: container, transports: transports);
}

Future<void> _pumpAbout(
  WidgetTester tester, {
  ClientDeviceInfo client = _clientInfo,
  required AsyncValue<DaemonDeviceInfo?> daemon,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientDeviceInfoProvider.overrideWithValue(AsyncValue.data(client)),
        daemonDeviceInfoProvider.overrideWithValue(daemon),
      ],
      child: const MaterialApp(home: AboutPage()),
    ),
  );
  await tester.pump();
}

void main() {
  test('未连接时后端结果是 null，不发调用也不报错', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final transports = FakeTransportFactory();
    final container = bootContainer(
      storage: prefs,
      transportFactory: transports.call,
    );
    addTearDown(container.dispose);
    container.listen(
      daemonDeviceInfoProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await pumpEventQueue();

    final async = container.read(daemonDeviceInfoProvider);
    expect(async.value, isNull);
    expect(async.hasError, isFalse);
    expect(transports.created, isEmpty);
  });

  test('连接后解析 core.host 与 core.info', () async {
    final app = await _bootDaemon();

    final async = app.container.read(daemonDeviceInfoProvider);
    expect(async.hasError, isFalse, reason: '${async.error}');
    final info = async.value;
    expect(info, isNotNull);

    final host = info!.host!;
    expect(host.hostname, 'edgecube-test');
    expect(host.systemLabel, 'Linux 6.8.0-test');
    expect(host.cpuCoresLabel, '8 核（4 物理）');
    expect(host.memoryLabel, '16 GB');
    expect(host.uptimeLabel, '1 天 1 小时');
    expect(info.daemonLabel, '2.0.0 · 已运行 1 分 0 秒');

    await app.container.read(connectionProvider.notifier).disconnect();
  });

  test('旧 daemon 没有 core.host：标记不支持，但保留 core.info', () async {
    final app = await _bootDaemon(
      responders: {
        'core.host': (_) =>
            throw const DaemonException('method_not_found', '没有 core.host'),
      },
    );

    final info = app.container.read(daemonDeviceInfoProvider).value;
    expect(info, isNotNull);
    expect(info!.host, isNull);
    expect(info.hostUnsupported, isTrue);
    expect(info.daemonLabel, '2.0.0 · 已运行 1 分 0 秒');

    await app.container.read(connectionProvider.notifier).disconnect();
  });

  testWidgets('两张卡分别显示前端与后端设备信息', (tester) async {
    await _pumpAbout(
      tester,
      daemon: const AsyncValue.data(
        DaemonDeviceInfo(
          host: _hostInfo,
          info: {'version': '2.0.0', 'uptime_ms': 3723000},
        ),
      ),
    );

    expect(find.text('前端运行设备'), findsOneWidget);
    expect(find.text('后端运行设备'), findsOneWidget);

    expect(find.text('Android 14 · SDK 34'), findsOneWidget);
    expect(find.text('Xiaomi 23127PN0CC'), findsOneWidget);
    expect(find.text('8 核'), findsOneWidget);
    expect(find.text('8 GB'), findsOneWidget);
    expect(find.text('2.0.0+200'), findsOneWidget);

    expect(find.text('mc-host'), findsOneWidget);
    expect(find.text('Ubuntu 24.04 LTS'), findsOneWidget);
    expect(find.text('AMD Ryzen 7 5800X'), findsOneWidget);
    expect(find.text('16 核（8 物理）'), findsOneWidget);
    expect(find.text('32 GB'), findsOneWidget);
    expect(find.text('1 天 1 小时'), findsOneWidget);
    expect(find.text('2.0.0 · 已运行 1 小时 2 分'), findsOneWidget);
  });

  testWidgets('未连接时后端卡只提示未连接，前端卡照常显示', (tester) async {
    await _pumpAbout(tester, daemon: const AsyncValue.data(null));

    expect(find.textContaining('未连接守护进程'), findsOneWidget);
    expect(find.text('前端运行设备'), findsOneWidget);
    expect(find.text('2.0.0+200'), findsOneWidget);
    expect(find.textContaining('读取后端设备信息失败'), findsNothing);
  });

  testWidgets('旧 daemon 不支持 core.host 时给升级提示而不是错误', (tester) async {
    await _pumpAbout(
      tester,
      daemon: const AsyncValue.data(
        DaemonDeviceInfo(hostUnsupported: true, info: {'version': '1.9.0'}),
      ),
    );

    expect(find.textContaining('不支持 core.host'), findsOneWidget);
    expect(find.text('1.9.0'), findsOneWidget);
    expect(find.textContaining('读取后端设备信息失败'), findsNothing);
  });
}
