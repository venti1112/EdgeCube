import 'dart:async';
import 'dart:convert';

import 'transport.dart';

/// 服务端握手信息 —— 连接建立后服务端主动发来的第一条消息。
///
/// 客户端据此得知:对端是谁、能调哪些方法、能订阅哪些主题。
class DaemonHello {
  const DaemonHello({
    required this.protocol,
    required this.product,
    required this.version,
    required this.connId,
    required this.peer,
    required this.methods,
    required this.topics,
    required this.modules,
    required this.authRequired,
    required this.maxInflightCalls,
  });

  /// 对端协议版本;与服务端不一致时上层可以提示升级
  final int protocol;
  final String product;
  final String version;
  final int connId;
  final String peer;

  /// 可调用的 WS 方法名
  final List<String> methods;

  /// 可订阅的事件主题
  final List<String> topics;

  /// 已装载模块 id
  final List<String> modules;

  final bool authRequired;
  final int maxInflightCalls;

  factory DaemonHello.fromJson(Map<String, dynamic> json) => DaemonHello(
    protocol: json['protocol'] as int? ?? 0,
    product: json['product'] as String? ?? 'unknown',
    version: json['version'] as String? ?? '0.0.0',
    connId: json['conn_id'] as int? ?? 0,
    peer: json['peer'] as String? ?? '',
    methods: _names(json['methods'], 'name'),
    topics: _names(json['topics'], 'topic'),
    modules: _names(json['modules'], 'id'),
    authRequired: json['auth_required'] as bool? ?? false,
    maxInflightCalls: json['max_inflight_calls'] as int? ?? 0,
  );

  static List<String> _names(Object? list, String key) {
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map && item[key] is String) item[key] as String,
    ];
  }

  @override
  String toString() =>
      'DaemonHello($product $version, ${methods.length} methods)';
}

/// 服务端返回的业务错误,与 daemon 的 `RpcError` 一一对应。
///
/// [code] 是稳定字符串(如 `method_not_found`),UI 按它分支,**不要**匹配 message。
class DaemonException implements Exception {
  const DaemonException(this.code, this.message, {this.data});

  final String code;
  final String message;
  final Object? data;

  /// 令牌不对
  bool get isUnauthorized => code == 'unauthorized';

  /// 方法不存在(通常是两端版本不匹配)
  bool get isMethodNotFound => code == 'method_not_found';

  @override
  String toString() => 'DaemonException($code): $message';
}

/// daemon WS 协议客户端。
///
/// 负责把「一条长连接」包装成用起来像 HTTP 的东西:
///
/// ```dart
/// final hello  = await client.connect();
/// final info   = await client.callObject('core.info');
/// client.events.listen((event) => print(event['topic']));
/// await client.subscribe('ticker.*');
/// ```
///
/// 并发调用靠自增 id 配对,响应回来的顺序不保证;每次调用只可能收到一个 result。
class DaemonClient {
  DaemonClient(this._transport, this.uri);

  final DaemonTransport _transport;

  /// 实际连接的地址(含令牌查询串)
  final Uri uri;

  /// 单次调用的默认超时
  static const defaultCallTimeout = Duration(seconds: 20);

  /// 等待 hello 的超时
  static const handshakeTimeout = Duration(seconds: 10);

  final _pending = <int, Completer<Object?>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _done = Completer<void>();
  StreamSubscription<String>? _subscription;
  Completer<DaemonHello>? _hello;
  int _nextId = 1;
  bool _closed = false;
  String? _byeReason;
  String? _closeReason;
  DaemonHello? _helloInfo;

  /// 事件推送流(原始 `event` 信封)。
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// 连接结束(对端断开、出错或被本端关闭)时完成。
  Future<void> get done => _done.future;

  /// 是否仍在连接中
  bool get isAlive => !_closed && !_done.isCompleted;

  /// 服务端告别原因(收到 `bye` 时有值)
  String? get byeReason => _byeReason;

  /// 服务端握手信息(连接成功后才有)。
  ///
  /// 想知道对端能调哪些方法、能订哪些主题,读它就行,不用再去问一遍。
  DaemonHello? get hello => _helloInfo;

  /// 连接断开的原因,用于给用户看的提示
  String? get disconnectReason => _closeReason ?? _byeReason;

  // ══════════════════════════════════════════════════════════════════════
  // 连接
  // ══════════════════════════════════════════════════════════════════════

  /// 建立连接并等待 `hello`。
  ///
  /// 任何失败(握手被拒 / hello 超时)都会抛异常,且客户端随后不可用。
  Future<DaemonHello> connect({Duration timeout = handshakeTimeout}) async {
    if (_closed) throw StateError('DaemonClient 已经关闭,请新建实例');

    final hello = Completer<DaemonHello>();
    _hello = hello;

    _subscription = _transport.incoming.listen(
      _onFrame,
      onError: (Object error, StackTrace stack) {
        if (!hello.isCompleted) {
          hello.completeError(error, stack);
        }
        _finish(error: error, stack: stack);
      },
      onDone: _finish,
      cancelOnError: false,
    );

    try {
      await _transport.connect(uri);
    } catch (error, stack) {
      if (!hello.isCompleted) hello.completeError(error, stack);
      _finish(error: error, stack: stack);
    }

    try {
      final info = await hello.future.timeout(timeout);
      _helloInfo = info;
      return info;
    } on TimeoutException {
      await close();
      throw TimeoutException('等待服务端 hello 超时(${timeout.inSeconds}s)');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 调用
  // ══════════════════════════════════════════════════════════════════════

  /// 调用一个 WS 方法,返回 `result` 字段(类型可能是任意 JSON)。
  Future<Object?> call(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) => _request({
    'type': 'call',
    'method': method,
    'params': params ?? const <String, dynamic>{},
  }, timeout: timeout);

  /// 同 [call],但要求返回值是对象(绝大多数方法都是)。
  Future<Map<String, dynamic>> callObject(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    final result = await call(method, params: params, timeout: timeout);
    if (result is Map) return result.cast<String, dynamic>();
    if (result == null) return const {};
    throw DaemonException('internal', '方法 $method 的返回值不是对象:$result');
  }

  /// 订阅事件主题(支持 `*` / `prefix.*`)。
  Future<void> subscribe(String topic) =>
      _request({'type': 'subscribe', 'topic': topic});

  /// 取消订阅。
  Future<void> unsubscribe(String topic) =>
      _request({'type': 'unsubscribe', 'topic': topic});

  /// 应用层 ping(与 WS 控制帧 Ping 是两回事,给不方便发控制帧的场景用)。
  Future<void> ping() => _request({'type': 'ping'});

  /// 发送请求并等待与之配对的应答。
  Future<Object?> _request(
    Map<String, dynamic> envelope, {
    Duration? timeout,
  }) async {
    if (!isAlive) {
      throw const DaemonException('disconnected', '连接尚未建立或已断开');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send({...envelope, 'id': id});
    try {
      return await completer.future.timeout(timeout ?? defaultCallTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw DaemonException(
        'timeout',
        '${envelope['method'] ?? envelope['type']} 响应超时',
      );
    }
  }

  void _send(Map<String, dynamic> envelope) {
    if (_closed) return;
    _transport.send(jsonEncode(envelope));
  }

  // ══════════════════════════════════════════════════════════════════════
  // 收帧
  // ══════════════════════════════════════════════════════════════════════

  void _onFrame(String raw) {
    final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      message = decoded.cast<String, dynamic>();
    } catch (_) {
      // 单帧解析失败不该拖垮整条连接
      return;
    }

    switch (message['type']) {
      case 'hello':
        _hello?.complete(DaemonHello.fromJson(message));
        _hello = null;

      case 'result':
        _settleResult(message);

      case 'pong':
        _pending.remove(message['id'])?.complete(null);

      case 'event':
        if (!_events.isClosed) _events.add(message);

      case 'error':
        // 协议级错误:能对上 id 就交给调用方,否则丢弃
        final pending = _pending.remove(message['id']);
        final error = message['error'];
        pending?.completeError(
          error is Map
              ? DaemonException(
                  error['code'] as String? ?? 'internal',
                  error['message'] as String? ?? '未知错误',
                )
              : const DaemonException('internal', '未知错误'),
        );

      case 'bye':
        _byeReason = message['reason'] as String?;
    }
  }

  void _settleResult(Map<String, dynamic> message) {
    final completer = _pending.remove(message['id']);
    if (completer == null) return;
    if (message['ok'] == true) {
      completer.complete(message['result']);
      return;
    }
    final error = message['error'];
    completer.completeError(
      error is Map
          ? DaemonException(
              error['code'] as String? ?? 'internal',
              error['message'] as String? ?? '未知错误',
              data: error['data'],
            )
          : const DaemonException('internal', '未知错误'),
    );
  }

  void _finish({Object? error, StackTrace? stack}) {
    if (_closed) return;
    _closed = true;
    _subscription?.cancel();
    _subscription = null;

    final reason = _byeReason ?? (error == null ? '连接已断开' : error.toString());
    _closeReason = reason;

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(DaemonException('disconnected', reason));
      }
    }
    _pending.clear();

    final hello = _hello;
    if (hello != null && !hello.isCompleted) {
      hello.completeError(DaemonException('disconnected', reason));
    }
    _hello = null;

    if (!_events.isClosed) _events.close();
    if (!_done.isCompleted) _done.complete();
  }

  /// 主动关闭。已关闭时是幂等的。
  Future<void> close({int? code = 1000, String? reason}) async {
    if (!_closed) {
      _closed = true;
      _subscription?.cancel();
      _subscription = null;
      final reasonText = reason ?? _byeReason ?? '客户端关闭连接';
      _closeReason = reasonText;
      for (final completer in _pending.values) {
        if (!completer.isCompleted) {
          completer.completeError(DaemonException('disconnected', reasonText));
        }
      }
      _pending.clear();
      if (!_events.isClosed) _events.close();
      if (!_done.isCompleted) _done.complete();
    }
    await _transport.close(code, reason);
  }

  @override
  String toString() => 'DaemonClient($uri)';
}
