import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/stun_store.dart';
import 'proxy_protocol.dart';
import 'stun_client.dart';

/// STUN 隧道的运行状态。
enum StunTunnelStatus {
  /// 未启用 / 已停止。
  stopped,

  /// 正在向 STUN 服务器探测公网映射，或正在等待重试。
  probing,

  /// 隧道已就绪，正在转发。
  running,

  /// 多次尝试后仍无法建立隧道（通常是 NAT 类型不支持）。
  failed,
}

/// 纯 Dart 实现的 STUN 隧道（NAT1 打洞）。
///
/// 参考 MSL 的「STUN 隧道」与 Natter 的思路：向 STUN 服务器发起 **TCP** 探测，
/// 让 NAT 为本地端口 P 建立映射并得知其公网端点；随后把监听套接字绑定到同一个
/// 本地端口 P，外部玩家连到公网端点即可被 NAT 转发进来，再由本服务转发到本地
/// 服务端端口。全程不依赖任何中转服务器，带宽即家宽上行。
///
/// **仅对全锥形 NAT（NAT1）有效**。移动网络、CGNAT、对称 NAT 下无法建立，
/// 此时应改用 FRP 隧道。
///
/// 与 MSL 版本的关键差异：MSL 每 15 秒用同一源端口新建一条出站连接来保活，
/// 该做法在 Linux/Android 上会被内核的 bind 冲突检查拒绝（监听套接字处于
/// LISTEN 态时必须双方都有 `SO_REUSEPORT`，而 Dart 无法在 bind 前设置）。
/// 这里改为保持探测连接长期存活并在其上周期重发 Binding Request，
/// 详见 [StunTcpSession]。
class StunTunnelService extends ChangeNotifier {
  StunTunnelService._();

  /// 全局单例：隧道是进程级资源（占用一个本地端口），且多个页面都要读它的状态。
  static final StunTunnelService instance = StunTunnelService._();

  static const int _maxLogLines = 500;

  /// 连续失败多少轮后放弃（避免在不支持的网络下无休止重试）。
  static const int _maxConsecutiveFailures = 3;

  // —— 运行时状态 ——
  StunTunnelStatus _status = StunTunnelStatus.stopped;
  StunMappedAddress? _publicAddress;
  String? _lastError;
  int _localPort = 0;
  int _targetPort = 0;

  // —— 连接与流量统计 ——
  int _activeConnections = 0;
  int _totalUpload = 0;
  int _totalDownload = 0;
  int _uploadSpeed = 0;
  int _downloadSpeed = 0;
  int _lastUpload = 0;
  int _lastDownload = 0;

  // —— 内部持有 ——
  StunConfig _config = const StunConfig();
  ServerSocket? _listener;
  StreamSubscription<Socket>? _acceptSub;
  StunTcpSession? _session;
  Timer? _speedTimer;
  final Set<Socket> _liveSockets = {};

  /// 启停代次：递增后使仍在运行的旧循环自行退出，避免重复启动时互相踩踏。
  int _epoch = 0;
  bool _running = false;

  // —— 日志 ——
  final List<String> _logBuffer = [];
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  // ── 公共状态 ────────────────────────────────────────────────

  StunTunnelStatus get status => _status;

  /// 隧道是否已启用（含探测中与重试中）。
  bool get isActive => _status != StunTunnelStatus.stopped;

  /// 隧道是否已就绪并可转发。
  bool get isRunning => _status == StunTunnelStatus.running;

  /// 公网直连端点；未就绪时为 null。
  StunMappedAddress? get publicAddress => _publicAddress;

  /// 最近一次失败原因；正常时为 null。
  String? get lastError => _lastError;

  /// 正在转发的入站连接数。
  int get activeConnections => _activeConnections;

  /// 并发连接上限。
  int get maxConnections => _config.maxConnections;

  /// 本次运行累计上行 / 下行字节数（上行 = 服务端发给玩家）。
  int get totalUpload => _totalUpload;
  int get totalDownload => _totalDownload;

  /// 最近一秒的上行 / 下行速率（字节每秒）。
  int get uploadSpeed => _uploadSpeed;
  int get downloadSpeed => _downloadSpeed;

  /// 隧道转发的目标本地端口（服务端实际监听端口）。
  int get targetPort => _targetPort;

  /// 隧道监听的本地端口，即 NAT 映射的内侧端点；未就绪时为 0。
  int get localPort => _localPort;

  /// 日志流：新订阅者先收到历史日志回放，随后接收实时日志。
  Stream<String> logs() {
    late StreamController<String> replay;
    StreamSubscription<String>? sub;
    replay = StreamController<String>(
      onListen: () {
        for (final line in _logBuffer) {
          replay.add(line);
        }
        sub = _logController.stream.listen(
          replay.add,
          onError: replay.addError,
          onDone: replay.close,
        );
      },
      onCancel: () => sub?.cancel(),
    );
    return replay.stream;
  }

  void clearLog() {
    _logBuffer.clear();
    notifyListeners();
  }

  // ── 生命周期 ──────────────────────────────────────────────

  /// 启动隧道。
  ///
  /// [targetPort] 为要暴露的本地服务端口。重复调用会先停止旧隧道。
  Future<void> start(StunConfig config, {required int targetPort}) async {
    await stop();
    _config = config;
    _targetPort = targetPort;
    _running = true;
    _status = StunTunnelStatus.probing;
    _lastError = null;
    _publicAddress = null;
    _totalUpload = 0;
    _totalDownload = 0;
    _lastUpload = 0;
    _lastDownload = 0;
    _uploadSpeed = 0;
    _downloadSpeed = 0;
    notifyListeners();

    _speedTimer?.cancel();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickSpeed());

    final epoch = ++_epoch;
    _log('隧道启动中，本地目标端口 $targetPort');
    unawaited(_runLoop(epoch));
  }

  /// 停止隧道并释放全部套接字。
  Future<void> stop() async {
    if (!_running && _status == StunTunnelStatus.stopped) return;
    _running = false;
    _epoch++;
    _speedTimer?.cancel();
    _speedTimer = null;
    await _teardown();
    _status = StunTunnelStatus.stopped;
    _publicAddress = null;
    _activeConnections = 0;
    _uploadSpeed = 0;
    _downloadSpeed = 0;
    _localPort = 0;
    _log('隧道已停止');
    notifyListeners();
  }

  // ── 主循环 ────────────────────────────────────────────────

  /// 一轮 = 探测公网映射 → 绑定监听 → 保活并监控 → 需要时重建。
  Future<void> _runLoop(int epoch) async {
    var failures = 0;
    while (_running && epoch == _epoch) {
      final session = await _probe(epoch);
      if (!_running || epoch != _epoch) break;

      if (session == null) {
        failures++;
        if (failures >= _maxConsecutiveFailures) {
          _fail('全部 STUN 服务器均无法建立隧道，当前网络可能不支持（对称 NAT / CGNAT），请改用 FRP 隧道');
          return;
        }
        _log('本轮探测失败，15 秒后重试（$failures/$_maxConsecutiveFailures）');
        _status = StunTunnelStatus.probing;
        notifyListeners();
        await _sleep(const Duration(seconds: 15), epoch);
        continue;
      }

      final bound = await _bindListener(session, epoch);
      if (!_running || epoch != _epoch) {
        await session.close();
        break;
      }
      if (!bound) {
        failures++;
        await session.close();
        // 探测虽已拿到映射，但没能监听，该地址不可用，不要留在界面上。
        _publicAddress = null;
        notifyListeners();
        if (failures >= _maxConsecutiveFailures) {
          _fail('无法在映射端口上建立监听，隧道启动失败');
          return;
        }
        await _sleep(const Duration(seconds: 5), epoch);
        continue;
      }

      failures = 0;
      // 保活 + 公网地址变化监控；返回即表示需要重建隧道。
      await _keepAlive(session, epoch);
      if (!_running || epoch != _epoch) break;

      await _teardown();
      _status = StunTunnelStatus.probing;
      _publicAddress = null;
      notifyListeners();
      _log('正在重建隧道…');
      await _sleep(const Duration(seconds: 3), epoch);
    }
  }

  /// 依次尝试各 STUN 服务器，返回可用的长连接会话；全部失败返回 null。
  Future<StunTcpSession?> _probe(int epoch) async {
    final servers =
        _config.servers.isNotEmpty ? _config.servers : StunClient.defaultServers;
    for (final server in servers) {
      if (!_running || epoch != _epoch) return null;
      _log('正在从 STUN 服务器探测：$server');
      StunTcpSession? session;
      try {
        session = await StunTcpSession.connect(server);
        final mapped = await session.requestMapping();
        if (!_running || epoch != _epoch) {
          await session.close();
          return null;
        }
        _publicAddress = mapped;
        _localPort = session.localPort;
        _lastError = null;
        _log('探测成功：本地端口 ${session.localPort} → 公网 $mapped');
        return session;
      } catch (e) {
        _lastError = '$e';
        _log('STUN [$server] 不可用：$e');
        await session?.close();
      }
    }
    return null;
  }

  /// 把监听套接字绑定到 STUN 会话所用的本地端口。
  ///
  /// 能成功的前提是 [StunTcpSession] 已给探测连接设置了 `SO_REUSEADDR`。
  Future<bool> _bindListener(StunTcpSession session, int epoch) async {
    try {
      final listener = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        session.localPort,
      );
      if (!_running || epoch != _epoch) {
        await listener.close();
        return false;
      }
      _listener = listener;
      _session = session;
      _acceptSub = listener.listen(
        (client) => unawaited(_handleInbound(client, epoch)),
        onError: (Object e) => _log('监听套接字出错：$e'),
      );
      _status = StunTunnelStatus.running;
      _lastError = null;
      notifyListeners();
      _log('隧道已就绪：tcp://127.0.0.1:$_targetPort → tcp://0.0.0.0:${session.localPort}');
      _log('公网直连地址：${_publicAddress ?? '-'}');
      return true;
    } catch (e) {
      _lastError = '$e';
      _log('绑定本地端口 ${session.localPort} 失败：$e');
      return false;
    }
  }

  /// 在探测连接上周期重发 Binding Request：既保活 NAT 映射，又能发现公网地址变化。
  ///
  /// 返回即表示隧道需要重建（连接断开或公网地址变了）。
  Future<void> _keepAlive(StunTcpSession session, int epoch) async {
    final interval = Duration(seconds: _config.keepAliveSeconds);
    final baseline = _publicAddress;
    while (_running && epoch == _epoch) {
      await _sleep(interval, epoch);
      if (!_running || epoch != _epoch) return;
      if (session.isClosed) {
        _log('保活连接已断开，NAT 映射可能失效');
        return;
      }
      try {
        final mapped = await session.requestMapping();
        if (mapped != baseline) {
          _log('检测到公网地址变化：$baseline → $mapped');
          return;
        }
      } catch (e) {
        _log('保活探测失败：$e');
        return;
      }
    }
  }

  // ── 转发 ──────────────────────────────────────────────────

  /// 处理一条入站连接：连本地服务端口，双向转发。
  Future<void> _handleInbound(Socket inbound, int epoch) async {
    final remote = '${inbound.remoteAddress.address}:${inbound.remotePort}';
    if (!_running || epoch != _epoch) {
      inbound.destroy();
      return;
    }
    if (_activeConnections >= _config.maxConnections) {
      if (_config.showConnectionLog) {
        _log('拒绝 $remote：已达并发上限 ${_config.maxConnections}');
      }
      inbound.destroy();
      return;
    }

    _activeConnections++;
    _liveSockets.add(inbound);
    notifyListeners();
    if (_config.showConnectionLog) _log('入站连接 $remote');

    Socket? backend;
    try {
      inbound.setOption(SocketOption.tcpNoDelay, true);
      backend = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _targetPort,
        timeout: const Duration(seconds: 5),
      );
      backend.setOption(SocketOption.tcpNoDelay, true);
      _liveSockets.add(backend);

      // PROXY protocol v2：让服务端拿到玩家真实 IP（需服务端开启对应支持）。
      if (_config.proxyProtocol) {
        backend.add(
          ProxyProtocolV2.buildHeader(
            src: inbound.remoteAddress,
            srcPort: inbound.remotePort,
            dst: inbound.address,
            dstPort: inbound.port,
          ),
        );
      }

      await Future.any([
        _pump(inbound, backend, upload: false),
        _pump(backend, inbound, upload: true),
      ]);
    } catch (e) {
      if (_config.showConnectionLog) _log('$remote 转发失败：$e');
    } finally {
      _liveSockets.remove(inbound);
      if (backend != null) _liveSockets.remove(backend);
      _destroy(inbound);
      if (backend != null) _destroy(backend);
      _activeConnections--;
      if (_activeConnections < 0) _activeConnections = 0;
      if (_config.showConnectionLog) _log('断开连接 $remote');
      notifyListeners();
    }
  }

  /// 单向搬运数据并计流量。
  ///
  /// 用 [IOSink.addStream] 而非逐块 `add`，以便在对端较慢时自动施加背压，
  /// 避免大文件下载类流量把数据全堆在内存里。
  Future<void> _pump(Socket from, Socket to, {required bool upload}) async {
    try {
      await to.addStream(
        from.map((chunk) {
          if (upload) {
            _totalUpload += chunk.length;
          } else {
            _totalDownload += chunk.length;
          }
          return chunk;
        }),
      );
    } catch (_) {
      // 任一端断开都会走到这里，由调用方统一收尾。
    }
  }

  // ── 工具 ──────────────────────────────────────────────────

  /// 关闭监听、保活连接与全部在途转发连接。
  Future<void> _teardown() async {
    await _acceptSub?.cancel();
    _acceptSub = null;
    try {
      await _listener?.close();
    } catch (_) {
      // 已关闭，忽略。
    }
    _listener = null;
    await _session?.close();
    _session = null;
    for (final socket in _liveSockets.toList()) {
      _destroy(socket);
    }
    _liveSockets.clear();
    _activeConnections = 0;
  }

  void _destroy(Socket socket) {
    try {
      socket.destroy();
    } catch (_) {
      // 已关闭，忽略。
    }
  }

  /// 可被停止操作提前打断的延时。
  Future<void> _sleep(Duration duration, int epoch) async {
    const step = Duration(milliseconds: 250);
    var remaining = duration;
    while (remaining > Duration.zero) {
      if (!_running || epoch != _epoch) return;
      final slice = remaining < step ? remaining : step;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
  }

  void _tickSpeed() {
    final upload = _totalUpload;
    final download = _totalDownload;
    _uploadSpeed = upload - _lastUpload;
    _downloadSpeed = download - _lastDownload;
    _lastUpload = upload;
    _lastDownload = download;
    if (_status == StunTunnelStatus.running) notifyListeners();
  }

  void _fail(String reason) {
    _lastError = reason;
    _status = StunTunnelStatus.failed;
    _running = false;
    _publicAddress = null;
    _speedTimer?.cancel();
    _speedTimer = null;
    unawaited(_teardown());
    _log('隧道启动失败：$reason');
    notifyListeners();
  }

  void _log(String message) {
    final now = DateTime.now();
    final stamp = '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
    final line = '$stamp $message';
    _logBuffer.add(line);
    if (_logBuffer.length > _maxLogLines) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxLogLines);
    }
    if (!_logController.isClosed) _logController.add(line);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// 把字节数格式化为可读文本（供 UI 复用）。
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(2)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
