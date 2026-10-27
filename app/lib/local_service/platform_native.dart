import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'model.dart';
import 'platform_base.dart';
import 'platform_stub.dart';

/// Android 端实现:MethodChannel 发动作,EventChannel 收状态与日志。
///
/// 通道名与 `localservice/LocalServiceChannel.kt` 保持一致。
/// 底层用 proot 是 Android 侧的实现细节,这里只协议通信。
class AndroidLocalServicePlatform implements LocalServicePlatform {
  static const _methodChannel = MethodChannel(
    'com.venti1112.edgecube/local_service',
  );
  static const _eventChannel = EventChannel(
    'com.venti1112.edgecube/local_service_events',
  );

  late final Stream<LocalServiceEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map(localServiceEventFrom)
      .where((event) => event != null)
      .cast<LocalServiceEvent>();

  @override
  Stream<LocalServiceEvent> get events => _events;

  @override
  Future<bool> isSupported() async =>
      await _methodChannel.invokeMethod<bool>('isSupported') ?? false;

  @override
  Future<LocalServiceStatus> status() async => _toStatus(
    await _methodChannel.invokeMapMethod<String, Object?>('status'),
  );

  @override
  Future<LocalServiceStatus> start() async =>
      _toStatus(await _methodChannel.invokeMapMethod<String, Object?>('start'));

  @override
  Future<LocalServiceStatus> stop() async =>
      _toStatus(await _methodChannel.invokeMapMethod<String, Object?>('stop'));

  @override
  Future<List<String>> logs() async =>
      await _methodChannel.invokeListMethod<String>('logs') ?? const <String>[];

  @override
  Future<void> clearLogs() => _methodChannel.invokeMethod<void>('clearLogs');

  LocalServiceStatus _toStatus(Map<String, Object?>? raw) =>
      LocalServiceStatus.fromMap(raw ?? const <String, Object?>{});
}

LocalServicePlatform createLocalServicePlatform() {
  if (Platform.isAndroid) return AndroidLocalServicePlatform();
  // 桌面端后续接入原生进程时在这里分流
  return const UnsupportedLocalServicePlatform();
}
