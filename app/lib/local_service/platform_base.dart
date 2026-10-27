import 'model.dart';

/// 本地服务的平台能力。
///
/// Flutter 层只知道这组动作,不知道底层是 proot、原生进程还是别的方式 ——
/// 换平台实现时 UI、状态机、持久化都不用改。
abstract class LocalServicePlatform {
  /// 当前平台/安装包是否具备启动本地服务的能力
  Future<bool> isSupported();

  /// 当前状态(应用重启后先读一次,不用等事件)
  Future<LocalServiceStatus> status();

  /// 请求启动。返回的是请求刚受理时的状态,后续进展走 [events]。
  Future<LocalServiceStatus> start();

  /// 请求停止。同样立即返回,完成与否看事件。
  Future<LocalServiceStatus> stop();

  /// 已有日志(用于重新挂上事件流时补历史)
  Future<List<String>> logs();

  Future<void> clearLogs();

  /// 状态与日志事件流
  Stream<LocalServiceEvent> get events;
}
