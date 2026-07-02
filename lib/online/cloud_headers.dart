import 'package:package_info_plus/package_info_plus.dart';

class CloudHeaders {
  static String? Function()? _deviceIdProvider;

  static void init({String? Function()? deviceIdProvider}) {
    _deviceIdProvider = deviceIdProvider;
  }

  static Future<Map<String, String>> base() async {
    final info = await PackageInfo.fromPlatform();
    final headers = <String, String>{
      'User-Agent': 'EdgeCube/${info.version}',
    };
    final deviceId = _deviceIdProvider?.call();
    if (deviceId != null && deviceId.isNotEmpty) {
      headers['X-Device-Id'] = deviceId;
    }
    return headers;
  }
}
