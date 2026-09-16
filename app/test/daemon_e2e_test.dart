@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真机联调:拿**真实的** WebSocket 传输去连**真实的** daemon 进程。
///
/// 单元测试用的是假传输,验不了两边协议是否真的对得上(字段名、错误码、
/// 订阅信封……)。这个文件把 daemon 二进制拉起来(port = 0 让系统分配,
/// 从 JSON 日志里读回真实端口),再走一遍握手 / 调用 / 订阅推送 / 鉴权拒绝,
/// 以及「连接断开后订阅不会残留」。
///
/// 没编译过后端时自动跳过,不阻塞前端开发:
///
/// ```bash
/// cd daemon && cargo build
/// ```

/// 在常见位置找 daemon 二进制(测试的工作目录是 app/ 包根)
File? _findDaemonBinary() {
  for (final path in const [
    '../daemon/target/debug/edgecube-daemon',
    'daemon/target/debug/edgecube-daemon',
    '../daemon/target/release/edgecube-daemon',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

final File? _binary = _findDaemonBinary();
final String? _skipReason = _binary == null
    ? '没找到 daemon 二进制,先执行 `cd daemon && cargo build`'
    : null;

const _token = 'e2e-token';

/// 某个 daemon 实例的句柄。
typedef DaemonUnderTest = ({
  Process process,
  int port,
  Directory dir,
  List<String> logs,
});

/// 起 daemon 并等它报出真实监听端口,同时登记测试结束后的清理。
Future<DaemonUnderTest> startDaemon() async {
  final dir = Directory.systemTemp.createTempSync('edgecube-e2e-');
  final config = File('${dir.path}/daemon.toml');
  config.writeAsStringSync('''
[server]
host = "127.0.0.1"
# 0 = 由系统分配,避免与开发机上已在跑的服务撞端口
port = 0
token = "$_token"

[log]
level = "info"
# json 日志便于把真实端口读回来
format = "json"

[modules.config.ticker]
interval_ms = 60
''');

  final process = await Process.start(_binary!.path, ['-c', config.path]);
  final logs = <String>[];
  final port = Completer<int>();

  void onLine(String line) {
    logs.add(line);
    if (port.isCompleted) return;
    try {
      final parsed = jsonDecode(line) as Map<String, dynamic>;
      final fields = parsed['fields'] as Map<String, dynamic>?;
      final addr = fields?['addr'] as String?;
      if (addr != null && addr.contains(':')) {
        port.complete(int.parse(addr.split(':').last));
      }
    } catch (_) {
      // 非 JSON 行(如 panic)忽略,靠下面的超时报错
    }
  }

  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onLine);
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onLine);

  final value = await port.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () =>
        throw StateError('daemon 未在 20s 内就绪,日志:\n${logs.join('\n')}'),
  );

  addTearDown(() async {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    dir.deleteSync(recursive: true);
  });

  return (process: process, port: value, dir: dir, logs: logs);
}

/// 连上指定 daemon 的一条新连接。
Future<DaemonClient> connectClient(DaemonUnderTest daemon, {String? token}) async {
  final client = DaemonClient(
    WebSocketDaemonTransport(),
    Uri.parse('ws://127.0.0.1:${daemon.port}/ws?token=${token ?? _token}'),
  );
  addTearDown(client.close);
  await client.connect();
  return client;
}

void main() {
  test('真实 daemon:握手 / 调用 / 订阅推送 / 鉴权拒绝', () async {
    final daemon = await startDaemon();

    // ── 令牌不对:握手就该被拒 ──────────────────────────────────────────
    final rejected = DaemonClient(
      WebSocketDaemonTransport(),
      Uri.parse('ws://127.0.0.1:${daemon.port}/ws?token=nope'),
    );
    addTearDown(rejected.close);
    await expectLater(rejected.connect(), throwsA(anything));

    // ── 正令牌:hello 自报家门 ─────────────────────────────────────────
    final client = await connectClient(daemon);

    final hello = client.hello!;
    expect(hello.product, 'edgecube-daemon');
    expect(hello.protocol, 1);
    expect(hello.methods, contains('core.ping'));
    expect(hello.methods, contains('ticker.start'));
    expect(hello.topics, contains('ticker.tick'));
    expect(hello.modules, containsAll(<String>['core', 'ticker']));
    expect(hello.authRequired, isTrue);

    // ── 类 HTTP 的一问一答 ─────────────────────────────────────────────
    final info = await client.callObject('core.info');
    expect(info['product'], 'edgecube-daemon');
    // bind 必须是**实际**监听地址(配置里是 port = 0)
    expect(info['bind'], '127.0.0.1:${daemon.port}');
    expect(info['auth_required'], isTrue);
    expect(info['shutting_down'], isFalse);

    final pong = await client.callObject('core.ping');
    expect(pong['pong'], isTrue);

    // 未知方法 → 稳定错误码,且连接不被打断
    await expectLater(
      client.call('core.nope'),
      throwsA(
        isA<DaemonException>().having((e) => e.code, 'code', 'method_not_found'),
      ),
    );
    expect((await client.callObject('core.ping'))['pong'], isTrue);

    // 参数不合法 → invalid_params
    await expectLater(
      client.call('ticker.start', params: {'interval_ms': 'soon'}),
      throwsA(
        isA<DaemonException>().having((e) => e.code, 'code', 'invalid_params'),
      ),
    );

    // ── 订阅 + 服务端主动推送 ──────────────────────────────────────────
    // 先挂上监听,再让它开跑,避免抢跑丢事件
    final firstTick = client.events.firstWhere(
      (event) => event['topic'] == 'ticker.tick',
    );
    await client.subscribe('ticker.*');
    await client.callObject('ticker.start', params: {'interval_ms': 60});
    final event = await firstTick.timeout(const Duration(seconds: 5));
    expect(event['source'], 'ticker');
    expect((event['data'] as Map)['n'], isA<int>());

    final status = await client.callObject('ticker.status');
    expect(status['running'], isTrue);

    await client.close();
    expect(client.isAlive, isFalse);
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  test('真实 daemon:连接断开后订阅不会留给下一条连接', () async {
    final daemon = await startDaemon();

    // A:订阅 + 收到推送
    final a = await connectClient(daemon);
    await a.subscribe('ticker.*');
    final tickForA = a.events.firstWhere((e) => e['topic'] == 'ticker.tick');
    await a.callObject('ticker.start', params: {'interval_ms': 60});
    await tickForA.timeout(const Duration(seconds: 5));
    await a.close();

    // B:新连接,什么也没订。ticker 还在推,但 B 不该收到任何东西。
    final b = await connectClient(daemon);
    final leaked = <String>[];
    final sink = b.events.listen((e) => leaked.add('${e['topic']}'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(leaked, isEmpty, reason: '订阅是连接级的,断了就该没,不能漏给下一条连接');

    // 反证:B 自己订上就能收到,说明上面不是因为 ticker 停了
    final tickForB = b.events.firstWhere((e) => e['topic'] == 'ticker.tick');
    await b.subscribe('ticker.*');
    await tickForB.timeout(const Duration(seconds: 5));
    expect(leaked, isNotEmpty);

    await sink.cancel();
    await b.callObject('ticker.stop');
    await b.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));
}
