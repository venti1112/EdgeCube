import 'package:package_info_plus/package_info_plus.dart';

/// 全局 User-Agent 统一入口：`EdgeCube/<version>`。
///
/// [userAgent] 首次调用时异步初始化，之后同步返回缓存值。
/// [base] / [withHeader] 便捷方法适用于不同 caller 场景。
class CloudHeaders {
  CloudHeaders._();

  static String? _cachedUserAgent;

  /// 全局 User-Agent，格式 `EdgeCube/<version>`。
  /// 首次调用异步初始化，之后缓存同步返回。
  static Future<String> get userAgent async {
    if (_cachedUserAgent != null) return _cachedUserAgent!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedUserAgent = 'EdgeCube/${info.version}';
    } catch (_) {
      _cachedUserAgent = 'EdgeCube';
    }
    return _cachedUserAgent!;
  }

  /// 返回 `{User-Agent: <userAgent>}` 请求头。
  static Future<Map<String, String>> base() async {
    return {'User-Agent': await userAgent};
  }

  /// 在 [headers] 中注入 User-Agent（已含则不覆盖），返回新 Map。
  static Future<Map<String, String>> withHeader([
    Map<String, String>? headers,
  ]) async {
    final ua = {'User-Agent': await userAgent};
    if (headers == null || headers.isEmpty) return ua;
    return {...ua, ...headers};
  }
}
