import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/monitor/models.dart';
import 'package:edgecube_app/monitor/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 一次推送用的快照（形状与 daemon 的 `monitor.stats` 事件里的 data 一致）。
Map<String, Object?> pushedSnapshot({
  int sampledAtMs = 1700000009999,
  int totalMemMb = 100,
  int usedMemMb = 50,
  double? cpuUsage = 7.5,
}) => {
  'sampled_at_ms': sampledAtMs,
  'interval_ms': 2000,
  'supported': true,
  'total_mem_mb': totalMemMb,
  'used_mem_mb': usedMemMb,
  'available_mem_mb': totalMemMb - usedMemMb,
  'used_mem_percent': totalMemMb == 0 ? 0.0 : usedMemMb / totalMemMb * 100,
  'cpu_usage': cpuUsage,
  'cpu_cores': 2,
  'server_mem_mb': null,
};

const _settings = ConnectionSettings(host: '127.0.0.1', port: 8787, token: 't');

/// 按住 Provider。
///
/// **Riverpod 3 的 Provider 默认是 auto-dispose 的**：没有监听者就会被回收，
/// 回收后异步回写会被 `ref.mounted` 挡掉，再 `read` 又是一个全新的
/// loading 实例。界面上是 `_MonitorCard` 的 `ref.watch` 在按住它，
/// 这里没有 widget，只好自己挂一个空监听。
void _keepAlive(ProviderContainer container) {
  container.listen(monitorSnapshotProvider, (_, _) {}, fireImmediately: true);
}

/// 建好容器并连上假 daemon。
Future<({ProviderContainer container, FakeTransportFactory transports})> boot({
  Map<String, Object?>? responses,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final transports = FakeTransportFactory(responses: responses);
  final container = bootContainer(
    storage: prefs,
    persisted: _settings,
    transportFactory: transports.call,
  );
  addTearDown(container.dispose);
  await container.read(connectionProvider.notifier).connect(_settings);
  _keepAlive(container);
  return (container: container, transports: transports);
}

/// 只建容器，不连接。
Future<ProviderContainer> bootOffline() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final transports = FakeTransportFactory();
  final container = bootContainer(
    storage: prefs,
    transportFactory: transports.call,
  );
  addTearDown(container.dispose);
  _keepAlive(container);
  return container;
}

void main() {
  test('没连上时只登记订阅意图，不发任何调用', () async {
    final container = await bootOffline();

    // 没连也要能读：页面停在连接页时也会 watch 它
    final async = container.read(monitorSnapshotProvider);
    expect(async.value, isNull);
    expect(async.hasError, isFalse, reason: '未连接不该是错误态');

    // 意图已登记：连上/重连后由连接层自动补订，页面不用管
    expect(
      container.read(connectionProvider.notifier).desiredTopics,
      contains(kMonitorStatsTopic),
    );
  });

  test('连上后先拉一次 monitor.snapshot，并按线上格式解析', () async {
    final app = await boot();
    expect(app.container.read(monitorSnapshotProvider).value, isNull);

    await pumpEventQueue();

    final snapshot = app.container.read(monitorSnapshotProvider).value;
    expect(snapshot, isNotNull, reason: '首拉应当在连接后就完成');
    // 数字来自 FakeDaemonTransport.defaultResponses['monitor.snapshot']
    expect(snapshot!.totalMemMb, 31845);
    expect(snapshot.usedMemMb, 10253);
    expect(snapshot.cpuCores, 8);
    expect(snapshot.memoryLabel, '10253 MB / 31845 MB');
    expect(snapshot.cpuLabel, '11.0%');
    expect(snapshot.cpuPercent, 11.0);
    expect(snapshot.serverMemMb, isNull, reason: '进程模块没接入，恒为 null');
    expect(snapshot.hasMemory, isTrue);

    expect(
      app.container.read(connectionProvider.notifier).desiredTopics,
      contains(kMonitorStatsTopic),
    );
    await app.container.read(connectionProvider.notifier).disconnect();
  });

  test('之后靠 monitor.stats 推送更新，不再回拉一次', () async {
    final app = await boot();
    await pumpEventQueue();
    int snapshotCalls() => app.transports.latest.sent
        .where((e) => e['method'] == 'monitor.snapshot')
        .length;
    final callsBefore = snapshotCalls();

    app.transports.latest.pushEvent(kMonitorStatsTopic, pushedSnapshot());
    await pumpEventQueue();

    final snapshot = app.container.read(monitorSnapshotProvider).value!;
    expect(snapshot.usedMemMb, 50);
    expect(snapshot.totalMemMb, 100);
    expect(snapshot.memoryLabel, '50 MB / 100 MB');
    expect(snapshot.cpuLabel, '7.5%');

    // 推送里带的就是完整快照，不该再回一次 monitor.snapshot
    //（默认 2s 一份，回拉等于把 WS 流量翻倍）
    expect(snapshotCalls(), callsBefore, reason: '推送之后不该再多一次回拉');

    await app.container.read(connectionProvider.notifier).disconnect();
  });

  test('cpu_usage 为 null（刚起来 / 平台不支持）时显示不可用，不假装 0', () async {
    final app = await boot(
      responses: {
        'monitor.snapshot': {
          'sampled_at_ms': 1700000000000,
          'interval_ms': 2000,
          'supported': true,
          'total_mem_mb': 31845,
          'used_mem_mb': 10253,
          'available_mem_mb': 21592,
          'used_mem_percent': 32.2,
          // daemon 刚起来：还没攒够两次采样，如实是 null
          'cpu_usage': null,
          'cpu_cores': 8,
          'server_mem_mb': null,
        },
      },
    );
    await pumpEventQueue();

    final snapshot = app.container.read(monitorSnapshotProvider).value!;
    expect(snapshot.hasCpu, isFalse);
    expect(snapshot.cpuLabel, '不可用');
    expect(snapshot.cpuPercent, 0.0, reason: '进度条空着，不假装有占用');
    // 内存是有的，不该被 CPU 的 null 带下水
    expect(snapshot.memoryLabel, '10253 MB / 31845 MB');

    await app.container.read(connectionProvider.notifier).disconnect();
  });

  test('平台不支持时两项都显示不可用', () async {
    final app = await boot(
      responses: {
        'monitor.snapshot': {
          'sampled_at_ms': 1700000000000,
          'interval_ms': 2000,
          'supported': false,
          'total_mem_mb': 0,
          'used_mem_mb': 0,
          'available_mem_mb': 0,
          'used_mem_percent': 0.0,
          'cpu_usage': null,
          'cpu_cores': 0,
          'server_mem_mb': null,
        },
      },
    );
    await pumpEventQueue();

    final snapshot = app.container.read(monitorSnapshotProvider).value!;
    expect(snapshot.supported, isFalse);
    expect(snapshot.hasMemory, isFalse);
    expect(snapshot.memoryLabel, '不可用');
    expect(snapshot.cpuLabel, '不可用');

    await app.container.read(connectionProvider.notifier).disconnect();
  });

  test('字段缺失 / 类型不对时不炸，退化成不可用', () {
    final snapshot = SystemSnapshot.fromJson({'cpu_usage': 'nonsense'});
    expect(snapshot.supported, isFalse);
    expect(snapshot.totalMemMb, 0);
    expect(snapshot.cpuUsage, isNull);
    expect(snapshot.memoryLabel, '不可用');
    expect(snapshot.cpuLabel, '不可用');
  });
}
