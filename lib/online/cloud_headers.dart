import 'package:package_info_plus/package_info_plus.dart';

/// 统一请求头构建：仅提供 User-Agent，不包含任何设备标识信息。
class CloudHeaders {
  static Future<Map<String, String>> base() async {
    final info = await PackageInfo.fromPlatform();
    return {
      'User-Agent': 'EdgeCube/${info.version}',
    };
  }
}
