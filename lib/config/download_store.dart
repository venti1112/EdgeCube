import 'config_store.dart';

/// 下载引擎参数的本地持久化（存于 `config/download.json`）。
///
/// 这些参数在 [DownloadEngine] 初始化时读取并注入 downloadx 管理器。
/// 其中 maxParallel/targetChunkCount/minChunkSize/speedLimit 支持运行时修改
/// （经 DownloadEngine.applyXxx 转发 downloadx 的 setXxx 即时生效）；
/// requestTimeout 仅在管理器构造时生效，修改后需重启应用。
class DownloadStore {
  DownloadStore._();

  static const String _fileName = 'download.json';
  static const String _maxParallelKey = 'maxParallel';
  static const String _targetChunkCountKey = 'targetChunkCount';
  static const String _minChunkSizeKey = 'minChunkSize';
  static const String _requestTimeoutKey = 'requestTimeout';
  static const String _speedLimitKey = 'speedLimit';

  static const int defaultMaxParallel = 8;
  static const int defaultTargetChunkCount = 4;
  static const int defaultMinChunkSize = 1024 * 1024; // 1 MiB
  static const int defaultRequestTimeout = 30000; // ms
  static const int defaultSpeedLimit = 0; // 0 = 不限速

  static Future<int> loadMaxParallel() async {
    final m = await ConfigStore.readConfig(_fileName);
    final v = m[_maxParallelKey];
    return v is int && v >= 1 ? v : defaultMaxParallel;
  }

  static Future<void> saveMaxParallel(int value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_maxParallelKey] = value < 1 ? 1 : value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<int> loadTargetChunkCount() async {
    final m = await ConfigStore.readConfig(_fileName);
    final v = m[_targetChunkCountKey];
    return v is int && v >= 1 ? v : defaultTargetChunkCount;
  }

  static Future<void> saveTargetChunkCount(int value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_targetChunkCountKey] = value < 1 ? 1 : value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<int> loadMinChunkSize() async {
    final m = await ConfigStore.readConfig(_fileName);
    final v = m[_minChunkSizeKey];
    return v is int && v >= 1 ? v : defaultMinChunkSize;
  }

  static Future<void> saveMinChunkSize(int bytes) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_minChunkSizeKey] = bytes < 1 ? 1 : bytes;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<int> loadRequestTimeout() async {
    final m = await ConfigStore.readConfig(_fileName);
    final v = m[_requestTimeoutKey];
    return v is int && v >= 1000 ? v : defaultRequestTimeout;
  }

  static Future<void> saveRequestTimeout(int ms) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_requestTimeoutKey] = ms < 1000 ? 1000 : ms;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<int> loadSpeedLimit() async {
    final m = await ConfigStore.readConfig(_fileName);
    final v = m[_speedLimitKey];
    return v is int && v >= 0 ? v : defaultSpeedLimit;
  }

  static Future<void> saveSpeedLimit(int bytesPerSec) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_speedLimitKey] = bytesPerSec < 0 ? 0 : bytesPerSec;
    await ConfigStore.writeConfig(_fileName, m);
  }
}
