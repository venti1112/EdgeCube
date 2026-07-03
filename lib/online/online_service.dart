import 'dart:async';

import 'package:android_cn_oaid/android_cn_oaid.dart';
import 'package:flutter/foundation.dart';

import '../config/config_store.dart';

/// 在线服务管理器：管理在线服务总开关状态、设备唯一标识与各在线服务访问地址。
///
/// 设备 ID 规则：
/// - 若设备支持 OAID / AAID，则获取后加上前缀 `AA`；
/// - 若不支持，则回退到 GUID 并加上前缀 `GG`。
///
/// 开关状态与设备 ID 一并保存在 `config/online.json`，只要开关打开且尚无
/// 设备 ID 就自动获取并保存；已有则直接复用（对应"开→关→开"场景）。
///
/// 各在线服务访问地址支持配置多个 URL，请求时并行请求，取第一个有效响应。
/// 优先级：
/// 1. 若配置了多 URL 列表（`updateCheckUrls` / `ecpkgCatalogUrls`），则直接用
/// 2. 否则使用内置默认 URL
class OnlineService extends ChangeNotifier {
  static const _fileName = 'online.json';
  static const _enabledKey = 'enabled';
  static const _askedKey = 'asked';
  static const _deviceIdKey = 'deviceId';
  static const _backendApiBaseUrlKey = 'backendApiBaseUrl';
  static const _updateCheckUrlKey = 'updateCheckUrl';
  static const _updateCheckUrlsKey = 'updateCheckUrls';
  static const _ecpkgCatalogUrlKey = 'ecpkgCatalogUrl';
  static const _ecpkgCatalogUrlsKey = 'ecpkgCatalogUrls';

  static const String defaultBackendApiBaseUrl =
      'https://edgecube-api.ventichat.com';

  static const List<String> defaultUpdateCheckUrls = [
    'https://edgecube-files.ventichat.com/updates.json',
  ];

  static const List<String> defaultEcpkgCatalogUrls = [
    'https://edgecube-files.ventichat.com/ecpkg.json',
  ];

  // ── 静态单例 ──────────────────────────────────────────────────────

  static OnlineService? _instance;

  /// 供无 BuildContext 的静态 service 访问实例。
  static OnlineService get instance {
    assert(_instance != null, 'OnlineService 尚未初始化');
    return _instance!;
  }

  // ── 字段 ──────────────────────────────────────────────────────────

  bool _enabled = false;
  bool _asked = false;
  String? _deviceId;
  String _backendApiBaseUrl = defaultBackendApiBaseUrl;
  List<String> _updateCheckUrls = [];
  List<String> _ecpkgCatalogUrls = [];

  // ── 公开 getter ──────────────────────────────────────────────────

  bool get enabled => _enabled;
  bool get asked => _asked;
  String? get deviceId => _deviceId;
  String get backendApiBaseUrl => _backendApiBaseUrl;

  /// 检查更新地址列表，未配置时返回默认值。
  List<String> get updateCheckUrls =>
      _updateCheckUrls.isNotEmpty ? _updateCheckUrls : defaultUpdateCheckUrls;

  /// ecpkg 下载中心地址列表，未配置时返回默认值。
  List<String> get ecpkgCatalogUrls =>
      _ecpkgCatalogUrls.isNotEmpty ? _ecpkgCatalogUrls : defaultEcpkgCatalogUrls;

  /// 兼容旧版：取第一个更新检查地址。
  String get updateCheckUrl => updateCheckUrls.first;

  /// 兼容旧版：取第一个 ecpkg 下载中心地址。
  String get ecpkgCatalogUrl => ecpkgCatalogUrls.first;

  /// 是否独立配置了更新检查地址列表。
  bool get hasCustomUpdateCheckUrl => _updateCheckUrls.isNotEmpty;

  /// 是否独立配置了 ecpkg 下载中心地址列表。
  bool get hasCustomEcpkgCatalogUrl => _ecpkgCatalogUrls.isNotEmpty;

  // ── 数据迁移 ──────────────────────────────────────────────────────

  /// 供数据迁移使用：直接写入持久化的 enabled/asked，不触发设备 ID 生成等副作用。
  static Future<void> importState({bool? enabled, bool? asked}) async {
    final m = await ConfigStore.readConfig(_fileName);
    if (enabled != null) m[_enabledKey] = enabled;
    if (asked != null) m[_askedKey] = asked;
    await ConfigStore.writeConfig(_fileName, m);
  }

  // ── 初始化 ────────────────────────────────────────────────────────

  Future<void> init() async {
    final m = await ConfigStore.readConfig(_fileName);
    _enabled = m[_enabledKey] as bool? ?? false;
    _asked = m[_askedKey] as bool? ?? false;
    _deviceId = m[_deviceIdKey] as String?;

    _backendApiBaseUrl =
        m[_backendApiBaseUrlKey] as String? ?? defaultBackendApiBaseUrl;

    _updateCheckUrls = _loadUrlList(
      m,
      listKey: _updateCheckUrlsKey,
      singleKey: _updateCheckUrlKey,
    );
    _ecpkgCatalogUrls = _loadUrlList(
      m,
      listKey: _ecpkgCatalogUrlsKey,
      singleKey: _ecpkgCatalogUrlKey,
    );

    _instance = this;

    if (_enabled) {
      await _ensureDeviceId();
    }
  }

  /// 从配置 map 中读取 URL 列表，优先读 listKey，回退读 singleKey 包装为列表。
  List<String> _loadUrlList(
    Map<String, dynamic> m, {
    required String listKey,
    required String singleKey,
  }) {
    final list = m[listKey] as List?;
    if (list != null && list.isNotEmpty) {
      return list.whereType<String>().toList();
    }
    final single = m[singleKey] as String?;
    if (single != null && single.isNotEmpty) {
      return [single];
    }
    return [];
  }

  // ── 写入到 config/online.json 的内部辅助 ──────────────────────────

  Future<void> _setAndPersist(String key, dynamic value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[key] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  // ── enabled / asked ───────────────────────────────────────────────

  /// 标记"已询问"状态，控制首次启动弹窗只展示一次。
  Future<void> markAsked() async {
    _asked = true;
    await _setAndPersist(_askedKey, true);
  }

  /// 设置在线服务总开关。开启时自动确保设备 ID 存在。
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _setAndPersist(_enabledKey, value);
    if (value) {
      await _ensureDeviceId();
    }
    notifyListeners();
  }

  // ── backendApiBaseUrl ─────────────────────────────────────────────

  /// 设置服务后端 API 基础地址。
  Future<void> setBackendApiBaseUrl(String url) async {
    _backendApiBaseUrl = url;
    await _setAndPersist(_backendApiBaseUrlKey, url);
    notifyListeners();
  }

  // ── updateCheckUrls ──────────────────────────────────────────────

  /// 设置检查更新专用地址列表，设为空列表则回退到默认。
  Future<void> setUpdateCheckUrls(List<String> urls) async {
    _updateCheckUrls = urls.where((u) => u.isNotEmpty).toList();
    await _setAndPersist(_updateCheckUrlsKey, _updateCheckUrls);
    notifyListeners();
  }

  /// 兼容旧版：设置单个检查更新地址。
  Future<void> setUpdateCheckUrl(String? url) async {
    if (url?.isNotEmpty == true) {
      await setUpdateCheckUrls([url!]);
    } else {
      await setUpdateCheckUrls([]);
    }
  }

  // ── ecpkgCatalogUrls ─────────────────────────────────────────────

  /// 设置 ecpkg 下载中心专用地址列表，设为空列表则回退到默认。
  Future<void> setEcpkgCatalogUrls(List<String> urls) async {
    _ecpkgCatalogUrls = urls.where((u) => u.isNotEmpty).toList();
    await _setAndPersist(_ecpkgCatalogUrlsKey, _ecpkgCatalogUrls);
    notifyListeners();
  }

  /// 兼容旧版：设置单个 ecpkg 下载中心地址。
  Future<void> setEcpkgCatalogUrl(String? url) async {
    if (url?.isNotEmpty == true) {
      await setEcpkgCatalogUrls([url!]);
    } else {
      await setEcpkgCatalogUrls([]);
    }
  }

  // ── 并行请求辅助 ──────────────────────────────────────────────────

  /// 并行请求多个 URL，返回第一个有效结果。
  ///
  /// [urls] 请求地址列表
  /// [fetch] 对单个 URL 执行请求并返回结果
  /// [isValid] 判断结果是否有效（无效结果会被忽略）
  ///
  /// 所有 URL 均无效或请求失败时抛出异常。
  static Future<T> fetchFirstValid<T>(
    List<String> urls,
    Future<T> Function(String url) fetch,
    bool Function(T) isValid,
  ) async {
    if (urls.isEmpty) throw ArgumentError('urls must not be empty');
    if (urls.length == 1) {
      final result = await fetch(urls.first);
      if (!isValid(result)) throw Exception('Invalid data from ${urls.first}');
      return result;
    }

    final completer = Completer<T>();
    var failures = 0;

    for (final url in urls) {
      Future.microtask(() async {
        try {
          final result = await fetch(url);
          if (isValid(result) && !completer.isCompleted) {
            completer.complete(result);
            return;
          }
        } catch (_) {}
        if (!completer.isCompleted) {
          failures++;
          if (failures == urls.length) {
            completer.completeError(
              Exception('All URLs failed or returned invalid data'),
            );
          }
        }
      });
    }

    return completer.future;
  }

  // ── 设备 ID ───────────────────────────────────────────────────────

  Future<void> _ensureDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return;
    await _generateAndSaveDeviceId();
  }

  Future<void> _generateAndSaveDeviceId() async {
    final plugin = AndroidCnOaid();
    await plugin.register();

    String id;
    try {
      final supported = await plugin.isSupported();
      if (supported) {
        final oaid = await plugin.getOAID();
        if (oaid != null && oaid.isNotEmpty) {
          id = 'AA$oaid';
        } else {
          final guid = await plugin.getGUID();
          id = 'GG$guid';
        }
      } else {
        final guid = await plugin.getGUID();
        id = 'GG$guid';
      }
    } catch (_) {
      final guid = await plugin.getGUID();
      id = 'GG$guid';
    }

    _deviceId = id;
    await _setAndPersist(_deviceIdKey, id);
  }
}
