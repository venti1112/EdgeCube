import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/log_store.dart';

/// 日志文件保留天数；超过此天数的日志文件在 [init] 时自动删除。
const int kLogRetentionDays = 7;

/// 日志文件名前缀，完整格式为 `log_YYYY-MM-DD.txt`。
const String _kLogFilePrefix = 'log_';
const String _kLogFileSuffix = '.txt';

/// 应用软件日志服务（单例）。
///
/// 基于 [logging](https://pub.dev/packages/logging) 包，将日志同时输出到：
/// - **文件**：`<documents>/logs/log_YYYY-MM-DD.txt`，按日期轮转。
/// - **Android logcat**：通过 `dart:developer` log()，在 Android 上自动输出。
///
/// 日志开关与等级由 [LogStore] 持久化，默认关闭。在 [main] 中调用 [init]
/// 完成初始化；设置页面通过 [setEnabled] / [setLevel] 运行时切换。
///
/// 使用方式：
/// ```dart
/// final log = Logger('ServerController');
/// log.info('Server started on port 25565');
/// log.warning('Memory low');
/// log.severe('Failed to start', error);
/// ```
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  bool _enabled = false;
  Level _level = Level.INFO;
  StreamSubscription<LogRecord>? _subscription;
  IOSink? _sink;
  String? _currentDate; // YYYY-MM-DD
  Directory? _logDir;

  /// 初始化：读取设置、应用配置、清理过期日志。
  ///
  /// 在 `main()` 中 `WidgetsFlutterBinding.ensureInitialized()` 之后调用。
  Future<void> init() async {
    _enabled = await LogStore.loadEnabled();
    _level = await LogStore.loadLevel();
    _applyConfig();
    await _cleanOldLogs();
  }

  /// 当前日志是否已启用。
  bool get isEnabled => _enabled;

  /// 当前日志等级。
  Level get level => _level;

  /// 运行时切换日志开关，同时持久化并立即生效。
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await LogStore.saveEnabled(value);
    _applyConfig();
  }

  /// 运行时切换日志等级，同时持久化并立即生效。
  Future<void> setLevel(Level value) async {
    _level = value;
    await LogStore.saveLevel(value);
    if (_enabled) {
      Logger.root.level = value;
    }
  }

  // ── 内部：配置应用 ──────────────────────────────────────────

  void _applyConfig() {
    if (_enabled) {
      Logger.root.level = _level;
      _subscription ??= Logger.root.onRecord.listen(_onRecord);
    } else {
      Logger.root.level = Level.OFF;
      _subscription?.cancel();
      _subscription = null;
      _closeSink();
    }
  }

  // ── 内部：日志记录处理 ──────────────────────────────────────

  void _onRecord(LogRecord r) {
    // 输出到 Android logcat（dart:developer 在 Android 上自动写入 logcat）
    developer.log(
      r.message,
      name: r.loggerName,
      level: r.level.value,
      error: r.error,
      stackTrace: r.stackTrace,
      time: r.time,
    );
    // 写入文件（异步，不阻塞调用方）
    _writeLine(_formatLine(r));
  }

  /// 格式化一条日志记录为单行文本。
  static String _formatLine(LogRecord r) {
    final buf = StringBuffer()
      ..write(_formatTime(r.time))
      ..write(' [')
      ..write(r.level.name)
      ..write('] [')
      ..write(r.loggerName)
      ..write('] ')
      ..write(r.message);
    if (r.error != null) {
      buf.write(' :: ');
      buf.write(r.error);
    }
    if (r.stackTrace != null) {
      buf.write('\n');
      buf.write(r.stackTrace);
    }
    return buf.toString();
  }

  /// 将一行日志写入当天文件；日期变化时自动轮转。
  Future<void> _writeLine(String line) async {
    try {
      final today = _todayKey();
      if (_currentDate != today) {
        _closeSink();
        _currentDate = today;
        final file = await _fileForDate(today);
        _sink = file.openWrite(mode: FileMode.append);
      }
      _sink?.writeln(line);
      await _sink?.flush();
    } catch (_) {
      // 日志写入失败不应影响应用正常运行
    }
  }

  void _closeSink() {
    _sink?.flush().then((_) => _sink?.close());
    _sink = null;
    _currentDate = null;
  }

  // ── 内部：日期与文件路径 ────────────────────────────────────

  /// 当天日期键，格式 `YYYY-MM-DD`。
  static String _todayKey() => _dateKey(DateTime.now());

  static String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 格式化时间戳为 `YYYY-MM-DD HH:mm:ss.SSS`。
  static String _formatTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $h:$min:$s.$ms';
  }

  /// 日志文件目录 `<documents>/logs/`，不存在时自动创建。
  Future<Directory> _logDirectory() async {
    if (_logDir != null) return _logDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _logDir = dir;
    return dir;
  }

  /// 获取指定日期的日志文件。
  Future<File> _fileForDate(String dateKey) async {
    final dir = await _logDirectory();
    return File(p.join(dir.path, '$_kLogFilePrefix$dateKey$_kLogFileSuffix'));
  }

  /// 从日志文件名中提取日期键，如 `log_2026-08-01.txt` → `2026-08-01`。
  static String? _dateKeyFromFileName(String name) {
    if (!name.startsWith(_kLogFilePrefix) || !name.endsWith(_kLogFileSuffix)) {
      return null;
    }
    return name.substring(
      _kLogFilePrefix.length,
      name.length - _kLogFileSuffix.length,
    );
  }

  // ── 内部：清理过期日志 ──────────────────────────────────────

  /// 删除超过 [kLogRetentionDays] 天的日志文件。
  Future<void> _cleanOldLogs() async {
    try {
      final dir = await _logDirectory();
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(
        const Duration(days: kLogRetentionDays),
      );
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final dateKey = _dateKeyFromFileName(p.basename(entity.path));
        if (dateKey == null) continue;
        final dt = DateTime.tryParse(dateKey);
        if (dt == null) continue;
        if (dt.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day))) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 清理失败不影响应用运行
    }
  }

  // ── 公开：查询 / 读取 / 导出 / 清除 ─────────────────────────

  /// 列出所有日志文件，按日期倒序排列（最新在前）。
  Future<List<File>> getLogFiles() async {
    final dir = await _logDirectory();
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith(_kLogFilePrefix) &&
            name.endsWith(_kLogFileSuffix)) {
          files.add(entity);
        }
      }
    }
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  /// 读取指定日志文件的完整内容。
  Future<String> readLogFile(File file) async {
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// 清除所有日志文件。关闭当前写入流后删除目录下全部日志文件。
  Future<void> clearAllLogs() async {
    _closeSink();
    final dir = await _logDirectory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith(_kLogFilePrefix) &&
            name.endsWith(_kLogFileSuffix)) {
          await entity.delete();
        }
      }
    }
  }
}
