@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/transport.dart';
import 'package:edgecube_app/download/models.dart';
import 'package:edgecube_app/frp/api.dart';
import 'package:edgecube_app/frp/models.dart';
import 'package:edgecube_app/instance/api.dart';
import 'package:edgecube_app/instance/config/api.dart';
import 'package:edgecube_app/mcserver/models.dart';
import 'package:edgecube_app/mods/api.dart';
import 'package:edgecube_app/monitor/models.dart';
import 'package:edgecube_app/runtime/api.dart';
import 'package:edgecube_app/task/api.dart';
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

[modules.config.download]
# 默认 500ms;这条用例要看到下载途中的事件,压到 50ms
progress_interval_ms = 50
''');

  final process = await Process.start(
    _binary!.path,
    ['-c', config.path],
    // 不下发 EDGECUBE_DATA_DIR 的话 daemon 会写开发机自己的数据目录
    // （`~/.local/share/edgecube`）：测试实例会留在那儿，重跑时撞名字。
    //
    // NO_PROXY 也是必须的：daemon 里的下载引擎是 reqwest，它会读环境里的
    // HTTP_PROXY —— 开发机上真配了代理的话，连回环的下载都会被塞进代理。
    environment: {
      'EDGECUBE_DATA_DIR': '${dir.path}/data',
      'NO_PROXY': '127.0.0.1,localhost,::1',
      'no_proxy': '127.0.0.1,localhost,::1',
    },
  );
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

/// 一台只服务一个固定字节串的本地 HTTP 服务。
///
/// 下载那一段用它当下载源，而不是真去下几十 MB 的服务端 jar：
/// 这条用例要验的是「App ↔ daemon 的协议 + 事件推送 + 文件真的落盘」，
/// 不是 gosh-dl 能不能下大文件（那是 daemon 侧集成测试的事）。
Future<String> startFileServer(String payload) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final bytes = utf8.encode(payload);
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.binary
      ..headers.contentLength = bytes.length
      // 不走分段下载，走单连接那条路
      ..headers.set(HttpHeaders.acceptRangesHeader, 'none')
      ..add(bytes);
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return 'http://127.0.0.1:${server.port}/server.jar';
}

/// 在 daemon 的数据目录里摆一个「装好的 JDK」。
///
/// 只摆 daemon 认的两样东西：环境元数据（`config/runtimes/<id>.json`）与目录里
/// 那个可执行文件。表单模式拼命令时靠它们算出 java 的绝对路径 —— 不摆就看不到
/// `launch_command`（daemon 会说运行环境不在了）。
///
/// 不真跑 java：这个假二进制只是个占位，用例要验的是「字段存得住 +
/// 命令拼得出」，不是 JDK 能不能启动。
/// 轮询单条隧道的运行态直到条件成立（进程是 daemon 那边的线程在起，要等它）。
Future<FrpRun?> _pollRun(
  FrpApi api,
  String localId,
  bool Function(FrpRun?) done,
) async {
  for (var i = 0; i < 40; i++) {
    final run = await api.run(localId);
    if (done(run)) return run;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return api.run(localId);
}

/// 现编一张 `width`×`height` 的纯色 PNG（真走 `dart:ui` 的编码器，
/// 不是手拼字节 —— 这样「前端编出来的 PNG」与线上实际发的完全是一回事）。
Future<Uint8List> _solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3B82F6),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// 摆一个假 frpc：会打一行日志然后常驻，够 `frp.run.*` 验「起 / 看日志 / 停」。
///
/// 与 `_plantFakeJdk` 一样只是占位 —— 这里要验的是「进程起得来、日志收得到、
/// 一条隧道同时只有一个进程」，不是 frpc 本身能不能穿透。
void _plantFakeFrpc(Directory root, String envId) {
  final dir = Directory('${root.path}/data/runtimes/$envId')
    ..createSync(recursive: true);
  final binary = File('${dir.path}/frpc')
    ..writeAsStringSync('#!/bin/sh\necho "[fake-frpc] started"\nsleep 60\n');
  // daemon 直接 spawn，没有可执行位会 EACCES
  final chmod = Process.runSync('chmod', ['+x', binary.path]);
  expect(chmod.exitCode, 0);

  final configDir = Directory('${root.path}/data/config/runtimes')
    ..createSync(recursive: true);
  File('${configDir.path}/$envId.json').writeAsStringSync(
    jsonEncode({
      'id': envId,
      'vendor': 'frp',
      'package_type': 'frpc',
      'version': '0.71.0',
      'version_name': '0.71.0',
      'vendor_version': '',
      'os': 'linux',
      'arch': 'x64',
      'archive_type': 'tar.gz',
      'package_uuid': 'uuid',
      'file_name': 'frp.tar.gz',
      'url': 'https://github.com/fatedier/frp/releases/download/v0.71.0/frp.tar.gz',
      'sha256': null,
      'md5': null,
      'size': null,
      'support_term': null,
      'build_date': null,
      'state': 'installed',
      'stage': null,
      'error': null,
      'task_id': null,
      'home': '',
      'binary': 'frpc',
      'created_at_ms': 1,
      'installed_at_ms': 1,
      'updated_at_ms': 1,
    }),
  );
}

void _plantFakeJdk(Directory root, String envId) {  const home = 'zulu21';
  final bin = Directory('${root.path}/data/runtimes/$envId/$home/bin')
    ..createSync(recursive: true);
  File('${bin.path}/java').writeAsStringSync('#!/bin/sh\n');

  final configDir = Directory('${root.path}/data/config/runtimes')
    ..createSync(recursive: true);
  File('${configDir.path}/$envId.json').writeAsStringSync(
    jsonEncode({
      'id': envId,
      'vendor': 'zulu',
      'package_type': 'jdk',
      'version': '21',
      'version_name': '21.0.12.1',
      'vendor_version': '21.52.203',
      'os': 'linux',
      'arch': 'x64',
      'archive_type': 'tar.gz',
      'package_uuid': 'uuid',
      'file_name': 'zulu.tar.gz',
      'url': 'https://cdn.azul.com/zulu/bin/zulu.tar.gz',
      'sha256': null,
      'md5': null,
      'size': null,
      'support_term': null,
      'build_date': null,
      'state': 'installed',
      'stage': null,
      'error': null,
      'task_id': null,
      'home': home,
      'binary': '$home/bin/java',
      'created_at_ms': 1,
      'installed_at_ms': 1,
      'updated_at_ms': 1,
    }),
  );
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

  test('真实 daemon:实例设置能整份存下来（走前端真正发的那个形状）', () async {
    final daemon = await startDaemon();
    final api = InstanceApi(await connectClient(daemon));

    final created = await api.create(name: '设置往返');
    expect(created.name, '设置往返');

    // 这就是设置对话框 `_collectPatch()` 发出去的那份补丁：`id` 与字段平铺在
    // `params` 同一层。daemon 一度把它当「不认识的字段 id」整份拒绝，
    // 于是设置页根本存不下去 —— 这条用例专门钉住它。
    final updated = await api.update(created.id, {
      'name': '改过的名字',
      'startup_command': 'java -jar server.jar nogui',
      'stop_command': '^C',
      'compat_mode': true,
      'auto_restart_on_exit': false,
      'line_ending': '\r\n',
    });
    expect(updated.id, created.id, reason: 'id 不该被改掉');
    expect(updated.name, '改过的名字');
    expect(updated.startupCommand, 'java -jar server.jar nogui');
    expect(updated.stopCommand, '^C');
    expect(updated.compatMode, isTrue);
    expect(updated.lineEnding, '\r\n');

    // 重新读一遍：确认是落盘了，不是只在返回值里对
    final reread = await api.get(created.id);
    expect(reread.name, '改过的名字');
    expect(reread.stopCommand, '^C');
    expect(reread.lineEnding, '\r\n');
    expect(reread.startupCommand, 'java -jar server.jar nogui');
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  test('真实 daemon:表单模式的启动配置能整份存下来，命令由 daemon 现拼', () async {
    final daemon = await startDaemon();
    final api = InstanceApi(await connectClient(daemon));

    const envId = 'zulu-jdk-21-linux-x64';
    _plantFakeJdk(daemon.dir, envId);
    final created = await api.create(name: '表单往返');

    // 设置对话框在表单模式下发的补丁（`manual_command` 关着，四个字段都给）
    final updated = await api.update(created.id, {
      'name': '表单往返',
      'manual_command': false,
      'runtime_env_id': envId,
      'server_file': 'server.jar',
      'max_memory': 2048,
      'custom_jvm_args': '-XX:+UseG1GC',
      'stop_command': '^C',
      'compat_mode': false,
      'auto_restart_on_exit': false,
      'line_ending': '\n',
      'frp_tunnel_id': null,
    });
    expect(updated.manualCommand, isFalse);
    expect(updated.runtimeEnvId, envId);
    expect(updated.serverFile, 'server.jar');
    expect(updated.maxMemory, 2048);
    expect(updated.customJvmArgs, '-XX:+UseG1GC');
    expect(
      updated.launchCommand,
      isNull,
      reason: '实例目录里还没有那个 jar，这时 daemon 给不出命令',
    );

    // 把 jar 放进去 → 表单拼出一条生效命令：java 来自运行环境，
    // 内存 / JVM 参数插在 -jar 之前
    final jar = File('${daemon.dir.path}/data/instances/${created.id}/server.jar');
    jar.writeAsStringSync('jar');
    final got = await api.get(created.id);
    expect(got.launchCommand, contains('runtimes/$envId/zulu21/bin/java'));
    expect(
      got.launchCommand,
      endsWith('-Xmx2048M -XX:+UseG1GC -jar server.jar nogui'),
    );

    // 落盘了：重新读一遍四个字段都还在
    expect(got.runtimeEnvId, envId);
    expect(got.serverFile, 'server.jar');
    expect(got.maxMemory, 2048);
    expect(got.customJvmArgs, '-XX:+UseG1GC');

    // 切到手动模式：跑的是自己写的那条，表单那几项留档不抹
    final manual = await api.update(created.id, {
      'manual_command': true,
      'startup_command': 'python3 main.py',
    });
    expect(manual.manualCommand, isTrue);
    expect(manual.launchCommand, 'python3 main.py');
    expect(manual.runtimeEnvId, envId, reason: '切手动不该把表单的存档删掉');
    expect(manual.serverFile, 'server.jar');
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  test('真实 daemon:服务端配置的检测与读写（认哪种文件在后端）', () async {
    final daemon = await startDaemon();
    final client = await connectClient(daemon);
    final api = InstanceApi(client);
    final config = InstanceConfigApi(client);

    final created = await api.create(name: '配置往返');

    // 一个配置文件都没有：**不是错误**，回 `kind = null` + 默认文件名，
    // 让前端去说「先启动一次服务端」。
    final empty = await config.get(created.id);
    expect(empty.exists, isFalse);
    expect(empty.kind, isNull);
    expect(empty.file, 'server.properties');

    final dir = Directory('${daemon.dir.path}/data/instances/${created.id}')
      ..createSync(recursive: true);

    // ── 摆一份 Java 的 server.properties ──
    final props = File('${dir.path}/server.properties');
    props.writeAsStringSync('# 注释\nmotd=旧\nmax-players=20\n');

    final java = await config.get(created.id);
    expect(java.kind, 'java', reason: '只有 server.properties 就是 Java 版');
    expect(java.exists, isTrue);
    expect(java.file, 'server.properties');
    expect(java.content, '# 注释\nmotd=旧\nmax-players=20\n');

    // ── 存：写的是 daemon 按 kind 算出来的那个文件，前端给不了路径 ──
    await config.save(created.id, 'java', '# 注释\nmotd=新\nmax-players=20\n');
    expect(
      props.readAsStringSync(),
      '# 注释\nmotd=新\nmax-players=20\n',
      reason: '应当落在 server.properties 上',
    );

    // ── 再摆一个 pnx.yml：优先级压过 server.properties（阈值在 daemon 里）──
    File('${dir.path}/pnx.yml').writeAsStringSync('settings:\n  motd: hi\n');
    final pnx = await config.get(created.id);
    expect(pnx.kind, 'pnx');
    expect(pnx.file, 'pnx.yml');

    // ── PocketMine 靠布尔值写法认出来 ──
    File('${dir.path}/pnx.yml').deleteSync();
    props.writeAsStringSync('pvp=on\n');
    final pmmp = await config.get(created.id);
    expect(pmmp.kind, 'pmmp', reason: 'on/off 是 PocketMine 的写法');

    // ── 不认识的 kind 当场被拒（写哪个文件由枚举决定，不进白名单就没得写）──
    await expectLater(
      config.save(created.id, 'nope', 'x'),
      throwsA(
        isA<DaemonException>().having((e) => e.code, 'code', 'invalid_params'),
      ),
    );

    // ── 文件不在时不写：不凭空造一份半成品配置 ──
    await expectLater(
      config.save(created.id, 'allay', 'settings:\n'),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'instance_config_missing',
        ),
      ),
    );
    expect(
      File('${dir.path}/server-settings.yml').existsSync(),
      isFalse,
      reason: '不该因为一次保存就凭空建文件',
    );

    await client.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  /// 服务端图标的往返：**前端真编一份 64×64 PNG → daemon 校验 → 落盘**。
  ///
  /// 用 `testWidgets` + `runAsync` 是因为要真跑 `dart:ui` 的图片编码 —— 那是引擎
  /// 的异步，在假时钟下不会完成。这条同时也证明了「前端编出来的 PNG，daemon 的
  /// 头部校验认」（两边对 64×64 的理解是一致的）。
  testWidgets('真实 daemon:服务端图标往返（只收 64×64 的 PNG）', (tester) async {
    await tester.runAsync(() async {
      final daemon = await startDaemon();
      final client = await connectClient(daemon);
      final api = InstanceApi(client);
      final config = InstanceConfigApi(client);

      final created = await api.create(name: '图标往返');
      final dir = Directory('${daemon.dir.path}/data/instances/${created.id}')
        ..createSync(recursive: true);

      // 一开始没有图标：不是错误
      final empty = await config.iconGet(created.id);
      expect(empty.exists, isFalse);
      expect(empty.bytes, isNull);
      expect(empty.file, 'server-icon.png');

      // 真编一份 64×64 的 PNG
      final png = await _solidPng(64, 64);
      await config.iconSave(created.id, png);

      // 读回来一模一样，且真的落在实例目录里
      final saved = await config.iconGet(created.id);
      expect(saved.exists, isTrue);
      expect(saved.bytes, png);
      expect(dir.listSync().map((e) => e.path).join(), contains('server-icon.png'));

      // 尺寸不对要拒（Minecraft 对尺寸不符的图标是**静默忽略**，最难查，
      // 所以在入口就拦）
      final wrong = await _solidPng(32, 32);
      await expectLater(
        config.iconSave(created.id, wrong),
        throwsA(
          isA<DaemonException>().having(
            (e) => e.code,
            'code',
            'instance_icon_invalid',
          ),
        ),
      );
      // 拒了就不该动原来那份
      expect((await config.iconGet(created.id)).bytes, png);

      // 不是 PNG 也要拒
      await expectLater(
        config.iconSave(
          created.id,
          Uint8List.fromList(List.filled(64, 0x41)),
        ),
        throwsA(
          isA<DaemonException>().having(
            (e) => e.code,
            'code',
            'instance_icon_invalid',
          ),
        ),
      );

      await client.close();
    });
    // `testWidgets` 的 `skip` 只收 bool（不支持带原因），原因见上面的
    // `_findDaemonBinary` / `_skipReason`。
  }, skip: _skipReason != null, timeout: const Timeout(Duration(seconds: 60)));

  /// FRP 实例的运行：一条隧道配置 = 一个可独立运行的进程。
  ///
  /// 真起一个假 frpc，验「装没装决定 `frp.runtimes`」「起 → running + 日志」
  /// 「重复起不起第二个」「停 → 记录摘掉」这条链路与线上模型对得上。
  test('真实 daemon:FRP 实例的运行（一条隧道一个进程）', () async {
    final daemon = await startDaemon();
    final client = await connectClient(daemon);
    final api = FrpApi(client);

    const envId = 'frp-frpc-0.71.0-linux-x64';
    _plantFakeFrpc(daemon.dir, envId);

    // 装了 frpc → 列得出来，没选过就回落到第一个
    final runtimes = await api.runtimes();
    expect(runtimes.runtimes.map((r) => r.id), contains(envId));
    expect(runtimes.selected, envId);

    // 存一条自定义隧道（不需要平台），daemon 会现生成一份 toml
    final saved = await api.saveTunnel(
      FrpTunnelInput.customRaw(
        name: 'e2e 穿透',
        toml: 'serverAddr = "127.0.0.1"\nserverPort = 7000\n',
      ),
    );
    final localId = saved.tunnel.localId;
    expect(localId, isNotEmpty);

    // 还没起 → 没有记录
    expect(await api.run(localId), isNull);

    // 起 → running + pid + 日志里那句。日志是 daemon 的读线程一行行收的，
    // 比「进程进入 running」晚一拍，所以要等日志真的到了再断言。
    await api.startRun(localId);
    final run = await _pollRun(
      api,
      localId,
      (r) => r?.isRunning == true && r!.log.join().contains('[fake-frpc] started'),
    );
    expect(run, isNotNull, reason: '起一条隧道应当进入 running 且收得到日志');

    // 已经在跑再起一次 → 幂等，还是那一个进程
    await api.startRun(localId);
    final again = await api.run(localId);
    expect(again!.isRunning, isTrue);
    expect(again.pid, run!.pid, reason: '重复 start 不该换进程');

    // 列表里也看得到它
    final list = await api.runs();
    expect(list.map((r) => r.localId), contains(localId));

    // 停 → 记录摘掉
    await api.stopRun(localId);
    expect(await api.run(localId), isNull);

    await client.close();
  });

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

  test('真实 daemon:系统监控的线上格式能被前端模型解析', () async {
    final daemon = await startDaemon();

    // ── 拉一次：字段名与类型必须和 `SystemSnapshot` 对得上 ──────────────
    final client = await connectClient(daemon);
    final raw = await client.callObject('monitor.snapshot');
    final snapshot = SystemSnapshot.fromJson(raw);

    expect(snapshot.intervalMs, greaterThan(0));
    expect(snapshot.sampledAtMs, greaterThan(0));
    expect(snapshot.cpuCores, greaterThan(0));
    // 进程管理还没接进 daemon：这个字段必须是 null，而不是被解析成 0
    expect(snapshot.serverMemMb, isNull);
    if (snapshot.supported) {
      expect(snapshot.totalMemMb, greaterThan(0), reason: 'daemon 原样返回: $raw');
      expect(snapshot.usedMemMb + snapshot.availableMemMb,
          lessThanOrEqualTo(snapshot.totalMemMb + 1));
      expect(snapshot.memoryLabel, isNot('不可用'));
    }

    // ── 推一份：事件里带的 data 就是同一个快照，直接喂给模型 ────────────
    final pushed = client.events.firstWhere((e) => e['topic'] == 'monitor.stats');
    await client.subscribe('monitor.stats');
    final event = await pushed.timeout(const Duration(seconds: 10));
    final fromEvent = SystemSnapshot.fromJson(
      (event['data'] as Map).cast<String, dynamic>(),
    );
    expect(fromEvent.sampledAtMs, greaterThanOrEqualTo(snapshot.sampledAtMs));
    expect(fromEvent.intervalMs, snapshot.intervalMs);
    // 采样器是常驻的，跟第一份快照之间至少隔了一个间隔，CPU 读数该有了
    expect(fromEvent.hasCpu, isTrue, reason: '推送里应当带上 CPU 读数: ${event['data']}');
    expect(fromEvent.cpuPercent, inInclusiveRange(0, 100));

    await client.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  test('真实 daemon:服务端目录 + 下载队列(建实例 → 提交下载 → 看进度)', () async {
    final daemon = await startDaemon();
    final client = await connectClient(daemon);

    // ── 类型表:daemon 侧是常量,前端零硬编码靠它 ────────────────────────
    final catalog = ServerCatalog.fromJson(
      await client.callObject('mcserver.types'),
    );
    expect(catalog.categories.length, 4, reason: '四个分类:原版 / 插件 / 模组 / 代理');
    expect(catalog.kinds.length, 9);
    final paper = catalog.byId('paper')!;
    expect(paper.fileName, 'server.jar');
    expect(paper.startupCommand, 'java -jar server.jar nogui');
    expect(paper.checksum, 'sha256');
    expect(paper.needsLoader, isFalse);
    // Folia 与 paper 同源(PaperMC 的另一个 project),信息形状也一样
    final folia = catalog.byId('folia')!;
    expect(folia.category, 'plugin');
    expect(folia.fileName, 'server.jar');
    expect(folia.checksum, 'sha256');
    expect(
      catalog.categories
          .firstWhere((category) => category.id == 'plugin')
          .types,
      ['paper', 'folia', 'purpur', 'leaf', 'leaves'],
      reason: '插件分类的展示顺序',
    );
    // 代理没有 GUI,启动命令刻意不带 nogui
    expect(catalog.byId('velocity')!.startupCommand, 'java -jar velocity.jar');
    // 只有 Fabric 要再选一个加载器版本
    expect(catalog.byId('fabric')!.needsLoader, isTrue);

    // ── 参数类错误码(这几条不联网) ────────────────────────────────────
    await expectLater(
      client.call('mcserver.plan', params: {'type': 'paper'}),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'mcserver_version_required',
        ),
      ),
    );
    await expectLater(
      client.call('mcserver.versions', params: {'type': '不存在'}),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'mcserver_type_not_found',
        ),
      ),
    );

    // ── 建实例 + 提交下载(下载源是本地 HTTP 服务,不依赖外网) ───────────
    const payload = 'edgecube-e2e-server-jar';
    final url = await startFileServer(payload);

    final created = await client.callObject(
      'instance.create',
      params: {'name': 'e2e 下载服', 'startup_command': 'java -jar server.jar nogui'},
    );
    final instanceId = (created['instance'] as Map)['id'] as String;

    // **先订阅再提交**:下载几毫秒就完了,提交之后再订阅会错过那个终态事件
    final finished = client.events
        .where((event) => event['topic'] == 'download.state')
        .map(
          (event) => DownloadTask.fromJson(
            (event['data'] as Map).cast<String, dynamic>(),
          ),
        )
        .firstWhere((task) => task.state.isFinished)
        .timeout(const Duration(seconds: 30));
    await client.subscribe('download.state');
    await client.subscribe('download.progress');

    final added = DownloadTask.fromJson(
      ((await client.callObject(
                    'download.add',
                    params: {
                      'url': url,
                      'instance_id': instanceId,
                      'filename': 'server.jar',
                    },
                  ))
                  ['task'] as Map)
              .cast<String, dynamic>(),
    );
    expect(added.filename, 'server.jar');
    expect(added.target, 'server.jar');
    expect(added.instanceId, instanceId);
    expect(added.state.isActive, isTrue, reason: '刚提交应当是排队/下载中');

    // 事件里的任务对象与快照同形,成功终态会推过来
    final done = await finished;
    expect(done.id, added.id);
    expect(done.state, DownloadState.completed, reason: '本地小文件应当秒下完');
    expect(done.completedSize, payload.length);
    expect(done.totalSize, payload.length);

    // 快照与事件说的是同一件事
    final snapshot = DownloadTask.fromJson(
      ((await client.callObject('download.status', params: {'id': added.id}))
              ['task'] as Map)
          .cast<String, dynamic>(),
    );
    expect(snapshot.state, DownloadState.completed);
    expect(snapshot.completedSize, payload.length);

    // ── 文件真的落在实例目录里 ────────────────────────────────────────
    final written = File(
      '${daemon.dir.path}/data/instances/$instanceId/server.jar',
    );
    expect(
      written.existsSync(),
      isTrue,
      reason: '服务端文件应当落在实例工作目录: ${written.path}',
    );
    expect(written.readAsStringSync(), payload);

    // ── 联网那一段:上游不通就只验错误码(不是功能坏了) ─────────────────
    try {
      final versions = await client.callObject(
        'mcserver.versions',
        params: {'type': 'paper'},
      );
      final list = (versions['versions'] as List).cast<String>();
      expect(list, isNotEmpty);
      // daemon 已经排好序:新版本在前
      final plan = ServerPlan.fromJson(
        await client.callObject(
          'mcserver.plan',
          params: {'type': 'paper', 'version': list.first},
        ),
      );
      expect(plan.fileName, 'server.jar');
      expect(plan.url, startsWith('https://'));
      expect(plan.checksum?.algorithm, 'sha256');
      expect(plan.checksum!.value.length, 64);
      expect(plan.startupCommand, 'java -jar server.jar nogui');
    } on DaemonException catch (error) {
      // 离线 / 网络被挡时上游会失败 —— 那时只要求它的错误码是「网络或解析」,
      // 而不是我们这边写错了(比如类型名拼错、版本没传)
      expect(
        error.code,
        anyOf('mcserver_upstream_error', 'mcserver_parse_error'),
        reason: '上游失败应当是网络或解析问题: ${error.message}',
      );
    }

    await client.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 90)));

  test('真实 daemon:运行环境模块挂上来了，列表与厂商表形状能被前端模型解析', () async {
    final daemon = await startDaemon();
    final client = await connectClient(daemon);
    final api = RuntimeApi(client);

    // 厂商表：本机平台要给出来（这台 CI 是 linux x64，能装）
    final catalog = await api.catalog();
    expect(catalog.defaultProvider, 'zulu');
    expect(catalog.defaultPackageType, 'jdk');
    expect(catalog.providers.map((p) => p.id), contains('zulu'));
    expect(catalog.providers.map((p) => p.id), contains('frp'),
        reason: 'frp 环境（GitHub 分发）也注册上来了');
    expect(catalog.supported, isTrue, reason: 'linux x64 有对应的 Zulu 构建');
    expect(catalog.host?.os, 'linux');

    // 空列表
    final list = await api.list();
    expect(list.environments, isEmpty);
    expect(list.dir, endsWith('runtimes'));

    // 安装**只能**走工作流了（`runtime.install` 已经删掉），流程清单里要有它
    final tasks = TaskApi(client);
    final flows = await tasks.flows();
    expect(
      flows.map((f) => f.name),
      containsAll(<String>['runtime-install', 'instance-provision']),
    );
    final install = flows.firstWhere((f) => f.name == 'runtime-install');
    expect(install.stepTitles, ['下载运行环境', '解压运行环境']);

    // 缺版本号 → `task.submit` 在参数校验阶段就拒（不进队、不拿 id）
    await expectLater(
      tasks.submit('runtime-install', {}),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'task_invalid_params',
        ),
      ),
    );

    await client.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  test('真实 daemon:EULA 同意机制（eula.txt 的判定与写入）', () async {
    final daemon = await startDaemon();
    final client = await connectClient(daemon);
    final api = InstanceApi(client);

    // 新建的实例上服务端还没生成 eula.txt → 没同意（要弹框的情形）
    final instance = await api.create(name: 'EULA 测试服');
    var status = await api.eula(instance.id);
    expect(status.exists, isFalse);
    expect(status.agreed, isFalse);
    expect(status.file, 'eula.txt');

    // 同意 → 文件被建出来，内容是固定文案
    await api.acceptEula(instance.id);
    status = await api.eula(instance.id);
    expect(status.exists, isTrue);
    expect(status.agreed, isTrue);

    final file = File('${daemon.dir.path}/data/instances/${instance.id}/eula.txt');
    expect(file.existsSync(), isTrue, reason: '同意之后 eula.txt 必须存在');
    expect(
      file.readAsStringSync(),
      '#By changing the setting below to TRUE you are indicating your agreement '
      'to our EULA (https://aka.ms/MinecraftEULA).\neula=true\n',
      reason: '内容一字不差',
    );

    // 判定口径宽松：大小写不敏感、`=` 两边可以有空白
    file.writeAsStringSync('eula = TRUE\n');
    expect((await api.eula(instance.id)).agreed, isTrue);
    file.writeAsStringSync('EULA=True\n');
    expect((await api.eula(instance.id)).agreed, isTrue);

    // 服务端把它改回 false（或用户手改）→ 又要重新同意
    file.writeAsStringSync('eula=false\n');
    status = await api.eula(instance.id);
    expect(status.exists, isTrue, reason: '文件在，只是没同意');
    expect(status.agreed, isFalse);

    // 实例不存在：两个方法都要给 `instance_not_found`
    await expectLater(
      api.eula('no-such-instance'),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'instance_not_found',
        ),
      ),
    );

    await client.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));

  test('真实 daemon:模组与插件（目录规则、启停改名、已装清单的线上形状）', () async {
    final daemon = await startDaemon();
    final client = await connectClient(daemon);
    final api = ModsApi(client);

    // ── 表：前端零硬编码靠它 ────────────────────────────────────────
    final catalog = await api.catalog();
    // 后缀表是 daemon 给的（jar 是 Java 系，phar 是 PocketMine）
    expect(catalog.fileExts, contains('jar'));
    expect(catalog.fileExts, contains('phar'));
    expect(catalog.disabledSuffix, '.disabled');
    expect(catalog.sources.map((s) => s.id), contains('modrinth'));
    expect(catalog.projectTypes.map((t) => t.id), ['mod', 'plugin']);
    // 「装到哪个目录」这条规则只有一处实现，界面上显示的也是它
    expect(catalog.projectType('mod')!.dir, 'mods');
    expect(catalog.projectType('plugin')!.dir, 'plugins');
    expect(catalog.projectType('mod')!.loaders, contains('fabric'));
    expect(catalog.projectType('plugin')!.loaders, contains('paper'));

    // ── 筛选器的可选值（`mods.tags`）────────────────────────────────
    //
    // 这一段以前没测，结果线上出了「游戏版本只有『任意』」——
    // 根因是 daemon 换了 `game_versions` 的元素形状（字符串 → 对象），
    // 前端拿到旧形状会一个都解析不出来。所以这里把**形状**也钉住。
    try {
      final modTags = await api.tags(projectType: 'mod');
      expect(
        modTags.gameVersions,
        isNotEmpty,
        reason: '游戏版本清单不能是空的（否则菜单里只有「任意」）',
      );
      expect(modTags.gameVersions.first.version, isNotEmpty);
      expect(modTags.gameVersions.first.versionType, isNotEmpty);
      // 加载器表按项目类型分开：模组这一栏是 fabric 系
      expect(
        modTags.loaders.map((l) => l.id).toSet(),
        {'fabric', 'forge', 'quilt', 'neoforge'},
      );

      final pluginTags = await api.tags(projectType: 'plugin');
      expect(
        pluginTags.loaders.map((l) => l.id).toList(),
        [
          'paper',
          'spigot',
          'bukkit',
          'bungeecord',
          'velocity',
          'waterfall',
          'folia',
          'purpur',
        ],
        reason: '插件那一栏绝不能出现模组加载器',
      );
    } on DaemonException catch (e) {
      expect(
        e.code,
        'mods_upstream_error',
        reason: '拿不到游戏版本时应当是可重试的码，实际 ${e.code}：${e.message}',
      );
      // ignore: avoid_print
      print('跳过 `mods.tags` 那一段（连不上 Modrinth）: ${e.message}');
    }

    // ── 实例不存在时的错误码（不联网） ──────────────────────────────
    await expectLater(
      api.installed('no-such-instance'),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'mods_instance_not_found',
        ),
      ),
    );

    // ── 建实例，先看空态 ───────────────────────────────────────────
    final instance = await InstanceApi(client).create(name: '模组 e2e 服');

    var installed = await api.installed(instance.id);
    expect(installed.total, 0);
    // 这个实例的启动命令是 java，所以不是 PocketMine（判定在 daemon）
    expect(installed.pmmp, isFalse);
    // 两个目录都出现在响应里（带 `exists`），由前端决定要不要显示标签
    expect(installed.dirs.map((d) => d.dir), ['mods', 'plugins']);
    expect(installed.dirs.every((d) => !d.exists), isTrue);

    // ── 放一个 `.jar` 与一个不该被认出的文件 ────────────────────────
    //
    // 这个 jar 的内容**不是真 zip**：daemon 的元数据解析（读 `fabric.mod.json`
    // 那一套）已经由它自己的单测与 `framework.rs` 钉住了，这里验的是**线上形状**
    // —— 文件名、启用位，以及「读不出元数据时 `meta` 是 null」这条契约。
    final root = Directory('${daemon.dir.path}/data/instances/${instance.id}');
    Directory('${root.path}/mods').createSync(recursive: true);
    File('${root.path}/mods/plain.jar').writeAsStringSync('not a real jar');
    File('${root.path}/mods/readme.txt').writeAsStringSync('hello');

    installed = await api.installed(instance.id);
    final mods = installed.dir('mod')!;
    expect(mods.exists, isTrue);
    expect(mods.count, 1, reason: 'txt 不该被当成模组');
    final file = mods.files.single;
    expect(file.fileName, 'plain.jar');
    expect(file.baseName, 'plain.jar');
    expect(file.enabled, isTrue);
    expect(file.size, greaterThan(0));
    expect(file.meta, isNull, reason: '内容不是 zip，读不出元数据');
    expect(file.displayName, 'plain.jar', reason: '读不出元数据就退回文件名');

    // ── 更新检查：这个文件上游必然不认得，要如实标 known=false ──────
    try {
      final report = await api.checkUpdates(
        instanceId: instance.id,
        projectType: 'mod',
      );
      expect(report.checked, 1);
      final update = report.byFileName['plain.jar']!;
      expect(update.known, isFalse);
      expect(update.hasUpdate, isFalse, reason: '不认得就不该说它有更新');
      expect(update.latest, isNull);
      expect(report.updateCount, 0);
    } on DaemonException catch (e) {
      // 上游不通（离线 / 代理劫持）不算功能坏了 —— 与 mcserver 那条同样的处理
      expect(
        e.code,
        'mods_upstream_error',
        reason: '上游失败时应当给可重试的码，实际 ${e.code}：${e.message}',
      );
      // ignore: avoid_print
      print('跳过更新检查那一段（连不上 Modrinth）: ${e.message}');
    }

    // ── 启停就是改名：服务端只认 `*.jar` ───────────────────────────
    final renamed = await api.setEnabled(
      instanceId: instance.id,
      projectType: 'mod',
      fileName: 'plain.jar',
      enabled: false,
    );
    expect(renamed, 'plain.jar.disabled');
    expect(File('${root.path}/mods/plain.jar.disabled').existsSync(), isTrue);
    expect(File('${root.path}/mods/plain.jar').existsSync(), isFalse);

    installed = await api.installed(instance.id);
    final disabled = installed.dir('mod')!.files.single;
    expect(disabled.enabled, isFalse);
    // 显示名去掉后缀，文件名保留 —— 前端拿 file_name 当主键
    expect(disabled.baseName, 'plain.jar');
    expect(disabled.fileName, 'plain.jar.disabled');
    // 副行取法：**有元数据才是「版本 · 加载器」，没有就是文件大小**。
    // 「已禁用」不在副行里 —— 它靠整卡灰化 + 标题删除线表达。
    expect(
      disabled.subtitle,
      '14 B',
      reason: '内容不是 zip 读不出元数据 → 退回文件大小',
    );

    // 幂等：再禁用一次不该报错
    expect(
      await api.setEnabled(
        instanceId: instance.id,
        projectType: 'mod',
        fileName: 'plain.jar.disabled',
        enabled: false,
      ),
      'plain.jar.disabled',
    );

    // ── 删除 ──────────────────────────────────────────────────────
    await api.remove(
      instanceId: instance.id,
      projectType: 'mod',
      fileName: 'plain.jar.disabled',
    );
    expect(File('${root.path}/mods/plain.jar.disabled').existsSync(), isFalse);
    expect((await api.installed(instance.id)).total, 0);

    // ── 工作流清单里要有它，且就是两步 ─────────────────────────────
    final tasks = TaskApi(client);
    final flows = await tasks.flows();
    final install = flows.firstWhere((f) => f.name == 'mods-install');
    expect(install.stepTitles, ['解析下载地址', '下载并安装']);

    // 缺参数：当场被拒（不进队、不拿 id）
    await expectLater(
      tasks.submit('mods-install', {}),
      throwsA(
        isA<DaemonException>().having(
          (e) => e.code,
          'code',
          'task_invalid_params',
        ),
      ),
    );

    await client.close();
  }, skip: _skipReason, timeout: const Timeout(Duration(seconds: 60)));
}
