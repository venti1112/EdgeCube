import 'model.dart';
import 'platform_base.dart';

/// 不支持本地服务的平台(Web,以及尚未接入原生进程的桌面端)。
///
/// 所有动作都是无害的空操作,UI 会根据 [isSupported] 隐藏入口。
class UnsupportedLocalServicePlatform implements LocalServicePlatform {
  const UnsupportedLocalServicePlatform();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<LocalServiceStatus> status() async => const LocalServiceStatus();

  @override
  Future<LocalServiceStatus> start() async => const LocalServiceStatus();

  @override
  Future<LocalServiceStatus> stop() async => const LocalServiceStatus();

  @override
  Future<List<String>> logs() async => const <String>[];

  @override
  Future<void> clearLogs() async {}

  @override
  Stream<LocalServiceEvent> get events => const Stream.empty();
}

LocalServicePlatform createLocalServicePlatform() =>
    const UnsupportedLocalServicePlatform();
