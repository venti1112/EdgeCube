import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config_store.dart';

/// 备份模式。
enum BackupMode {
  /// 完整备份：每次打包整个实例目录。
  full,

  /// 增量备份：基于文件清单只打包变更文件。
  incremental;

  static BackupMode fromName(String? name) {
    return name == 'incremental' ? BackupMode.incremental : BackupMode.full;
  }

  String get name => switch (this) {
        BackupMode.full => 'full',
        BackupMode.incremental => 'incremental',
      };
}

/// 可选的调度间隔（小时）。
const List<int> kBackupIntervalOptions = [6, 12, 24, 48, 168];

/// 可选的保留组数。
const List<int> kBackupRetentionOptions = [1, 3, 5, 10];

/// 备份配置的本地持久化。
///
/// 存储于 `config/backup.json`，遵循 [ConfigStore] 的 read-modify-write 原子写入模式。
/// WebDav 密码单独存于 [FlutterSecureStorage]（Android Keystore），不写入明文 JSON。
class BackupStore {
  BackupStore._();

  static const String _fileName = 'backup.json';

  static const String _enabledKey = 'enabled';
  static const String _modeKey = 'mode';
  static const String _intervalKey = 'intervalHours';
  static const String _selectedKey = 'selectedInstanceIds';
  static const String _localEnabledKey = 'localEnabled';
  static const String _localPathKey = 'localPath';
  static const String _webdavEnabledKey = 'webdavEnabled';
  static const String _webdavUrlKey = 'webdavUrl';
  static const String _webdavUserKey = 'webdavUsername';
  static const String _webdavRemoteKey = 'webdavRemotePath';
  static const String _retentionKey = 'retentionSets';
  static const String _lastBackupKey = 'lastBackupTime';

  static const _storage = FlutterSecureStorage();
  static const _webdavPasswordKey = 'backup_webdav_password';

  // ── 总开关 ────────────────────────────────────────────────

  static Future<bool> loadEnabled() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_enabledKey];
    return raw is bool ? raw : false;
  }

  static Future<void> saveEnabled(bool value) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_enabledKey] = value;
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── 备份模式 ──────────────────────────────────────────────

  static Future<BackupMode> loadMode() async {
    final config = await ConfigStore.readConfig(_fileName);
    return BackupMode.fromName(config[_modeKey] as String?);
  }

  static Future<void> saveMode(BackupMode mode) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_modeKey] = mode.name;
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── 调度间隔 ──────────────────────────────────────────────

  static Future<int> loadIntervalHours() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_intervalKey];
    return raw is int ? raw : 24;
  }

  static Future<void> saveIntervalHours(int hours) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_intervalKey] = hours;
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── 勾选实例 ──────────────────────────────────────────────

  static Future<List<String>> loadSelectedInstanceIds() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_selectedKey];
    if (raw is! List) return [];
    return raw.whereType<String>().toList();
  }

  static Future<void> saveSelectedInstanceIds(List<String> ids) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_selectedKey] = ids;
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── 本地备份目标 ──────────────────────────────────────────

  static Future<bool> loadLocalEnabled() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_localEnabledKey];
    return raw is bool ? raw : false;
  }

  static Future<void> saveLocalEnabled(bool value) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_localEnabledKey] = value;
    await ConfigStore.writeConfig(_fileName, config);
  }

  static Future<String?> loadLocalPath() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_localPathKey];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  static Future<void> saveLocalPath(String? path) async {
    final config = await ConfigStore.readConfig(_fileName);
    if (path == null || path.isEmpty) {
      config.remove(_localPathKey);
    } else {
      config[_localPathKey] = path;
    }
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── WebDav 备份目标 ───────────────────────────────────────

  static Future<bool> loadWebdavEnabled() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_webdavEnabledKey];
    return raw is bool ? raw : false;
  }

  static Future<void> saveWebdavEnabled(bool value) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_webdavEnabledKey] = value;
    await ConfigStore.writeConfig(_fileName, config);
  }

  static Future<String> loadWebdavUrl() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_webdavUrlKey];
    return raw is String ? raw : '';
  }

  static Future<void> saveWebdavUrl(String url) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_webdavUrlKey] = url;
    await ConfigStore.writeConfig(_fileName, config);
  }

  static Future<String> loadWebdavUsername() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_webdavUserKey];
    return raw is String ? raw : '';
  }

  static Future<void> saveWebdavUsername(String username) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_webdavUserKey] = username;
    await ConfigStore.writeConfig(_fileName, config);
  }

  static Future<String> loadWebdavRemotePath() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_webdavRemoteKey];
    return raw is String && raw.isNotEmpty ? raw : '/EdgeCube';
  }

  static Future<void> saveWebdavRemotePath(String path) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_webdavRemoteKey] = path;
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── WebDav 密码（加密存储）────────────────────────────────

  static Future<String> loadWebdavPassword() async {
    final value = await _storage.read(key: _webdavPasswordKey);
    return value ?? '';
  }

  static Future<void> saveWebdavPassword(String password) async {
    await _storage.write(key: _webdavPasswordKey, value: password);
  }

  // ── 保留组数 ──────────────────────────────────────────────

  static Future<int> loadRetentionSets() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_retentionKey];
    return raw is int ? raw : 3;
  }

  static Future<void> saveRetentionSets(int sets) async {
    final config = await ConfigStore.readConfig(_fileName);
    config[_retentionKey] = sets;
    await ConfigStore.writeConfig(_fileName, config);
  }

  // ── 上次备份时间 ──────────────────────────────────────────

  static Future<int?> loadLastBackupTime() async {
    final config = await ConfigStore.readConfig(_fileName);
    final raw = config[_lastBackupKey];
    return raw is int ? raw : null;
  }

  static Future<void> saveLastBackupTime(int? millis) async {
    final config = await ConfigStore.readConfig(_fileName);
    if (millis == null) {
      config.remove(_lastBackupKey);
    } else {
      config[_lastBackupKey] = millis;
    }
    await ConfigStore.writeConfig(_fileName, config);
  }
}
