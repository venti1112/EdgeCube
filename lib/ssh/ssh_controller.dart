import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ssh_store.dart';
import 'ssh_service.dart';

/// SSH 服务的全局生命周期管理器。
///
/// 持有当前 SSH 运行状态与配置，负责：
/// - 按 SFTP / SSH 终端两个开关启停服务（任一启用即运行，全部关闭则停止）；
/// - 当实例切换或配置变更导致根目录/配置变化时自动重启 SSH 服务。
///
/// 由 [main] 创建并注入 [InstanceController] 的变化监听，在实例切换后自动以新实例目录
/// 作为根目录重启 SSH 服务（若之前正在运行）。SFTP 与 SSH 终端共用同一端口、账号与主机密钥。
class SshController extends ChangeNotifier {
  SshController();

  SshConfig _config = const SshConfig();
  bool _running = false;
  String? _rootDir;

  /// 当前 SSH 配置。
  SshConfig get config => _config;

  /// SSH 服务是否正在运行。
  bool get isRunning => _running;

  /// 当前根目录（SFTP 根目录与 SSH 终端初始工作目录）。
  String? get rootDir => _rootDir;

  /// 初始化：加载持久化配置与运行状态。若上次退出时服务仍开启，则自动恢复。
  Future<void> init() async {
    _config = await SshStore.load();
    _running = await SshService.isRunning();
    notifyListeners();
  }

  /// 设置当前根目录（通常为当前选中实例的工作目录）。
  /// 若服务正在运行且目录发生变化，则自动重启以应用新根目录。
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

  /// 切换 SFTP 文件访问开关。
  Future<void> setSftpEnabled(bool value) async {
    if (value == _config.sftpEnabled) return;
    _config = _config.copyWith(sftpEnabled: value);
    await SshStore.save(_config);
    await _reconcile();
    notifyListeners();
  }

  /// 切换 SSH 终端开关。
  Future<void> setShellEnabled(bool value) async {
    if (value == _config.shellEnabled) return;
    _config = _config.copyWith(shellEnabled: value);
    await SshStore.save(_config);
    await _reconcile();
    notifyListeners();
  }

  /// 应用新配置（端口/账号/写入/IPv6 等）。若服务正在运行则以新配置重启。
  Future<void> applyConfig(SshConfig config) async {
    _config = config;
    await SshStore.save(_config);
    await _reconcile();
    notifyListeners();
  }

  /// 依据当前配置与根目录，校正 native 服务的运行状态：
  /// 满足启动条件（有根目录、已设账号、至少启用一项能力）时启动；正在运行时先停后启以应用变更；
  /// 否则停止。native 服务为一次性启动，配置/开关变化都需重启才能生效。
  Future<void> _reconcile() async {
    final shouldRun =
        _rootDir != null &&
        _config.hasCredentials &&
        (_config.sftpEnabled || _config.shellEnabled);
    if (shouldRun) {
      if (_running) {
        await _stopInternal();
      }
      await _startInternal();
    } else if (_running) {
      await _stopInternal();
    }
  }

  Future<void> _startInternal() async {
    final dir = _rootDir;
    if (dir == null) return;
    if (!_config.hasCredentials) return;
    if (!_config.sftpEnabled && !_config.shellEnabled) return;
    await SshService.start(
      rootDir: dir,
      port: _config.port,
      username: _config.username,
      password: _config.password,
      writable: _config.writable,
      sftpEnabled: _config.sftpEnabled,
      shellEnabled: _config.shellEnabled,
      ipv6: _config.ipv6Enabled,
    );
    _running = true;
  }

  Future<void> _stopInternal() async {
    await SshService.stop();
    _running = false;
  }
}
