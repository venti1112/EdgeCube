import 'dart:async';
import 'dart:convert';

import 'package:edgecube_app/connection/client.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/connection/state.dart';
import 'package:edgecube_app/connection/transport.dart';
import 'package:edgecube_app/settings/appearance.dart';
import 'package:edgecube_app/storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存里的实例后端：够 widget 测试跑完「列表 / 新建 / 选中 / 编辑 / 删除」。
///
/// 数据用 daemon 的**线上格式**（snake_case）存，和真后端的响应形状一致 ——
/// 这样假传输也能当作协议文档看。
class FakeInstanceStore {
  /// id → 元数据（线上形状）。
  final Map<String, Map<String, dynamic>> instances = {};

  /// 当前选中的 id。
  String? selected;

  /// 数据根目录（列表里回给前端显示）。
  String dataDir = '/tmp/edgecube-fake';

  int _seq = 0;

  /// 直接塞一个实例（测试准备数据用）。
  String seed({required String name, String runtime = 'java', int? maxMemory}) {
    final id = _nextId();
    instances[id] = {
      'id': id,
      'name': name,
      'runtime': runtime,
      'max_memory': maxMemory,
      'runtime_env_id': null,
      'server_file': null,
      'custom_jvm_args': null,
      'compat_mode': false,
      'auto_restart_on_exit': false,
      'proot_startup_command': null,
      'path': null,
      'line_ending': '\n',
      'created_at_ms': 1700000000000 + _seq,
      'updated_at_ms': 1700000000000 + _seq,
    };
    selected ??= id;
    return id;
  }

  String _nextId() => (++_seq).toRadixString(16).padLeft(16, '0');

  /// 处理一个 `instance.*` 调用；出错时抛 [DaemonException]（假传输会转成
  /// error 信封，与真后端一致）。
  Map<String, dynamic> handle(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'instance.list':
        return {
          'instances': [
            for (final entry in instances.entries)
              {
                'id': entry.key,
                'name': entry.value['name'],
                'path': entry.value['path'],
                'selected': entry.key == selected,
              },
          ],
          'count': instances.length,
          'selected': selected,
          'data_dir': dataDir,
        };

      case 'instance.get':
        final config = _require(params);
        return {'instance': config, 'dir': _dir(config), 'lint': <String>[]};

      case 'instance.status':
        final config = _require(params);
        return {
          'status': {
            'id': config['id'],
            'name': config['name'],
            'phase': 'stopped',
            'running': false,
            'process_managed': false,
            'dir': _dir(config),
            'dir_exists': true,
            'size_bytes': 1536,
            'size_human': '1.5 KiB',
            'file_count': 2,
            'dir_count': 1,
            'size_truncated': false,
            'created_at_ms': config['created_at_ms'],
            'updated_at_ms': config['updated_at_ms'],
            'warnings': const <String>[],
          },
        };

      case 'instance.create':
        final name = (params['name'] as String? ?? '').trim();
        if (name.isEmpty) {
          throw const DaemonException('invalid_params', '实例名称不能为空');
        }
        if (instances.values.any((c) => (c['name'] as String).trim() == name)) {
          throw DaemonException('instance_name_taken', '已存在名为 `$name` 的实例');
        }
        final id = _nextId();
        instances[id] = {
          'id': id,
          'name': name,
          'runtime': params['runtime'] ?? 'java',
          'max_memory': params['max_memory'],
          'runtime_env_id': params['runtime_env_id'],
          'server_file': params['server_file'],
          'custom_jvm_args': null,
          'compat_mode': false,
          'auto_restart_on_exit': false,
          'proot_startup_command': null,
          'path': null,
          'line_ending': '\n',
          'created_at_ms': 1700000000000 + _seq,
          'updated_at_ms': 1700000000000 + _seq,
        };
        selected = id;
        return {
          'instance': instances[id],
          'dir': _dir(instances[id]!),
          'selected': id,
          'count': instances.length,
        };

      case 'instance.update':
        final config = _require(params);
        final patch = Map<String, dynamic>.from(params)..remove('id');
        final name = patch['name'] as String?;
        if (name != null) {
          if (name.trim().isEmpty) {
            throw const DaemonException('invalid_params', '实例名称不能为空');
          }
          final taken = instances.entries.any(
            (e) => e.key != config['id'] && e.value['name'] == name,
          );
          if (taken) {
            throw DaemonException('instance_name_taken', '已存在名为 `$name` 的实例');
          }
        }
        var changed = false;
        for (final entry in patch.entries) {
          if (config[entry.key] != entry.value) changed = true;
          config[entry.key] = entry.value;
        }
        if (changed) {
          config['updated_at_ms'] = 1700000009999;
        }
        return {
          'instance': config,
          'changed': changed,
          'dir': _dir(config),
          'lint': <String>[],
        };

      case 'instance.delete':
        final config = _require(params);
        instances.remove(config['id']);
        if (selected == config['id']) {
          selected = instances.keys.firstOrNull;
        }
        return {
          'deleted': true,
          'id': config['id'],
          'name': config['name'],
          'dir': _dir(config),
          'files_deleted': true,
          'metadata_deleted': true,
          'selected': selected,
          'remaining': instances.length,
        };

      case 'instance.select':
        final id = params['id'] as String?;
        if (id != null && !instances.containsKey(id)) {
          throw DaemonException('instance_not_found', '没有 id 为 `$id` 的实例');
        }
        selected = id;
        return {'selected': selected, 'count': instances.length};

      case 'instance.scan':
        return {
          'skipped': false,
          'pruned': const <String>[],
          'adopted': const <String>[],
          'ignored': const <String>[],
          'total': instances.length,
          'selected': selected,
        };

      default:
        throw DaemonException('method_not_found', '假传输没有实现 $method');
    }
  }

  Map<String, dynamic> _require(Map<String, dynamic> params) {
    final id = params['id'] as String?;
    final config = id == null ? null : instances[id];
    if (config == null) {
      throw DaemonException('instance_not_found', '没有 id 为 `$id` 的实例');
    }
    return config;
  }

  String _dir(Map<String, dynamic> config) =>
      '${config['path'] ?? '$dataDir/instances/${config['id']}'}';
}

/// 测试用的假传输:在内存里把协议跑一遍,不碰真实网络。
///
/// 它能做三件真实服务端能做的事:发 hello、按 method 回 result、
/// 主动推 event;还能模拟握手被拒与连接中断。
class FakeDaemonTransport implements DaemonTransport {
  FakeDaemonTransport({
    this.accept = true,
    this.rejectWith,
    this.helloDelay = Duration.zero,
    Map<String, Object?>? responses,
    this.instances,
  }) : responses = {...defaultResponses, ...?responses};

  /// daemon `core.info` 的假返回值
  static const Map<String, Object?> defaultResponses = {
    'core.info': {
      'product': 'edgecube-daemon',
      'version': '2.0.0',
      'protocol_version': 1,
      'pid': 1,
      'os': 'linux',
      'arch': 'x86_64',
      'bind': '127.0.0.1:8787',
      'uptime_human': '1m 00s',
      'uptime_ms': 60000,
      'connections': 1,
      'subscribers': 0,
      'auth_required': true,
      'config_path': null,
      'shutting_down': false,
    },
  };

  /// 是否接受握手
  final bool accept;

  /// 拒绝时抛出的异常(默认当成"连不上")
  final DaemonException? rejectWith;

  /// 握手包延迟多久发出(用于制造"连接还在途中"的竞态)
  final Duration helloDelay;

  final Map<String, Object?> responses;

  /// 内存实例后端；给了它就会接管所有 `instance.*` 调用。
  final FakeInstanceStore? instances;

  /// 客户端实际连接的地址,用来断言令牌是否放进了查询串
  Uri? uri;

  final _incoming = StreamController<String>.broadcast();
  final _sent = <Map<String, dynamic>>[];
  bool _closed = false;

  /// 客户端发出去的所有信封
  List<Map<String, dynamic>> get sent => List.unmodifiable(_sent);

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> connect(Uri uri) async {
    this.uri = uri;
    if (!accept) {
      throw rejectWith ??
          const DaemonException('disconnected', '测试:无法连接到服务端');
    }
    if (helloDelay == Duration.zero) {
      _emit(helloFor(uri));
    } else {
      Timer(helloDelay, () => _emit(helloFor(uri)));
    }
  }

  /// 服务端握手包
  static Map<String, Object?> helloFor(Uri uri) => {
    'type': 'hello',
    'protocol': 1,
    'product': 'edgecube-daemon',
    'version': '2.0.0',
    'pid': 1,
    'conn_id': 1,
    'peer': '127.0.0.1:55555',
    'started_at_ms': 0,
    'auth_required': true,
    'config_path': null,
    'modules': [
      {'id': 'core'},
      {'id': 'ticker'},
    ],
    'methods': [
      {'name': 'core.ping'},
      {'name': 'ticker.start'},
    ],
    'topics': [
      {'topic': 'ticker.tick'},
    ],
    'max_inflight_calls': 32,
    'request_timeout_secs': 30,
    'ts': 0,
  };

  @override
  void send(String payload) {
    final Map<String, dynamic> envelope;
    try {
      envelope = (jsonDecode(payload) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    _sent.add(envelope);
    final id = envelope['id'];
    // 模拟服务端异步处理:下一轮微任务再回包
    scheduleMicrotask(() {
      if (_closed) return;
      switch (envelope['type']) {
        case 'call':
          final method = envelope['method'] as String?;
          if (responses.containsKey(method)) {
            _emit({
              'type': 'result',
              'id': id,
              'ok': true,
              'result': responses[method],
            });
          } else {
            _emit({
              'type': 'result',
              'id': id,
              'ok': false,
              'error': {
                'code': 'method_not_found',
                'message': '假传输没有实现 $method',
              },
            });
          }
        case 'subscribe':
          _emit({
            'type': 'result',
            'id': id,
            'ok': true,
            'result': {'topic': envelope['topic']},
          });
        case 'unsubscribe':
          _emit({
            'type': 'result',
            'id': id,
            'ok': true,
            'result': {'unsubscribed': true},
          });
        case 'ping':
          _emit({'type': 'pong', 'id': id, 'ts': 0});
      }
    });
  }

  /// 服务端主动推送一条事件
  void pushEvent(String topic, [Map<String, Object?> data = const {}]) => _emit({
    'type': 'event',
    'topic': topic,
    'seq': 1,
    'ts': 0,
    'source': 'fake',
    'data': data,
  });

  /// 模拟连接中断(触发客户端掉线处理)
  void dropConnection() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _closed = true;
    if (!_incoming.isClosed) _incoming.close();
  }

  void _emit(Map<String, Object?> frame) {
    if (_incoming.isClosed) return;
    _incoming.add(jsonEncode(frame));
  }
}

/// 每次连接都新建一个假传输(重连时才会拿到干净的一条)。
///
/// 客户端每次 `connect` 都会调用一次工厂,所以重连场景下
/// [latest] 指向的是当前这条连接。
class FakeTransportFactory {
  FakeTransportFactory({
    this.accept = true,
    this.rejectWith,
    this.helloDelay = Duration.zero,
    this.responses,
  });

  final List<FakeDaemonTransport> created = [];
  bool accept;
  DaemonException? rejectWith;
  Duration helloDelay;
  Map<String, Object?>? responses;

  FakeDaemonTransport get latest => created.last;

  int get count => created.length;

  DaemonTransport call() {
    final transport = FakeDaemonTransport(
      accept: accept,
      rejectWith: rejectWith,
      helloDelay: helloDelay,
      responses: responses,
    );
    created.add(transport);
    return transport;
  }
}

/// 复刻 `main()` 的启动路径:预加载 → override。
///
/// 直接返回建好的容器(而不是丢一个 overrides 列表出来),
/// 因为 riverpod 3 不再从 `flutter_riverpod` 导出 `Override` 类型。
ProviderContainer bootContainer({
  required SharedPreferences storage,
  AppearanceSettings appearance = const AppearanceSettings(),
  ConnectionSettings? persisted,
  required DaemonTransportFactory transportFactory,
}) => ProviderContainer(
  overrides: [
    storageProvider.overrideWithValue(storage),
    initialAppearanceProvider.overrideWithValue(appearance),
    initialPersistedConnectionProvider.overrideWithValue(persisted),
    initialConnectionSettingsProvider.overrideWithValue(
      persisted ?? ConnectionSettings.empty,
    ),
    daemonTransportFactoryProvider.overrideWithValue(transportFactory),
  ],
);
