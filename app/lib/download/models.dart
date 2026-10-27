/// 下载任务的线上模型。
///
/// 字段名与 daemon 的**线上格式**一一对应（snake_case）。三个方法
/// （`download.add` / `download.status` / `download.list`）与两条事件主题
/// （`download.progress` / `download.state`）返回的**是同一个形状** ——
/// 所以这里一套模型就能同时吃快照与推送。
library;

/// 任务状态。
///
/// daemon 用的是小写字符串；认不出来的值一律当 [unknown]，页面不该因为
/// 「daemon 加了个状态」就崩。
enum DownloadState {
  queued,
  connecting,
  downloading,
  seeding,
  paused,

  /// 文件下完了，daemon 正在算 sha1（只有带 `sha1` 的任务会经过它，通常几百毫秒）。
  verifying,
  completed,
  error,

  /// 本端不认识的状态（daemon 升级了、本端没跟上）。
  unknown;

  static DownloadState parse(Object? raw) => switch (raw) {
    'queued' => DownloadState.queued,
    'connecting' => DownloadState.connecting,
    'downloading' => DownloadState.downloading,
    'seeding' => DownloadState.seeding,
    'paused' => DownloadState.paused,
    'verifying' => DownloadState.verifying,
    'completed' => DownloadState.completed,
    'error' => DownloadState.error,
    _ => DownloadState.unknown,
  };

  /// 还在路上（含排队与校验中）—— 进度条该转着。
  bool get isActive => switch (this) {
    DownloadState.queued ||
    DownloadState.connecting ||
    DownloadState.downloading ||
    DownloadState.seeding ||
    DownloadState.paused ||
    DownloadState.verifying => true,
    _ => false,
  };

  /// 已经有结论了（成功或失败）。
  bool get isFinished =>
      this == DownloadState.completed || this == DownloadState.error;
}

/// 任务的校验值。`algorithm` 的取值就是 `download.add` 的参数名。
class DownloadChecksum {
  const DownloadChecksum({required this.algorithm, required this.value});

  final String algorithm;
  final String value;

  static DownloadChecksum? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final algorithm = raw['algorithm'];
    final value = raw['value'];
    if (algorithm is! String || value is! String) return null;
    return DownloadChecksum(algorithm: algorithm, value: value);
  }

  /// 展示用的大写名字（`sha256` → `SHA256`）。
  String get label => algorithm.toUpperCase();
}

/// 失败原因。daemon 只在 `state = error` 时给。
class DownloadFailure {
  const DownloadFailure({
    required this.kind,
    required this.message,
    required this.retryable,
  });

  /// 稳定的机器可读分类（如 `checksum_mismatch`、`network`）。
  final String kind;
  final String message;

  /// daemon 认为「重试可能有救」（网络类通常是 true）。
  final bool retryable;

  static DownloadFailure? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return DownloadFailure(
      kind: raw['kind']?.toString() ?? '',
      message: raw['message']?.toString() ?? '',
      retryable: raw['retryable'] == true,
    );
  }

  /// sha1 对不上（daemon 已经把文件删掉了）。
  bool get isChecksumMismatch => kind == 'checksum_mismatch';
}

/// 一个下载任务。
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.state,
    this.instanceId,
    this.path,
    this.filename,
    this.target,
    this.url,
    this.totalSize,
    this.completedSize = 0,
    this.downloadSpeed = 0,
    this.etaSeconds,
    this.connections = 0,
    this.progressPercent = 0,
    this.checksum,
    this.createdAtMs,
    this.finishedAtMs,
    this.error,
  });

  /// 完整 UUID（daemon 用的是 gosh-dl 的 `DownloadId`，**不是** 16 位 GID）。
  final String id;
  final DownloadState state;

  /// 任务归属的实例（列表里按它分组用得上）。
  final String? instanceId;

  /// 相对实例根目录的目录（`""` 表示实例根）。
  final String? path;

  /// 文件名。
  final String? filename;

  /// 展示用：相对实例根目录的完整路径（`path` + `filename`）。
  final String? target;

  final String? url;

  /// 总字节数。**可能是 null**：引擎的进度回调只在读到数据时触发，
  /// 而且同一连接内最快 250ms 一次 —— 刚开始下那几帧还没有这个值。
  /// 为空时进度条要画「不确定」那种。
  final int? totalSize;

  final int completedSize;
  final int downloadSpeed;
  final int? etaSeconds;
  final int connections;
  final double progressPercent;

  final DownloadChecksum? checksum;
  final int? createdAtMs;
  final int? finishedAtMs;
  final DownloadFailure? error;

  /// 有总大小才画得出确定进度。
  bool get hasTotal => totalSize != null && totalSize! > 0;

  /// 0..1 的完成度；不知道总大小时为 `null`。
  double? get fraction =>
      hasTotal ? (completedSize / totalSize!).clamp(0.0, 1.0) : null;

  /// 剩下的时间（秒）。daemon 那边是按瞬时速度估的，别当承诺。
  Duration? get eta =>
      etaSeconds == null ? null : Duration(seconds: etaSeconds!);

  static DownloadTask fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id']?.toString() ?? '',
      state: DownloadState.parse(json['state']),
      instanceId: json['instance_id']?.toString(),
      path: json['path']?.toString(),
      filename: json['filename']?.toString(),
      target: json['target']?.toString(),
      url: json['url']?.toString(),
      totalSize: _int(json['total_size']),
      completedSize: _int(json['completed_size']) ?? 0,
      downloadSpeed: _int(json['download_speed']) ?? 0,
      etaSeconds: _int(json['eta_seconds']),
      connections: _int(json['connections']) ?? 0,
      progressPercent: _double(json['progress_percent']) ?? 0,
      checksum: DownloadChecksum.fromJson(json['checksum']),
      createdAtMs: _int(json['created_at_ms']),
      finishedAtMs: _int(json['finished_at_ms']),
      error: DownloadFailure.fromJson(json['error']),
    );
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  static double? _double(Object? raw) {
    if (raw is num) return raw.toDouble();
    return null;
  }
}

/// 任务列表 + 汇总速率。
class DownloadList {
  const DownloadList({required this.tasks, this.downloadSpeed = 0});

  final List<DownloadTask> tasks;
  final int downloadSpeed;

  static const DownloadList empty = DownloadList(tasks: []);

  DownloadTask? byId(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  static DownloadList fromJson(Map<String, dynamic> json) {
    final raw = json['tasks'];
    final tasks = <DownloadTask>[
      if (raw is List)
        for (final item in raw)
          if (item is Map) DownloadTask.fromJson(item.cast<String, dynamic>()),
    ];
    final stats = json['stats'];
    final speed = stats is Map ? DownloadTask._int(stats['download_speed']) : null;
    return DownloadList(tasks: tasks, downloadSpeed: speed ?? 0);
  }
}
