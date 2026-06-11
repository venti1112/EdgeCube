import 'dart:async';

import 'package:flutter/foundation.dart';

import 'system_monitor_service.dart';

/// 定时轮询 [SystemMonitorService]，把最新系统状态暴露给 UI 层。
///
/// 全局单例，通过 [SystemMonitorScope] 注入 widget 树。默认每 2 秒刷新一次。
class SystemMonitorController extends ChangeNotifier {
  SystemMonitorController({
    SystemMonitorService? service,
    this._interval = const Duration(seconds: 2),
  }) : _service = service ?? SystemMonitorService() {
    _startPolling();
  }

  final SystemMonitorService _service;
  final Duration _interval;
  Timer? _timer;

  SystemInfo _info = const SystemInfo(
    totalMemMb: 0,
    usedMemMb: 0,
    availMemMb: 0,
    cpuUsage: -1,
    serverMemMb: null,
  );

  SystemInfo get info => _info;

  void _startPolling() {
    // 立即取一次，然后按 interval 轮询。
    _fetch();
    _timer = Timer.periodic(_interval, (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      final snapshot = await _service.getSystemInfo();
      _info = snapshot;
      notifyListeners();
    } catch (_) {
      // 通道调用失败时保持上次的值，不触发重建。
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
