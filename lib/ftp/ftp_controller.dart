import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ftp_store.dart';
import 'ftp_service.dart';

/// FTP 服务的全局生命周期管理器。
///
/// 持有当前 FTP 运行状态与配置，负责：
/// - 启动/停止 FTP 服务（基于传入的根目录）；
/// - 当实例切换或配置变更导致根目录/配置变化时自动重启 FTP。
///
/// 由 [main] 创建并注入 [InstanceController] 的变化监听，
/// 在实例切换后自动以新实例目录作为根目录重启 FTP（若之前正在运行）。
class FtpController extends ChangeNotifier {
  FtpController();

  FtpConfig _config = const FtpConfig();
  bool _running = false;
  String? _rootDir;

  /// 当前 FTP 配置。
  FtpConfig get config => _config;

  /// FTP 服务是否正在运行。
  bool get isRunning => _running;

  /// 当前 FTP 根目录。
  String? get rootDir => _rootDir;

  /// 初始化：加载持久化配置与运行状态。若上次退出时 FTP 仍开启，则自动恢复。
  Future<void> init() async {
    _config = await FtpStore.load();
    _running = await FtpService.isRunning();
    notifyListeners();
  }

  /// 设置当前 FTP 根目录（通常为当前选中实例的工作目录）。
  /// 若 FTP 正在运行且目录发生变化，则自动重启以应用新根目录。
  Future<void> setRootDir(String? dir) async {
    if (dir == _rootDir) return;
    final wasRunning = _running;
    if (wasRunning) {
      await _stopInternal();
    }
    _rootDir = dir;
    if (wasRunning) {
      await _startInternal();
    }
    notifyListeners();
  }

  /// 开启/关闭 FTP 服务。
  Future<void> setEnabled(bool value) async {
    if (value == _running) return;
    if (value) {
      await _startInternal();
    } else {
      await _stopInternal();
    }
    _config = _config.copyWith(enabled: value);
    await FtpStore.save(_config);
    notifyListeners();
  }

  /// 应用新配置。若 FTP 正在运行则以新配置重启。
  Future<void> applyConfig(FtpConfig config) async {
    final wasRunning = _running;
    if (wasRunning) {
      await _stopInternal();
    }
    _config = config;
    await FtpStore.save(_config);
    if (wasRunning) {
      await _startInternal();
    }
    notifyListeners();
  }

  Future<void> _startInternal() async {
    final dir = _rootDir;
    if (dir == null) return;
    await FtpService.start(
      rootDir: dir,
      port: _config.port,
      username: _config.username,
      password: _config.password,
      writable: _config.writable,
    );
    _running = true;
  }

  Future<void> _stopInternal() async {
    await FtpService.stop();
    _running = false;
  }
}
