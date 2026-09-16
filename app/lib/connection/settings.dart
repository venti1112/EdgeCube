import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/base.dart';

/// 连接配置:一台 daemon 的地址与访问令牌。
///
/// 这是一份**值对象**:相等性按三个字段比较,便于 Provider 判断"没变就不重建"。
class ConnectionSettings {
  const ConnectionSettings({
    this.host = '',
    this.port = defaultPort,
    this.token = '',
  });

  /// 存储键。整份配置存一个 key 的 JSON,不拆成多个 key。
  static const storageKey = 'connection';

  /// daemon 默认端口(与 `daemon/config.example.toml` 的 server.port 一致)
  static const defaultPort = 8787;
  static const portMin = 1;
  static const portMax = 65535;

  /// daemon 的 WebSocket 路径
  static const wsPath = '/ws';

  /// 输入框里的示例地址
  static const hostExample = '192.168.1.10';

  /// 空配置(首次启动时的工作副本)
  static const empty = ConnectionSettings();

  final String host;
  final int port;
  final String token;

  /// 是否填了地址 —— 没地址就没法连。
  bool get isConfigured => host.trim().isNotEmpty;

  /// 供 UI 显示的目标,如 `192.168.1.10:8787`
  String get target => '$host:$port';

  /// WS 连接地址。
  ///
  /// 令牌只能挂在查询串上:浏览器 WebSocket API 不允许自定义请求头,
  /// 而 daemon 三种带法(`Authorization` / `X-EdgeCube-Token` / `?token=`)
  /// 里只有查询串是跨平台的。
  Uri get wsUri => Uri(
    scheme: 'ws',
    host: host,
    port: port,
    path: wsPath,
    queryParameters: token.isEmpty ? null : {'token': token},
  );

  ConnectionSettings copyWith({String? host, int? port, String? token}) =>
      ConnectionSettings(
        host: host ?? this.host,
        port: port ?? this.port,
        token: token ?? this.token,
      );

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'token': token,
  };

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) =>
      ConnectionSettings(
        host: (json['host'] as String? ?? '').trim(),
        // 存储被手工改坏时也不能让端口越界
        port: clampPort(json['port'] as int? ?? defaultPort),
        token: json['token'] as String? ?? '',
      );

  static int clampPort(int port) => port.clamp(portMin, portMax);

  @override
  bool operator ==(Object other) =>
      other is ConnectionSettings &&
      other.host == host &&
      other.port == port &&
      other.token == token;

  @override
  int get hashCode => Object.hash(host, port, token);

  @override
  String toString() => 'ConnectionSettings($host:$port)';

  // ══════════════════════════════════════════════════════════════════════
  // 用户输入解析 / 表单校验
  // ══════════════════════════════════════════════════════════════════════

  /// 把用户随手粘进来的内容整理成 `(host, port?)`。
  ///
  /// 容忍这些写法(谁都可能直接从浏览器地址栏复制):
  ///
  /// ```
  /// 192.168.1.10
  /// 192.168.1.10:8787
  /// ws://192.168.1.10:8787/ws?token=x
  /// http://admin@192.168.1.10/
  /// [::1]:8787
  /// ```
  ///
  /// 返回的 `port` 为 `null` 表示输入里没带端口,调用方应保留端口输入框的值。
  static ({String host, int? port}) parseHostInput(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return (host: '', port: null);

    // 去掉协议前缀
    final schemeAt = text.indexOf('://');
    if (schemeAt >= 0) text = text.substring(schemeAt + 3);

    // 去掉路径 / 查询 / 锚点
    for (final separator in const ['/', '?', '#']) {
      final at = text.indexOf(separator);
      if (at >= 0) text = text.substring(0, at);
    }

    // 去掉 userinfo(user@host)
    final at = text.lastIndexOf('@');
    if (at >= 0) text = text.substring(at + 1);
    if (text.isEmpty) return (host: '', port: null);

    // IPv6 字面量:[::1]:8787
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end > 0) {
        final host = text.substring(1, end);
        final rest = text.substring(end + 1);
        final port = rest.startsWith(':')
            ? int.tryParse(rest.substring(1))
            : null;
        return (host: host, port: port == null ? null : clampPort(port));
      }
    }

    // 末尾的 :port(host 里不该再有冒号,IPv6 已在上面处理)
    final colon = text.lastIndexOf(':');
    if (colon > 0) {
      final port = int.tryParse(text.substring(colon + 1));
      if (port != null) {
        return (host: text.substring(0, colon), port: clampPort(port));
      }
    }
    return (host: text, port: null);
  }

  /// 表单校验:地址
  static String? validateHost(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '请输入服务器地址';
    if (text.contains(RegExp(r'\s'))) return '地址不能包含空格';
    final parsed = parseHostInput(text);
    if (parsed.host.isEmpty) return '地址格式不正确';
    return null;
  }

  /// 表单校验:端口
  static String? validatePort(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '请输入端口';
    final port = int.tryParse(text);
    if (port == null) return '端口必须是数字';
    if (port < portMin || port > portMax) return '端口需在 $portMin–$portMax 之间';
    return null;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 持久化(只存"连成功过"的配置)
// ══════════════════════════════════════════════════════════════════════════

/// 读存储里的连接配置;没有记录或解析失败 → `null`(视为"从未连接过")。
///
/// 令牌目前明文存在 shared_preferences 里:这是本机开发工具的取舍,
/// 等做权限分级时再换安全存储。
ConnectionSettings? loadPersistedConnection(SharedPreferences storage) {
  final raw = storage.getString(ConnectionSettings.storageKey);
  if (raw == null) return null;
  try {
    final settings = ConnectionSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return settings.isConfigured ? settings : null;
  } catch (_) {
    return null;
  }
}

Future<void> saveConnection(
  SharedPreferences storage,
  ConnectionSettings settings,
) => storage.setString(
  ConnectionSettings.storageKey,
  jsonEncode(settings.toJson()),
);

Future<void> clearConnection(SharedPreferences storage) =>
    storage.remove(ConnectionSettings.storageKey);

// ══════════════════════════════════════════════════════════════════════════
// 聚合状态(编辑中的工作副本)
// ══════════════════════════════════════════════════════════════════════════

/// 启动时的连接配置初始值(有历史则回填),main() 中 override。
final initialConnectionSettingsProvider = Provider<ConnectionSettings>(
  (ref) => ConnectionSettings.empty,
);

/// 聚合状态:当前**编辑中**的连接配置,唯一真源。
///
/// 与外观设置的区别:这里的 setter **不落盘**。用户可能只输入了半个地址,
/// 或者连的是台连不上的机器 —— 都不该被记住。真正落盘发生在
/// 「连接成功」的那一刻(见 `state.dart` 的 `ConnectionNotifier`)。
final connectionSettingsProvider =
    NotifierProvider<ConnectionSettingsNotifier, ConnectionSettings>(
      ConnectionSettingsNotifier.new,
    );

class ConnectionSettingsNotifier extends Notifier<ConnectionSettings> {
  @override
  ConnectionSettings build() => ref.watch(initialConnectionSettingsProvider);

  Future<void> setHost(String value) async {
    final host = value.trim();
    if (state.host == host) return;
    state = state.copyWith(host: host);
  }

  Future<void> setPort(int value) async {
    final port = ConnectionSettings.clampPort(value);
    if (state.port == port) return;
    state = state.copyWith(port: port);
  }

  Future<void> setToken(String value) async {
    if (state.token == value) return;
    state = state.copyWith(token: value);
  }

  /// 一次性覆盖(设置页「保存并重连」、忘记服务器后清空)
  Future<void> replace(ConnectionSettings value) async {
    if (state == value) return;
    state = value;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 单项设置全局 Provider
// ══════════════════════════════════════════════════════════════════════════
//
// 读: ref.watch(daemonHostProvider)
// 写: ref.read(daemonHostProvider.notifier).set('192.168.1.10')
//
// 骨架见 `settings/base.dart`;数据仍只有一份(聚合状态),单项只是门面。

abstract class ConnectionSetting<T>
    extends
        SettingNotifierBase<ConnectionSettings, T, ConnectionSettingsNotifier> {
  @override
  NotifierProvider<ConnectionSettingsNotifier, ConnectionSettings>
  get aggregate => connectionSettingsProvider;
}

/// daemon 地址(IP 或域名,可带 scheme / 端口,提交时会自动整理)
class _DaemonHostSetting extends ConnectionSetting<String> {
  @override
  String selectValue(ConnectionSettings s) => s.host;

  @override
  Future<void> applyValue(ConnectionSettingsNotifier n, String value) =>
      n.setHost(value);
}

final daemonHostProvider = NotifierProvider<_DaemonHostSetting, String>(
  _DaemonHostSetting.new,
);

/// daemon 端口
class _DaemonPortSetting extends ConnectionSetting<int> {
  @override
  int selectValue(ConnectionSettings s) => s.port;

  @override
  Future<void> applyValue(ConnectionSettingsNotifier n, int value) =>
      n.setPort(value);
}

final daemonPortProvider = NotifierProvider<_DaemonPortSetting, int>(
  _DaemonPortSetting.new,
);

/// 访问令牌(可空:服务端未开启鉴权时)
class _DaemonTokenSetting extends ConnectionSetting<String> {
  @override
  String selectValue(ConnectionSettings s) => s.token;

  @override
  Future<void> applyValue(ConnectionSettingsNotifier n, String value) =>
      n.setToken(value);
}

final daemonTokenProvider = NotifierProvider<_DaemonTokenSetting, String>(
  _DaemonTokenSetting.new,
);

/// 派生:目标地址字符串,如 `192.168.1.10:8787`
final connectionTargetProvider = Provider<String>(
  (ref) => ref.watch(
    connectionSettingsProvider.select((s) => s.target),
  ),
);
