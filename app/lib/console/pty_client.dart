import 'dart:async';
import 'dart:convert';

import '../instance/models.dart';
import 'pty_transport.dart';

/// 控制台流的客户端（`/pty/{id}`）。
///
/// 协议来自 daemon 的 `instance::serve_pty`，也就是 `pty-terminal-demo` 那套：
///
/// * **服务端 → 客户端**：文本帧是控制 JSON（`history_begin` / `history_end` /
///   `exit`），二进制帧是原始输出；
/// * **客户端 → 服务端**：二进制帧 = 原样写进 PTY 的字节（敲键），
///   文本帧 = `{"resize":{"cols":…,"rows":…}}`。
///
/// 与 demo 的差别只有一条：`history_end` 顺带带上当前状态，所以连上来就能知道
/// 「现在到底跑没跑」，不用再问一次。
class PtyClient {
  PtyClient(this.url, {PtyTransport Function(Uri)? transport})
    : _transport = transport ?? WebSocketPtyTransport.new;

  final Uri url;

  /// 传输工厂。测试注入内存实现，生产就是 WebSocket。
  final PtyTransport Function(Uri) _transport;

  final _bytes = StreamController<List<int>>();
  final _status = StreamController<PtyStatus>.broadcast();
  final _historyBegin = StreamController<void>.broadcast();
  final _historyEnd = StreamController<void>.broadcast();

  /// 原始输出。用 `utf8.decoder` 而不是手工 decode —— 分块读取会把一个多字节
  /// 字符切成两半，交给 StreamTransformer 才拼得回来。
  late final Stream<String> output = _bytes.stream.transform(
    const Utf8Decoder(allowMalformed: true),
  );

  /// 状态变化（连上 / 进程阶段 / 退出）。
  Stream<PtyStatus> get status => _status.stream;

  /// 服务端**马上要重放历史**了 —— 页面收到它就该清屏。
  ///
  /// 清屏只能挂在这一帧上：挂到 [`historyEnd`] 上的话，擦掉的是刚重放完的历史。
  Stream<void> get historyBegin => _historyBegin.stream;

  /// 历史快照发完了 —— 页面收到它就可以认为「后面的都是实时的」。
  Stream<void> get historyEnd => _historyEnd.stream;

  PtyTransport? _link;
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;
  bool _connected = false;

  bool get isConnected => _connected;

  void connect() {
    if (_closed || _link != null) return;
    try {
      final link = _transport(url);
      _link = link;
      _subscription = link.frames.listen(
        _onFrame,
        onError: (Object error) => _fail('控制台连接出错：$error'),
        onDone: () => _fail('控制台连接已断开'),
      );
      _connected = true;
      _emit(const PtyStatus.connecting());
      // 连接一建立就把已知尺寸发下去（握手完成前的消息会被通道缓存住，
      // 所以这里不必等 ready）。
      _sendSize();
    } catch (error) {
      _fail('连不上控制台：$error');
    }
  }

  /// 敲键（可以直接把 xterm 的 `onOutput` 接过来）。
  void write(String data) => _send(binary: utf8.encode(data));

  /// 报告控制台尺寸。
  ///
  /// **会记住这个尺寸**，连接（含重连）一建立就立刻补发一次。终端往往在连接
  /// 之前就量好了尺寸 —— 那一次调用落在「页面还没拿到客户端」的空窗里，
  /// 不补发的话服务端会一直按默认的 80×24 排版和换行。
  void resize(int cols, int rows) {
    _size = (cols: cols, rows: rows);
    _sendSize();
  }

  /// 当前尺寸；还没量出来时为 `null`。
  ({int cols, int rows})? _size;

  void _sendSize() {
    final size = _size;
    if (size == null || _link == null) return;
    _send(
      text: jsonEncode({
        'resize': {'cols': size.cols, 'rows': size.rows},
      }),
    );
  }

  Future<void> close() async {
    _closed = true;
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    // transport 的 close 也**不能 await**：订阅已经在上一行取消，没人收 done 时
    // 这个 Future 可能永远不完成 —— 重连会卡在 detach 里，页面永远连不上新的流。
    // 关连接本身是 sink 侧的动作，不 await 也会执行。
    final link = _link;
    _link = null;
    if (link != null) unawaited(link.close());
    // 这三个流的 close() 同理不能 await：`_bytes` 是单订阅流，**没人监听时**
    // 它的 `close()` 返回的 Future 永远不完成（要等 done 送达监听者），
    // await 会把 dispose 卡死。这里 fire-and-forget 就够。
    unawaited(_bytes.close());
    unawaited(_status.close());
    unawaited(_historyBegin.close());
    unawaited(_historyEnd.close());
  }

  void _send({List<int>? binary, String? text}) {
    final link = _link;
    if (link == null) return;
    if (binary != null) {
      link.send(binary);
    } else if (text != null) {
      link.send(text);
    }
  }

  void _onFrame(dynamic frame) {
    if (frame is List<int>) {
      // web_socket_channel 在部分平台给的是 Uint8List，也有给 String 的
      if (!_bytes.isClosed) _bytes.add(frame);
      return;
    }
    if (frame is! String) return;
    final Object? decoded = jsonDecode(frame);
    if (decoded is! Map) return;
    switch (decoded['type']) {
      case 'history_begin':
        // 页面借此清屏，避免同一个实例来回切页时历史叠两层
        if (!_historyBegin.isClosed) _historyBegin.add(null);
      case 'history_end':
        if (!_historyEnd.isClosed) _historyEnd.add(null);
        _emit(PtyStatus.fromState(decoded['state'], connected: true));
      case 'exit':
        _emit(
          PtyStatus(
            connected: _connected,
            phase: ServerPhase.parse(decoded['phase'] as String?),
            exitCode: (decoded['code'] as num?)?.toInt(),
          ),
        );
    }
  }

  void _emit(PtyStatus status) {
    if (!_status.isClosed) _status.add(status);
  }

  void _fail(String message) {
    _connected = false;
    _link = null;
    _emit(PtyStatus.error(message));
  }
}

/// 控制台的状态快照。
class PtyStatus {
  const PtyStatus({
    this.connected = false,
    this.phase,
    this.exitCode,
    this.error,
  });

  const PtyStatus.connecting() : this();

  const PtyStatus.error(String message) : this(error: message);

  /// 从 `history_end` 里的 `state` 解析（字段就是 daemon 的 `RunInfo`）。
  factory PtyStatus.fromState(Object? state, {required bool connected}) {
    if (state is! Map) return PtyStatus(connected: connected);
    return PtyStatus(
      connected: connected,
      phase: ServerPhase.parse(state['phase'] as String?),
      exitCode: (state['exit_code'] as num?)?.toInt(),
    );
  }

  final bool connected;

  /// 进程阶段；`null` = 还没拿到。
  final ServerPhase? phase;

  /// 上一次退出的退出码。
  final int? exitCode;

  /// 出错时的一句话（连接失败 / 断开）。
  final String? error;

  bool get hasError => error != null;

  /// 标题栏上的那一行状态文案。
  String get label {
    if (error != null) return error!;
    final phase = this.phase;
    if (phase == null) return '读取状态中…';
    if (phase == ServerPhase.stopped && exitCode != null) {
      return '${phase.label}（上次退出码 $exitCode）';
    }
    return phase.label;
  }

  /// 是否处于「进程活着」的阶段。
  bool get alive =>
      phase != null &&
      phase != ServerPhase.stopped &&
      phase != ServerPhase.crashed;
}
