import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart' hide Logger;
import 'package:logging/logging.dart';

import '../config/backup_store.dart';
import '../instance/instance_controller.dart';
import 'backup_manifest.dart';
import 'backup_service.dart';
import 'backup_target.dart';
import 'ftp_backup_target.dart';
import 'sftp_backup_target.dart';
import 'webdav_backup_target.dart';

final _log = Logger('BackupController');

/// 定时调度的检查间隔：每 10 分钟检查一次是否到备份时间。
const Duration _kScheduleCheckInterval = Duration(minutes: 10);

/// 备份功能的调度与状态管理控制器。
///
/// 全局单例，通过 [BackupScope] 注入 widget 树。在应用运行期间以
/// [Timer.periodic] 每 10 分钟检查是否到达备份间隔；启动时也检查一次，
/// 若上次备份距今超过间隔则补做。仅在应用前台运行时生效。
class BackupController extends ChangeNotifier {
  BackupController({required InstanceController instanceController})
      : _instanceController = instanceController,
        _service = BackupService(instanceController);

  final InstanceController _instanceController;
  final BackupService _service;
  Timer? _timer;

  // ── 状态 ──────────────────────────────────────────────────

  bool _isRunning = false;
  String _currentInstanceName = '';
  int _processedCount = 0;
  int _totalCount = 0;
  String? _lastError;
  BackupResult? _lastResult;
  int? _lastBackupTime;

  bool get isRunning => _isRunning;
  String get currentInstanceName => _currentInstanceName;
  int get processedCount => _processedCount;
  int get totalCount => _totalCount;
  String? get lastError => _lastError;
  BackupResult? get lastResult => _lastResult;
  int? get lastBackupTime => _lastBackupTime;

  // ── 配置缓存（供 UI 读取，避免每次 await）─────────────────

  bool _enabled = false;
  BackupMode _mode = BackupMode.full;
  int _intervalHours = 24;
  List<String> _selectedInstanceIds = [];
  bool _localEnabled = false;
  String? _localPath;
  bool _webdavEnabled = false;
  String _webdavUrl = '';
  String _webdavUsername = '';
  String _webdavPassword = '';
  String _webdavRemotePath = '/EdgeCube';
  bool _ftpEnabled = false;
  String _ftpHost = '';
  int _ftpPort = 21;
  String _ftpUsername = '';
  String _ftpPassword = '';
  String _ftpRemotePath = '/EdgeCube';
  String _ftpSecurityType = 'ftp';
  bool _sftpEnabled = false;
  String _sftpHost = '';
  int _sftpPort = 22;
  String _sftpUsername = '';
  String _sftpPassword = '';
  String _sftpRemotePath = '/EdgeCube';
  Map<String, String> _sftpTrustedHostKeys = {};
  int _retentionSets = 3;

  bool get enabled => _enabled;
  BackupMode get mode => _mode;
  int get intervalHours => _intervalHours;
  List<String> get selectedInstanceIds =>
      List.unmodifiable(_selectedInstanceIds);
  bool get localEnabled => _localEnabled;
  String? get localPath => _localPath;
  bool get webdavEnabled => _webdavEnabled;
  String get webdavUrl => _webdavUrl;
  String get webdavUsername => _webdavUsername;
  String get webdavRemotePath => _webdavRemotePath;
  bool get ftpEnabled => _ftpEnabled;
  String get ftpHost => _ftpHost;
  int get ftpPort => _ftpPort;
  String get ftpUsername => _ftpUsername;
  String get ftpRemotePath => _ftpRemotePath;
  String get ftpSecurityType => _ftpSecurityType;
  bool get sftpEnabled => _sftpEnabled;
  String get sftpHost => _sftpHost;
  int get sftpPort => _sftpPort;
  String get sftpUsername => _sftpUsername;
  String get sftpRemotePath => _sftpRemotePath;
  int get retentionSets => _retentionSets;

  // ── 初始化 ────────────────────────────────────────────────

  /// 加载配置并启动定时器。应在应用启动时调用一次。
  Future<void> init() async {
    await _loadConfig();
    _startTimer();
    // 启动时检查一次是否需要补做备份。
    _checkSchedule();
  }

  Future<void> _loadConfig() async {
    _enabled = await BackupStore.loadEnabled();
    _mode = await BackupStore.loadMode();
    _intervalHours = await BackupStore.loadIntervalHours();
    _selectedInstanceIds = await BackupStore.loadSelectedInstanceIds();
    _localEnabled = await BackupStore.loadLocalEnabled();
    _localPath = await BackupStore.loadLocalPath();
    _webdavEnabled = await BackupStore.loadWebdavEnabled();
    _webdavUrl = await BackupStore.loadWebdavUrl();
    _webdavUsername = await BackupStore.loadWebdavUsername();
    _webdavPassword = await BackupStore.loadWebdavPassword();
    _webdavRemotePath = await BackupStore.loadWebdavRemotePath();
    _ftpEnabled = await BackupStore.loadFtpEnabled();
    _ftpHost = await BackupStore.loadFtpHost();
    _ftpPort = await BackupStore.loadFtpPort();
    _ftpUsername = await BackupStore.loadFtpUsername();
    _ftpPassword = await BackupStore.loadFtpPassword();
    _ftpRemotePath = await BackupStore.loadFtpRemotePath();
    _ftpSecurityType = await BackupStore.loadFtpSecurityType();
    _sftpEnabled = await BackupStore.loadSftpEnabled();
    _sftpHost = await BackupStore.loadSftpHost();
    _sftpPort = await BackupStore.loadSftpPort();
    _sftpUsername = await BackupStore.loadSftpUsername();
    _sftpPassword = await BackupStore.loadSftpPassword();
    _sftpRemotePath = await BackupStore.loadSftpRemotePath();
    _sftpTrustedHostKeys = await BackupStore.loadSftpTrustedHostKeys();
    _retentionSets = await BackupStore.loadRetentionSets();
    _lastBackupTime = await BackupStore.loadLastBackupTime();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_enabled) {
      _timer = Timer.periodic(_kScheduleCheckInterval, (_) => _checkSchedule());
    }
  }

  // ── 调度 ──────────────────────────────────────────────────

  void _checkSchedule() {
    if (!_enabled || _isRunning) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastBackupTime ?? 0;
    final elapsed = now - last;
    final intervalMs = _intervalHours * 3600 * 1000;
    if (elapsed >= intervalMs) {
      runBackupNow();
    }
  }

  // ── 执行备份 ──────────────────────────────────────────────

  /// 立即执行一次备份。
  Future<BackupResult> runBackupNow() async {
    if (_isRunning) return _lastResult ?? const BackupResult();

    final targets = _buildTargets();
    if (targets.isEmpty) {
      _lastError = 'no_target';
      _lastResult = const BackupResult(error: 'no_target');
      notifyListeners();
      return _lastResult!;
    }

    _isRunning = true;
    _lastError = null;
    _processedCount = 0;
    _totalCount = 0;
    _currentInstanceName = '';
    notifyListeners();

    try {
      final result = await _service.runBackup(
        targets: targets,
        mode: _mode,
        retentionSets: _retentionSets,
        onInstanceProgress: (current, total, name) {
          _processedCount = current;
          _totalCount = total;
          _currentInstanceName = name;
          notifyListeners();
        },
      );
      _lastResult = result;
      if (result.error != null) {
        _lastError = result.error;
      } else if (result.failed > 0) {
        _lastError = 'partial_failed';
      }
      // 只要有至少一个实例成功备份，就更新时间。
      if (result.backed > 0 || result.error == null && result.failed == 0) {
        _lastBackupTime = DateTime.now().millisecondsSinceEpoch;
        await BackupStore.saveLastBackupTime(_lastBackupTime!);
      }
    } catch (e, s) {
      _log.severe('备份执行失败', e, s);
      _lastError = e.toString();
      _lastResult = BackupResult(error: e.toString());
    } finally {
      _isRunning = false;
      _currentInstanceName = '';
      notifyListeners();
    }

    return _lastResult!;
  }

  /// 根据当前配置构造已启用的备份目标列表。
  List<BackupTarget> _buildTargets() {
    final targets = <BackupTarget>[];
    if (_localEnabled && _localPath != null && _localPath!.isNotEmpty) {
      targets.add(LocalBackupTarget(_localPath!));
    }
    if (_webdavEnabled && _webdavUrl.isNotEmpty) {
      targets.add(WebDavBackupTarget(
        url: _webdavUrl,
        username: _webdavUsername,
        password: _webdavPassword,
        remotePath: _webdavRemotePath,
      ));
    }
    if (_ftpEnabled && _ftpHost.isNotEmpty) {
      targets.add(FtpBackupTarget(
        host: _ftpHost,
        port: _ftpPort,
        username: _ftpUsername,
        password: _ftpPassword,
        remotePath: _ftpRemotePath,
        securityType: _ftpSecurity,
      ));
    }
    if (_sftpEnabled && _sftpHost.isNotEmpty) {
      targets.add(SftpBackupTarget(
        host: _sftpHost,
        port: _sftpPort,
        username: _sftpUsername,
        password: _sftpPassword,
        remotePath: _sftpRemotePath,
        trustedHostKeys: _sftpTrustedHostKeys,
      ));
    }
    return targets;
  }

  /// 测试 WebDav 连接（供设置页「测试连接」按钮调用）。
  Future<bool> testWebdavConnection({
    required String url,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final target = WebDavBackupTarget(
      url: url,
      username: username,
      password: password,
      remotePath: remotePath,
    );
    return target.testConnection();
  }

  /// 测试 FTP 连接（供设置页「测试连接」按钮调用）。
  Future<bool> testFtpConnection({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
    String securityType = 'ftp',
  }) async {
    final target = FtpBackupTarget(
      host: host,
      port: port,
      username: username,
      password: password,
      remotePath: remotePath,
      securityType: _toFtpSecurity(securityType),
    );
    return target.testConnection();
  }

  /// 测试 SFTP 连接。首次遇到未信任主机密钥时调用 [onUnknownHostKey]，
  /// 由调用方决定是否信任并持久化。
  Future<bool> testSftpConnection({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remotePath,
    Future<bool> Function(String fingerprint)? onUnknownHostKey,
  }) async {
    final target = SftpBackupTarget(
      host: host,
      port: port,
      username: username,
      password: password,
      remotePath: remotePath,
      trustedHostKeys: _sftpTrustedHostKeys,
      onUnknownHostKey: onUnknownHostKey,
    );
    try {
      final ok = await target.testConnection();
      return ok;
    } finally {
      // 信任操作会更新 controller 缓存，这里刷新以防新写入的指纹丢失。
      if (onUnknownHostKey != null) {
        _sftpTrustedHostKeys = await BackupStore.loadSftpTrustedHostKeys();
      }
    }
  }

  /// 记录一条已信任的 SFTP 主机密钥指纹（首次信任）。
  Future<void> trustSftpHostKey(
    String host,
    int port,
    String fingerprint,
  ) async {
    _sftpTrustedHostKeys = {..._sftpTrustedHostKeys, '$host:$port': fingerprint};
    await BackupStore.saveSftpTrustedHostKeys(_sftpTrustedHostKeys);
    notifyListeners();
  }

  /// password 修改不触发清单失效。
  Future<String> loadFtpPassword() => BackupStore.loadFtpPassword();
  Future<String> loadSftpPassword() => BackupStore.loadSftpPassword();

  /// 将存储的安全类型字符串转换为 ftpconnect 的枚举。
  static SecurityType _toFtpSecurity(String type) {
    return switch (type) {
      'ftpes' => SecurityType.ftpes,
      'ftps' => SecurityType.ftps,
      _ => SecurityType.ftp,
    };
  }

  SecurityType get _ftpSecurity => _toFtpSecurity(_ftpSecurityType);

  // ── 配置变更 ──────────────────────────────────────────────

  /// 清空所有实例的清单文件，使下次备份强制为全量备份。
  ///
  /// 在备份目标（本地路径、WebDav 配置）变更后调用：新位置没有之前的
  /// 全量备份基底，必须重新建立全量基础。
  Future<void> _invalidateAllManifests() async {
    for (final instance in _instanceController.instances) {
      await BackupManifest.delete(instance.id);
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await BackupStore.saveEnabled(value);
    _startTimer();
    notifyListeners();
  }

  Future<void> setMode(BackupMode value) async {
    _mode = value;
    await BackupStore.saveMode(value);
    notifyListeners();
  }

  Future<void> setIntervalHours(int hours) async {
    _intervalHours = hours;
    await BackupStore.saveIntervalHours(hours);
    notifyListeners();
  }

  Future<void> setSelectedInstanceIds(List<String> ids) async {
    _selectedInstanceIds = List.of(ids);
    await BackupStore.saveSelectedInstanceIds(_selectedInstanceIds);
    notifyListeners();
  }

  Future<void> setLocalEnabled(bool value) async {
    _localEnabled = value;
    await BackupStore.saveLocalEnabled(value);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setLocalPath(String? path) async {
    _localPath = path;
    await BackupStore.saveLocalPath(path);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setWebdavEnabled(bool value) async {
    _webdavEnabled = value;
    await BackupStore.saveWebdavEnabled(value);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setWebdavUrl(String url) async {
    _webdavUrl = url;
    await BackupStore.saveWebdavUrl(url);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setWebdavUsername(String username) async {
    _webdavUsername = username;
    await BackupStore.saveWebdavUsername(username);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setWebdavPassword(String password) async {
    _webdavPassword = password;
    await BackupStore.saveWebdavPassword(password);
    await _invalidateAllManifests();
  }

  Future<String> loadWebdavPassword() => BackupStore.loadWebdavPassword();

  Future<void> setWebdavRemotePath(String path) async {
    _webdavRemotePath = path;
    await BackupStore.saveWebdavRemotePath(path);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setFtpEnabled(bool value) async {
    _ftpEnabled = value;
    await BackupStore.saveFtpEnabled(value);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setFtpHost(String host) async {
    _ftpHost = host;
    await BackupStore.saveFtpHost(host);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setFtpPort(int port) async {
    _ftpPort = port;
    await BackupStore.saveFtpPort(port);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setFtpUsername(String username) async {
    _ftpUsername = username;
    await BackupStore.saveFtpUsername(username);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setFtpPassword(String password) async {
    _ftpPassword = password;
    await BackupStore.saveFtpPassword(password);
    await _invalidateAllManifests();
  }

  Future<void> setFtpRemotePath(String path) async {
    _ftpRemotePath = path;
    await BackupStore.saveFtpRemotePath(path);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setFtpSecurityType(String type) async {
    _ftpSecurityType = type;
    await BackupStore.saveFtpSecurityType(type);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setSftpEnabled(bool value) async {
    _sftpEnabled = value;
    await BackupStore.saveSftpEnabled(value);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setSftpHost(String host) async {
    _sftpHost = host;
    await BackupStore.saveSftpHost(host);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setSftpPort(int port) async {
    _sftpPort = port;
    await BackupStore.saveSftpPort(port);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setSftpUsername(String username) async {
    _sftpUsername = username;
    await BackupStore.saveSftpUsername(username);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setSftpPassword(String password) async {
    _sftpPassword = password;
    await BackupStore.saveSftpPassword(password);
    await _invalidateAllManifests();
  }

  Future<void> setSftpRemotePath(String path) async {
    _sftpRemotePath = path;
    await BackupStore.saveSftpRemotePath(path);
    await _invalidateAllManifests();
    notifyListeners();
  }

  Future<void> setRetentionSets(int sets) async {
    _retentionSets = sets;
    await BackupStore.saveRetentionSets(sets);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
