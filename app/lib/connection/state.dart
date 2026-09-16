import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../storage.dart';
import 'client.dart';
import 'settings.dart';
import 'transport.dart';

/// 连接所处阶段。UI 只依赖这一个枚举,不用自己拼一堆布尔。
enum ConnectionPhase {
  /// 未连接(启动时还没有历史配置,或用户主动断开)
  idle,

  /// 正在握手
  connecting,

  /// 已连接可用
  connected,

  /// 连接失败或掉线
  failed,
}

/// 连接状态快照。
class ConnectionStatus {
  const ConnectionStatus({
    this.phase = ConnectionPhase.idle,
    this.target,
    this.error,
    this.hello,
    this.client,
    this.attempt = 0,
    this.subscriptions = const <String>{},
  });

  final ConnectionPhase phase;

  /// 目标地址 `host:port`,供 UI 显示
  final String? target;

  /// 失败原因(给人看的)
  final String? error;

  /// 服务端握手信息(连上后才有)
  final DaemonHello? hello;

  /// 当前客户端(未连接时为空)。放在状态里,重连后依赖它的 Provider 会自动重跑。
  final DaemonClient? client;

  /// 连续失败次数(连上即归零)
  final int attempt;

  /// **当前这条连接上真正生效**的订阅。
  ///
  /// 订阅是连接级的:连接一断,服务端那侧随之消失,这里也就清空。
  /// 注意别和「期望订阅」(`ConnectionNotifier.desiredTopics`)搞混 ——
  /// 后者是重连后要不要自动补订的意图。
  final Set<String> subscriptions;

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isConnecting => phase == ConnectionPhase.connecting;

  static const _unset = Object();

  ConnectionStatus copyWith({
    ConnectionPhase? phase,
    Object? target = _unset,
    Object? error = _unset,
    Object? hello = _unset,
    Object? client = _unset,
    int? attempt,
    Set<String>? subscriptions,
  }) => ConnectionStatus(
    phase: phase ?? this.phase,
    target: target == _unset ? this.target : target as String?,
    error: error == _unset ? this.error : error as String?,
    hello: hello == _unset ? this.hello : hello as DaemonHello?,
    client: client == _unset ? this.client : client as DaemonClient?,
    attempt: attempt ?? this.attempt,
    subscriptions: subscriptions ?? this.subscriptions,
  );

  @override
  bool operator ==(Object other) =>
      other is ConnectionStatus &&
      other.phase == phase &&
      other.target == target &&
      other.error == error &&
      other.attempt == attempt &&
      setEquals(other.subscriptions, subscriptions) &&
      // 客户端按身份比较:重连后换新实例 → 依赖它的 Provider 会重跑
      identical(other.client, client);

  @override
  int get hashCode => Object.hash(
    phase,
    target,
    error,
    attempt,
    identityHashCode(client),
    Object.hashAllUnordered(subscriptions),
  );

  @override
  String toString() => 'ConnectionStatus($phase, target: $target)';
}

// ══════════════════════════════════════════════════════════════════════════
// 持久化配置("连成功过"的那一份)
// ══════════════════════════════════════════════════════════════════════════

/// 启动时读到的历史配置(从未连接过则 null),main() 中 override。
final initialPersistedConnectionProvider = Provider<ConnectionSettings?>(
  (ref) => null,
);

/// 已成功连接过并已落盘的配置。
///
/// **路由据此判断要不要先走连接页**:它非空就说明用户配过、连通过,
/// 之后即使掉线也留在主界面(顶部横幅提示),而不是把人踢回连接页。
final persistedConnectionProvider =
    NotifierProvider<PersistedConnectionNotifier, ConnectionSettings?>(
      PersistedConnectionNotifier.new,
    );

class PersistedConnectionNotifier extends Notifier<ConnectionSettings?> {
  @override
  ConnectionSettings? build() => ref.watch(initialPersistedConnectionProvider);

  /// 连接成功时调用:记住这台服务器。
  Future<void> save(ConnectionSettings settings) async {
    if (state != settings) state = settings;
    await saveConnection(ref.read(storageProvider), settings);
  }

  /// 忘记这台服务器(回到"从未连接过"的状态)。
  Future<void> clear() async {
    if (state != null) state = null;
    await clearConnection(ref.read(storageProvider));
  }
}

// 注:这里**特意不提供** `hasSavedConnectionProvider` 之类的派生布尔。
// 路由守卫需要"有没有配过"，若读的是派生值，会在真源变更的监听回调里
// 拿到还没失效的旧缓存（踩过一次）。要判断就直读 persistedConnectionProvider。

// ══════════════════════════════════════════════════════════════════════════
// 连接状态机
// ══════════════════════════════════════════════════════════════════════════

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionStatus>(
      ConnectionNotifier.new,
    );

/// 连上之后如果掉线,自动重连的最大次数;超过就让用户手动点重试。
const int maxAutoRetries = 5;

class ConnectionNotifier extends Notifier<ConnectionStatus> {
  static const _baseRetryDelay = Duration(seconds: 1);
  static const _maxRetryDelay = Duration(seconds: 15);

  DaemonClient? _client;
  Timer? _retryTimer;

  /// **期望订阅**:连上之后想订阅哪些主题,只服务于「掉线后自动补订」。
  ///
  /// 与 [`ConnectionStatus::subscriptions`] 的分工:
  ///
  /// | 场景 | 生效订阅(subscriptions) | 期望订阅(desiredTopics) |
  /// | --- | --- | --- |
  /// | 订阅成功 | 加入 | 加入 |
  /// | 主动 unsubscribe | 移出 | 移出 |
  /// | 掉线(自动重连中) | **清空**(服务端那侧也没了) | 保留 → 重连后自动补订 |
  /// | 主动断开 / 忘记服务器 | 清空 | **清空**(用户就是想不收了) |
  /// | 换一台服务器 | 清空 | **清空**(旧服务器的主题不能带过去) |
  /// | 自动重试次数用尽 | 清空 | **清空**(不会再恢复了) |
  final _desiredTopics = <String>{};

  /// `_desiredTopics` 属于哪台服务器;换目标时据此判断要不要丢弃。
  String? _subscriptionTarget;

  bool _wantConnected = false;

  /// 是否允许自动重连。
  ///
  /// 只在「连上过又掉线」时打开(见 `_listen`),这样**首次**连接失败(地址写错、
  /// daemon 没开)不会自己反复重试刷屏;而重连失败时还能继续排下一次,
  /// 直到 [maxAutoRetries] 用尽。
  bool _autoRetryEnabled = false;

  /// 连接请求代数。每次发起/断开都 +1，回来的旧请求发现代数变了就直接放弃，
  /// 免得「先连 A 又立刻改连 B」时 A 的迟到结果覆盖 B 的状态。
  int _generation = 0;

  @override
  ConnectionStatus build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      _retryTimer = null;
      final client = _client;
      _client = null;
      // 应用退出时别把 socket 留着
      unawaited(client?.close(reason: '应用退出'));
    });
    return const ConnectionStatus();
  }

  /// 期望订阅(只读快照),重连成功后会被逐条补订。
  Set<String> get desiredTopics => Set.unmodifiable(_desiredTopics);

  // ── 连接 ────────────────────────────────────────────────────────────────

  /// 用给定配置建立连接。成功则落盘并返回 `true`。
  Future<bool> connect(ConnectionSettings settings) async {
    _retryTimer?.cancel();
    _retryTimer = null;

    if (!settings.isConfigured) {
      state = ConnectionStatus(
        phase: ConnectionPhase.failed,
        error: '请先填写服务器地址',
        attempt: state.attempt + 1,
      );
      return false;
    }

    _wantConnected = true;
    final generation = ++_generation;
    await _teardown();

    // 已在连接同一目标就不重复发起(避免用户连点两次)
    if (state.isConnecting && state.target == settings.target) return false;

    // 换了服务器:旧的订阅意图不能带过去(主题名可能完全不同)
    if (_subscriptionTarget != null && _subscriptionTarget != settings.target) {
      _desiredTopics.clear();
    }
    _subscriptionTarget = settings.target;

    final attempt = state.attempt;
    state = ConnectionStatus(
      phase: ConnectionPhase.connecting,
      target: settings.target,
      attempt: attempt,
    );

    final transport = ref.read(daemonTransportFactoryProvider)();
    final client = DaemonClient(transport, settings.wsUri);

    try {
      final hello = await client.connect();
      if (generation != _generation) {
        // 期间用户改了目标或点了断开,这条结果作废
        await client.close(reason: '已被更新的连接请求取代');
        return false;
      }
      _client = client;
      _listen(client, settings);
      // 连上过 → 之后掉线就自动重连
      _autoRetryEnabled = true;
      // 新连接上的生效订阅从空开始,逐条补订成功后再计入
      state = ConnectionStatus(
        phase: ConnectionPhase.connected,
        target: settings.target,
        hello: hello,
        client: client,
      );
      // 连上了才落盘:半途输入或连不上的地址不该被记住
      await ref.read(persistedConnectionProvider.notifier).save(settings);
      // 掉线重连后恢复此前的订阅
      for (final topic in _desiredTopics) {
        unawaited(_subscribeNow(client, topic));
      }
      return true;
    } catch (error) {
      await client.close(reason: '连接失败');
      if (generation != _generation) return false;
      _client = null;
      if (!_wantConnected) return false;
      state = ConnectionStatus(
        phase: ConnectionPhase.failed,
        target: settings.target,
        error: describeConnectError(error, settings.target),
        attempt: attempt + 1,
      );
      // 重连失败也要接着排下一次,否则退避链第一步断掉、
      // 「最多重试 N 次」永远到不了。
      if (_autoRetryEnabled) _scheduleRetry(settings);
      return false;
    }
  }

  /// 启动时调用:有历史配置就直接连,没有则停在连接页。
  Future<bool> connectIfConfigured() async {
    final saved = ref.read(persistedConnectionProvider);
    if (saved == null) return false;
    if (state.isConnected || state.isConnecting) return false;
    return connect(saved);
  }

  /// 用户点「重试」:优先用编辑中的配置,其次用已保存的。
  Future<bool> retry() async {
    final settings = ref.read(connectionSettingsProvider);
    final fallback = ref.read(persistedConnectionProvider);
    final target = settings.isConfigured
        ? settings
        : (fallback ?? ConnectionSettings.empty);
    return connect(target);
  }

  /// 主动断开(保留配置,便于重连)。
  ///
  /// **订阅一并清掉**:用户点「断开」就是不想再收事件了,
  /// 何况服务端那侧的订阅已经随连接消失。
  Future<void> disconnect() async {
    _wantConnected = false;
    _autoRetryEnabled = false;
    // 代数 +1:正在途中的连接请求回来后会被丢弃
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _forgetSubscriptionIntent();
    final target = state.target;
    await _teardown();
    state = ConnectionStatus(phase: ConnectionPhase.idle, target: target);
  }

  /// 忘记这台服务器:断开、清存储、清空输入框。
  Future<void> forget() async {
    await disconnect();
    await ref.read(persistedConnectionProvider.notifier).clear();
    await ref
        .read(connectionSettingsProvider.notifier)
        .replace(ConnectionSettings.empty);
    state = const ConnectionStatus();
  }

  // ── 订阅 ────────────────────────────────────────────────────────────────

  /// 订阅主题。未连接时只登记意图,连上/重连后自动补订。
  Future<void> subscribe(String topic) async {
    final normalized = topic.trim();
    if (normalized.isEmpty) return;
    _desiredTopics.add(normalized);
    final client = _client;
    if (client == null || !client.isAlive) return;
    await _subscribeNow(client, normalized);
  }

  /// 取消订阅。
  Future<void> unsubscribe(String topic) async {
    _desiredTopics.remove(topic);
    _markActive(topic, active: false);
    final client = _client;
    if (client == null || !client.isAlive) return;
    try {
      await client.unsubscribe(topic);
    } on DaemonException {
      // 断开过程中的取消订阅失败无所谓
    }
  }

  /// 取消全部订阅(连接保留)。
  Future<void> unsubscribeAll() async {
    final topics = _desiredTopics.toList();
    _forgetSubscriptionIntent();
    // 生效集合也要清:它反映的是服务端那边的订阅,这边发完取消帧就没了
    if (state.subscriptions.isNotEmpty) {
      state = state.copyWith(subscriptions: const <String>{});
    }
    final client = _client;
    if (client == null || !client.isAlive) return;
    for (final topic in topics) {
      try {
        await client.unsubscribe(topic);
      } on DaemonException {
        // 同上
      }
    }
  }

  /// 真正发一次订阅,并把成功的记进「生效订阅」。
  Future<void> _subscribeNow(DaemonClient client, String topic) async {
    try {
      await client.subscribe(topic);
      _markActive(topic, active: true);
    } on DaemonException catch (e) {
      // 服务端拒绝(主题不存在 / 订阅数超限):不进"生效"集合,
      // 但保留意图 —— 下次重连还会再试一次。
      debugPrint('[connection] 订阅 `$topic` 失败: ${e.code} ${e.message}');
    }
  }

  /// 更新「生效订阅」集合。连接已经换了就别改状态了。
  void _markActive(String topic, {required bool active}) {
    if (!identical(state.client, _client)) return;
    final next = {...state.subscriptions};
    final changed = active ? next.add(topic) : next.remove(topic);
    if (!changed) return;
    state = state.copyWith(subscriptions: next);
  }

  void _forgetSubscriptionIntent() {
    _desiredTopics.clear();
    _subscriptionTarget = null;
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  /// 观察连接结束:若不是我们主动关的,就进入失败态并安排重连。
  void _listen(DaemonClient client, ConnectionSettings settings) {
    client.done.then((_) {
      if (!identical(_client, client)) return;
      _client = null;
      if (!_wantConnected) return;
      // 连接没了 → 生效订阅清空(服务端那侧同样已经没了);
      // 期望订阅保留,交给下面的自动重连去补。
      state = ConnectionStatus(
        phase: ConnectionPhase.failed,
        target: settings.target,
        error: client.disconnectReason ?? '与 ${settings.target} 的连接已断开',
        attempt: state.attempt + 1,
      );
      _scheduleRetry(settings);
    });
  }

  void _scheduleRetry(ConnectionSettings settings) {
    if (!_wantConnected || _retryTimer != null) return;
    if (state.attempt > maxAutoRetries) {
      // 放弃自动恢复:订阅意图留着只会误导 UI
      _autoRetryEnabled = false;
      if (_desiredTopics.isNotEmpty) {
        debugPrint(
          '[connection] 自动重连次数用尽,清空 ${_desiredTopics.length} 条订阅意图',
        );
        _forgetSubscriptionIntent();
      }
      state = state.copyWith(
        error: '${state.error}（已自动重试 $maxAutoRetries 次，可手动重试）',
      );
      return;
    }
    // 1s → 2s → 4s → 8s → 15s,退避但封顶
    final seconds = math.min(
      _baseRetryDelay.inSeconds * (1 << math.min(state.attempt - 1, 4)),
      _maxRetryDelay.inSeconds,
    );
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      unawaited(connect(settings));
    });
  }

  Future<void> _teardown() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    // 先让 _listen 里的 identical 判断失效,避免自己关连接触发"掉线重连"
    await client.close(reason: '切换连接');
  }
}

/// 把连接异常翻译成给用户看的一句话。
String describeConnectError(Object error, String target) {
  if (error is DaemonException) {
    if (error.isUnauthorized) return '访问令牌不正确';
    if (error.code == 'disconnected' || error.code == 'timeout') {
      return '无法连接到 $target，请确认 daemon 已启动且地址端口正确';
    }
    return error.message;
  }
  if (error is TimeoutException) {
    return '连接 $target 超时，请检查网络或 daemon 是否在运行';
  }
  if (error is WebSocketChannelException) {
    return '无法连接到 $target，请检查地址与端口，并确认 daemon 已启动';
  }
  return '连接 $target 失败：$error';
}

// ══════════════════════════════════════════════════════════════════════════
// 派生 Provider
// ══════════════════════════════════════════════════════════════════════════

/// 当前连接阶段
final connectionPhaseProvider = Provider<ConnectionPhase>(
  (ref) => ref.watch(connectionProvider.select((s) => s.phase)),
);

/// 是否已连接
final isConnectedProvider = Provider<bool>(
  (ref) => ref.watch(connectionPhaseProvider) == ConnectionPhase.connected,
);

/// 当前客户端(未连接时为 null)
final daemonClientProvider = Provider<DaemonClient?>(
  (ref) => ref.watch(connectionProvider.select((s) => s.client)),
);

/// **当前连接上真正生效**的订阅主题(未连接时是空集)。
///
/// 想知道"重连后会自动补订什么"请看
/// `ref.read(connectionProvider.notifier).desiredTopics`。
final subscriptionsProvider = Provider<Set<String>>(
  (ref) => ref.watch(connectionProvider.select((s) => s.subscriptions)),
);

/// 服务端自述信息(`core.info`)。
///
/// 连接变化(重连、断开)会导致本 Provider 重跑,所以主界面上的信息
/// 天然跟着连接走,不需要手动刷新。
final serverInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(daemonClientProvider);
  if (client == null) return const {};
  return client.callObject('core.info');
});
