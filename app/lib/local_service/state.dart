import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/settings.dart';
import '../connection/state.dart';
import 'platform.dart';
import 'settings.dart';

/// 日志最多保留多少行(平台侧同样有上限,这里再兜一层)
const int maxLocalServiceLogLines = 2000;

/// 平台能力来源。测试里 override 成假实现,正式运行按平台自动选择。
final localServicePlatformProvider = Provider<LocalServicePlatform>(
  (ref) => createLocalServicePlatform(),
);

/// UI 需要的本地服务快照。
class LocalServiceSnapshot {
  const LocalServiceSnapshot({
    this.supported,
    this.status = const LocalServiceStatus(),
    this.logs = const <String>[],
    this.error,
  });

  /// `null` = 还在检查平台能力;`false` = 当前平台不支持
  final bool? supported;

  final LocalServiceStatus status;
  final List<String> logs;

  /// 通道/平台异常(与 daemon 自己报的 [LocalServiceStatus.message] 分开)
  final String? error;

  static const _unset = Object();

  LocalServiceSnapshot copyWith({
    bool? supported,
    LocalServiceStatus? status,
    List<String>? logs,
    Object? error = _unset,
  }) => LocalServiceSnapshot(
    supported: supported ?? this.supported,
    status: status ?? this.status,
    logs: logs ?? this.logs,
    error: error == _unset ? this.error : error as String?,
  );
}

/// 本地服务状态机:启动/停止、日志收集,并在服务就绪后自动连上它。
///
/// 连接用 `persist: false`:本地端口与令牌每次启动都是新的,
/// 落盘只会让下次启动去连一个已经失效的地址,还会覆盖用户保存的远程服务器。
final localServiceProvider =
    NotifierProvider<LocalServiceNotifier, LocalServiceSnapshot>(
      LocalServiceNotifier.new,
    );

class LocalServiceNotifier extends Notifier<LocalServiceSnapshot> {
  late final LocalServicePlatform _platform;
  StreamSubscription<LocalServiceEvent>? _subscription;
  Future<void> _ready = Future<void>.value();
  bool _disposed = false;

  /// 当前连接来自本地服务时记下目标;服务停掉后据此断开,
  /// 不会误伤用户手动连接的 127.0.0.1(那只是普通远程配置)。
  String? _localTarget;
  String? _connectingTarget;

  @override
  LocalServiceSnapshot build() {
    _platform = ref.watch(localServicePlatformProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
    });
    _ready = _initialize();
    return const LocalServiceSnapshot();
  }

  Future<void> _initialize() async {
    try {
      final supported = await _platform.isSupported();
      if (_disposed) return;
      if (!supported) {
        state = state.copyWith(supported: false);
        return;
      }
      final status = await _platform.status();
      final logs = await _platform.logs();
      if (_disposed) return;
      state = LocalServiceSnapshot(supported: true, status: status, logs: logs);
      // 平台在挂上监听时会回放当前状态,但初始化与监听之间仍可能有间隙,
      // 所以先把读到的状态处理一遍。
      _subscription = _platform.events.listen(_onEvent, onError: _onEventError);
      _reactToStatus(status);
    } catch (error) {
      if (_disposed) return;
      debugPrint('[local-service] 初始化失败: $error');
      state = state.copyWith(supported: false, error: '本地服务不可用：$error');
    }
  }

  // ── 启停 ────────────────────────────────────────────────────────────────

  /// 启动时必须已经等待初始化完成
  Future<void> start() async {
    await _ready;
    if (_disposed || state.supported != true) return;
    // 先落开关:即使这次启动失败,下次打开也还会自动重试
    await ref.read(localServiceEnabledProvider.notifier).set(true);
    if (_disposed) return;
    try {
      _applyStatus(await _platform.start());
    } catch (error) {
      if (_disposed) return;
      debugPrint('[local-service] 启动失败: $error');
      state = state.copyWith(
        status: LocalServiceStatus(
          phase: LocalServicePhase.failed,
          message: '本地服务启动失败：$error',
        ),
        error: '$error',
      );
    }
  }

  /// 应用启动时调用:配置里开着本地服务就自动启动。
  Future<void> startIfEnabled() async {
    await _ready;
    if (_disposed) return;
    if (!ref.read(localServiceEnabledProvider)) return;
    if (state.supported != true) return;
    if (state.status.isActive) {
      // 例如热重启后服务还在跑:直接补上连接
      _reactToStatus(state.status);
      return;
    }
    await start();
  }

  Future<void> stop() async {
    await _ready;
    if (_disposed) return;
    // 用户主动停止 = 不再自动启动
    await ref.read(localServiceEnabledProvider.notifier).set(false);
    if (state.supported != true) return;
    try {
      final status = await _platform.stop();
      _applyStatus(status);
      if (!status.isActive) unawaited(_disconnectLocal());
    } catch (error) {
      if (_disposed) return;
      debugPrint('[local-service] 停止失败: $error');
      state = state.copyWith(error: '$error');
    }
  }

  /// 横幅上的「重试」:本地服务已就绪时重连它,而不是去连手工填写的地址。
  Future<bool> retryConnection() async {
    final settings = state.status.connection;
    if (settings == null) return false;
    _localTarget = settings.target;
    return _connectLocal(settings);
  }

  Future<void> clearLogs() async {
    await _ready;
    if (_disposed || state.supported != true) return;
    try {
      await _platform.clearLogs();
    } catch (error) {
      debugPrint('[local-service] 清空日志失败: $error');
    }
    if (_disposed) return;
    state = state.copyWith(logs: const <String>[]);
  }

  // ── 事件与连接 ──────────────────────────────────────────────────────────

  void _onEvent(LocalServiceEvent event) {
    if (_disposed) return;
    switch (event) {
      case LocalServiceStatusEvent(:final status):
        _applyStatus(status);
      case LocalServiceLogEvent(:final line):
        _appendLog(line);
    }
  }

  void _onEventError(Object error) {
    if (_disposed) return;
    debugPrint('[local-service] 事件流异常: $error');
    state = state.copyWith(error: '$error');
  }

  void _applyStatus(LocalServiceStatus status) {
    if (_disposed) return;
    if (state.status == status) return;
    state = state.copyWith(status: status, error: null);
    _reactToStatus(status);
  }

  /// 服务就绪 → 自动连接;服务停止/失败 → 断开由它拉起的连接。
  void _reactToStatus(LocalServiceStatus status) {
    if (_disposed) return;
    if (!status.isActive) {
      unawaited(_disconnectLocal());
      return;
    }
    if (!status.isRunning) return;

    final settings = status.connection;
    if (settings == null) return;
    if (!ref.read(localServiceEnabledProvider)) return;

    _localTarget = settings.target;
    final current = ref.read(connectionProvider);
    if (current.isConnected && current.target == settings.target) return;
    if (current.isConnecting && current.target == settings.target) return;
    unawaited(_connectLocal(settings));
  }

  Future<bool> _connectLocal(ConnectionSettings settings) async {
    if (_connectingTarget == settings.target) return false;
    _connectingTarget = settings.target;
    try {
      return await ref
          .read(connectionProvider.notifier)
          .connect(settings, persist: false);
    } finally {
      if (_connectingTarget == settings.target) _connectingTarget = null;
    }
  }

  Future<void> _disconnectLocal() async {
    final target = _localTarget;
    _localTarget = null;
    if (target == null) return;
    final current = ref.read(connectionProvider);
    if (current.target != target) return;
    if (current.phase == ConnectionPhase.idle) return;
    await ref.read(connectionProvider.notifier).disconnect();
  }

  void _appendLog(String raw) {
    final line = raw.trimRight();
    if (line.isEmpty || _disposed) return;
    final logs = [...state.logs, line];
    if (logs.length > maxLocalServiceLogLines) {
      logs.removeRange(0, logs.length - maxLocalServiceLogLines);
    }
    state = state.copyWith(logs: logs);
  }
}
