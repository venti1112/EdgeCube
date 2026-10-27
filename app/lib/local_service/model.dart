import '../connection/settings.dart';

/// 本地服务所处的阶段。字符串与各平台实现一一对应,没认识的按「已停止」处理。
///
/// 这套模型是**平台无关**的:Android 目前用 proot 跑 daemon,
/// 以后桌面端换成原生进程,状态与事件仍然走同一套值。
enum LocalServicePhase {
  stopped,
  preparing,
  starting,
  running,
  stopping,
  failed,
}

LocalServicePhase localServicePhaseFrom(Object? raw) => switch (raw) {
  'preparing' => LocalServicePhase.preparing,
  'starting' => LocalServicePhase.starting,
  'running' => LocalServicePhase.running,
  'stopping' => LocalServicePhase.stopping,
  'failed' => LocalServicePhase.failed,
  _ => LocalServicePhase.stopped,
};

/// 本地服务状态快照。
///
/// 只有 [LocalServicePhase.running] 时 [host]/[port]/[token] 才有意义 ——
/// 端口是 daemon 启动后回报的(本地模式用 `--port 0`,不写死)。
class LocalServiceStatus {
  const LocalServiceStatus({
    this.phase = LocalServicePhase.stopped,
    this.message,
    this.host,
    this.port,
    this.wsPath,
    this.token,
    this.pid,
    this.version,
    this.rootfsVersion,
    this.prepared = false,
  });

  final LocalServicePhase phase;

  /// 给人看的一句话,准备/失败阶段尤其重要
  final String? message;

  /// 运行中的 daemon 地址(目前恒为 127.0.0.1)
  final String? host;
  final int? port;
  final String? wsPath;

  /// daemon 本次启动随机生成的访问令牌
  final String? token;

  final int? pid;

  /// daemon 自述版本
  final String? version;

  /// 已解压的本地环境版本(未解压时为空)
  final String? rootfsVersion;

  /// 本地环境是否已准备完成
  final bool prepared;

  bool get isRunning => phase == LocalServicePhase.running;

  /// 正在准备 / 启动 / 停止 —— 这几步都要转圈
  bool get isBusy =>
      phase == LocalServicePhase.preparing ||
      phase == LocalServicePhase.starting ||
      phase == LocalServicePhase.stopping;

  /// 从启动到停止之间的所有阶段(失败/已停止之外)
  bool get isActive =>
      isRunning ||
      phase == LocalServicePhase.preparing ||
      phase == LocalServicePhase.starting ||
      phase == LocalServicePhase.stopping;

  /// 运行中时的连接配置,其余阶段为 null。
  ConnectionSettings? get connection {
    final host = this.host;
    final port = this.port;
    if (!isRunning || host == null || port == null) return null;
    return ConnectionSettings(host: host, port: port, token: token ?? '');
  }

  factory LocalServiceStatus.fromMap(Map<Object?, Object?> raw) =>
      LocalServiceStatus(
        phase: localServicePhaseFrom(raw['state']),
        message: _string(raw['message']),
        host: _string(raw['host']),
        port: _int(raw['port']),
        wsPath: _string(raw['wsPath']),
        token: _string(raw['token']),
        pid: _int(raw['pid']),
        version: _string(raw['version']),
        rootfsVersion: _string(raw['rootfsVersion']),
        prepared: raw['prepared'] == true,
      );

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int? _int(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : null);

  @override
  bool operator ==(Object other) =>
      other is LocalServiceStatus &&
      other.phase == phase &&
      other.message == message &&
      other.host == host &&
      other.port == port &&
      other.wsPath == wsPath &&
      other.token == token &&
      other.pid == pid &&
      other.version == version &&
      other.rootfsVersion == rootfsVersion &&
      other.prepared == prepared;

  @override
  int get hashCode => Object.hash(
    phase,
    message,
    host,
    port,
    wsPath,
    token,
    pid,
    version,
    rootfsVersion,
    prepared,
  );

  @override
  String toString() => 'LocalServiceStatus(${phase.name}, $host:$port)';
}

/// 平台实现推送的事件:状态变化或一行日志。
sealed class LocalServiceEvent {
  const LocalServiceEvent();
}

class LocalServiceStatusEvent extends LocalServiceEvent {
  const LocalServiceStatusEvent(this.status);

  final LocalServiceStatus status;
}

class LocalServiceLogEvent extends LocalServiceEvent {
  const LocalServiceLogEvent(this.line);

  final String line;
}

/// 把通道里的事件解析成模型;不认识的返回 null。
LocalServiceEvent? localServiceEventFrom(Object? raw) {
  if (raw is! Map) return null;
  return switch (raw['type']) {
    'status' => LocalServiceStatusEvent(LocalServiceStatus.fromMap(raw)),
    'log' => LocalServiceLogEvent(raw['line'] as String? ?? ''),
    _ => null,
  };
}
